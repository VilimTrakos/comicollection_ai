import 'dart:async';

import 'package:comicollect/app_controller.dart';
import 'package:comicollect/data/catalog_repository.dart';
import 'package:comicollect/data/collection_repository.dart';
import 'package:comicollect/data/local_database.dart';
import 'package:comicollect/data/sync_service.dart';
import 'package:comicollect/models/catalog_issue.dart';
import 'package:comicollect/models/comic.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({'auto_sync': false}));

  test(
    'init loads preferences, catalog, mappings and seeds only once',
    () async {
      SharedPreferences.setMockInitialValues({
        'dark_mode': false,
        'accent': 'blue',
        'comic_titles': true,
        'show_statistics': false,
        'auto_sync': false,
        'new_issue_notifications': false,
        'last_sync': 123,
      });
      final issue = _issue('catalog-test-1', 1);
      final db = _MemoryDatabase()
        ..stored['existing'] = _comic('existing', 1)
        ..mappings['123'] = issue.id;
      final catalog = _FakeCatalog([issue]);
      final controller = AppController(
        db: db,
        catalog: catalog,
        nowMilliseconds: () => 1000,
      );
      addTearDown(controller.dispose);

      await controller.init();

      expect(controller.loading, isFalse);
      expect(controller.startupError, isNull);
      expect(controller.darkMode, isFalse);
      expect(controller.accent, 'blue');
      expect(controller.comicTitles, isTrue);
      expect(controller.showStatistics, isFalse);
      expect(controller.autoSync, isFalse);
      expect(controller.newIssueNotifications, isFalse);
      expect(controller.lastSyncAt!.millisecondsSinceEpoch, 123);
      expect(controller.comics.single.id, 'existing');
      expect(catalog.loadCalls, 1);
      expect(catalog.registered['123'], same(issue));
      expect(db.catalogSeed, hasLength(368));
      expect(db.catalogSeed.last.id, issue.id);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('starter_catalog_v1'), isTrue);
      expect(prefs.getBool('starter_catalog_v2'), isTrue);
      expect(prefs.getBool('starter_catalog_v3'), isTrue);

      db.catalogSeed.clear();
      await controller.init();
      expect(db.catalogSeed, isEmpty);
    },
  );

  test('init reports startup errors and always leaves loading state', () async {
    final catalog = _FakeCatalog(const [])..loadError = StateError('pokvareno');
    final controller = AppController(db: _MemoryDatabase(), catalog: catalog);
    addTearDown(controller.dispose);

    await controller.init();

    expect(controller.loading, isFalse);
    expect(controller.startupError, contains('pokvareno'));
    expect(controller.syncMessage, 'Greška lokalnih podataka');
  });

  test(
    'uses an injected collection repository as its persistence boundary',
    () async {
      final db = _MemoryDatabase();
      final repository = CollectionRepository(db);
      final controller = AppController(
        collectionRepository: repository,
        catalog: _FakeCatalog(const []),
        nowMilliseconds: () => 321,
      )..autoSync = false;
      addTearDown(controller.dispose);

      await controller.save(_comic('one', 1));

      expect(controller.db, same(db));
      expect(controller.collectionRepository, same(repository));
      expect(db.stored['one']!.updatedAt, 321);
    },
  );

  test('scoped listenables ignore unrelated controller notifications', () {
    final controller = AppController(
      db: _MemoryDatabase(),
      catalog: _FakeCatalog(const []),
    );
    addTearDown(controller.dispose);
    var appearanceNotifications = 0;
    var startupNotifications = 0;
    var collectionNotifications = 0;
    var syncNotifications = 0;
    var preferenceNotifications = 0;
    controller.appearanceChanges.addListener(() => appearanceNotifications++);
    controller.startupChanges.addListener(() => startupNotifications++);
    controller.collectionChanges.addListener(() => collectionNotifications++);
    controller.syncChanges.addListener(() => syncNotifications++);
    controller.preferenceChanges.addListener(() => preferenceNotifications++);

    controller.notifyListeners();
    expect([
      appearanceNotifications,
      startupNotifications,
      collectionNotifications,
      syncNotifications,
      preferenceNotifications,
    ], everyElement(0));

    controller
      ..accent = 'blue'
      ..notifyListeners();
    expect(appearanceNotifications, 1);
    expect(preferenceNotifications, 1);
    expect(startupNotifications, 0);
    expect(collectionNotifications, 0);
    expect(syncNotifications, 0);

    controller
      ..comics = [_comic('one', 1)]
      ..notifyListeners();
    expect(collectionNotifications, 1);
    expect(appearanceNotifications, 1);

    controller
      ..syncing = true
      ..syncMessage = 'Sinkroniziram'
      ..notifyListeners();
    expect(syncNotifications, 1);
    expect(collectionNotifications, 1);

    controller
      ..loading = false
      ..notifyListeners();
    expect(startupNotifications, 1);
    expect(preferenceNotifications, 1);
  });

  test(
    'save inserts, updates and tombstone-removes with one timestamp',
    () async {
      final db = _MemoryDatabase();
      final sync = _FakeSyncService(db);
      final controller = AppController(
        db: db,
        catalog: _FakeCatalog(const []),
        syncService: sync,
        nowMilliseconds: () => 500,
      )..autoSync = true;
      addTearDown(controller.dispose);

      await controller.save(_comic('one', 1));
      expect(controller.comics.single.updatedAt, 500);
      expect(db.stored['one']!.updatedAt, 500);
      await _waitForSync(controller);
      expect(sync.calls, 1);

      await controller.save(_comic('one', 1).copyWith(title: 'Promjena'));
      await _waitForSync(controller);
      expect(controller.comics.single.title, 'Promjena');

      await controller.remove(controller.comics.single);
      await _waitForSync(controller);
      expect(controller.comics, isEmpty);
      expect(db.stored['one']!.deleted, isTrue);
    },
  );

  test('save rolls UI back from storage when persistence fails', () async {
    final db = _MemoryDatabase()..stored['old'] = _comic('old', 1);
    final controller = AppController(db: db, catalog: _FakeCatalog(const []))
      ..comics = [_comic('old', 1)]
      ..autoSync = false;
    addTearDown(controller.dispose);
    db.failUpsert = true;

    await expectLater(controller.save(_comic('new', 2)), throwsStateError);

    expect(controller.comics.map((comic) => comic.id), ['old']);
  });

  test(
    'saveScanResults updates existing and creates missing catalog records',
    () async {
      final first = _issue('one', 1, coverAsset: 'one.webp');
      final second = _issue('two', 2, coverAsset: 'two.webp');
      final db = _MemoryDatabase()
        ..stored['one'] = _comic('one', 1).copyWith(coverAsset: 'old.webp');
      final controller =
          AppController(
              db: db,
              catalog: _FakeCatalog([first, second]),
              nowMilliseconds: () => 700,
            )
            ..comics = db.visible
            ..autoSync = false;
      addTearDown(controller.dispose);

      await controller.saveScanResults({first: true, second: false});

      expect(db.stored['one']!.owned, isTrue);
      expect(db.stored['one']!.coverAsset, 'one.webp');
      expect(db.stored['two']!.owned, isFalse);
      expect(db.stored['two']!.coverAsset, 'two.webp');
      expect(db.stored.values.every((comic) => comic.updatedAt == 700), isTrue);
      expect(controller.comics, hasLength(2));
    },
  );

  test(
    'saveAll applies additions, updates, deletions and rollback on failure',
    () async {
      final db = _MemoryDatabase()
        ..stored.addAll({'one': _comic('one', 1), 'two': _comic('two', 2)});
      final controller =
          AppController(
              db: db,
              catalog: _FakeCatalog(const []),
              nowMilliseconds: () => 800,
            )
            ..comics = db.visible
            ..autoSync = false;
      addTearDown(controller.dispose);

      await controller.saveAll([
        _comic('one', 1).copyWith(title: 'Novo'),
        _comic('two', 2).copyWith(deleted: true),
        _comic('three', 3),
      ]);

      expect(
        controller.comics.map((comic) => comic.id),
        containsAll(['one', 'three']),
      );
      expect(controller.comics.any((comic) => comic.id == 'two'), isFalse);
      expect(db.stored['one']!.title, 'Novo');
      expect(db.stored['two']!.deleted, isTrue);
      expect(db.lastReplaced.every((comic) => comic.updatedAt == 800), isTrue);

      db.failReplace = true;
      await expectLater(
        controller.saveAll([_comic('four', 4)]),
        throwsStateError,
      );
      expect(controller.comics.any((comic) => comic.id == 'four'), isFalse);
    },
  );

  test('linkBarcode persists trimmed code and updates the catalog', () async {
    final issue = _issue('one', 1);
    final db = _MemoryDatabase();
    final catalog = _FakeCatalog([issue]);
    final controller = AppController(db: db, catalog: catalog);
    addTearDown(controller.dispose);

    await controller.linkBarcode(' 123 ', issue);

    expect(db.mappings, {'123': 'one'});
    expect(catalog.registered['123'], same(issue));
  });

  test('add trims input and forwards every metadata value', () async {
    final db = _MemoryDatabase();
    final controller = AppController(
      db: db,
      catalog: _FakeCatalog(const []),
      nowMilliseconds: () => 900,
      idGenerator: () => 'generated-id',
    )..autoSync = false;
    addTearDown(controller.dispose);

    await controller.add(
      series: ' Dylan Dog ',
      edition: ' Extra ',
      number: 14,
      title: ' Kuća sjećanja ',
      publisher: ' Ludens ',
      year: 2002,
      owned: false,
      read: true,
      condition: '',
      purchasePrice: 3.5,
      estimatedValue: 8,
      duplicate: true,
      loanedTo: ' Ana ',
      notes: ' Bilješka ',
      rating: 4,
      pageCount: 98,
      writer: ' Sclavi ',
      artist: ' Stano ',
    );

    final comic = controller.comics.single;
    expect(comic.id, 'generated-id');
    expect(comic.series, 'Dylan Dog');
    expect(comic.edition, 'Extra');
    expect(comic.title, 'Kuća sjećanja');
    expect(comic.publisher, 'Ludens');
    expect(comic.loanedTo, 'Ana');
    expect(comic.notes, 'Bilješka');
    expect(comic.writer, 'Sclavi');
    expect(comic.artist, 'Stano');
    expect(comic.number, 14);
    expect(comic.year, 2002);
    expect(comic.owned, isFalse);
    expect(comic.read, isTrue);
    expect(comic.condition, isEmpty);
    expect(comic.purchasePrice, 3.5);
    expect(comic.estimatedValue, 8);
    expect(comic.duplicate, isTrue);
    expect(comic.rating, 4);
    expect(comic.pageCount, 98);
    expect(comic.updatedAt, 900);
  });

  test('reload publishes the current visible database rows', () async {
    final db = _MemoryDatabase()..stored['one'] = _comic('one', 1);
    final controller = AppController(db: db, catalog: _FakeCatalog(const []));
    addTearDown(controller.dispose);
    var notifications = 0;
    controller.addListener(() => notifications++);

    await controller.reload();

    expect(controller.comics.single.id, 'one');
    expect(notifications, 1);
  });

  test(
    'sync honors auto-sync, force, result state and successful reload',
    () async {
      SharedPreferences.setMockInitialValues({'last_sync': 456});
      final db = _MemoryDatabase()..stored['one'] = _comic('one', 1);
      final sync = _FakeSyncService(db);
      final controller = AppController(
        db: db,
        catalog: _FakeCatalog(const []),
        syncService: sync,
      )..autoSync = false;
      addTearDown(controller.dispose);

      await controller.sync();
      expect(sync.calls, 0);

      await controller.sync(force: true);
      expect(sync.calls, 1);
      expect(controller.online, isTrue);
      expect(controller.syncMessage, 'Sinkronizirano');
      expect(controller.comics.single.id, 'one');
      expect(controller.lastSyncAt!.millisecondsSinceEpoch, 456);

      sync.result = const SyncResult(false, 'Neuspjelo');
      await controller.sync(force: true);
      expect(controller.online, isFalse);
      expect(controller.syncMessage, 'Neuspjelo');
    },
  );

  test('sync ignores a concurrent invocation', () async {
    final db = _MemoryDatabase();
    final completer = Completer<SyncResult>();
    final sync = _FakeSyncService(db)..pending = completer.future;
    final controller = AppController(
      db: db,
      catalog: _FakeCatalog(const []),
      syncService: sync,
    )..autoSync = true;
    addTearDown(controller.dispose);

    final first = controller.sync();
    await _flush();
    final second = controller.sync();
    expect(sync.calls, 1);
    completer.complete(const SyncResult(true, 'Gotovo'));
    await Future.wait([first, second]);
    expect(sync.calls, 1);
  });

  test(
    'sync always clears its busy state when a collaborator throws',
    () async {
      final db = _MemoryDatabase();
      final sync = _FakeSyncService(db)..error = StateError('network');
      final controller = AppController(
        db: db,
        catalog: _FakeCatalog(const []),
        syncService: sync,
      )..autoSync = true;
      addTearDown(controller.dispose);

      await expectLater(controller.sync(), throwsStateError);

      expect(controller.syncing, isFalse);
      expect(sync.calls, 1);
    },
  );

  test(
    'updatePreferences persists every setting and controls auto-sync',
    () async {
      final db = _MemoryDatabase();
      final sync = _FakeSyncService(db);
      final controller = AppController(
        db: db,
        catalog: _FakeCatalog(const []),
        syncService: sync,
      );
      addTearDown(controller.dispose);

      await controller.updatePreferences(
        darkMode: false,
        accent: 'yellow',
        comicTitles: true,
        showStatistics: false,
        autoSync: false,
        newIssueNotifications: false,
      );
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('dark_mode'), isFalse);
      expect(prefs.getString('accent'), 'yellow');
      expect(prefs.getBool('comic_titles'), isTrue);
      expect(prefs.getBool('show_statistics'), isFalse);
      expect(prefs.getBool('auto_sync'), isFalse);
      expect(prefs.getBool('new_issue_notifications'), isFalse);
      expect(controller.syncMessage, 'Automatska sinkronizacija isključena');

      await controller.updatePreferences(autoSync: true);
      await _waitForSync(controller);
      expect(sync.calls, 1);
      expect(controller.autoSync, isTrue);
    },
  );
}

Future<void> _flush() => Future<void>.delayed(Duration.zero);

Future<void> _waitForSync(AppController controller) async {
  do {
    await _flush();
  } while (controller.syncing);
}

class _MemoryDatabase extends LocalDatabase {
  final Map<String, Comic> stored = {};
  final Map<String, String> mappings = {};
  final List<Comic> catalogSeed = [];
  List<Comic> lastReplaced = [];
  bool failUpsert = false;
  bool failReplace = false;

  List<Comic> get visible =>
      stored.values.where((comic) => !comic.deleted).toList(growable: false);

  @override
  Future<List<Comic>> all({bool includeDeleted = false}) async =>
      includeDeleted ? stored.values.toList(growable: false) : visible;

  @override
  Future<void> upsert(Comic comic) async {
    if (failUpsert) throw StateError('upsert failed');
    stored[comic.id] = comic;
  }

  @override
  Future<void> replaceAll(Iterable<Comic> comics) async {
    if (failReplace) throw StateError('replace failed');
    lastReplaced = comics.toList(growable: false);
    for (final comic in lastReplaced) {
      stored[comic.id] = comic;
    }
  }

  @override
  Future<void> upsertCatalogAll(Iterable<Comic> comics) async {
    catalogSeed.addAll(comics);
  }

  @override
  Future<Map<String, String>> barcodeMappings() async => Map.of(mappings);

  @override
  Future<void> saveBarcodeMapping(String barcode, String comicId) async {
    mappings[barcode] = comicId;
  }
}

class _FakeCatalog extends CatalogRepository {
  _FakeCatalog(this.items);

  final List<CatalogIssue> items;
  final Map<String, CatalogIssue> registered = {};
  int loadCalls = 0;
  Object? loadError;

  @override
  List<CatalogIssue> get issues => items;

  @override
  Future<void> load() async {
    loadCalls++;
    if (loadError case final error?) throw error;
  }

  @override
  CatalogIssue? byId(String id) =>
      items.where((item) => item.id == id).firstOrNull;

  @override
  void registerBarcode(String value, CatalogIssue issue) {
    final normalized = value.trim();
    if (normalized.isNotEmpty) registered[normalized] = issue;
  }
}

class _FakeSyncService extends SyncService {
  _FakeSyncService(super.db);

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

CatalogIssue _issue(String id, int number, {String? coverAsset}) =>
    CatalogIssue(
      id: id,
      sourceEdition: 'DDLU',
      series: 'Dylan Dog',
      edition: 'Regularna (L)',
      number: number,
      title: 'Broj $number',
      publisher: 'Ludens',
      coverAsset: coverAsset,
    );
