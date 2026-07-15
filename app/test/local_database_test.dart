import 'dart:io';

import 'package:comicollect/data/local_database.dart';
import 'package:comicollect/models/comic.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late LocalDatabase database;

  setUp(() {
    database = LocalDatabase(pathOverride: inMemoryDatabasePath);
  });

  tearDown(() => database.close());

  test('creates the complete version 4 schema and indexes', () async {
    final db = await database.database;

    expect(await db.getVersion(), 4);
    final columns = await db.rawQuery('PRAGMA table_info(comics)');
    expect(
      columns.map((row) => row['name']),
      containsAll(<String>[
        'cover_asset',
        'rating',
        'page_count',
        'writer',
        'artist',
        'deleted',
        'updated_at',
      ]),
    );
    final indexes = await db.rawQuery('PRAGMA index_list(comics)');
    expect(indexes.map((row) => row['name']), contains('idx_comics_series'));
    final foreignKeys = await db.rawQuery('PRAGMA foreign_keys');
    expect(foreignKeys.single['foreign_keys'], 1);
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
      'comics',
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

    expect(await db.getVersion(), 4);
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
