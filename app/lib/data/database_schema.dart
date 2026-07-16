import 'package:sqflite/sqflite.dart';

/// Current local database schema.
///
/// Version 5 separates immutable catalogue metadata from user collection state
/// and physical copies.  [createV5Schema] is deliberately shared by fresh
/// database creation and legacy migration so both paths produce identical
/// tables, indexes and foreign keys.
const int schemaVersion = 5;

const String bundledOrigin = 'bundled';
const String customOrigin = 'custom';

/// Creates an empty version 5 schema.
///
/// Only SQLite features available on the application's oldest supported
/// Android version are used here.  In particular, writes do not depend on the
/// newer UPSERT or RETURNING syntax.
Future<void> createV5Schema(DatabaseExecutor db) async {
  await db.execute('''
    CREATE TABLE IF NOT EXISTS catalog_issues(
      id TEXT PRIMARY KEY NOT NULL,
      series TEXT NOT NULL,
      edition TEXT NOT NULL,
      number INTEGER NOT NULL,
      title TEXT NOT NULL,
      publisher TEXT NOT NULL DEFAULT '',
      year INTEGER,
      cover_asset TEXT NOT NULL DEFAULT '',
      page_count INTEGER,
      writer TEXT NOT NULL DEFAULT '',
      artist TEXT NOT NULL DEFAULT '',
      origin TEXT NOT NULL DEFAULT '$customOrigin'
        CHECK(origin IN ('$bundledOrigin', '$customOrigin')),
      source_edition TEXT NOT NULL DEFAULT '',
      metadata_updated_at INTEGER NOT NULL DEFAULT 0
    )
  ''');
  await db.execute('''
    CREATE INDEX IF NOT EXISTS idx_catalog_issues_series
    ON catalog_issues(series, edition, number)
  ''');
  await db.execute('''
    CREATE INDEX IF NOT EXISTS idx_catalog_issues_source
    ON catalog_issues(source_edition, number)
  ''');

  await db.execute('''
    CREATE TABLE IF NOT EXISTS collection_entries(
      issue_id TEXT PRIMARY KEY NOT NULL,
      owned INTEGER NOT NULL DEFAULT 0 CHECK(owned IN (0, 1)),
      is_wanted INTEGER NOT NULL DEFAULT 0 CHECK(is_wanted IN (0, 1)),
      is_read INTEGER NOT NULL DEFAULT 0 CHECK(is_read IN (0, 1)),
      is_duplicate INTEGER NOT NULL DEFAULT 0
        CHECK(is_duplicate IN (0, 1)),
      rating INTEGER NOT NULL DEFAULT 0 CHECK(rating BETWEEN 0 AND 5),
      notes TEXT NOT NULL DEFAULT '',
      deleted INTEGER NOT NULL DEFAULT 0 CHECK(deleted IN (0, 1)),
      updated_at INTEGER NOT NULL,
      FOREIGN KEY(issue_id) REFERENCES catalog_issues(id) ON DELETE CASCADE
    )
  ''');
  await db.execute('''
    CREATE INDEX IF NOT EXISTS idx_collection_entries_updated
    ON collection_entries(updated_at)
  ''');

  await db.execute('''
    CREATE TABLE IF NOT EXISTS copies(
      id TEXT PRIMARY KEY NOT NULL,
      issue_id TEXT NOT NULL,
      ordinal INTEGER NOT NULL CHECK(ordinal >= 0),
      active INTEGER NOT NULL DEFAULT 1 CHECK(active IN (0, 1)),
      condition_grade TEXT NOT NULL DEFAULT 'F',
      purchase_price REAL,
      estimated_value REAL,
      loaned_to TEXT NOT NULL DEFAULT '',
      deleted INTEGER NOT NULL DEFAULT 0 CHECK(deleted IN (0, 1)),
      updated_at INTEGER NOT NULL,
      UNIQUE(issue_id, ordinal),
      FOREIGN KEY(issue_id) REFERENCES catalog_issues(id) ON DELETE CASCADE
    )
  ''');
  await db.execute('''
    CREATE INDEX IF NOT EXISTS idx_copies_issue_active
    ON copies(issue_id, active, ordinal)
  ''');

  await db.execute('''
    CREATE TABLE IF NOT EXISTS barcode_mappings(
      barcode TEXT PRIMARY KEY NOT NULL,
      issue_id TEXT NOT NULL,
      FOREIGN KEY(issue_id) REFERENCES catalog_issues(id) ON DELETE CASCADE
    )
  ''');
  await db.execute('''
    CREATE INDEX IF NOT EXISTS idx_barcode_mappings_issue
    ON barcode_mappings(issue_id)
  ''');
}

/// Migrates any supported legacy `comics` schema (versions 1 through 4) to
/// version 5 without relying on the incremental legacy ALTER TABLE steps.
///
/// The caller is expected to invoke this from sqflite's `onUpgrade`, which
/// provides the surrounding transaction.  Legacy rows are read before their
/// tables are removed, then normalized into catalogue metadata, collection
/// state and physical copies.  Catalogue rows that contain only bundled seed
/// defaults intentionally do not get a collection entry; this prevents the
/// bundled catalogue from becoming user data or entering incremental sync.
Future<void> migrateLegacySchemaToV5(
  DatabaseExecutor db,
  int oldVersion, [
  int newVersion = schemaVersion,
]) async {
  if (oldVersion >= schemaVersion || newVersion < schemaVersion) return;
  if (oldVersion < 1 || oldVersion > 4) {
    throw StateError('Unsupported local database version: $oldVersion');
  }
  if (!await _tableExists(db, 'comics')) {
    throw StateError('Legacy comics table is missing.');
  }

  final legacyComics = await db.query('comics');
  final legacyBarcodes = await _readLegacyBarcodes(db);

  // The legacy table references `comics`, while v5 references
  // `catalog_issues`. Drop the child table before creating its replacement.
  if (await _tableExists(db, 'barcode_mappings')) {
    await db.execute('DROP TABLE barcode_mappings');
  }

  await createV5Schema(db);

  for (final row in legacyComics) {
    await _migrateLegacyComic(db, row);
  }
  for (final mapping in legacyBarcodes) {
    final barcode = mapping['barcode'];
    final issueId = mapping['issue_id'];
    if (barcode is! String || issueId is! String) {
      throw StateError('A legacy barcode mapping is malformed.');
    }
    await db.insert('barcode_mappings', {
      'barcode': barcode,
      'issue_id': issueId,
    });
  }

  await db.execute('DROP TABLE comics');
}

/// Stable identifier used for copies materialized from the old single-row
/// representation. Newer code may use UUIDs for additional copies.
String migratedCopyId(String issueId, int ordinal) => '$issueId:copy:$ordinal';

Future<List<Map<String, Object?>>> _readLegacyBarcodes(
  DatabaseExecutor db,
) async {
  if (!await _tableExists(db, 'barcode_mappings')) return const [];
  final columns = await db.rawQuery('PRAGMA table_info(barcode_mappings)');
  final names = columns.map((column) => column['name']).whereType<String>();
  final issueColumn = names.contains('issue_id')
      ? 'issue_id'
      : names.contains('comic_id')
      ? 'comic_id'
      : null;
  if (issueColumn == null || !names.contains('barcode')) {
    throw StateError('Legacy barcode mapping columns are missing.');
  }
  return db.rawQuery(
    'SELECT barcode, $issueColumn AS issue_id FROM barcode_mappings',
  );
}

Future<void> _migrateLegacyComic(
  DatabaseExecutor db,
  Map<String, Object?> row,
) async {
  final issueId = _text(row['id']);
  if (issueId.trim().isEmpty) {
    throw StateError('A legacy comic has no id.');
  }

  final notes = _text(row['notes']);
  final sourceEdition = _sourceEdition(issueId, notes);
  final origin = sourceEdition.isEmpty ? customOrigin : bundledOrigin;
  final updatedAt = _integer(row['updated_at']);

  await db.insert('catalog_issues', {
    'id': issueId,
    'series': _text(row['series']),
    'edition': _text(row['edition']),
    'number': _integer(row['number']),
    'title': _text(row['title']),
    'publisher': _text(row['publisher']),
    'year': _nullableInteger(row['year']),
    'cover_asset': _text(row['cover_asset']),
    'page_count': _nullableInteger(row['page_count']),
    'writer': _text(row['writer']),
    'artist': _text(row['artist']),
    'origin': origin,
    'source_edition': sourceEdition,
    'metadata_updated_at': updatedAt,
  });

  final state = _LegacyState.fromRow(row, notes: notes);
  if (origin != bundledOrigin || !state.isInertBundled) {
    await db.insert('collection_entries', {
      'issue_id': issueId,
      'owned': state.owned,
      'is_wanted': state.owned == 0 && state.deleted == 0 ? 1 : 0,
      'is_read': state.isRead,
      'is_duplicate': state.isDuplicate,
      'rating': state.rating,
      'notes': notes,
      'deleted': state.deleted,
      'updated_at': updatedAt,
    });
  }

  if (state.needsPrimaryCopy) {
    await db.insert('copies', {
      'id': migratedCopyId(issueId, 0),
      'issue_id': issueId,
      'ordinal': 0,
      'active': state.owned != 0 && state.deleted == 0 ? 1 : 0,
      'condition_grade': state.condition,
      'purchase_price': state.purchasePrice,
      'estimated_value': state.estimatedValue,
      'loaned_to': state.loanedTo,
      'deleted': state.deleted,
      'updated_at': updatedAt,
    });
  }
  if (state.isDuplicate != 0) {
    await db.insert('copies', {
      'id': migratedCopyId(issueId, 1),
      'issue_id': issueId,
      'ordinal': 1,
      'active': state.owned != 0 && state.deleted == 0 ? 1 : 0,
      // Legacy data only described one physical copy. The second row records
      // the known duplicate without inventing condition or monetary values.
      'condition_grade': '',
      'purchase_price': null,
      'estimated_value': null,
      'loaned_to': '',
      'deleted': state.deleted,
      'updated_at': updatedAt,
    });
  }
}

Future<bool> _tableExists(DatabaseExecutor db, String name) async {
  final rows = await db.rawQuery(
    "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ? LIMIT 1",
    [name],
  );
  return rows.isNotEmpty;
}

String _sourceEdition(String issueId, String notes) {
  final idMatch = RegExp(r'^catalog-([A-Za-z0-9_]+)-').firstMatch(issueId);
  if (idMatch != null) return idMatch.group(1)!.toUpperCase();

  final starterMatch = RegExp(
    r'BSP oznaka\s+([A-Za-z0-9_]+)\s*$',
    caseSensitive: false,
  ).firstMatch(notes);
  if (starterMatch != null) return starterMatch.group(1)!.toUpperCase();

  final bspMatch = RegExp(
    r'^BSP katalog\s*[·:-]\s*([A-Za-z0-9_]+)\s*$',
    caseSensitive: false,
  ).firstMatch(notes.trim());
  return bspMatch?.group(1)?.toUpperCase() ?? '';
}

bool _isBundledProvenanceNote(String value) {
  final notes = value.trim();
  if (notes.isEmpty) return true;
  return RegExp(
        r'^Početni katalog\s*[·:-]\s*BSP oznaka\s+[A-Za-z0-9_]+\s*$',
        caseSensitive: false,
      ).hasMatch(notes) ||
      RegExp(
        r'^BSP katalog\s*[·:-]\s*[A-Za-z0-9_]+\s*$',
        caseSensitive: false,
      ).hasMatch(notes);
}

String _text(Object? value, [String fallback = '']) =>
    value is String ? value : value?.toString() ?? fallback;

int _integer(Object? value, [int fallback = 0]) => switch (value) {
  num number => number.toInt(),
  String text => int.tryParse(text) ?? fallback,
  _ => fallback,
};

int? _nullableInteger(Object? value) => switch (value) {
  null => null,
  num number => number.toInt(),
  String text => int.tryParse(text),
  _ => null,
};

double? _nullableDouble(Object? value) => switch (value) {
  null => null,
  num number => number.toDouble(),
  String text => double.tryParse(text),
  _ => null,
};

final class _LegacyState {
  const _LegacyState({
    required this.owned,
    required this.isRead,
    required this.isDuplicate,
    required this.rating,
    required this.deleted,
    required this.condition,
    required this.purchasePrice,
    required this.estimatedValue,
    required this.loanedTo,
    required this.hasUserNotes,
  });

  factory _LegacyState.fromRow(
    Map<String, Object?> row, {
    required String notes,
  }) => _LegacyState(
    owned: _integer(row['owned']) == 0 ? 0 : 1,
    isRead: _integer(row['is_read']) == 0 ? 0 : 1,
    isDuplicate: _integer(row['is_duplicate']) == 0 ? 0 : 1,
    rating: _integer(row['rating']).clamp(0, 5),
    deleted: _integer(row['deleted']) == 0 ? 0 : 1,
    condition: _text(row['condition_grade'], 'F'),
    purchasePrice: _nullableDouble(row['purchase_price']),
    estimatedValue: _nullableDouble(row['estimated_value']),
    loanedTo: _text(row['loaned_to']),
    hasUserNotes: !_isBundledProvenanceNote(notes),
  );

  final int owned;
  final int isRead;
  final int isDuplicate;
  final int rating;
  final int deleted;
  final String condition;
  final double? purchasePrice;
  final double? estimatedValue;
  final String loanedTo;
  final bool hasUserNotes;

  bool get hasCopyDetails =>
      condition != 'F' ||
      purchasePrice != null ||
      estimatedValue != null ||
      loanedTo.isNotEmpty;

  bool get needsPrimaryCopy => owned != 0 || isDuplicate != 0 || hasCopyDetails;

  bool get isInertBundled =>
      owned == 0 &&
      isRead == 0 &&
      isDuplicate == 0 &&
      rating == 0 &&
      deleted == 0 &&
      !hasUserNotes &&
      !hasCopyDetails;
}
