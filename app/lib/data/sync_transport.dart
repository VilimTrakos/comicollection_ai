import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models/comic.dart';

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
  HttpSyncTransport({HttpClient Function()? clientFactory})
    : _clientFactory = clientFactory ?? HttpClient.new;

  final HttpClient Function() _clientFactory;

  @override
  Future<SyncExchange> exchange({
    required String serverUrl,
    required String apiToken,
    required int since,
    required Iterable<Comic> changes,
  }) async {
    final client = _clientFactory()
      ..connectionTimeout = const Duration(seconds: 5);
    try {
      final request = await client.postUrl(Uri.parse('$serverUrl/api/v1/sync'));
      request.headers.contentType = ContentType.json;
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $apiToken');
      final requestBody = utf8.encode(
        jsonEncode({
          'since': since,
          'changes': changes.map((comic) => comic.toJson()).toList(),
        }),
      );
      request.contentLength = requestBody.length;
      request.add(requestBody);
      final response = await request.close().timeout(
        const Duration(seconds: 10),
      );
      final body = await utf8.decoder.bind(response).join();
      if (response.statusCode != HttpStatus.ok) {
        throw SyncServerException.fromResponse(response.statusCode, body);
      }
      return _decode(body);
    } finally {
      client.close(force: true);
    }
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
