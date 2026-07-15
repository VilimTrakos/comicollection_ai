import 'package:comicollect/data/local_database.dart';
import 'package:comicollect/data/sync_service.dart';
import 'package:comicollect/data/sync_settings_repository.dart';
import 'package:comicollect/data/sync_transport.dart';
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
  late _MemoryApiTokenStore tokens;
  late SyncSettingsRepository settings;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    database = LocalDatabase(pathOverride: inMemoryDatabasePath);
    tokens = _MemoryApiTokenStore();
    settings = SyncSettingsRepository(apiTokenStore: tokens);
  });

  tearDown(() => database.close());

  test('SyncService exchanges changes through injected boundaries', () async {
    await database.upsert(_comic('old', updatedAt: 9));
    await database.upsert(_comic('local', updatedAt: 11));
    await settings.saveConnection(
      serverUrl: ' https://server.test/// ',
      apiToken: ' secret ',
    );
    await settings.saveCursor(10);
    final transport = _RecordingTransport(
      response: SyncExchange(
        serverTime: 25,
        changes: [_comic('remote', updatedAt: 20)],
      ),
    );
    final service = SyncService(
      database,
      settingsRepository: settings,
      transport: transport,
    );

    final result = await service.sync();

    expect(result.ok, isTrue);
    expect(transport.serverUrl, 'https://server.test');
    expect(transport.apiToken, 'secret');
    expect(transport.since, 10);
    expect(transport.changes.map((comic) => comic.id), ['local']);
    expect((await database.all()).map((comic) => comic.id), contains('remote'));
    expect((await settings.load()).cursor, 25);
  });

  test(
    'SyncService does not call transport without full configuration',
    () async {
      final transport = _RecordingTransport(
        response: const SyncExchange(serverTime: 1, changes: []),
      );
      final service = SyncService(
        database,
        settingsRepository: settings,
        transport: transport,
      );

      final result = await service.sync();

      expect(result.message, 'Server nije podešen');
      expect(transport.calls, 0);
    },
  );

  test('SyncService maps server failures and preserves cursor', () async {
    await settings.saveConnection(
      serverUrl: 'https://server.test',
      apiToken: 'secret',
    );
    await settings.saveCursor(12);
    final service = SyncService(
      database,
      settingsRepository: settings,
      transport: _ThrowingTransport(const SyncServerException(401)),
    );

    final result = await service.sync();

    expect(result.ok, isFalse);
    expect(result.message, 'Server: 401');
    expect((await settings.load()).cursor, 12);
  });
}

class _MemoryApiTokenStore implements ApiTokenStore {
  String value = '';

  @override
  Future<String> read() async => value;

  @override
  Future<void> write(String token) async => value = token;
}

class _RecordingTransport implements SyncTransport {
  _RecordingTransport({required this.response});

  final SyncExchange response;
  int calls = 0;
  String? serverUrl;
  String? apiToken;
  int? since;
  List<Comic> changes = const [];

  @override
  Future<SyncExchange> exchange({
    required String serverUrl,
    required String apiToken,
    required int since,
    required Iterable<Comic> changes,
  }) async {
    calls++;
    this.serverUrl = serverUrl;
    this.apiToken = apiToken;
    this.since = since;
    this.changes = changes.toList(growable: false);
    return response;
  }
}

class _ThrowingTransport implements SyncTransport {
  const _ThrowingTransport(this.error);

  final Exception error;

  @override
  Future<SyncExchange> exchange({
    required String serverUrl,
    required String apiToken,
    required int since,
    required Iterable<Comic> changes,
  }) async => throw error;
}

Comic _comic(String id, {required int updatedAt}) => Comic(
  id: id,
  series: 'Dylan Dog',
  edition: 'Extra',
  number: id.hashCode,
  title: id,
  updatedAt: updatedAt,
);
