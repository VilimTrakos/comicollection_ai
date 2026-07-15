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
  const SyncServerException(this.statusCode);

  final int statusCode;
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
      request.write(
        jsonEncode({
          'since': since,
          'changes': changes.map((comic) => comic.toJson()).toList(),
        }),
      );
      final response = await request.close().timeout(
        const Duration(seconds: 10),
      );
      final body = await utf8.decoder.bind(response).join();
      if (response.statusCode != HttpStatus.ok) {
        throw SyncServerException(response.statusCode);
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
