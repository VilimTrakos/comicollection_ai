import 'dart:convert';
import 'dart:io';

import 'package:comicollect/data/local_database.dart';
import 'package:comicollect/data/sync_service.dart';
import 'package:comicollect/models/comic.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late LocalDatabase database;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    database = LocalDatabase(pathOverride: inMemoryDatabasePath);
  });

  tearDown(() => database.close());

  test('returns a configuration error without server and token', () async {
    final result = await _service(database).sync();

    expect(result.ok, isFalse);
    expect(result.message, 'Server nije podešen');
  });

  test('returns a configuration error when only one setting exists', () async {
    SharedPreferences.setMockInitialValues({'server_url': 'http://localhost'});
    expect((await _service(database).sync()).message, 'Server nije podešen');

    SharedPreferences.setMockInitialValues({'api_token': 'secret'});
    expect((await _service(database).sync()).message, 'Server nije podešen');
  });

  test(
    'uploads local changes, merges remote changes and stores cursor',
    () async {
      await database.upsert(_comic('local', updatedAt: 20));
      SharedPreferences.setMockInitialValues({'last_sync': 10});
      late Map<String, dynamic> received;
      late String? authorization;
      late String path;
      final server = await _server((request) async {
        path = request.uri.path;
        authorization = request.headers.value(HttpHeaders.authorizationHeader);
        received = jsonDecode(await utf8.decoder.bind(request).join());
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.json
          ..write(
            jsonEncode({
              'server_time': 1234,
              'changes': [_comic('remote', updatedAt: 30).toJson()],
            }),
          );
        await request.response.close();
      });
      addTearDown(() => server.close(force: true));
      await _configure(server, trailingSlash: true);

      final result = await _service(database).sync();

      expect(result.ok, isTrue);
      expect(result.message, 'Sinkronizirano');
      expect(path, '/api/v1/sync');
      expect(authorization, 'Bearer test-token');
      expect(received['since'], 10);
      expect(received['changes'], hasLength(1));
      expect(received['changes'][0]['id'], 'local');
      expect(
        (await database.all()).map((comic) => comic.id),
        contains('remote'),
      );
      expect((await SharedPreferences.getInstance()).getInt('last_sync'), 1234);
    },
  );

  test('does not upload unchanged rows', () async {
    await database.upsert(_comic('old', updatedAt: 10));
    SharedPreferences.setMockInitialValues({'last_sync': 10});
    late Map<String, dynamic> received;
    final server = await _server((request) async {
      received = jsonDecode(await utf8.decoder.bind(request).join());
      request.response.write(
        jsonEncode({'server_time': 11, 'changes': <Object?>[]}),
      );
      await request.response.close();
    });
    addTearDown(() => server.close(force: true));
    await _configure(server);

    expect((await _service(database).sync()).ok, isTrue);
    expect(received['changes'], isEmpty);
  });

  test('keeps the existing cursor and data on HTTP errors', () async {
    SharedPreferences.setMockInitialValues({'last_sync': 55});
    final server = await _server((request) async {
      await request.drain<void>();
      request.response.statusCode = HttpStatus.unauthorized;
      await request.response.close();
    });
    addTearDown(() => server.close(force: true));
    await _configure(server);

    final result = await _service(database).sync();

    expect(result.ok, isFalse);
    expect(result.message, 'Server: 401');
    expect((await SharedPreferences.getInstance()).getInt('last_sync'), 55);
  });

  test('treats invalid response JSON as offline without throwing', () async {
    final server = await _server((request) async {
      await request.drain<void>();
      request.response.write('nije json');
      await request.response.close();
    });
    addTearDown(() => server.close(force: true));
    await _configure(server);

    final result = await _service(database).sync();

    expect(result.ok, isFalse);
    expect(result.message, 'Offline · spremljeno lokalno');
  });

  test('treats malformed URL and connection refusal as offline', () async {
    SharedPreferences.setMockInitialValues({
      'server_url': 'not a server',
      'api_token': 'test-token',
    });
    var result = await _service(database).sync();
    expect(result.ok, isFalse);
    expect(result.message, 'Offline · spremljeno lokalno');

    SharedPreferences.setMockInitialValues({
      'server_url': 'http://127.0.0.1:1',
      'api_token': 'test-token',
    });
    result = await _service(database).sync();
    expect(result.ok, isFalse);
    expect(result.message, 'Offline · spremljeno lokalno');
  });
}

SyncService _service(LocalDatabase database) => SyncService(
  database,
  clientFactory: () =>
      HttpOverrides.runWithHttpOverrides(HttpClient.new, _RealHttpOverrides()),
);

class _RealHttpOverrides extends HttpOverrides {}

Future<HttpServer> _server(
  Future<void> Function(HttpRequest request) handler,
) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen(handler);
  return server;
}

Future<void> _configure(HttpServer server, {bool trailingSlash = false}) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(
    'server_url',
    'http://127.0.0.1:${server.port}${trailingSlash ? '/' : ''}',
  );
  await prefs.setString('api_token', 'test-token');
}

Comic _comic(String id, {required int updatedAt}) => Comic(
  id: id,
  series: 'Dylan Dog',
  edition: 'Extra',
  number: id == 'local' ? 1 : 2,
  title: id,
  owned: true,
  updatedAt: updatedAt,
);
