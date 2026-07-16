import 'dart:async';

import 'package:comicollect/data/catalog_repository.dart';
import 'package:comicollect/data/collection_repository.dart';
import 'package:comicollect/data/local_database.dart';
import 'package:comicollect/data/settings_repository.dart';
import 'package:comicollect/data/sync_service.dart';
import 'package:comicollect/models/catalog_issue.dart';
import 'package:comicollect/models/comic.dart';
import 'package:comicollect/services/catalog_service.dart';
import 'package:comicollect/services/sync_coordinator.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CollectionRepository', () {
    test('delegates every collection operation to its database', () async {
      final database = _RecordingDatabase()
        ..stored['one'] = _comic('one', 1)
        ..mappings['123'] = 'one';
      final repository = CollectionRepository(database);

      expect(await repository.load(), hasLength(1));
      expect(database.allCalls, 1);

      final second = _comic('two', 2);
      await repository.upsert(second);
      expect(database.stored['two'], same(second));

      final third = _comic('three', 3);
      await repository.replaceAll([third]);
      expect(database.lastReplaced, [third]);

      final catalogComic = _comic('catalog', 4);
      await repository.upsertCatalogAll([catalogComic]);
      expect(database.catalogSeed, [catalogComic]);

      expect(await repository.barcodeMappings(), {'123': 'one'});
      await repository.saveBarcodeMapping('456', 'two');
      expect(database.mappings['456'], 'two');
    });
  });

  group('SettingsRepository', () {
    const repository = SettingsRepository();

    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('loads stable defaults when preferences do not exist', () async {
      final settings = await repository.load();

      expect(settings.darkMode, isTrue);
      expect(settings.accent, 'red');
      expect(settings.comicTitles, isFalse);
      expect(settings.showStatistics, isTrue);
      expect(settings.autoSync, isTrue);
      expect(settings.newIssueNotifications, isTrue);
      expect(settings.lastSyncAt, isNull);
      expect(await repository.loadLastSyncAt(), isNull);
      expect(await repository.loadCatalogVersion(), 0);
      expect(await repository.isStarterCatalogSeeded(), isFalse);
    });

    test('loads all persisted values and timestamp', () async {
      SharedPreferences.setMockInitialValues({
        'dark_mode': false,
        'accent': 'blue',
        'comic_titles': true,
        'show_statistics': false,
        'auto_sync': false,
        'new_issue_notifications': false,
        'last_sync': 1234,
        'catalog_version': 7,
        'starter_catalog_v3': true,
      });

      final settings = await repository.load();

      expect(settings.darkMode, isFalse);
      expect(settings.accent, 'blue');
      expect(settings.comicTitles, isTrue);
      expect(settings.showStatistics, isFalse);
      expect(settings.autoSync, isFalse);
      expect(settings.newIssueNotifications, isFalse);
      expect(settings.lastSyncAt!.millisecondsSinceEpoch, 1234);
      expect((await repository.loadLastSyncAt())!.millisecondsSinceEpoch, 1234);
      expect(await repository.loadCatalogVersion(), 7);
      expect(await repository.isStarterCatalogSeeded(), isTrue);
    });

    test('updates only supplied values and preserves current state', () async {
      final current = AppSettings(
        accent: 'red',
        comicTitles: true,
        lastSyncAt: _epoch,
      );

      final updated = await repository.update(
        current,
        darkMode: false,
        accent: 'yellow',
        comicTitles: false,
        showStatistics: false,
        autoSync: false,
        newIssueNotifications: false,
      );
      final prefs = await SharedPreferences.getInstance();

      expect(updated.darkMode, isFalse);
      expect(updated.accent, 'yellow');
      expect(updated.comicTitles, isFalse);
      expect(updated.showStatistics, isFalse);
      expect(updated.autoSync, isFalse);
      expect(updated.newIssueNotifications, isFalse);
      expect(updated.lastSyncAt, _epoch);
      expect(prefs.getBool('dark_mode'), isFalse);
      expect(prefs.getString('accent'), 'yellow');
      expect(prefs.getBool('comic_titles'), isFalse);
      expect(prefs.getBool('show_statistics'), isFalse);
      expect(prefs.getBool('auto_sync'), isFalse);
      expect(prefs.getBool('new_issue_notifications'), isFalse);
    });

    test('marks all starter catalog migrations as complete', () async {
      await repository.markStarterCatalogSeeded();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('starter_catalog_v1'), isTrue);
      expect(prefs.getBool('starter_catalog_v2'), isTrue);
      expect(prefs.getBool('starter_catalog_v3'), isTrue);
    });

    test('stores the applied catalog version under one stable key', () async {
      await repository.saveCatalogVersion(4);

      final prefs = await SharedPreferences.getInstance();
      expect(await repository.loadCatalogVersion(), 4);
      expect(prefs.getInt('catalog_version'), 4);
      await expectLater(repository.saveCatalogVersion(0), throwsArgumentError);
      expect(await repository.loadCatalogVersion(), 4);
    });
  });

  group('CatalogService', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test(
      'loads, refreshes each catalog version once and restores links',
      () async {
        final issue = _issue('catalog-issue', 202);
        final database = _RecordingDatabase()..mappings['978123'] = issue.id;
        final catalog = _RecordingCatalog([issue], version: 4);
        final service = CatalogService(
          catalog: catalog,
          collections: CollectionRepository(database),
          settings: const SettingsRepository(),
          nowMilliseconds: () => 777,
        );

        await service.initialize();

        expect(catalog.loadCalls, 1);
        expect(database.catalogSeed, hasLength(368));
        expect(database.catalogSeed.first.id, 'catalog-DESD-1');
        expect(database.catalogSeed.last.id, issue.id);
        expect(
          database.catalogSeed.every(
            (comic) => comic.id == issue.id || comic.updatedAt == 777,
          ),
          isTrue,
        );
        expect(catalog.registered['978123'], same(issue));
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getInt('catalog_version'), 4);

        database.catalogSeed.clear();
        await service.initialize();
        expect(catalog.loadCalls, 2);
        expect(database.catalogSeed, isEmpty);
      },
    );

    test(
      'legacy starter flag still refreshes into the stable version key',
      () async {
        SharedPreferences.setMockInitialValues({'starter_catalog_v3': true});
        final database = _RecordingDatabase();
        final service = CatalogService(
          catalog: _RecordingCatalog(const [], version: 1),
          collections: CollectionRepository(database),
          settings: const SettingsRepository(),
          nowMilliseconds: () => 777,
        );

        await service.initialize();

        expect(database.catalogSeed, hasLength(367));
        expect(
          (await SharedPreferences.getInstance()).getInt('catalog_version'),
          1,
        );
      },
    );

    test('does not mark a catalog version when its refresh fails', () async {
      final database = _RecordingDatabase()
        ..catalogError = StateError('write failed');
      final service = CatalogService(
        catalog: _RecordingCatalog(const [], version: 2),
        collections: CollectionRepository(database),
        settings: const SettingsRepository(),
        nowMilliseconds: () => 777,
      );

      await expectLater(service.initialize(), throwsStateError);

      expect(await const SettingsRepository().loadCatalogVersion(), 0);
    });

    test(
      'refreshes an upgrade and never downgrades an applied catalog',
      () async {
        SharedPreferences.setMockInitialValues({'catalog_version': 3});
        final upgradedDatabase = _RecordingDatabase();
        final upgraded = CatalogService(
          catalog: _RecordingCatalog(const [], version: 4),
          collections: CollectionRepository(upgradedDatabase),
          settings: const SettingsRepository(),
          nowMilliseconds: () => 777,
        );

        await upgraded.initialize();
        expect(upgradedDatabase.catalogSeed, hasLength(367));
        expect(await const SettingsRepository().loadCatalogVersion(), 4);

        SharedPreferences.setMockInitialValues({'catalog_version': 5});
        final olderDatabase = _RecordingDatabase();
        final older = CatalogService(
          catalog: _RecordingCatalog(const [], version: 4),
          collections: CollectionRepository(olderDatabase),
          settings: const SettingsRepository(),
          nowMilliseconds: () => 888,
        );

        await older.initialize();
        expect(olderDatabase.catalogSeed, isEmpty);
        expect(await const SettingsRepository().loadCatalogVersion(), 5);
      },
    );

    test('links a normalized barcode through storage and catalog', () async {
      final issue = _issue('one', 1);
      final database = _RecordingDatabase();
      final catalog = _RecordingCatalog([issue]);
      final service = CatalogService(
        catalog: catalog,
        collections: CollectionRepository(database),
        settings: const SettingsRepository(),
        nowMilliseconds: () => 0,
      );

      await service.linkBarcode('  978123  ', issue);

      expect(database.mappings, {'978123': 'one'});
      expect(catalog.registered['978123'], same(issue));
    });
  });

  group('SyncCoordinator', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('skips disabled synchronization unless it is forced', () async {
      final database = _RecordingDatabase();
      final sync = _RecordingSyncService(database);
      final coordinator = _coordinator(database, sync);
      addTearDown(coordinator.dispose);

      expect(await coordinator.synchronize(enabled: false), isNull);
      expect(sync.calls, 0);

      final execution = await coordinator.synchronize(
        enabled: false,
        force: true,
      );
      expect(execution!.result.ok, isTrue);
      expect(sync.calls, 1);
    });

    test('returns fresh collection and persisted time after success', () async {
      SharedPreferences.setMockInitialValues({'last_sync': 4321});
      final database = _RecordingDatabase()..stored['one'] = _comic('one', 1);
      final sync = _RecordingSyncService(database);
      final coordinator = _coordinator(database, sync);
      addTearDown(coordinator.dispose);

      final execution = await coordinator.synchronize(enabled: true);

      expect(execution!.result.message, 'Sinkronizirano');
      expect(execution.comics!.single.id, 'one');
      expect(execution.lastSyncAt!.millisecondsSinceEpoch, 4321);
      expect(database.allCalls, 1);
      expect(coordinator.running, isFalse);
    });

    test('does not reload collection after a failed result', () async {
      final database = _RecordingDatabase();
      final sync = _RecordingSyncService(database)
        ..result = const SyncResult(false, 'Offline');
      final coordinator = _coordinator(database, sync);
      addTearDown(coordinator.dispose);

      final execution = await coordinator.synchronize(enabled: true);

      expect(execution!.result.ok, isFalse);
      expect(execution.comics, isNull);
      expect(execution.lastSyncAt, isNull);
      expect(database.allCalls, 0);
    });

    test('guards concurrent calls and resets after success', () async {
      final database = _RecordingDatabase();
      final pending = Completer<SyncResult>();
      final sync = _RecordingSyncService(database)..pending = pending.future;
      final coordinator = _coordinator(database, sync);
      addTearDown(coordinator.dispose);

      final first = coordinator.synchronize(enabled: true);
      await Future<void>.delayed(Duration.zero);
      expect(coordinator.running, isTrue);
      expect(await coordinator.synchronize(enabled: true), isNull);
      expect(sync.calls, 1);

      pending.complete(const SyncResult(true, 'Gotovo'));
      await first;
      expect(coordinator.running, isFalse);
    });

    test('resets the running guard when synchronization throws', () async {
      final database = _RecordingDatabase();
      final sync = _RecordingSyncService(database)
        ..error = StateError('network');
      final coordinator = _coordinator(database, sync);
      addTearDown(coordinator.dispose);

      await expectLater(
        coordinator.synchronize(enabled: true),
        throwsStateError,
      );
      expect(coordinator.running, isFalse);
    });

    test('schedules enabled work and dispose cancels later ticks', () async {
      final database = _RecordingDatabase();
      final coordinator = SyncCoordinator(
        syncService: _RecordingSyncService(database),
        collections: CollectionRepository(database),
        settings: const SettingsRepository(),
        interval: const Duration(milliseconds: 5),
      );
      var calls = 0;
      final firstTick = Completer<void>();

      coordinator.schedule(
        enabled: true,
        action: () async {
          calls++;
          if (!firstTick.isCompleted) firstTick.complete();
        },
      );
      await firstTick.future.timeout(const Duration(seconds: 1));
      coordinator.dispose();
      final callsAtDispose = calls;
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(callsAtDispose, greaterThanOrEqualTo(1));
      expect(calls, callsAtDispose);
      coordinator.schedule(enabled: false, action: () async => calls++);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(calls, callsAtDispose);
    });
  });
}

final _epoch = DateTime.fromMillisecondsSinceEpoch(0);

SyncCoordinator _coordinator(
  _RecordingDatabase database,
  _RecordingSyncService sync,
) => SyncCoordinator(
  syncService: sync,
  collections: CollectionRepository(database),
  settings: const SettingsRepository(),
);

class _RecordingDatabase extends LocalDatabase {
  final Map<String, Comic> stored = {};
  final Map<String, String> mappings = {};
  final List<Comic> catalogSeed = [];
  Object? catalogError;
  List<Comic> lastReplaced = [];
  int allCalls = 0;

  @override
  Future<List<Comic>> all({bool includeDeleted = false}) async {
    allCalls++;
    return stored.values
        .where((comic) => includeDeleted || !comic.deleted)
        .toList(growable: false);
  }

  @override
  Future<void> upsert(Comic comic) async {
    stored[comic.id] = comic;
  }

  @override
  Future<void> replaceAll(Iterable<Comic> comics) async {
    lastReplaced = comics.toList(growable: false);
    for (final comic in lastReplaced) {
      stored[comic.id] = comic;
    }
  }

  @override
  Future<void> upsertCatalogAll(Iterable<Comic> comics) async {
    if (catalogError case final error?) throw error;
    catalogSeed.addAll(comics);
  }

  @override
  Future<Map<String, String>> barcodeMappings() async => Map.of(mappings);

  @override
  Future<void> saveBarcodeMapping(String barcode, String comicId) async {
    mappings[barcode] = comicId;
  }
}

class _RecordingCatalog extends CatalogRepository {
  _RecordingCatalog(this.items, {this.version = 1});

  final List<CatalogIssue> items;
  final int version;
  final Map<String, CatalogIssue> registered = {};
  int loadCalls = 0;

  @override
  int get catalogVersion => version;

  @override
  List<CatalogIssue> get issues => items;

  @override
  Future<void> load() async {
    loadCalls++;
  }

  @override
  CatalogIssue? byId(String id) {
    for (final issue in items) {
      if (issue.id == id) return issue;
    }
    return null;
  }

  @override
  void registerBarcode(String value, CatalogIssue issue) {
    registered[value.trim()] = issue;
  }
}

class _RecordingSyncService extends SyncService {
  _RecordingSyncService(super.db);

  int calls = 0;
  SyncResult result = const SyncResult(true, 'Sinkronizirano');
  Future<SyncResult>? pending;
  Object? error;

  @override
  Future<SyncResult> sync() async {
    calls++;
    if (error case final value?) throw value;
    return pending ?? result;
  }
}

Comic _comic(String id, int number) => Comic(
  id: id,
  series: 'Dylan Dog',
  edition: 'Extra',
  number: number,
  title: 'Broj $number',
  owned: false,
  updatedAt: number,
);

CatalogIssue _issue(String id, int number) => CatalogIssue(
  id: id,
  sourceEdition: 'DDLU',
  series: 'Dylan Dog',
  edition: 'Regularna (L)',
  number: number,
  title: 'Broj $number',
  publisher: 'Ludens',
);
