import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:uuid/uuid.dart';

import '../models/sync_v2.dart';
import '../models/sync_v2_response_validator.dart';
import '../services/auth/access_token_provider.dart';
import 'sync_transport.dart';

abstract interface class SyncV2Transport {
  Future<SyncV2Exchange> exchange({
    required String serverUrl,
    required String apiToken,
    required SyncUploadBatch batch,
    int limit = 100,
  });
}

class HttpSyncV2Transport implements SyncV2Transport {
  HttpSyncV2Transport({
    HttpClient Function()? clientFactory,
    String Function()? requestIdFactory,
    this.connectionTimeout = const Duration(seconds: 5),
    this.responseTimeout = const Duration(seconds: 10),
    this.maxResponseBytes = SyncV2ResponseValidator.maximumResponseBytes,
    this.accessTokenProvider,
  }) : _clientFactory = clientFactory ?? HttpClient.new,
       _requestIdFactory = requestIdFactory ?? const Uuid().v4;

  final HttpClient Function() _clientFactory;
  final String Function() _requestIdFactory;
  final Duration connectionTimeout;
  final Duration responseTimeout;
  final int maxResponseBytes;
  final AccessTokenProvider? accessTokenProvider;

  @override
  Future<SyncV2Exchange> exchange({
    required String serverUrl,
    required String apiToken,
    required SyncUploadBatch batch,
    int limit = 100,
  }) async {
    if (limit <= 0) throw ArgumentError.value(limit, 'limit');
    final requestId = _requestIdFactory().trim();
    if (requestId.isEmpty) {
      throw StateError('Sync request id must not be empty.');
    }
    final requestBody = utf8.encode(
      jsonEncode(batch.toRequestJson(requestId: requestId, limit: limit)),
    );
    var bearerToken = accessTokenProvider == null
        ? apiToken
        : await accessTokenProvider!.accessToken();
    final client = _clientFactory()..connectionTimeout = connectionTimeout;
    try {
      var response = await _send(
        client,
        serverUrl: serverUrl,
        bearerToken: bearerToken,
        requestBody: requestBody,
      );
      var failure = response.statusCode == HttpStatus.ok
          ? null
          : SyncServerException.fromResponse(
              response.statusCode,
              response.body,
            );
      if (failure?.statusCode == HttpStatus.unauthorized &&
          (failure?.code == 'access_expired' ||
              failure?.code == 'invalid_token') &&
          accessTokenProvider != null) {
        bearerToken = await accessTokenProvider!.accessToken(
          forceRefresh: true,
        );
        response = await _send(
          client,
          serverUrl: serverUrl,
          bearerToken: bearerToken,
          requestBody: requestBody,
        );
        failure = response.statusCode == HttpStatus.ok
            ? null
            : SyncServerException.fromResponse(
                response.statusCode,
                response.body,
              );
      }
      if (failure != null) throw failure;

      final exchange = _decode(response.body);
      _validateExchange(exchange, requestId: requestId, batch: batch);
      return exchange;
    } finally {
      client.close(force: true);
    }
  }

  Future<({int statusCode, String body})> _send(
    HttpClient client, {
    required String serverUrl,
    required String bearerToken,
    required List<int> requestBody,
  }) async {
    final request = await client.postUrl(Uri.parse('$serverUrl/api/v2/sync'));
    request.followRedirects = false;
    request.headers
      ..contentType = ContentType.json
      ..set(HttpHeaders.acceptHeader, ContentType.json.mimeType)
      ..set(HttpHeaders.authorizationHeader, 'Bearer $bearerToken');
    request.contentLength = requestBody.length;
    request.add(requestBody);
    final response = await request.close().timeout(responseTimeout);
    return (
      statusCode: response.statusCode,
      body: await _readBody(response).timeout(responseTimeout),
    );
  }

  Future<String> _readBody(HttpClientResponse response) async {
    final declaredLength = response.contentLength;
    if (declaredLength > maxResponseBytes) {
      throw const FormatException('Sync response is too large');
    }
    final bytes = <int>[];
    await for (final chunk in response) {
      if (bytes.length + chunk.length > maxResponseBytes) {
        throw const FormatException('Sync response is too large');
      }
      bytes.addAll(chunk);
    }
    return utf8.decode(bytes);
  }

  SyncV2Exchange _decode(String body) {
    final decoded = jsonDecode(body);
    if (decoded is! Map) throw const FormatException('Invalid sync payload');
    try {
      return SyncV2Exchange.fromJson(Map<String, Object?>.from(decoded));
    } on FormatException {
      rethrow;
    } on Object {
      throw const FormatException('Invalid sync payload');
    }
  }

  void _validateExchange(
    SyncV2Exchange exchange, {
    required String requestId,
    required SyncUploadBatch batch,
  }) {
    if (exchange.requestId != requestId) {
      throw const FormatException('Sync request id does not match');
    }
    if (batch.serverId.isNotEmpty && exchange.serverId != batch.serverId) {
      throw const FormatException('Sync server identity changed');
    }
    if (exchange.nextCursor < batch.cursor) {
      throw const FormatException('Sync cursor moved backwards');
    }
    var expectedRevision = batch.cursor + 1;
    for (final group in exchange.changeGroups) {
      if (group.revision != expectedRevision) {
        throw const FormatException('Sync response contains a revision gap');
      }
      expectedRevision++;
    }
    if (exchange.changeGroups.isEmpty && exchange.nextCursor != batch.cursor) {
      throw const FormatException('Sync cursor advanced without change groups');
    }
    if (exchange.hasMore && exchange.changeGroups.isEmpty) {
      throw const FormatException(
        'Sync continuation did not contain a change group',
      );
    }

    final requestedIds = batch.mutations
        .map((mutation) => mutation.mutationId)
        .toSet();
    final groupsByRevision = {
      for (final group in exchange.changeGroups) group.revision: group,
    };
    final acknowledgedIds = <String>{};
    for (final acknowledgement in exchange.acknowledgements) {
      if (!requestedIds.contains(acknowledgement.mutationId) ||
          !acknowledgedIds.add(acknowledgement.mutationId)) {
        throw const FormatException('Invalid mutation acknowledgement');
      }
      if (acknowledgement.revision <= batch.cursor) {
        throw const FormatException(
          'Acknowledgement does not advance the requested cursor',
        );
      }
      if (acknowledgement.revision <= exchange.nextCursor &&
          groupsByRevision[acknowledgement.revision]?.mutationId !=
              acknowledgement.mutationId) {
        throw const FormatException(
          'Acknowledgement does not match its change group',
        );
      }
    }
    if (acknowledgedIds.length != requestedIds.length) {
      throw const FormatException('Missing mutation acknowledgement');
    }
    if (!exchange.hasMore &&
        exchange.acknowledgements.any(
          (acknowledgement) => acknowledgement.revision > exchange.nextCursor,
        )) {
      throw const FormatException(
        'Acknowledged revision was not included in the final page',
      );
    }
  }
}
