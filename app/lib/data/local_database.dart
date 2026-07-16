import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import '../models/collection_entry.dart';
import '../models/comic.dart';
import '../models/comic_copy.dart';
import 'database_schema.dart';

class LocalDatabase {
  LocalDatabase({this.pathOverride, int Function()? nowMilliseconds})
    : _nowMilliseconds =
          nowMilliseconds ?? (() => DateTime.now().millisecondsSinceEpoch);

  final String? pathOverride;
  final int Function() _nowMilliseconds;
  Database? _db;

  Future<Database> get database async => _db ??= await openDatabase(
    pathOverride ?? join(await getDatabasesPath(), 'comicollect.db'),
    version: schemaVersion,
    onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
    onCreate: (db, version) => createV5Schema(db),
    onUpgrade: migrateLegacySchemaToV5,
  );

  Future<List<Comic>> all({bool includeDeleted = false}) async {
    final rows = await (await database).rawQuery('''$_comicProjection
      ${includeDeleted ? '' : 'WHERE entry.deleted IS NULL OR entry.deleted = 0'}
      ORDER BY issue.series COLLATE NOCASE,
               issue.edition COLLATE NOCASE,
               issue.number''');
    return rows.map(Comic.fromMap).toList(growable: false);
  }

  /// Returns only user-state mutations. Catalog-only rows deliberately never
  /// enter the sync stream.
  Future<List<Comic>> changedSince(int timestamp) async {
    final rows = await (await database).rawQuery(
      '''$_comicProjection
      WHERE entry.updated_at > ?
      ORDER BY entry.updated_at, issue.id''',
      [timestamp],
    );
    return rows.map(Comic.fromMap).toList(growable: false);
  }

  Future<void> upsert(Comic comic) async {
    final db = await database;
    await db.transaction((transaction) => _upsertComic(transaction, comic));
  }

  /// Insert-only compatibility API used by imports that must not overwrite an
  /// issue already known to the local catalog.
  Future<void> upsertAll(Iterable<Comic> comics) async {
    final db = await database;
    await db.transaction((transaction) async {
      for (final comic in comics) {
        final existing = await transaction.query(
          'catalog_issues',
          columns: ['id'],
          where: 'id = ?',
          whereArgs: [comic.id],
          limit: 1,
        );
        if (existing.isEmpty) await _upsertComic(transaction, comic);
      }
    });
  }

  /// Refreshes immutable catalog metadata without touching user state or
  /// physical-copy details.
  Future<void> upsertCatalogAll(Iterable<Comic> comics) async {
    final db = await database;
    await db.transaction((transaction) async {
      for (final comic in comics) {
        await _upsertIssueMetadata(
          transaction,
          comic,
          origin: 'bundled',
          preservePersonalMetadata: true,
        );
      }
    });
  }

  Future<void> replaceAll(Iterable<Comic> comics) async {
    final db = await database;
    await db.transaction((transaction) async {
      for (final comic in comics) {
        await _upsertComic(transaction, comic);
      }
    });
  }

  Future<CollectionEntry?> collectionEntry(String issueId) async {
    final rows = await (await database).query(
      'collection_entries',
      where: 'issue_id = ?',
      whereArgs: [issueId],
      limit: 1,
    );
    return rows.isEmpty ? null : CollectionEntry.fromMap(rows.single);
  }

  Future<List<ComicCopy>> copiesForIssue(String issueId) async {
    final rows = await (await database).query(
      'copies',
      where: 'issue_id = ?',
      whereArgs: [issueId],
      orderBy: 'ordinal',
    );
    return rows.map(ComicCopy.fromMap).toList(growable: false);
  }

  /// Copy-aware API for the next UI layer. The legacy aggregate flags are kept
  /// in sync so current screens continue to behave exactly as before.
  Future<void> saveCopy(ComicCopy copy) async {
    final db = await database;
    await db.transaction((transaction) async {
      final currentRows = await transaction.query(
        'collection_entries',
        where: 'issue_id = ?',
        whereArgs: [copy.issueId],
        limit: 1,
      );
      final existingEntry = currentRows.isEmpty
          ? null
          : CollectionEntry.fromMap(currentRows.single);
      final updatedAt = _monotonicTimestamp(
        requested: copy.updatedAt,
        previous: existingEntry?.updatedAt,
        now: _nowMilliseconds(),
      );
      await _upsertCopy(transaction, copy.copyWith(updatedAt: updatedAt));
      final counts = await transaction.rawQuery(
        '''SELECT COUNT(*) AS active_count
           FROM copies
           WHERE issue_id = ? AND active = 1 AND deleted = 0''',
        [copy.issueId],
      );
      final activeCount = (counts.single['active_count'] as num).toInt();
      final revived = activeCount > 0;
      final deleted = revived ? false : existingEntry?.deleted ?? false;
      final current = existingEntry == null
          ? CollectionEntry(
              issueId: copy.issueId,
              owned: revived,
              wanted: !revived && !deleted,
              duplicate: activeCount > 1,
              deleted: deleted,
              updatedAt: updatedAt,
            )
          : existingEntry.copyWith(
              owned: revived,
              wanted: !revived && !deleted,
              duplicate: activeCount > 1,
              deleted: deleted,
              updatedAt: updatedAt,
            );
      await _upsertCollectionEntry(transaction, current);
    });
  }

  Future<Map<String, String>> barcodeMappings() async {
    final rows = await (await database).query('barcode_mappings');
    return {
      for (final row in rows)
        row['barcode'] as String: row['issue_id'] as String,
    };
  }

  Future<void> saveBarcodeMapping(String barcode, String comicId) async {
    final db = await database;
    await db.transaction((transaction) async {
      await transaction.insert('barcode_mappings', {
        'barcode': barcode,
        'issue_id': comicId,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
      final updated = await transaction.update(
        'barcode_mappings',
        {'issue_id': comicId},
        where: 'barcode = ?',
        whereArgs: [barcode],
      );
      if (updated != 1) {
        throw StateError('Barcode $barcode could not be persisted.');
      }
    });
  }

  Future<void> mergeRemote(Iterable<Comic> remote) async {
    final db = await database;
    await db.transaction((transaction) async {
      for (final comic in remote) {
        final localState = await transaction.rawQuery(
          '''SELECT entry.updated_at, issue.cover_asset
             FROM catalog_issues issue
             LEFT JOIN collection_entries entry ON entry.issue_id = issue.id
             WHERE issue.id = ?
             LIMIT 1''',
          [comic.id],
        );
        final localUpdatedAt = localState.isEmpty
            ? null
            : (localState.single['updated_at'] as num?)?.toInt();
        if (localUpdatedAt == null || localUpdatedAt < comic.updatedAt) {
          final localCover = localState.isEmpty
              ? ''
              : (localState.single['cover_asset'] as String? ?? '');
          final merged = comic.coverAsset.isEmpty && localCover.isNotEmpty
              ? comic.copyWith(coverAsset: localCover)
              : comic;
          await _upsertComic(transaction, merged);
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

const _comicProjection = '''
  SELECT issue.id,
         issue.series,
         issue.edition,
         issue.number,
         issue.title,
         issue.publisher,
         issue.year,
         COALESCE(entry.owned, 0) AS owned,
         COALESCE(entry.is_read, 0) AS is_read,
         COALESCE(primary_copy.condition_grade, 'F') AS condition_grade,
         primary_copy.purchase_price,
         primary_copy.estimated_value,
         COALESCE(entry.is_duplicate, 0) AS is_duplicate,
         COALESCE(primary_copy.loaned_to, '') AS loaned_to,
         COALESCE(entry.notes, '') AS notes,
         issue.cover_asset,
         COALESCE(entry.rating, 0) AS rating,
         issue.page_count,
         issue.writer,
         issue.artist,
         COALESCE(entry.deleted, 0) AS deleted,
         COALESCE(entry.updated_at, 0) AS updated_at
  FROM catalog_issues issue
  LEFT JOIN collection_entries entry ON entry.issue_id = issue.id
  LEFT JOIN copies primary_copy
    ON primary_copy.id = (
      SELECT selected_copy.id
      FROM copies selected_copy
      WHERE selected_copy.issue_id = issue.id
      ORDER BY CASE
                 WHEN selected_copy.active = 1 AND selected_copy.deleted = 0
                   THEN 0
                 ELSE 1
               END,
               selected_copy.ordinal
      LIMIT 1
    )
''';

Future<void> _upsertComic(DatabaseExecutor database, Comic comic) async {
  await _upsertIssueMetadata(
    database,
    comic,
    origin: 'custom',
    preservePersonalMetadata: false,
  );
  await _upsertCollectionEntry(
    database,
    CollectionEntry(
      issueId: comic.id,
      owned: comic.owned,
      wanted: !comic.owned && !comic.deleted,
      read: comic.read,
      duplicate: comic.duplicate,
      rating: comic.rating,
      notes: comic.notes,
      deleted: comic.deleted,
      updatedAt: comic.updatedAt,
    ),
  );
  await _upsertCopy(
    database,
    ComicCopy(
      id: migratedCopyId(comic.id, 0),
      issueId: comic.id,
      ordinal: 0,
      active: comic.owned && !comic.deleted,
      condition: comic.condition,
      purchasePrice: comic.purchasePrice,
      estimatedValue: comic.estimatedValue,
      loanedTo: comic.loanedTo,
      deleted: comic.deleted,
      updatedAt: comic.updatedAt,
    ),
  );
  if (comic.duplicate) {
    final existing = await database.query(
      'copies',
      where: 'issue_id = ? AND ordinal = 1',
      whereArgs: [comic.id],
      limit: 1,
    );
    final secondary = existing.isEmpty
        ? ComicCopy(
            id: migratedCopyId(comic.id, 1),
            issueId: comic.id,
            ordinal: 1,
            active: comic.owned && !comic.deleted,
            deleted: comic.deleted,
            updatedAt: comic.updatedAt,
          )
        : ComicCopy.fromMap(existing.single).copyWith(
            active: comic.owned && !comic.deleted,
            deleted: comic.deleted,
            updatedAt: comic.updatedAt,
          );
    await _upsertCopy(database, secondary);
  } else {
    await database.update(
      'copies',
      {'active': 0, 'deleted': 1, 'updated_at': comic.updatedAt},
      where: 'issue_id = ? AND ordinal > 0',
      whereArgs: [comic.id],
    );
  }
  if (comic.deleted) {
    await database.update(
      'copies',
      {'active': 0, 'deleted': 1, 'updated_at': comic.updatedAt},
      where: 'issue_id = ?',
      whereArgs: [comic.id],
    );
  }
}

Future<void> _upsertIssueMetadata(
  DatabaseExecutor database,
  Comic comic, {
  required String origin,
  required bool preservePersonalMetadata,
}) async {
  final existing = await database.query(
    'catalog_issues',
    columns: ['origin'],
    where: 'id = ?',
    whereArgs: [comic.id],
    limit: 1,
  );
  if (origin == 'custom' &&
      existing.isNotEmpty &&
      existing.single['origin'] == 'bundled') {
    return;
  }
  final sourceEdition = _sourceEdition(comic.id);
  await database.insert('catalog_issues', {
    'id': comic.id,
    'origin': origin,
    'source_edition': sourceEdition,
    'series': comic.series,
    'edition': comic.edition,
    'number': comic.number,
    'title': comic.title,
    'publisher': comic.publisher,
    'year': comic.year,
    'cover_asset': comic.coverAsset,
    'page_count': comic.pageCount,
    'writer': comic.writer,
    'artist': comic.artist,
    'metadata_updated_at': comic.updatedAt,
  }, conflictAlgorithm: ConflictAlgorithm.ignore);

  final values = <String, Object?>{
    'series': comic.series,
    'edition': comic.edition,
    'number': comic.number,
    'title': comic.title,
    'publisher': comic.publisher,
    'metadata_updated_at': comic.updatedAt,
  };
  if (origin == 'bundled') {
    values
      ..['origin'] = 'bundled'
      ..['source_edition'] = sourceEdition;
  }
  if (comic.year != null || !preservePersonalMetadata) {
    values['year'] = comic.year;
  }
  if (comic.coverAsset.isNotEmpty || !preservePersonalMetadata) {
    values['cover_asset'] = comic.coverAsset;
  }
  if (!preservePersonalMetadata || comic.pageCount != null) {
    values['page_count'] = comic.pageCount;
  }
  if (!preservePersonalMetadata || comic.writer.isNotEmpty) {
    values['writer'] = comic.writer;
  }
  if (!preservePersonalMetadata || comic.artist.isNotEmpty) {
    values['artist'] = comic.artist;
  }
  final updated = await database.update(
    'catalog_issues',
    values,
    where: 'id = ?',
    whereArgs: [comic.id],
  );
  if (updated != 1) {
    throw StateError('Catalog issue ${comic.id} could not be persisted.');
  }
}

Future<void> _upsertCollectionEntry(
  DatabaseExecutor database,
  CollectionEntry entry,
) async {
  await database.insert(
    'collection_entries',
    entry.toMap(),
    conflictAlgorithm: ConflictAlgorithm.ignore,
  );
  final values = Map<String, Object?>.from(entry.toMap())..remove('issue_id');
  final updated = await database.update(
    'collection_entries',
    values,
    where: 'issue_id = ?',
    whereArgs: [entry.issueId],
  );
  if (updated != 1) {
    throw StateError(
      'Collection entry ${entry.issueId} could not be persisted.',
    );
  }
}

Future<void> _upsertCopy(DatabaseExecutor database, ComicCopy copy) async {
  final byId = await database.query(
    'copies',
    columns: ['id'],
    where: 'id = ?',
    whereArgs: [copy.id],
    limit: 1,
  );
  final byOrdinal = byId.isEmpty
      ? await database.query(
          'copies',
          columns: ['id'],
          where: 'issue_id = ? AND ordinal = ?',
          whereArgs: [copy.issueId, copy.ordinal],
          limit: 1,
        )
      : byId;
  if (byOrdinal.isEmpty) {
    await database.insert('copies', copy.toMap());
    return;
  }

  // `(issue_id, ordinal)` is the stable physical position. Preserve the
  // already-persisted id when the compatibility Comic API addresses a copy
  // using its deterministic legacy id.
  final persistedId = byOrdinal.single['id'] as String;
  final values = Map<String, Object?>.from(copy.toMap())..remove('id');
  final updated = await database.update(
    'copies',
    values,
    where: 'id = ?',
    whereArgs: [persistedId],
  );
  if (updated != 1) {
    throw StateError('Copy ${copy.id} could not be persisted.');
  }
}

int _monotonicTimestamp({
  required int requested,
  required int? previous,
  required int now,
}) {
  var result = requested > now ? requested : now;
  if (previous != null && result <= previous) result = previous + 1;
  return result;
}

String _sourceEdition(String issueId) {
  final match = RegExp(r'^catalog-([^-]+)-').firstMatch(issueId);
  return match?.group(1) ?? '';
}
