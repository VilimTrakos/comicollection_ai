import 'dart:async';

import 'package:comicollect/app/app_runtime.dart';
import 'package:comicollect/app_controller.dart';
import 'package:comicollect/data/collection_repository.dart';
import 'package:comicollect/data/local_database.dart';
import 'package:comicollect/data/settings_repository.dart';
import 'package:comicollect/data/sync_service.dart';
import 'package:comicollect/data/sync_transport.dart';
import 'package:comicollect/models/auth_failure.dart';
import 'package:comicollect/models/comic.dart';
import 'package:comicollect/services/auth/access_token_provider.dart';
import 'package:comicollect/services/auth/account_bound_access_token_provider.dart';
import 'package:comicollect/services/sync_coordinator.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'runtime drains active synchronization before closing its database',
    () async {
      final database = _CloseTrackingDatabase();
      final sync = _BlockingSyncService(database);
      final controller = AppController(db: database, syncService: sync)
        ..autoSync = true;
      final runtime = AppRuntime(controller: controller, database: database);

      final synchronization = controller.sync(force: true);
      await sync.started.future;

      var closeCompleted = false;
      final close = runtime.close().then((_) => closeCompleted = true);
      await Future<void>.delayed(Duration.zero);

      expect(closeCompleted, isFalse);
      expect(database.closed, isFalse);

      sync.pending.complete(const SyncResult(false, 'Offline'));
      await Future.wait([synchronization, close]);

      expect(database.closed, isTrue);
      expect(controller.syncCoordinator.running, isFalse);
    },
  );

  test(
    'account switch cannot send account A sync with account B token',
    () async {
      var currentAccountId = 'account-a';
      final delegate = _DelayedAccessTokenProvider();
      final tokens = AccountBoundAccessTokenProvider(
        delegate: delegate,
        expectedAccountId: 'account-a',
        currentAccountId: () => currentAccountId,
      );
      final transport = _RecordingTransport();
      final service = SyncService(
        LocalDatabase(pathOverride: '/tmp/account-bound-unused.db'),
        productionServerUrl: 'https://sync.example.test',
        accessTokenProvider: tokens,
        transport: transport,
      );

      final synchronization = service.sync();
      await delegate.requested.future;
      currentAccountId = 'account-b';
      delegate.pending.complete('account-b-token');

      final result = await synchronization;

      expect(result.ok, isFalse);
      expect(result.message, contains('Sesija je istekla'));
      expect(transport.calls, 0);
    },
  );

  test(
    'account-bound token rejects a stale runtime before token lookup',
    () async {
      final delegate = _DelayedAccessTokenProvider();
      final tokens = AccountBoundAccessTokenProvider(
        delegate: delegate,
        expectedAccountId: 'account-a',
        currentAccountId: () => 'account-b',
      );

      await expectLater(
        tokens.accessToken(),
        throwsA(
          isA<AuthException>().having(
            (error) => error.code,
            'code',
            'account_changed',
          ),
        ),
      );
      expect(delegate.calls, 0);
    },
  );

  test('runtime also drains controller post-processing before close', () async {
    final database = _CloseTrackingDatabase();
    final collections = _BlockingCollectionRepository(database);
    final coordinator = _ImmediateSyncCoordinator(
      database: database,
      collections: collections,
    );
    final controller = AppController(
      db: database,
      collectionRepository: collections,
      syncCoordinator: coordinator,
    )..autoSync = true;
    final runtime = AppRuntime(controller: controller, database: database);

    final synchronization = controller.sync(force: true);
    await collections.started.future;
    final close = runtime.close();
    await Future<void>.delayed(Duration.zero);

    expect(coordinator.quiesced, isTrue);
    expect(database.closed, isFalse);

    collections.pending.complete(const []);
    await Future.wait([synchronization, close]);
    expect(database.closed, isTrue);
  });

  test(
    'runtime still drains post-processing when coordinator shutdown fails',
    () async {
      final database = _CloseTrackingDatabase();
      final collections = _BlockingCollectionRepository(database);
      final coordinator = _ImmediateSyncCoordinator(
        database: database,
        collections: collections,
        quiesceError: StateError('coordinator shutdown failed'),
      );
      final controller = AppController(
        db: database,
        collectionRepository: collections,
        syncCoordinator: coordinator,
      )..autoSync = true;
      final runtime = AppRuntime(controller: controller, database: database);

      final synchronization = controller.sync(force: true);
      await collections.started.future;
      final close = runtime.close();
      await Future<void>.delayed(Duration.zero);

      expect(database.closed, isFalse);

      collections.pending.complete(const []);
      await synchronization;
      await expectLater(close, throwsStateError);
      expect(database.closed, isTrue);
    },
  );

  test('runtime close is idempotent', () async {
    final database = _CloseTrackingDatabase();
    final runtime = AppRuntime(
      controller: AppController(db: database)..autoSync = false,
      database: database,
    );

    final first = runtime.close();
    final second = runtime.close();

    expect(identical(first, second), isTrue);
    await Future.wait([first, second]);
    expect(database.closeCalls, 1);
  });

  test('runtime drains an in-flight collection save before close', () async {
    final database = _CloseTrackingDatabase();
    final collections = _BlockingUpsertCollectionRepository(database);
    final controller = AppController(
      db: database,
      collectionRepository: collections,
    )..autoSync = false;
    final runtime = AppRuntime(controller: controller, database: database);

    final save = controller.save(
      Comic(
        id: 'issue-1',
        series: 'Dylan Dog',
        edition: 'Extra',
        number: 1,
        title: 'Zora živih mrtvaca',
        owned: true,
        updatedAt: 1,
      ),
    );
    await collections.started.future;
    final close = runtime.close();
    await Future<void>.delayed(Duration.zero);

    expect(database.closed, isFalse);

    collections.pending.complete();
    await Future.wait([save, close]);
    expect(database.closed, isTrue);
  });
}

final class _CloseTrackingDatabase extends LocalDatabase {
  bool closed = false;
  int closeCalls = 0;

  @override
  Future<void> close() async {
    closeCalls++;
    closed = true;
  }
}

final class _BlockingSyncService extends SyncService {
  _BlockingSyncService(super.db);

  final started = Completer<void>();
  final pending = Completer<SyncResult>();

  @override
  Future<SyncResult> sync() {
    if (!started.isCompleted) started.complete();
    return pending.future;
  }
}

final class _DelayedAccessTokenProvider implements AccessTokenProvider {
  final requested = Completer<void>();
  final pending = Completer<String>();
  int calls = 0;

  @override
  Future<String> accessToken({bool forceRefresh = false}) {
    calls++;
    if (!requested.isCompleted) requested.complete();
    return pending.future;
  }
}

final class _RecordingTransport implements SyncTransport {
  int calls = 0;

  @override
  Future<SyncExchange> exchange({
    required String serverUrl,
    required String apiToken,
    required int since,
    required Iterable changes,
  }) async {
    calls++;
    throw StateError('A sync request must not be sent after account switch.');
  }
}

final class _BlockingCollectionRepository extends CollectionRepository {
  _BlockingCollectionRepository(super.database);

  final started = Completer<void>();
  final pending = Completer<List<Comic>>();

  @override
  Future<List<Comic>> load() {
    if (!started.isCompleted) started.complete();
    return pending.future;
  }
}

final class _BlockingUpsertCollectionRepository extends CollectionRepository {
  _BlockingUpsertCollectionRepository(super.database);

  final started = Completer<void>();
  final pending = Completer<void>();

  @override
  Future<void> upsert(Comic comic) {
    if (!started.isCompleted) started.complete();
    return pending.future;
  }
}

final class _ImmediateSyncCoordinator extends SyncCoordinator {
  _ImmediateSyncCoordinator({
    required LocalDatabase database,
    required CollectionRepository collections,
    this.quiesceError,
  }) : super(
         syncService: SyncService(database),
         collections: collections,
         settings: const SettingsRepository(),
       );

  bool quiesced = false;
  final Object? quiesceError;

  @override
  Future<SyncExecution?> synchronize({
    required bool enabled,
    bool force = false,
  }) async => const SyncExecution(result: SyncResult(true, 'ok'));

  @override
  Future<void> quiesce() async {
    quiesced = true;
    final error = quiesceError;
    if (error != null) throw error;
  }
}
