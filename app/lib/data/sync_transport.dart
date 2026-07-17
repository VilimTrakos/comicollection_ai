import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models/comic.dart';
import '../models/sync_v2_response_validator.dart';
import '../services/auth/access_token_provider.dart';

class SyncExchange {
  const SyncExchange({required this.serverTime, required this.changes});

  final int serverTime;
  final List<Comic> changes;
}

class SyncServerException implements Exception {
  const SyncServerException(
    this.statusCode, {
    this.code,
    this.serverMessage,
    this.responseBody,
  });

  final int statusCode;
  final String? code;
  final String? serverMessage;
  final String? responseBody;

  factory SyncServerException.fromResponse(int statusCode, String body) {
    String? code;
    String? message;
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) {
        final payload = Map<String, Object?>.from(decoded);
        if (payload['code'] case final String value) code = value;
        if (payload['error'] case final String value) message = value;
      }
    } on FormatException {
      // Non-JSON response bodies are still retained for diagnostics.
    }
    return SyncServerException(
      statusCode,
      code: code,
      serverMessage: message,
      responseBody: body,
    );
  }
}

abstract interface class SyncTransport {
  Future<SyncExchange> exchange({
    required String serverUrl,
    required String apiToken,
    required int since,
    required Iterable<Comic> changes,
  });
}

/// HTTP implementation kept separate from local persistence and merge logic.
class HttpSyncTransport implements SyncTransport {
  HttpSyncTransport({
    HttpClient Function()? clientFactory,
    this.accessTokenProvider,
    this.maxResponseBytes = SyncV2ResponseValidator.maximumResponseBytes,
    this.responseTimeout = const Duration(seconds: 10),
  }) : _clientFactory = clientFactory ?? HttpClient.new;

  final HttpClient Function() _clientFactory;
  final AccessTokenProvider? accessTokenProvider;
  final int maxResponseBytes;
  final Duration responseTimeout;

  @override
  Future<SyncExchange> exchange({
    required String serverUrl,
    required String apiToken,
    required int since,
    required Iterable<Comic> changes,
  }) async {
    final requestBody = utf8.encode(
      jsonEncode({
        'since': since,
        'changes': changes.map((comic) => comic.toJson()).toList(),
      }),
    );
    var bearerToken = accessTokenProvider == null
        ? apiToken
        : await accessTokenProvider!.accessToken();
    final client = _clientFactory()
      ..connectionTimeout = const Duration(seconds: 5);
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
      return _decode(response.body);
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
    final request = await client.postUrl(Uri.parse('$serverUrl/api/v1/sync'));
    request.followRedirects = false;
    request.headers.contentType = ContentType.json;
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $bearerToken');
    request.contentLength = requestBody.length;
    request.add(requestBody);
    final response = await request.close().timeout(responseTimeout);
    return (
      statusCode: response.statusCode,
      body: await _readBody(response).timeout(responseTimeout),
    );
  }

  Future<String> _readBody(HttpClientResponse response) async {
    if (response.contentLength > maxResponseBytes) {
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

  SyncExchange _decode(String body) {
    final decoded = jsonDecode(body);
    if (decoded is! Map) throw const FormatException('Invalid sync payload');
    final payload = Map<String, Object?>.from(decoded);
    final serverTime = payload['server_time'];
    final encodedChanges = payload['changes'];
    if (serverTime is! num || encodedChanges is! List) {
      throw const FormatException('Invalid sync payload');
    }

    final changes = <Comic>[];
    for (final encoded in encodedChanges) {
      if (encoded is! Map) {
        throw const FormatException('Invalid remote comic');
      }
      try {
        changes.add(Comic.fromMap(Map<String, Object?>.from(encoded)));
      } on Object {
        throw const FormatException('Invalid remote comic');
      }
    }
    return SyncExchange(
      serverTime: serverTime.toInt(),
      changes: List.unmodifiable(changes),
    );
  }
}
