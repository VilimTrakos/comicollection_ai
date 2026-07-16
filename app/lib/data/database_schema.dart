import 'dart:convert';

import 'package:sqflite/sqflite.dart';

/// Current local database schema.
///
/// Version 5 separated immutable catalogue metadata from collection state and
/// physical copies. Version 6 adds durable revision-based synchronization and
/// makes copy ids, rather than presentation ordinals, distributed identities.
const int schemaVersion = 6;
const int normalizedSchemaVersion = 5;

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

/// Creates the current schema through the same v5 -> v6 migration used by
/// installed applications. Keeping one upgrade path prevents fresh and
/// migrated databases from drifting apart.
Future<void> createV6Schema(DatabaseExecutor db) async {
  await createV5Schema(db);
  await migrateV5SchemaToV6(db);
}

/// Single sqflite upgrade dispatcher. Every branch executes inside the
/// transaction provided by `openDatabase`, including all table rebuilds.
Future<void> migrateDatabaseSchema(
  DatabaseExecutor db,
  int oldVersion,
  int newVersion,
) async {
  var currentVersion = oldVersion;
  if (currentVersion < normalizedSchemaVersion &&
      newVersion >= normalizedSchemaVersion) {
    await migrateLegacySchemaToV5(db, currentVersion, normalizedSchemaVersion);
    currentVersion = normalizedSchemaVersion;
  }
  if (currentVersion == normalizedSchemaVersion &&
      newVersion >= schemaVersion) {
    await migrateV5SchemaToV6(db);
    currentVersion = schemaVersion;
  }
  if (currentVersion != newVersion) {
    throw StateError(
      'Unsupported local database upgrade: $oldVersion -> $newVersion',
    );
  }
}

/// Rebuilds v5 tables whose constraints changed and installs the durable sync
/// journal. Only SQLite syntax available on Android API 24 is used.
Future<void> migrateV5SchemaToV6(DatabaseExecutor db) async {
  if (!await _tableExists(db, 'copies') ||
      !await _tableExists(db, 'barcode_mappings')) {
    throw StateError('Version 5 collection tables are missing.');
  }

  await db.execute('''
    CREATE TABLE sync_quarantine(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      entity_type TEXT NOT NULL,
      entity_id TEXT NOT NULL,
      reason TEXT NOT NULL,
      payload_json TEXT NOT NULL,
      created_at INTEGER NOT NULL DEFAULT 0
    )
  ''');
  await db.execute('''
    CREATE INDEX idx_sync_quarantine_entity
    ON sync_quarantine(entity_type, entity_id)
  ''');

  // V5 predates the wire contract and therefore allowed values which a v2
  // server must reject. Normalize them inside the upgrade transaction so one
  // historical row can never poison the durable outbox.
  final issueRows = await db.query('catalog_issues');
  for (final issue in issueRows) {
    final issueId = _text(issue['id']);
    final values = <String, Object?>{
      'series': _wireText(
        issue['series'],
        200,
        requiredFallback: 'Nepoznati serijal',
      ),
      'edition': _wireText(issue['edition'], 200),
      'number': _wireInteger(issue['number'], 0, 1000000000),
      'title': _wireText(issue['title'], 500, requiredFallback: 'Bez naslova'),
      'publisher': _wireText(issue['publisher'], 200),
      'year': _wireNullableInteger(issue['year'], 0, 3000),
      'page_count': _wireNullableInteger(issue['page_count'], 0, 100000),
      'writer': _wireText(issue['writer'], 300),
      'artist': _wireText(issue['artist'], 300),
      'metadata_updated_at': _wireInteger(
        issue['metadata_updated_at'],
        0,
        _maximumSignedInt64,
      ),
    };
    final changedFields = _changedFields(issue, values);
    if (changedFields.isNotEmpty) {
      await _quarantine(
        db,
        'catalog_issue',
        issueId,
        'Normalized v5 fields: ${changedFields.join(', ')}',
        issue,
      );
    }
    if (!_validWireIdentifier(issueId, 128)) {
      await _quarantine(
        db,
        'issue',
        issueId,
        'Invalid v2 issue identifier',
        issue,
      );
    }
    await db.update(
      'catalog_issues',
      values,
      where: 'id = ?',
      whereArgs: [issue['id']],
    );
  }
  final entryRows = await db.query('collection_entries');
  for (final entry in entryRows) {
    final values = <String, Object?>{
      'rating': _wireInteger(entry['rating'], 0, 5),
      'notes': _wireText(entry['notes'], 10000),
      'updated_at': _wireInteger(entry['updated_at'], 0, _maximumSignedInt64),
    };
    final changedFields = _changedFields(entry, values);
    if (changedFields.isNotEmpty) {
      await _quarantine(
        db,
        'collection_entry',
        _text(entry['issue_id']),
        'Normalized v5 fields: ${changedFields.join(', ')}',
        entry,
      );
    }
    await db.update(
      'collection_entries',
      values,
      where: 'issue_id = ?',
      whereArgs: [entry['issue_id']],
    );
  }
  final copyRows = await db.query('copies');

  await db.execute('DROP INDEX IF EXISTS idx_copies_issue_active');
  await db.execute('ALTER TABLE copies RENAME TO copies_v5');
  await db.execute('''
    CREATE TABLE copies(
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
      FOREIGN KEY(issue_id) REFERENCES catalog_issues(id) ON DELETE CASCADE
    )
  ''');
  for (final copy in copyRows) {
    final rawCondition = _text(copy['condition_grade']);
    final copyId = _text(copy['id']);
    final issueId = _text(copy['issue_id']);
    final values = <String, Object?>{
      'id': copy['id'],
      'issue_id': copy['issue_id'],
      'ordinal': _wireInteger(copy['ordinal'], 0, 1000000),
      'active': _integer(copy['active']) == 0 ? 0 : 1,
      'condition_grade': _wireConditionGrades.contains(rawCondition)
          ? rawCondition
          : 'F',
      'purchase_price': _wirePrice(copy['purchase_price']),
      'estimated_value': _wirePrice(copy['estimated_value']),
      'loaned_to': _wireText(copy['loaned_to'], 300),
      'deleted': _integer(copy['deleted']) == 0 ? 0 : 1,
      'updated_at': _wireInteger(copy['updated_at'], 0, _maximumSignedInt64),
    };
    final changedFields = _changedFields(copy, values);
    if (changedFields.isNotEmpty) {
      await _quarantine(
        db,
        'copy_audit',
        copyId,
        'Normalized v5 fields: ${changedFields.join(', ')}',
        copy,
      );
    }
    if (!_validWireIdentifier(copyId, 128) ||
        !_validWireIdentifier(issueId, 128)) {
      await _quarantine(
        db,
        'copy',
        copyId,
        'Invalid v2 copy or issue identifier',
        copy,
      );
    }
    await db.insert('copies', values);
  }
  await db.execute('DROP TABLE copies_v5');
  await db.execute('''
    CREATE INDEX idx_copies_issue_active
    ON copies(issue_id, active, ordinal)
  ''');

  await db.execute('''
    ALTER TABLE barcode_mappings
    ADD COLUMN deleted INTEGER NOT NULL DEFAULT 0 CHECK(deleted IN (0, 1))
  ''');
  await db.execute('''
    ALTER TABLE barcode_mappings
    ADD COLUMN updated_at INTEGER NOT NULL DEFAULT 0
  ''');
  final mappingRows = await db.query('barcode_mappings');
  for (final mapping in mappingRows) {
    final barcode = _text(mapping['barcode']);
    final issueId = _text(mapping['issue_id']);
    if (!_validWireIdentifier(barcode, 512) ||
        !_validWireIdentifier(issueId, 128)) {
      await _quarantine(
        db,
        'barcode_mapping',
        barcode,
        'Invalid v2 barcode or issue identifier',
        mapping,
      );
    }
  }

  await db.execute('''
    CREATE TABLE sync_state(
      id INTEGER PRIMARY KEY CHECK(id = 1),
      device_id TEXT NOT NULL,
      server_id TEXT NOT NULL DEFAULT '',
      cursor INTEGER NOT NULL DEFAULT 0 CHECK(cursor >= 0),
      bootstrapped INTEGER NOT NULL DEFAULT 0 CHECK(bootstrapped IN (0, 1)),
      legacy_seeded INTEGER NOT NULL DEFAULT 0
        CHECK(legacy_seeded IN (0, 1)),
      baseline_complete INTEGER NOT NULL DEFAULT 0
        CHECK(baseline_complete IN (0, 1)),
      force_full_export INTEGER NOT NULL DEFAULT 0
        CHECK(force_full_export IN (0, 1)),
      legacy_cursor INTEGER NOT NULL DEFAULT 0 CHECK(legacy_cursor >= 0),
      v1_fallback_pending INTEGER NOT NULL DEFAULT 0
        CHECK(v1_fallback_pending IN (0, 1)),
      v1_fallback_cursor INTEGER NOT NULL DEFAULT 0
        CHECK(v1_fallback_cursor >= 0),
      v1_fallback_outbox_sequence INTEGER NOT NULL DEFAULT 0
        CHECK(v1_fallback_outbox_sequence >= 0),
      last_success_at INTEGER
    )
  ''');
  await db.execute('''
    CREATE TABLE sync_outbox(
      sequence INTEGER PRIMARY KEY AUTOINCREMENT,
      mutation_id TEXT NOT NULL UNIQUE,
      created_at INTEGER NOT NULL,
      changes_json TEXT NOT NULL,
      ack_revision INTEGER CHECK(ack_revision IS NULL OR ack_revision >= 0),
      ack_status TEXT CHECK(
        ack_status IS NULL OR ack_status IN ('applied', 'duplicate')
      ),
      CHECK(
        (ack_revision IS NULL AND ack_status IS NULL)
        OR (ack_revision IS NOT NULL AND ack_status IS NOT NULL)
      )
    )
  ''');
  await db.execute('''
    CREATE INDEX idx_sync_outbox_ack_sequence
    ON sync_outbox(ack_revision, sequence)
  ''');
  await db.execute('''
    CREATE TABLE sync_outbox_entities(
      mutation_id TEXT NOT NULL,
      entity_type TEXT NOT NULL,
      entity_id TEXT NOT NULL,
      PRIMARY KEY(mutation_id, entity_type, entity_id),
      FOREIGN KEY(mutation_id) REFERENCES sync_outbox(mutation_id)
        ON DELETE CASCADE
    )
  ''');
  await db.execute('''
    CREATE INDEX idx_sync_outbox_entities_lookup
    ON sync_outbox_entities(entity_type, entity_id)
  ''');
  await db.execute('''
    CREATE TABLE sync_entity_versions(
      entity_type TEXT NOT NULL,
      entity_id TEXT NOT NULL,
      revision INTEGER NOT NULL CHECK(revision >= 0),
      PRIMARY KEY(entity_type, entity_id)
    )
  ''');
}

const int _maximumSignedInt64 = 0x7FFFFFFFFFFFFFFF;
const Set<String> _wireConditionGrades = {'', 'M', 'VF', 'F', 'G', 'P'};

int _wireInteger(Object? value, int minimum, int maximum) =>
    _integer(value).clamp(minimum, maximum);

int? _wireNullableInteger(Object? value, int minimum, int maximum) {
  final number = _nullableInteger(value);
  return number != null && number >= minimum && number <= maximum
      ? number
      : null;
}

double? _wirePrice(Object? value) {
  final number = _nullableDouble(value);
  return number != null && number.isFinite && number >= 0 ? number : null;
}

String _wireText(
  Object? value,
  int maximumBytes, {
  String requiredFallback = '',
}) {
  var text = _text(value);
  // Re-encoding replaces malformed surrogate halves with U+FFFD.
  text = utf8.decode(utf8.encode(text), allowMalformed: true);
  if (text.trim().isEmpty && requiredFallback.isNotEmpty) {
    text = requiredFallback;
  }
  if (utf8.encode(text).length <= maximumBytes) return text;

  final output = StringBuffer();
  var bytes = 0;
  for (final rune in text.runes) {
    final character = String.fromCharCode(rune);
    final length = utf8.encode(character).length;
    if (bytes + length > maximumBytes) break;
    output.write(character);
    bytes += length;
  }
  final truncated = output.toString();
  if (truncated.trim().isEmpty && requiredFallback.isNotEmpty) {
    return requiredFallback;
  }
  return truncated;
}

List<String> _changedFields(
  Map<String, Object?> original,
  Map<String, Object?> normalized,
) => [
  for (final entry in normalized.entries)
    if (original[entry.key] != entry.value) entry.key,
];

bool _validWireIdentifier(String value, int maximumBytes) {
  if (value.isEmpty || value != value.trim()) return false;
  if (value.codeUnits.any((unit) => unit < 0x20 || unit == 0x7F)) {
    return false;
  }
  try {
    return utf8.encode(value).length <= maximumBytes;
  } on FormatException {
    return false;
  }
}

Future<void> _quarantine(
  DatabaseExecutor db,
  String entityType,
  String entityId,
  String reason,
  Map<String, Object?> original,
) => db.insert('sync_quarantine', {
  'entity_type': entityType,
  'entity_id': entityId,
  'reason': reason,
  'payload_json': jsonEncode(_jsonSafe(original)),
  'created_at': 0,
});

Map<String, Object?> _jsonSafe(Map<String, Object?> value) => {
  for (final entry in value.entries) entry.key: _jsonSafeValue(entry.value),
};

Object? _jsonSafeValue(Object? value) => switch (value) {
  null || bool _ || int _ || String _ => value,
  double number when number.isFinite => number,
  num number => number.toString(),
  List list => list.map(_jsonSafeValue).toList(growable: false),
  Map map => {
    for (final entry in map.entries)
      entry.key.toString(): _jsonSafeValue(entry.value),
  },
  _ => value.toString(),
};

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
  int newVersion = normalizedSchemaVersion,
]) async {
  if (oldVersion >= normalizedSchemaVersion ||
      newVersion < normalizedSchemaVersion) {
    return;
  }
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
