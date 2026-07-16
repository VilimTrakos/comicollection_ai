import 'dart:io';

import 'package:comicollect/data/local_database.dart';
import 'package:comicollect/models/comic.dart';
import 'package:comicollect/models/comic_copy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late LocalDatabase database;
  late int now;

  setUp(() {
    now = 10000;
    database = LocalDatabase(
      pathOverride: inMemoryDatabasePath,
      nowMilliseconds: () => now++,
    );
  });

  tearDown(() => database.close());

  test('creates the normalized version 5 schema and indexes', () async {
    final db = await database.database;

    expect(await db.getVersion(), 5);
    final tables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table'",
    );
    expect(
      tables.map((row) => row['name']),
      containsAll(<String>[
        'catalog_issues',
        'collection_entries',
        'copies',
        'barcode_mappings',
      ]),
    );
    expect(tables.map((row) => row['name']), isNot(contains('comics')));

    final columns = await db.rawQuery('PRAGMA table_info(catalog_issues)');
    expect(
      columns.map((row) => row['name']),
      containsAll(<String>[
        'origin',
        'source_edition',
        'cover_asset',
        'page_count',
        'writer',
        'artist',
        'metadata_updated_at',
      ]),
    );
    final indexes = await db.rawQuery('PRAGMA index_list(catalog_issues)');
    expect(
      indexes.map((row) => row['name']),
      contains('idx_catalog_issues_series'),
    );
    final barcodeIndexes = await db.rawQuery(
      'PRAGMA index_list(barcode_mappings)',
    );
    expect(
      barcodeIndexes.map((row) => row['name']),
      contains('idx_barcode_mappings_issue'),
    );
    final foreignKeys = await db.rawQuery('PRAGMA foreign_keys');
    expect(foreignKeys.single['foreign_keys'], 1);
    expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
    expect(
      (await db.rawQuery('PRAGMA integrity_check')).single['integrity_check'],
      'ok',
    );

    await db.insert('catalog_issues', {
      'id': 'constraint-test',
      'series': 'Dylan Dog',
      'edition': 'Test',
      'number': 1,
      'title': 'Test',
    });
    await expectLater(
      db.insert('collection_entries', {
        'issue_id': 'constraint-test',
        'owned': 2,
        'updated_at': 1,
      }),
      throwsA(isA<DatabaseException>()),
    );
  });

  test('upsert, all and changedSince preserve and filter records', () async {
    await database.upsert(_comic('z', 2, updatedAt: 20));
    await database.upsert(_comic('a', 1, updatedAt: 10));
    await database.upsert(
      _comic('deleted', 3, updatedAt: 30).copyWith(deleted: true),
    );

    expect((await database.all()).map((comic) => comic.id), ['a', 'z']);
    expect(await database.all(includeDeleted: true), hasLength(3));
    expect((await database.changedSince(10)).map((comic) => comic.id), {
      'z',
      'deleted',
    });

    await database.upsert(_comic('a', 1, title: 'Promijenjen', updatedAt: 40));
    expect((await database.all()).first.title, 'Promijenjen');
  });

  test('upsert preserves barcode mappings for an edited comic', () async {
    await database.upsert(_comic('one', 1));
    await database.saveBarcodeMapping('123', 'one');

    await database.upsert(_comic('one', 1, title: 'Promijenjen', updatedAt: 2));

    expect(await database.barcodeMappings(), {'123': 'one'});
    expect((await database.all()).single.title, 'Promijenjen');
  });

  test(
    'upsertAll ignores existing rows and inserts new rows atomically',
    () async {
      await database.upsert(_comic('one', 1, title: 'Original'));

      await database.upsertAll([
        _comic('one', 1, title: 'Ne smije prepisati'),
        _comic('two', 2),
      ]);

      final byId = {for (final comic in await database.all()) comic.id: comic};
      expect(byId['one']!.title, 'Original');
      expect(byId, contains('two'));
    },
  );

  test(
    'catalog upsert refreshes metadata but preserves collection state',
    () async {
      final owned = _comic('catalog-one', 1, title: 'Stari naslov').copyWith(
        owned: true,
        read: true,
        condition: 'VF',
        purchasePrice: 4.5,
        estimatedValue: 9,
        duplicate: true,
        loanedTo: 'Ana',
        notes: 'Moja bilješka',
        rating: 5,
        pageCount: 98,
        writer: 'Stari autor',
        artist: 'Stari crtač',
      );
      await database.upsert(owned);

      await database.upsertCatalogAll([
        _comic('catalog-one', 1, title: 'Novi naslov').copyWith(
          publisher: 'Novi izdavač',
          year: 2026,
          coverAsset: 'assets/new.webp',
        ),
      ]);

      final result = (await database.all()).single;
      expect(result.title, 'Novi naslov');
      expect(result.publisher, 'Novi izdavač');
      expect(result.year, 2026);
      expect(result.coverAsset, 'assets/new.webp');
      expect(result.owned, isTrue);
      expect(result.read, isTrue);
      expect(result.condition, 'VF');
      expect(result.purchasePrice, 4.5);
      expect(result.estimatedValue, 9);
      expect(result.duplicate, isTrue);
      expect(result.loanedTo, 'Ana');
      expect(result.notes, 'Moja bilješka');
      expect(result.rating, 5);
      expect(result.pageCount, 98);
      expect(result.writer, 'Stari autor');
      expect(result.artist, 'Stari crtač');
    },
  );

  test('replaceAll replaces existing rows and keeps unrelated rows', () async {
    await database.upsertAll([_comic('one', 1), _comic('two', 2)]);

    await database.replaceAll([
      _comic('one', 1, title: 'Zamijenjen'),
      _comic('three', 3),
    ]);

    final byId = {for (final comic in await database.all()) comic.id: comic};
    expect(byId.keys, containsAll(['one', 'two', 'three']));
    expect(byId['one']!.title, 'Zamijenjen');
  });

  test('replaceAll preserves barcode mappings for replaced comics', () async {
    await database.upsert(_comic('one', 1));
    await database.saveBarcodeMapping('123', 'one');

    await database.replaceAll([
      _comic('one', 1, title: 'Zamijenjen', updatedAt: 2),
    ]);

    expect(await database.barcodeMappings(), {'123': 'one'});
    expect((await database.all()).single.title, 'Zamijenjen');
  });

  test('barcode mappings insert, replace and cascade on delete', () async {
    await database.upsertAll([_comic('one', 1), _comic('two', 2)]);
    await database.saveBarcodeMapping('123', 'one');
    expect(await database.barcodeMappings(), {'123': 'one'});

    await database.saveBarcodeMapping('123', 'two');
    expect(await database.barcodeMappings(), {'123': 'two'});

    await (await database.database).delete(
      'catalog_issues',
      where: 'id = ?',
      whereArgs: ['two'],
    );
    expect(await database.barcodeMappings(), isEmpty);
  });

  test('barcode mapping rejects an unknown comic id', () async {
    expect(
      () => database.saveBarcodeMapping('bad', 'missing'),
      throwsA(isA<DatabaseException>()),
    );
  });

  test(
    'mergeRemote accepts only newer data and preserves a local cover',
    () async {
      await database.upsert(
        _comic(
          'one',
          1,
          title: 'Lokalno',
          updatedAt: 100,
        ).copyWith(coverAsset: 'assets/local.webp'),
      );

      await database.mergeRemote([
        _comic('one', 1, title: 'Starije', updatedAt: 99),
      ]);
      expect((await database.all()).single.title, 'Lokalno');

      await database.mergeRemote([
        _comic('one', 1, title: 'Novije', updatedAt: 101),
        _comic('two', 2, title: 'Udaljeno', updatedAt: 101),
      ]);
      final byId = {for (final comic in await database.all()) comic.id: comic};
      expect(byId['one']!.title, 'Novije');
      expect(byId['one']!.coverAsset, 'assets/local.webp');
      expect(byId['two']!.title, 'Udaljeno');

      await database.mergeRemote([
        _comic(
          'one',
          1,
          updatedAt: 102,
        ).copyWith(coverAsset: 'assets/remote.webp'),
      ]);
      expect((await database.all()).first.coverAsset, 'assets/remote.webp');
    },
  );

  test('mergeRemote preserves barcode mappings for merged comics', () async {
    await database.upsert(_comic('one', 1, updatedAt: 1));
    await database.saveBarcodeMapping('123', 'one');

    await database.mergeRemote([
      _comic('one', 1, title: 'Udaljeno', updatedAt: 2),
    ]);

    expect(await database.barcodeMappings(), {'123': 'one'});
    expect((await database.all()).single.title, 'Udaljeno');
  });

  test('catalog-only metadata never enters the user sync stream', () async {
    await database.upsertCatalogAll([
      _comic('catalog-DDLU-1', 1, title: 'Katalog', updatedAt: 500),
    ]);

    expect(await database.all(), hasLength(1));
    expect(await database.collectionEntry('catalog-DDLU-1'), isNull);
    expect(await database.changedSince(0), isEmpty);

    await database.upsert(
      _comic(
        'catalog-DDLU-1',
        1,
        title: 'Katalog',
        updatedAt: 501,
      ).copyWith(owned: true),
    );

    expect((await database.changedSince(500)).single.id, 'catalog-DDLU-1');
  });

  test('user-state writes cannot overwrite bundled catalog metadata', () async {
    await database.upsertCatalogAll([
      _comic(
        'catalog-DDLU-1',
        1,
        title: 'Službeni naslov',
        updatedAt: 10,
      ).copyWith(coverAsset: 'assets/official.webp'),
    ]);

    await database.upsert(
      _comic(
        'catalog-DDLU-1',
        1,
        title: 'Zastarjeli naslov',
        updatedAt: 20,
      ).copyWith(owned: true, coverAsset: 'assets/stale.webp'),
    );

    final result = (await database.all()).single;
    expect(result.title, 'Službeni naslov');
    expect(result.coverAsset, 'assets/official.webp');
    expect(result.owned, isTrue);
  });

  test(
    'copy-aware writes update aggregate state and preserve copy details',
    () async {
      await database.upsert(
        _comic(
          'one',
          1,
          updatedAt: 1,
        ).copyWith(owned: true, condition: 'VF', purchasePrice: 4),
      );
      await database.saveCopy(
        const ComicCopy(
          id: 'one-copy-2',
          issueId: 'one',
          ordinal: 1,
          condition: 'G',
          estimatedValue: 8,
          updatedAt: 2,
        ),
      );

      var entry = await database.collectionEntry('one');
      var copies = await database.copiesForIssue('one');
      expect(entry!.owned, isTrue);
      expect(entry.duplicate, isTrue);
      expect(copies, hasLength(2));
      expect(copies[0].condition, 'VF');
      expect(copies[1].condition, 'G');
      expect((await database.all()).single.duplicate, isTrue);

      await database.saveCopy(
        copies[1].copyWith(active: false, deleted: true, updatedAt: 3),
      );
      entry = await database.collectionEntry('one');
      expect(entry!.owned, isTrue);
      expect(entry.duplicate, isFalse);

      copies = await database.copiesForIssue('one');
      await database.saveCopy(
        copies[0].copyWith(active: false, deleted: true, updatedAt: 4),
      );
      entry = await database.collectionEntry('one');
      expect(entry!.owned, isFalse);
      expect(entry.wanted, isTrue);
      final aggregate = (await database.all()).single;
      expect(aggregate.owned, isFalse);
      expect(aggregate.condition, 'VF');
      expect(aggregate.purchasePrice, 4);
    },
  );

  test(
    'copy writes use active details and keep collection timestamps monotonic',
    () async {
      await database.upsert(
        _comic('one', 1, updatedAt: 500).copyWith(owned: true, condition: 'VF'),
      );
      await database.saveCopy(
        const ComicCopy(
          id: 'one-copy-2',
          issueId: 'one',
          ordinal: 1,
          condition: 'G',
          updatedAt: 1,
        ),
      );
      final firstTimestamp = (await database.collectionEntry('one'))!.updatedAt;

      final primary = (await database.copiesForIssue('one')).first;
      await database.saveCopy(
        primary.copyWith(active: false, deleted: true, updatedAt: 1),
      );

      final aggregate = (await database.all()).single;
      final secondTimestamp = (await database.collectionEntry(
        'one',
      ))!.updatedAt;
      expect(aggregate.owned, isTrue);
      expect(aggregate.condition, 'G');
      expect(secondTimestamp, greaterThan(firstTimestamp));
      expect((await database.changedSince(firstTimestamp)).single.id, 'one');
    },
  );

  test(
    'copy natural key survives aggregate writes and revives a tombstone',
    () async {
      await database.upsertCatalogAll([_comic('one', 1)]);
      await database.saveCopy(
        const ComicCopy(
          id: 'uuid-primary',
          issueId: 'one',
          ordinal: 0,
          condition: 'VF',
          updatedAt: 1,
        ),
      );

      final aggregate = (await database.all()).single;
      await database.upsert(
        aggregate.copyWith(deleted: true, updatedAt: 20000),
      );
      expect(await database.all(), isEmpty);

      final deletedCopy = (await database.copiesForIssue('one')).single;
      expect(deletedCopy.id, 'uuid-primary');
      await database.saveCopy(
        deletedCopy.copyWith(active: true, deleted: false, updatedAt: 2),
      );

      expect((await database.all()).single.owned, isTrue);
      expect((await database.collectionEntry('one'))!.deleted, isFalse);
      expect((await database.copiesForIssue('one')).single.id, 'uuid-primary');
    },
  );

  test('migrates an exact version 4 database without user data loss', () async {
    final path =
        '${Directory.systemTemp.path}/comicollect-v4-migration-${DateTime.now().microsecondsSinceEpoch}.db';
    final old = await _createVersion4Fixture(path);
    await old.close();

    final migrated = LocalDatabase(pathOverride: path);
    addTearDown(() async {
      await migrated.close();
      await databaseFactoryFfi.deleteDatabase(path);
    });

    final db = await migrated.database;
    expect(await db.getVersion(), 5);
    expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
    expect(
      (await db.rawQuery('PRAGMA integrity_check')).single['integrity_check'],
      'ok',
    );

    final byId = {
      for (final comic in await migrated.all(includeDeleted: true))
        comic.id: comic,
    };
    final owned = byId['catalog-DDLU-61']!;
    expect(owned.title, 'Nesmiljeni Hook');
    expect(owned.owned, isTrue);
    expect(owned.read, isTrue);
    expect(owned.condition, 'VF');
    expect(owned.purchasePrice, 4.5);
    expect(owned.estimatedValue, 9);
    expect(owned.duplicate, isTrue);
    expect(owned.loanedTo, 'Ana');
    expect(owned.notes, 'Moja bilješka');
    expect(owned.coverAsset, 'assets/61.webp');
    expect(owned.rating, 5);
    expect(owned.pageCount, 98);
    expect(owned.writer, 'Sclavi');
    expect(owned.artist, 'Stano');
    expect(owned.updatedAt, 1234);

    final ownedCopies = await migrated.copiesForIssue(owned.id);
    expect(ownedCopies.map((copy) => copy.ordinal), [0, 1]);
    expect(ownedCopies.first.condition, 'VF');
    expect(ownedCopies.first.purchasePrice, 4.5);
    expect(ownedCopies.last.condition, isEmpty);
    expect(ownedCopies.last.purchasePrice, isNull);

    expect(await migrated.collectionEntry('catalog-DDLU-62'), isNull);
    expect(byId['catalog-DDLU-62']!.owned, isFalse);

    final custom = byId['manual-1']!;
    expect(custom.owned, isFalse);
    expect(custom.condition, isEmpty);
    expect(custom.notes, 'Ručno dodan');
    expect((await migrated.collectionEntry(custom.id))!.wanted, isTrue);
    expect((await migrated.copiesForIssue(custom.id)).single.active, isFalse);

    expect(byId['manual-deleted']!.deleted, isTrue);
    expect(
      (await migrated.all()).map((comic) => comic.id),
      isNot(contains('manual-deleted')),
    );
    expect(await migrated.barcodeMappings(), {' 978123 ': owned.id});

    final origins = await db.query(
      'catalog_issues',
      columns: ['id', 'origin'],
      orderBy: 'id',
    );
    final originById = {for (final row in origins) row['id']: row['origin']};
    expect(originById[owned.id], 'bundled');
    expect(originById[custom.id], 'custom');

    await migrated.close();
    final reopened = await migrated.database;
    expect(await reopened.getVersion(), 5);
    expect(await reopened.query('catalog_issues'), hasLength(4));
    expect(await reopened.query('copies'), hasLength(4));
  });

  test('failed version 4 migration rolls the complete schema back', () async {
    final path =
        '${Directory.systemTemp.path}/comicollect-v4-rollback-${DateTime.now().microsecondsSinceEpoch}.db';
    final old = await _createVersion4Fixture(path);
    await old.insert('comics', {
      'id': '',
      'series': 'Neispravno',
      'edition': '',
      'number': 9,
      'title': 'Bez identifikatora',
      'owned': 0,
      'is_read': 0,
      'condition_grade': 'F',
      'is_duplicate': 0,
      'updated_at': 1500,
    });
    await old.close();

    final broken = LocalDatabase(pathOverride: path);
    await expectLater(broken.database, throwsStateError);
    await broken.close();

    final restored = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(version: 4),
    );
    addTearDown(() async {
      await restored.close();
      await databaseFactoryFfi.deleteDatabase(path);
    });

    expect(await restored.getVersion(), 4);
    final tables = await restored.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table'",
    );
    expect(tables.map((row) => row['name']), contains('comics'));
    expect(tables.map((row) => row['name']), contains('barcode_mappings'));
    expect(tables.map((row) => row['name']), isNot(contains('catalog_issues')));
    expect(await restored.query('comics'), hasLength(5));
    expect(await restored.query('barcode_mappings'), hasLength(1));
  });

  test('migrates a version 1 database through every schema upgrade', () async {
    final path =
        '${Directory.systemTemp.path}/comicollect-migration-${DateTime.now().microsecondsSinceEpoch}.db';
    final old = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, version) async {
          await db.execute('''CREATE TABLE comics(
            id TEXT PRIMARY KEY, series TEXT NOT NULL, edition TEXT NOT NULL,
            number INTEGER NOT NULL, title TEXT NOT NULL, publisher TEXT NOT NULL DEFAULT '',
            year INTEGER, owned INTEGER NOT NULL, is_read INTEGER NOT NULL,
            condition_grade TEXT NOT NULL, purchase_price REAL, estimated_value REAL,
            is_duplicate INTEGER NOT NULL, loaned_to TEXT NOT NULL DEFAULT '',
            notes TEXT NOT NULL DEFAULT '', deleted INTEGER NOT NULL DEFAULT 0,
            updated_at INTEGER NOT NULL)''');
          await db.execute(
            'CREATE INDEX idx_comics_series ON comics(series, edition, number)',
          );
          await db.insert('comics', {
            'id': 'legacy',
            'series': 'Dylan Dog',
            'edition': 'Extra',
            'number': 1,
            'title': 'Naslijeđeni zapis',
            'owned': 1,
            'is_read': 0,
            'condition_grade': 'F',
            'is_duplicate': 0,
            'updated_at': 1,
          });
        },
      ),
    );
    await old.close();

    final migrated = LocalDatabase(pathOverride: path);
    addTearDown(() async {
      await migrated.close();
      await databaseFactoryFfi.deleteDatabase(path);
    });
    final db = await migrated.database;

    expect(await db.getVersion(), 5);
    final comic = (await migrated.all()).single;
    expect(comic.id, 'legacy');
    expect(comic.coverAsset, isEmpty);
    expect(comic.rating, 0);
    expect(comic.pageCount, isNull);
    expect(comic.writer, isEmpty);
    expect(comic.artist, isEmpty);
    expect(await migrated.barcodeMappings(), isEmpty);
  });

  test('close is safe before opening and can reopen the database', () async {
    await database.close();
    await database.upsert(_comic('one', 1));
    expect(await database.all(), hasLength(1));
    await database.close();
  });
}

Comic _comic(String id, int number, {String? title, int updatedAt = 1}) =>
    Comic(
      id: id,
      series: 'Dylan Dog',
      edition: 'Regularna (L)',
      number: number,
      title: title ?? 'Broj $number',
      publisher: 'Ludens',
      owned: false,
      read: false,
      condition: 'F',
      updatedAt: updatedAt,
    );

Future<Database> _createVersion4Fixture(String path) =>
    databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 4,
        onCreate: (db, version) async {
          await db.execute('''CREATE TABLE comics(
            id TEXT PRIMARY KEY, series TEXT NOT NULL, edition TEXT NOT NULL,
            number INTEGER NOT NULL, title TEXT NOT NULL,
            publisher TEXT NOT NULL DEFAULT '', year INTEGER,
            owned INTEGER NOT NULL, is_read INTEGER NOT NULL,
            condition_grade TEXT NOT NULL, purchase_price REAL,
            estimated_value REAL, is_duplicate INTEGER NOT NULL,
            loaned_to TEXT NOT NULL DEFAULT '', notes TEXT NOT NULL DEFAULT '',
            cover_asset TEXT NOT NULL DEFAULT '', rating INTEGER NOT NULL DEFAULT 0,
            page_count INTEGER, writer TEXT NOT NULL DEFAULT '',
            artist TEXT NOT NULL DEFAULT '', deleted INTEGER NOT NULL DEFAULT 0,
            updated_at INTEGER NOT NULL)''');
          await db.execute(
            'CREATE INDEX idx_comics_series ON comics(series, edition, number)',
          );
          await db.execute('''CREATE TABLE barcode_mappings(
            barcode TEXT PRIMARY KEY, comic_id TEXT NOT NULL,
            FOREIGN KEY(comic_id) REFERENCES comics(id) ON DELETE CASCADE)''');

          await db.insert('comics', {
            'id': 'catalog-DDLU-61',
            'series': 'Dylan Dog',
            'edition': 'Regularna (L)',
            'number': 61,
            'title': 'Nesmiljeni Hook',
            'publisher': 'Ludens',
            'year': 2002,
            'owned': 1,
            'is_read': 1,
            'condition_grade': 'VF',
            'purchase_price': 4.5,
            'estimated_value': 9,
            'is_duplicate': 1,
            'loaned_to': 'Ana',
            'notes': 'Moja bilješka',
            'cover_asset': 'assets/61.webp',
            'rating': 5,
            'page_count': 98,
            'writer': 'Sclavi',
            'artist': 'Stano',
            'deleted': 0,
            'updated_at': 1234,
          });
          await db.insert('comics', {
            'id': 'catalog-DDLU-62',
            'series': 'Dylan Dog',
            'edition': 'Regularna (L)',
            'number': 62,
            'title': 'Katalog bez stanja',
            'publisher': 'Ludens',
            'owned': 0,
            'is_read': 0,
            'condition_grade': 'F',
            'is_duplicate': 0,
            'notes': 'BSP katalog · DDLU',
            'updated_at': 1234,
          });
          await db.insert('comics', {
            'id': 'manual-1',
            'series': 'Zagor',
            'edition': 'Custom',
            'number': 1,
            'title': 'Ručno izdanje',
            'owned': 0,
            'is_read': 0,
            'condition_grade': '',
            'is_duplicate': 0,
            'notes': 'Ručno dodan',
            'updated_at': 1300,
          });
          await db.insert('comics', {
            'id': 'manual-deleted',
            'series': 'Zagor',
            'edition': 'Custom',
            'number': 2,
            'title': 'Obrisan',
            'owned': 1,
            'is_read': 0,
            'condition_grade': 'F',
            'is_duplicate': 0,
            'deleted': 1,
            'updated_at': 1400,
          });
          await db.insert('barcode_mappings', {
            'barcode': ' 978123 ',
            'comic_id': 'catalog-DDLU-61',
          });
        },
      ),
    );
