import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import '../models/comic.dart';

class LocalDatabase {
  LocalDatabase({this.pathOverride});

  final String? pathOverride;
  Database? _db;

  Future<Database> get database async => _db ??= await openDatabase(
    pathOverride ?? join(await getDatabasesPath(), 'comicollect.db'),
    version: 4,
    onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
    onCreate: (db, version) async {
      await db.execute('''CREATE TABLE comics(
        id TEXT PRIMARY KEY, series TEXT NOT NULL, edition TEXT NOT NULL,
        number INTEGER NOT NULL, title TEXT NOT NULL, publisher TEXT NOT NULL DEFAULT '',
        year INTEGER, owned INTEGER NOT NULL, is_read INTEGER NOT NULL,
        condition_grade TEXT NOT NULL, purchase_price REAL, estimated_value REAL,
        is_duplicate INTEGER NOT NULL, loaned_to TEXT NOT NULL DEFAULT '',
        notes TEXT NOT NULL DEFAULT '', cover_asset TEXT NOT NULL DEFAULT '',
        rating INTEGER NOT NULL DEFAULT 0, page_count INTEGER,
        writer TEXT NOT NULL DEFAULT '', artist TEXT NOT NULL DEFAULT '',
        deleted INTEGER NOT NULL DEFAULT 0,
        updated_at INTEGER NOT NULL)''');
      await db.execute(
        'CREATE INDEX idx_comics_series ON comics(series, edition, number)',
      );
      await db.execute('''CREATE TABLE barcode_mappings(
        barcode TEXT PRIMARY KEY, comic_id TEXT NOT NULL,
        FOREIGN KEY(comic_id) REFERENCES comics(id) ON DELETE CASCADE)''');
    },
    onUpgrade: (db, oldVersion, newVersion) async {
      if (oldVersion < 2) {
        await db.execute(
          "ALTER TABLE comics ADD COLUMN cover_asset TEXT NOT NULL DEFAULT ''",
        );
      }
      if (oldVersion < 3) {
        await db.execute('''CREATE TABLE barcode_mappings(
          barcode TEXT PRIMARY KEY, comic_id TEXT NOT NULL,
          FOREIGN KEY(comic_id) REFERENCES comics(id) ON DELETE CASCADE)''');
      }
      if (oldVersion < 4) {
        await db.execute(
          'ALTER TABLE comics ADD COLUMN rating INTEGER NOT NULL DEFAULT 0',
        );
        await db.execute('ALTER TABLE comics ADD COLUMN page_count INTEGER');
        await db.execute(
          "ALTER TABLE comics ADD COLUMN writer TEXT NOT NULL DEFAULT ''",
        );
        await db.execute(
          "ALTER TABLE comics ADD COLUMN artist TEXT NOT NULL DEFAULT ''",
        );
      }
    },
  );

  Future<List<Comic>> all({bool includeDeleted = false}) async {
    final db = await database;
    final rows = await db.query(
      'comics',
      where: includeDeleted ? null : 'deleted = 0',
      orderBy: 'series COLLATE NOCASE, edition COLLATE NOCASE, number',
    );
    return rows.map(Comic.fromMap).toList();
  }

  Future<List<Comic>> changedSince(int timestamp) async {
    final db = await database;
    final rows = await db.query(
      'comics',
      where: 'updated_at > ?',
      whereArgs: [timestamp],
    );
    return rows.map(Comic.fromMap).toList();
  }

  Future<void> upsert(Comic comic) async => (await database).insert(
    'comics',
    comic.toMap(),
    conflictAlgorithm: ConflictAlgorithm.replace,
  );

  Future<void> upsertAll(Iterable<Comic> comics) async {
    final db = await database;
    await db.transaction((txn) async {
      final batch = txn.batch();
      for (final comic in comics) {
        batch.insert(
          'comics',
          comic.toMap(),
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
      await batch.commit(noResult: true);
    });
  }

  Future<void> upsertCatalogAll(Iterable<Comic> comics) async {
    final db = await database;
    await db.transaction((txn) async {
      final batch = txn.batch();
      for (final comic in comics) {
        batch.rawInsert(
          '''INSERT INTO comics(
            id, series, edition, number, title, publisher, year, owned,
            is_read, condition_grade, purchase_price, estimated_value,
            is_duplicate, loaned_to, notes, cover_asset, deleted, updated_at
          ) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
          ON CONFLICT(id) DO UPDATE SET
            series = excluded.series,
            edition = excluded.edition,
            number = excluded.number,
            title = excluded.title,
            publisher = excluded.publisher,
            year = excluded.year,
            cover_asset = excluded.cover_asset''',
          [
            comic.id,
            comic.series,
            comic.edition,
            comic.number,
            comic.title,
            comic.publisher,
            comic.year,
            comic.owned ? 1 : 0,
            comic.read ? 1 : 0,
            comic.condition,
            comic.purchasePrice,
            comic.estimatedValue,
            comic.duplicate ? 1 : 0,
            comic.loanedTo,
            comic.notes,
            comic.coverAsset,
            comic.deleted ? 1 : 0,
            comic.updatedAt,
          ],
        );
      }
      await batch.commit(noResult: true);
    });
  }

  Future<void> replaceAll(Iterable<Comic> comics) async {
    final db = await database;
    await db.transaction((txn) async {
      final batch = txn.batch();
      for (final comic in comics) {
        batch.insert(
          'comics',
          comic.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
    });
  }

  Future<Map<String, String>> barcodeMappings() async {
    final rows = await (await database).query('barcode_mappings');
    return {
      for (final row in rows)
        row['barcode'] as String: row['comic_id'] as String,
    };
  }

  Future<void> saveBarcodeMapping(String barcode, String comicId) async {
    await (await database).insert('barcode_mappings', {
      'barcode': barcode,
      'comic_id': comicId,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> mergeRemote(Iterable<Comic> remote) async {
    final db = await database;
    await db.transaction((txn) async {
      for (final comic in remote) {
        final local = await txn.query(
          'comics',
          columns: ['updated_at', 'cover_asset'],
          where: 'id = ?',
          whereArgs: [comic.id],
          limit: 1,
        );
        if (local.isEmpty ||
            (local.first['updated_at'] as int) < comic.updatedAt) {
          final localCover = local.isEmpty
              ? ''
              : (local.first['cover_asset'] as String? ?? '');
          final merged = comic.coverAsset.isEmpty && localCover.isNotEmpty
              ? comic.copyWith(coverAsset: localCover)
              : comic;
          await txn.insert(
            'comics',
            merged.toMap(),
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      }
    });
  }

  Future<void> close() async {
    final db = _db;
    _db = null;
    await db?.close();
  }
}
