import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import '../models/comic.dart';

class LocalDatabase {
  Database? _db;

  Future<Database> get database async => _db ??= await openDatabase(
    join(await getDatabasesPath(), 'comicollect.db'),
    version: 1,
    onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
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

  Future<void> mergeRemote(Iterable<Comic> remote) async {
    final db = await database;
    await db.transaction((txn) async {
      for (final comic in remote) {
        final local = await txn.query(
          'comics',
          columns: ['updated_at'],
          where: 'id = ?',
          whereArgs: [comic.id],
          limit: 1,
        );
        if (local.isEmpty ||
            (local.first['updated_at'] as int) < comic.updatedAt) {
          await txn.insert(
            'comics',
            comic.toMap(),
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      }
    });
  }
}
