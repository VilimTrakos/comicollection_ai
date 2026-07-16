import 'dart:async';

import 'package:comicollect/data/local_database.dart';
import 'package:comicollect/data/sync_service.dart';
import 'package:comicollect/data/sync_settings_repository.dart';
import 'package:comicollect/data/sync_transport.dart';
import 'package:comicollect/data/sync_v2_transport.dart';
import 'package:comicollect/models/comic.dart';
import 'package:comicollect/models/sync_v2.dart';
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
    expect(
      result.message,
      'Prijava na server nije uspjela · provjerite API token',
    );
    expect((await settings.load()).cursor, 12);
  });

  test(
    'SyncService prefers v2, drains pages and stores a display time',
    () async {
      await database.upsert(_comic('local-v2', updatedAt: 11));
      await settings.saveConnection(
        serverUrl: 'https://server.test',
        apiToken: 'secret',
      );
      await settings.saveCursor(10);
      final batches = <SyncUploadBatch>[];
      final transport = _CallbackV2Transport((batch) {
        batches.add(batch);
        if (batches.length == 1) {
          expect(batch.mutations, isEmpty);
          return SyncV2Exchange(
            serverId: 'server-1',
            requestId: 'request-1',
            serverTime: 100,
            nextCursor: 0,
            hasMore: false,
            acknowledgements: const [],
            changeGroups: const [],
          );
        }
        final acknowledgements = <SyncAcknowledgement>[];
        final groups = <SyncChangeGroup>[];
        for (var index = 0; index < batch.mutations.length; index++) {
          final mutation = batch.mutations[index];
          final revision = batch.cursor + index + 1;
          acknowledgements.add(
            SyncAcknowledgement(
              mutationId: mutation.mutationId,
              revision: revision,
              status: 'applied',
            ),
          );
          groups.add(
            SyncChangeGroup(
              revision: revision,
              mutationId: mutation.mutationId,
              changes: mutation.changes,
            ),
          );
        }
        return SyncV2Exchange(
          serverId: 'server-1',
          requestId: 'request-2',
          serverTime: 101,
          nextCursor: batch.cursor + batch.mutations.length,
          hasMore: false,
          acknowledgements: acknowledgements,
          changeGroups: groups,
        );
      });
      final legacy = _RecordingTransport(
        response: const SyncExchange(serverTime: 99, changes: []),
      );
      final service = SyncService(
        database,
        settingsRepository: settings,
        transport: legacy,
        v2Transport: transport,
        nowMilliseconds: () => 999,
      );

      final result = await service.sync();

      expect(result.ok, isTrue);
      expect(result.message, 'Sinkronizirano');
      expect(legacy.calls, 0);
      expect(batches, hasLength(2));
      expect(batches.first.serverId, isEmpty);
      expect(batches.first.mutations, isEmpty);
      expect(batches.last.serverId, 'server-1');
      expect(batches.last.cursor, 0);
      expect(batches.last.mutations, isNotEmpty);
      expect((await settings.load()).cursor, 10);
      expect(
        (await settings.load()).lastSuccessfulSyncAt!.millisecondsSinceEpoch,
        999,
      );
    },
  );

  test(
    'SyncService falls back only when v2 is unavailable and unpinned',
    () async {
      await settings.saveConnection(
        serverUrl: 'https://server.test',
        apiToken: 'secret',
      );
      final legacy = _RecordingTransport(
        response: const SyncExchange(serverTime: 33, changes: []),
      );
      final service = SyncService(
        database,
        settingsRepository: settings,
        transport: legacy,
        v2Transport: const _ThrowingV2Transport(SyncServerException(404)),
      );

      final result = await service.sync();

      expect(result.ok, isTrue);
      expect(legacy.calls, 1);
      expect((await settings.load()).cursor, 33);
    },
  );

  test(
    'successful v1 fallback rebases staging before a later v2 upgrade',
    () async {
      await database.upsert(_comic('legacy-upgrade', updatedAt: 11));
      await settings.saveConnection(
        serverUrl: 'https://server.test',
        apiToken: 'secret',
      );
      await settings.saveCursor(10);

      for (final serverTime in [20, 30]) {
        final legacy = _RecordingTransport(
          response: SyncExchange(serverTime: serverTime, changes: const []),
        );
        final fallback = SyncService(
          database,
          settingsRepository: settings,
          transport: legacy,
          v2Transport: const _ThrowingV2Transport(SyncServerException(404)),
        );

        expect((await fallback.sync()).ok, isTrue);
        expect(legacy.calls, 1);
        final sqlite = await database.database;
        expect(await sqlite.query('sync_outbox'), isEmpty);
        final state = (await sqlite.query('sync_state')).single;
        expect(state['server_id'], isEmpty);
        expect(state['legacy_seeded'], 0);
        expect(state['baseline_complete'], 0);

        if (serverTime == 20) {
          await database.upsert(
            _comic(
              'legacy-upgrade',
              updatedAt: 21,
            ).copyWith(title: 'Potvrđeno kroz v1'),
          );
        }
      }

      final v2 = _CallbackV2Transport((batch) {
        expect(batch.cursor, 0);
        expect(batch.mutations, isEmpty);
        return SyncV2Exchange(
          serverId: 'upgraded-server',
          requestId: 'upgrade-baseline',
          serverTime: 40,
          nextCursor: 1,
          hasMore: false,
          acknowledgements: const [],
          changeGroups: [
            SyncChangeGroup(
              revision: 1,
              mutationId: 'newer-v2-metadata',
              changes: [
                SyncEntityChange(
                  entityType: SyncEntityType.customIssue,
                  entityId: 'legacy-upgrade',
                  operation: SyncOperation.upsert,
                  data: const {
                    'series': 'Dylan Dog',
                    'edition': 'Extra',
                    'number': 1,
                    'title': 'Novije s v2 servera',
                    'publisher': 'Ludens',
                    'year': null,
                    'page_count': null,
                    'writer': '',
                    'artist': '',
                    'deleted': false,
                  },
                ),
              ],
            ),
          ],
        );
      });
      final upgraded = SyncService(
        database,
        settingsRepository: settings,
        transport: _RecordingTransport(
          response: const SyncExchange(serverTime: 0, changes: []),
        ),
        v2Transport: v2,
      );

      final result = await upgraded.sync();
      expect(result.ok, isTrue);
      expect(v2.calls, 1);
      expect((await database.all()).single.title, 'Novije s v2 servera');
      expect(await database.hasPendingSyncV2(), isFalse);
    },
  );

  test(
    'v1 fallback preserves and later uploads an in-flight local write',
    () async {
      await database.upsert(_comic('before-flight', updatedAt: 11));
      await settings.saveConnection(
        serverUrl: 'https://server.test',
        apiToken: 'secret',
      );
      await settings.saveCursor(10);
      final blockedLegacy = _BlockingTransport();
      final firstService = SyncService(
        database,
        settingsRepository: settings,
        transport: blockedLegacy,
        v2Transport: const _ThrowingV2Transport(SyncServerException(404)),
      );

      final firstSync = firstService.sync();
      await blockedLegacy.started.future;
      await database.upsert(_comic('during-flight', updatedAt: 12));
      blockedLegacy.response.complete(
        const SyncExchange(serverTime: 1000, changes: []),
      );
      expect((await firstSync).ok, isTrue);

      final sqlite = await database.database;
      final pendingEntities = await sqlite.query('sync_outbox_entities');
      expect(
        pendingEntities.map((row) => row['entity_id']),
        contains('during-flight'),
      );
      final firstState = (await sqlite.query('sync_state')).single;
      expect(firstState['legacy_cursor'], 1000);
      expect(firstState['v1_fallback_pending'], 0);

      final retriedLegacy = _RecordingTransport(
        response: const SyncExchange(serverTime: 1100, changes: []),
      );
      final secondService = SyncService(
        database,
        settingsRepository: settings,
        transport: retriedLegacy,
        v2Transport: const _ThrowingV2Transport(SyncServerException(404)),
      );
      expect((await secondService.sync()).ok, isTrue);
      expect(
        retriedLegacy.changes.map((comic) => comic.id),
        contains('during-flight'),
      );
      expect(await sqlite.query('sync_outbox'), isEmpty);
      expect((await settings.load()).cursor, 1100);
    },
  );

  test(
    'interrupted v1 fallback is durably retried before probing v2',
    () async {
      await database.upsert(_comic('crash-recovery', updatedAt: 11));
      await settings.saveConnection(
        serverUrl: 'https://server.test',
        apiToken: 'secret',
      );
      await settings.saveCursor(10);
      await database.prepareSyncV2(legacyCursor: 10);
      final interrupted = await database.prepareV1Fallback(10);
      expect(interrupted.changes.map((comic) => comic.id), ['crash-recovery']);

      // Simulate the old dangerous crash point: the network/server cursor was
      // persisted while SQLite staging cleanup had not committed yet.
      await settings.saveCursor(50);
      final v2 = _CallbackV2Transport((batch) {
        fail('v2 must not be probed while legacy recovery is pending');
      });
      final legacy = _RecordingTransport(
        response: const SyncExchange(serverTime: 60, changes: []),
      );
      final service = SyncService(
        database,
        settingsRepository: settings,
        transport: legacy,
        v2Transport: v2,
      );

      expect((await service.sync()).ok, isTrue);
      expect(v2.calls, 0);
      expect(legacy.since, 10);
      expect(legacy.changes.map((comic) => comic.id), ['crash-recovery']);
      expect(await database.hasPendingV1Fallback(), isFalse);
      expect((await settings.load()).cursor, 60);
      expect(await (await database.database).query('sync_outbox'), isEmpty);
    },
  );

  test(
    'v1 read-only cutover preserves pending writes and continues on v2',
    () async {
      final original = _comic('activation-race', updatedAt: 11);
      await database.upsert(original);
      await settings.saveConnection(
        serverUrl: 'https://server.test',
        apiToken: 'secret',
      );
      await settings.saveCursor(10);
      await database.prepareSyncV2(legacyCursor: 10);
      await database.prepareV1Fallback(10);
      await database.upsert(
        original.copyWith(title: 'Nastalo tijekom zahtjeva', updatedAt: 12),
      );

      var call = 0;
      final v2 = _CallbackV2Transport((batch) {
        call++;
        if (call == 1) {
          expect(batch.mutations, isEmpty);
          return SyncV2Exchange(
            serverId: 'activated-server',
            requestId: 'activation-baseline',
            serverTime: 20,
            nextCursor: 0,
            hasMore: false,
            acknowledgements: const [],
            changeGroups: const [],
          );
        }
        expect(batch.mutations, isNotEmpty);
        final acknowledgements = <SyncAcknowledgement>[];
        final groups = <SyncChangeGroup>[];
        for (var index = 0; index < batch.mutations.length; index++) {
          final mutation = batch.mutations[index];
          final revision = batch.cursor + index + 1;
          acknowledgements.add(
            SyncAcknowledgement(
              mutationId: mutation.mutationId,
              revision: revision,
              status: 'applied',
            ),
          );
          groups.add(
            SyncChangeGroup(
              revision: revision,
              mutationId: mutation.mutationId,
              changes: mutation.changes,
            ),
          );
        }
        return SyncV2Exchange(
          serverId: 'activated-server',
          requestId: 'activation-upload',
          serverTime: 21,
          nextCursor: batch.cursor + batch.mutations.length,
          hasMore: false,
          acknowledgements: acknowledgements,
          changeGroups: groups,
        );
      });
      final service = SyncService(
        database,
        settingsRepository: settings,
        transport: const _ThrowingTransport(
          SyncServerException(409, code: 'v1_read_only'),
        ),
        v2Transport: v2,
      );

      final result = await service.sync();
      expect(result.ok, isTrue);
      expect(v2.calls, 2);
      expect(await database.hasPendingV1Fallback(), isFalse);
      expect(await database.hasPendingSyncV2(), isFalse);
      expect((await database.all()).single.title, 'Nastalo tijekom zahtjeva');
    },
  );

  test(
    'SyncService never downgrades after a server identity is pinned',
    () async {
      await database.applySyncV2(
        SyncV2Exchange(
          serverId: 'server-1',
          requestId: 'pin',
          serverTime: 1,
          nextCursor: 0,
          hasMore: false,
          acknowledgements: const [],
          changeGroups: const [],
        ),
      );
      await settings.saveConnection(
        serverUrl: 'https://server.test',
        apiToken: 'secret',
      );
      final legacy = _RecordingTransport(
        response: const SyncExchange(serverTime: 33, changes: []),
      );
      final service = SyncService(
        database,
        settingsRepository: settings,
        transport: legacy,
        v2Transport: const _ThrowingV2Transport(SyncServerException(404)),
      );

      final result = await service.sync();

      expect(result.ok, isFalse);
      expect(
        result.message,
        'Sinkronizacija v2 nije dostupna na povezanom serveru',
      );
      expect(legacy.calls, 0);
    },
  );

  test(
    'SyncService preserves the durable outbox when transport fails',
    () async {
      await database.upsert(_comic('queued', updatedAt: 11));
      await settings.saveConnection(
        serverUrl: 'https://server.test',
        apiToken: 'secret',
      );
      final before = await database.prepareSyncV2();
      final service = SyncService(
        database,
        settingsRepository: settings,
        v2Transport: const _ThrowingV2Transport(SyncServerException(503)),
      );

      final result = await service.sync();
      final after = await database.prepareSyncV2();

      expect(result.ok, isFalse);
      expect(
        result.message,
        'Server trenutačno nije dostupan · spremljeno lokalno',
      );
      expect(
        after.mutations.map((mutation) => mutation.mutationId),
        before.mutations.map((mutation) => mutation.mutationId),
      );
    },
  );

  test('SyncService explains a server identity conflict', () async {
    await settings.saveConnection(
      serverUrl: 'https://server.test',
      apiToken: 'secret',
    );
    final legacy = _RecordingTransport(
      response: const SyncExchange(serverTime: 33, changes: []),
    );
    final service = SyncService(
      database,
      settingsRepository: settings,
      transport: legacy,
      v2Transport: const _ThrowingV2Transport(
        SyncServerException(409, code: 'server_mismatch'),
      ),
    );

    final result = await service.sync();

    expect(result.ok, isFalse);
    expect(
      result.message,
      'Drugi server · u Postavkama odaberite povezivanje novog servera',
    );
    expect(legacy.calls, 0);
  });

  test('SyncService explains an interrupted v1-to-v2 cutover', () async {
    await settings.saveConnection(
      serverUrl: 'https://server.test',
      apiToken: 'secret',
    );
    final service = SyncService(
      database,
      settingsRepository: settings,
      transport: const _ThrowingTransport(
        SyncServerException(409, code: 'v1_read_only'),
      ),
    );

    final result = await service.sync();

    expect(result.ok, isFalse);
    expect(result.message, contains('Server je nadograđen'));
    expect(result.message, contains('ponovno ga povežite'));
  });

  test('SyncService reset clears v1 and v2 server-scoped state', () async {
    await database.upsert(_comic('kept-local', updatedAt: 11));
    await database.prepareSyncV2();
    await database.applySyncV2(
      SyncV2Exchange(
        serverId: 'old-server',
        requestId: 'pin-old-server',
        serverTime: 100,
        nextCursor: 0,
        hasMore: false,
        acknowledgements: const [],
        changeGroups: const [],
      ),
    );
    await settings.saveCursor(999);
    await settings.saveLastSuccessfulSyncAt(
      DateTime.fromMillisecondsSinceEpoch(1000),
    );
    final service = SyncService(
      database,
      settingsRepository: settings,
      transport: _RecordingTransport(
        response: const SyncExchange(serverTime: 0, changes: []),
      ),
    );

    await service.resetServerBinding();

    final resetSettings = await settings.load();
    expect(resetSettings.cursor, 0);
    expect(resetSettings.lastSuccessfulSyncAt, isNull);
    final batch = await database.prepareSyncV2();
    expect(batch.serverId, isEmpty);
    expect(batch.cursor, 0);
    expect(batch.mutations, isEmpty);
    await database.applySyncV2(
      SyncV2Exchange(
        serverId: 'new-server',
        requestId: 'pin-new-server',
        serverTime: 101,
        nextCursor: 0,
        hasMore: false,
        acknowledgements: const [],
        changeGroups: const [],
      ),
    );
    expect((await database.prepareSyncV2()).mutations, isNotEmpty);
    expect((await database.all()).single.id, 'kept-local');
  });

  test('SyncService bounds a server continuation loop', () async {
    await settings.saveConnection(
      serverUrl: 'https://server.test',
      apiToken: 'secret',
    );
    var cursor = 0;
    final transport = _CallbackV2Transport((batch) {
      cursor++;
      return SyncV2Exchange(
        serverId: 'server-1',
        requestId: 'request-$cursor',
        serverTime: cursor,
        nextCursor: cursor,
        hasMore: true,
        acknowledgements: const [],
        changeGroups: [
          SyncChangeGroup(
            revision: cursor,
            mutationId: 'remote-$cursor',
            changes: [
              SyncEntityChange(
                entityType: SyncEntityType.customIssue,
                entityId: 'remote-$cursor',
                operation: SyncOperation.upsert,
                data: {
                  'series': 'Dylan Dog',
                  'edition': 'Remote',
                  'number': cursor,
                  'title': 'Remote $cursor',
                },
              ),
            ],
          ),
        ],
      );
    });
    final service = SyncService(
      database,
      settingsRepository: settings,
      v2Transport: transport,
      maxV2Iterations: 3,
    );

    final result = await service.sync();

    expect(transport.calls, 3);
    expect(result.ok, isTrue);
    expect(result.hasPending, isTrue);
    expect(result.message, 'Djelomično sinkronizirano · nastavak slijedi');
    expect((await settings.load()).lastSuccessfulSyncAt, isNull);
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

class _BlockingTransport implements SyncTransport {
  final started = Completer<void>();
  final response = Completer<SyncExchange>();

  @override
  Future<SyncExchange> exchange({
    required String serverUrl,
    required String apiToken,
    required int since,
    required Iterable<Comic> changes,
  }) {
    started.complete();
    return response.future;
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

class _CallbackV2Transport implements SyncV2Transport {
  _CallbackV2Transport(this.callback);

  final SyncV2Exchange Function(SyncUploadBatch batch) callback;
  int calls = 0;

  @override
  Future<SyncV2Exchange> exchange({
    required String serverUrl,
    required String apiToken,
    required SyncUploadBatch batch,
    int limit = 100,
  }) async {
    calls++;
    return callback(batch);
  }
}

class _ThrowingV2Transport implements SyncV2Transport {
  const _ThrowingV2Transport(this.error);

  final Exception error;

  @override
  Future<SyncV2Exchange> exchange({
    required String serverUrl,
    required String apiToken,
    required SyncUploadBatch batch,
    int limit = 100,
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
