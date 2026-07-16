import 'dart:convert';
import 'dart:io';

import 'package:comicollect/data/sync_transport.dart';
import 'package:comicollect/data/sync_v2_transport.dart';
import 'package:comicollect/models/sync_v2.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'posts the exact v2 envelope and validates the correlated response',
    () async {
      late Map<String, Object?> received;
      late String path;
      late String? authorization;
      late int declaredLength;
      late int actualLength;
      final server = await _server((request) async {
        path = request.uri.path;
        authorization = request.headers.value(HttpHeaders.authorizationHeader);
        declaredLength = request.contentLength;
        final body = await request.fold<List<int>>(
          <int>[],
          (bytes, chunk) => bytes..addAll(chunk),
        );
        actualLength = body.length;
        received = Map<String, Object?>.from(
          jsonDecode(utf8.decode(body)) as Map,
        );
        await _respond(request, _response());
      });
      addTearDown(() => server.close(force: true));
      final transport = _transport();

      final exchange = await transport.exchange(
        serverUrl: 'http://127.0.0.1:${server.port}',
        apiToken: 'secret',
        batch: _batch(),
      );

      expect(path, '/api/v2/sync');
      expect(authorization, 'Bearer secret');
      expect(declaredLength, actualLength);
      expect(declaredLength, greaterThan(0));
      expect(received['protocol'], 2);
      expect(received['request_id'], 'request-1');
      expect(received['device_id'], 'device-1');
      expect(received['server_id'], 'server-1');
      expect(received['cursor'], 7);
      expect(received['limit'], 100);
      expect(received['mutations'], hasLength(1));
      expect(exchange.nextCursor, 8);
    },
  );

  test(
    'rejects an uncorrelated request id or changed server identity',
    () async {
      final wrongRequestServer = await _server((request) async {
        await request.drain<void>();
        await _respond(request, _response(requestId: 'other-request'));
      });
      addTearDown(() => wrongRequestServer.close(force: true));

      await expectLater(
        _transport().exchange(
          serverUrl: 'http://127.0.0.1:${wrongRequestServer.port}',
          apiToken: 'secret',
          batch: _batch(),
        ),
        throwsFormatException,
      );

      final wrongServer = await _server((request) async {
        await request.drain<void>();
        await _respond(request, _response(serverId: 'server-2'));
      });
      addTearDown(() => wrongServer.close(force: true));
      await expectLater(
        _transport().exchange(
          serverUrl: 'http://127.0.0.1:${wrongServer.port}',
          apiToken: 'secret',
          batch: _batch(),
        ),
        throwsFormatException,
      );
    },
  );

  test(
    'requires exactly one acknowledgement for every uploaded mutation',
    () async {
      final server = await _server((request) async {
        await request.drain<void>();
        await _respond(request, {
          ..._response(),
          'acknowledgements': <Object?>[],
        });
      });
      addTearDown(() => server.close(force: true));

      await expectLater(
        _transport().exchange(
          serverUrl: 'http://127.0.0.1:${server.port}',
          apiToken: 'secret',
          batch: _batch(),
        ),
        throwsFormatException,
      );
    },
  );

  test('binds an acknowledgement revision to its canonical group', () async {
    final response = _response();
    final group = Map<String, Object?>.from(
      (response['change_groups']! as List).single as Map,
    )..['mutation_id'] = 'different-mutation';
    response['change_groups'] = [group];
    final server = await _server((request) async {
      await request.drain<void>();
      await _respond(request, response);
    });
    addTearDown(() => server.close(force: true));

    await expectLater(
      _transport().exchange(
        serverUrl: 'http://127.0.0.1:${server.port}',
        apiToken: 'secret',
        batch: _batch(),
      ),
      throwsFormatException,
    );
  });

  test('rejects revision gaps and cursor-only progress', () async {
    Future<void> expectRejected(Map<String, Object?> response) async {
      final server = await _server((request) async {
        await request.drain<void>();
        await _respond(request, response);
      });
      addTearDown(() => server.close(force: true));
      await expectLater(
        _transport().exchange(
          serverUrl: 'http://127.0.0.1:${server.port}',
          apiToken: 'secret',
          batch: _batch(),
        ),
        throwsFormatException,
      );
    }

    await expectRejected({
      ..._response(),
      'next_cursor': 9,
      'change_groups': [
        {
          'revision': 9,
          'mutation_id': 'mutation-1',
          'changes': [_change().toJson()],
        },
      ],
    });
    await expectRejected({..._response(), 'change_groups': <Object?>[]});
    await expectRejected({
      ..._response(),
      'next_cursor': 7,
      'has_more': true,
      'change_groups': <Object?>[],
    });
  });

  test(
    'maps non-success status and rejects oversized response bodies',
    () async {
      final unavailable = await _server((request) async {
        await request.drain<void>();
        request.response.statusCode = HttpStatus.conflict;
        request.response.write(
          jsonEncode({
            'code': 'server_mismatch',
            'error': 'server id does not match',
          }),
        );
        await request.response.close();
      });
      addTearDown(() => unavailable.close(force: true));
      await expectLater(
        _transport().exchange(
          serverUrl: 'http://127.0.0.1:${unavailable.port}',
          apiToken: 'secret',
          batch: _batch(),
        ),
        throwsA(
          isA<SyncServerException>()
              .having(
                (error) => error.statusCode,
                'statusCode',
                HttpStatus.conflict,
              )
              .having((error) => error.code, 'code', 'server_mismatch')
              .having(
                (error) => error.serverMessage,
                'serverMessage',
                'server id does not match',
              ),
        ),
      );

      final oversized = await _server((request) async {
        await request.drain<void>();
        request.response.write('123456');
        await request.response.close();
      });
      addTearDown(() => oversized.close(force: true));
      await expectLater(
        _transport(maxResponseBytes: 5).exchange(
          serverUrl: 'http://127.0.0.1:${oversized.port}',
          apiToken: 'secret',
          batch: _batch(),
        ),
        throwsFormatException,
      );
    },
  );
}

HttpSyncV2Transport _transport({int maxResponseBytes = 1024 * 1024}) =>
    HttpSyncV2Transport(
      clientFactory: () => HttpOverrides.runWithHttpOverrides(
        HttpClient.new,
        _RealHttpOverrides(),
      ),
      requestIdFactory: () => 'request-1',
      maxResponseBytes: maxResponseBytes,
    );

class _RealHttpOverrides extends HttpOverrides {}

Future<HttpServer> _server(
  Future<void> Function(HttpRequest request) handler,
) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen(handler);
  return server;
}

Future<void> _respond(HttpRequest request, Map<String, Object?> payload) async {
  request.response
    ..statusCode = HttpStatus.ok
    ..headers.contentType = ContentType.json
    ..write(jsonEncode(payload));
  await request.response.close();
}

SyncUploadBatch _batch() => SyncUploadBatch(
  deviceId: 'device-1',
  serverId: 'server-1',
  cursor: 7,
  mutations: [
    SyncMutation(
      mutationId: 'mutation-1',
      createdAt: 123,
      changes: [_change()],
    ),
  ],
);

SyncEntityChange _change() => SyncEntityChange(
  entityType: SyncEntityType.collectionEntry,
  entityId: 'issue-1',
  operation: SyncOperation.upsert,
  data: {
    'issue_id': 'issue-1',
    'owned': true,
    'is_wanted': false,
    'is_read': false,
    'is_duplicate': false,
    'rating': 0,
    'notes': '',
    'deleted': false,
    'updated_at': 123,
    'issue_hint': {
      'id': 'issue-1',
      'series': 'Dylan Dog',
      'edition': 'Extra',
      'number': 1,
      'title': 'Morgana',
      'publisher': 'Ludens',
      'year': 2002,
      'origin': 'bundled',
    },
  },
);

Map<String, Object?> _response({
  String serverId = 'server-1',
  String requestId = 'request-1',
}) => {
  'protocol': 2,
  'server_id': serverId,
  'request_id': requestId,
  'server_time': 456,
  'next_cursor': 8,
  'has_more': false,
  'acknowledgements': [
    {'mutation_id': 'mutation-1', 'revision': 8, 'status': 'applied'},
  ],
  'change_groups': [
    {
      'revision': 8,
      'mutation_id': 'mutation-1',
      'changes': [_change().toJson()],
    },
  ],
};
