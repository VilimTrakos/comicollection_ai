import 'dart:convert';

import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../models/collection_entry.dart';
import '../models/comic.dart';
import '../models/comic_copy.dart';
import '../models/sync_v2.dart';
import '../models/sync_v2_upload_validator.dart';
import 'database_schema.dart';

const _maximumUploadMutations = SyncV2UploadValidator.maximumMutations;
const _maximumChangesPerMutation =
    SyncV2UploadValidator.maximumChangesPerMutation;
const _maximumUploadChanges = SyncV2UploadValidator.maximumChangesPerRequest;

typedef LegacyFallbackBatch = ({
  int since,
  int outboxSequence,
  List<Comic> changes,
});

class LocalDatabase {
  LocalDatabase({
    this.pathOverride,
    int Function()? nowMilliseconds,
    String Function()? idGenerator,
  }) : _idGenerator = idGenerator ?? const Uuid().v4,
       _nowMilliseconds =
           nowMilliseconds ?? (() => DateTime.now().millisecondsSinceEpoch);

  final String? pathOverride;
  final String Function() _idGenerator;
  final int Function() _nowMilliseconds;
  Database? _db;

  Future<Database> get database async => _db ??= await openDatabase(
    pathOverride ?? join(await getDatabasesPath(), 'comicollect.db'),
    version: schemaVersion,
    onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
    onCreate: (db, version) => createV6Schema(db),
    onUpgrade: migrateDatabaseSchema,
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
    await db.transaction((transaction) async {
      final before = await _issueWireSnapshot(transaction, comic.id);
      await _upsertComic(transaction, comic);
      await _enqueueIssueDifference(transaction, comic.id, before);
    });
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
        if (existing.isEmpty) {
          final before = await _issueWireSnapshot(transaction, comic.id);
          await _upsertComic(transaction, comic);
          await _enqueueIssueDifference(transaction, comic.id, before);
        }
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
        final before = await _issueWireSnapshot(transaction, comic.id);
        await _upsertComic(transaction, comic);
        await _enqueueIssueDifference(transaction, comic.id, before);
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
      orderBy: 'ordinal, id',
    );
    return rows.map(ComicCopy.fromMap).toList(growable: false);
  }

  /// Active, non-deleted copies are authoritative for owned/duplicate state.
  /// The collection aggregate is recomputed after every copy write so current
  /// screens and synchronization observe the same derived flags.
  Future<void> saveCopy(ComicCopy copy) async {
    final db = await database;
    await db.transaction((transaction) async {
      final before = (await _issueWireSnapshot(transaction, copy.issueId))
          .where(
            (change) =>
                change.entityType == SyncEntityType.comicCopy &&
                change.entityId == copy.id,
          )
          .toList(growable: false);
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
      final after = (await _issueWireSnapshot(transaction, copy.issueId))
          .where(
            (change) =>
                change.entityType == SyncEntityType.comicCopy &&
                change.entityId == copy.id,
          )
          .toList(growable: false);
      // Collection ownership/duplicate/wanted flags are derived from active
      // copies. Uploading that aggregate snapshot here could overwrite newer
      // read/rating/notes values from another device. The server recomputes
      // and appends the canonical entry to the copy's atomic change group.
      await _insertOutboxMutations(transaction, _wireDifference(before, after));
    });
  }

  Future<Map<String, String>> barcodeMappings() async {
    final rows = await (await database).query(
      'barcode_mappings',
      where: 'deleted = 0',
    );
    return {
      for (final row in rows)
        row['barcode'] as String: row['issue_id'] as String,
    };
  }

  Future<void> saveBarcodeMapping(String barcode, String comicId) async {
    final normalizedBarcode = barcode.trim();
    if (normalizedBarcode.isEmpty) {
      throw ArgumentError.value(barcode, 'barcode', 'must not be empty');
    }
    if (comicId.trim().isEmpty) {
      throw ArgumentError.value(comicId, 'comicId', 'must not be empty');
    }
    final db = await database;
    await db.transaction((transaction) async {
      final before = await _barcodeWireSnapshot(transaction, normalizedBarcode);
      final existing = await transaction.query(
        'barcode_mappings',
        columns: ['updated_at'],
        where: 'barcode = ?',
        whereArgs: [normalizedBarcode],
        limit: 1,
      );
      final updatedAt = _monotonicTimestamp(
        requested: _nowMilliseconds(),
        previous: existing.isEmpty
            ? null
            : (existing.single['updated_at'] as num).toInt(),
        now: _nowMilliseconds(),
      );
      await transaction.insert('barcode_mappings', {
        'barcode': normalizedBarcode,
        'issue_id': comicId,
        'deleted': 0,
        'updated_at': updatedAt,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
      final updated = await transaction.update(
        'barcode_mappings',
        {'issue_id': comicId, 'deleted': 0, 'updated_at': updatedAt},
        where: 'barcode = ?',
        whereArgs: [normalizedBarcode],
      );
      if (updated != 1) {
        throw StateError('Barcode $normalizedBarcode could not be persisted.');
      }
      final after = await _barcodeWireSnapshot(transaction, normalizedBarcode);
      await _insertOutboxMutations(
        transaction,
        _wireDifference(
          before == null ? const [] : [before],
          after == null ? const [] : [after],
        ),
      );
    });
  }

  /// Returns a stable-device, cursor-based upload batch.
  ///
  /// V1 upgrades deliberately download the server baseline before uploading.
  /// The legacy seed is durable and protects only local state which is newer
  /// than the last successful v1 exchange, plus fields which v1 could never
  /// represent. This prevents a stale full-device snapshot from overwriting a
  /// newer server while still preserving every genuinely local change.
  Future<SyncUploadBatch> prepareSyncV2({
    int limit = 100,
    int legacyCursor = 0,
  }) async {
    if (limit <= 0) {
      throw ArgumentError.value(limit, 'limit', 'must be positive');
    }
    if (legacyCursor < 0) {
      throw ArgumentError.value(
        legacyCursor,
        'legacyCursor',
        'must not be negative',
      );
    }
    final db = await database;
    return db.transaction((transaction) async {
      var state = await _ensureSyncState(transaction);
      if (state.v1FallbackPending) {
        throw StateError(
          'A legacy fallback must finish before sync v2 can start.',
        );
      }
      final cutoverCursor = legacyCursor > state.legacyCursor
          ? legacyCursor
          : state.legacyCursor;
      if (!state.legacySeeded) {
        // A zero v1 cursor means this installation has no confirmed remote
        // baseline. An explicit server rebind has the same intent: preserve
        // the complete local collection while first downloading the target
        // server history. Staging before the pull makes those rows durable and
        // prevents the baseline from overwriting them.
        if (state.forceFullExport || cutoverCursor == 0) {
          await _seedFullLocalSnapshot(transaction);
        } else {
          await _seedLegacyCutover(transaction, cutoverCursor);
        }
        await transaction.update('sync_state', {
          'legacy_seeded': 1,
          'force_full_export': 0,
        }, where: 'id = 1');
        state = state.copyWith(legacySeeded: true, forceFullExport: false);
      }

      // The initial request and every baseline continuation are pull-only.
      // Seeded mutations remain durable so incoming groups cannot overwrite
      // the corresponding dirty local entities.
      if (!state.baselineComplete) {
        return SyncUploadBatch(
          deviceId: state.deviceId,
          serverId: state.serverId,
          cursor: state.cursor,
          mutations: const [],
        );
      }

      // A completed baseline at revision zero means the account/server has no
      // state. In that case the local installation is the only source of truth
      // and must publish a complete snapshot. Existing journal rows are kept.
      if (!state.bootstrapped) {
        if (state.cursor == 0) {
          await _seedFullLocalSnapshot(transaction);
        }
        await transaction.update('sync_state', {
          'bootstrapped': 1,
        }, where: 'id = 1');
        state = state.copyWith(bootstrapped: true);
      }

      final mutationLimit = limit < _maximumUploadMutations
          ? limit
          : _maximumUploadMutations;
      final rows = await transaction.query(
        'sync_outbox',
        columns: ['changes_json'],
        where: 'ack_revision IS NULL',
        orderBy: 'sequence',
        limit: mutationLimit,
      );
      final mutations = <SyncMutation>[];
      var totalChanges = 0;
      for (final row in rows) {
        final mutation = _decodeMutation(row['changes_json'] as String);
        if (mutation.changes.length > _maximumChangesPerMutation) {
          throw StateError(
            'Stored sync mutation ${mutation.mutationId} exceeds the '
            '$_maximumChangesPerMutation-change protocol limit.',
          );
        }
        final nextTotal = totalChanges + mutation.changes.length;
        if (mutations.isNotEmpty && nextTotal > _maximumUploadChanges) break;
        mutations.add(mutation);
        totalChanges = nextTotal;
      }
      return SyncUploadBatch(
        deviceId: state.deviceId,
        serverId: state.serverId,
        cursor: state.cursor,
        mutations: mutations,
      );
    });
  }

  Future<bool> hasPendingSyncV2() async {
    final db = await database;
    final queued = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM sync_outbox'),
    );
    if ((queued ?? 0) > 0) return true;

    final states = await db.query(
      'sync_state',
      columns: ['bootstrapped', 'baseline_complete'],
      where: 'id = 1',
      limit: 1,
    );
    if (states.isNotEmpty) {
      final state = states.single;
      if ((state['baseline_complete'] as num) == 0 ||
          (state['bootstrapped'] as num) == 0) {
        return true;
      }
      return false;
    }
    final localState = Sqflite.firstIntValue(
      await db.rawQuery(
        '''
        SELECT COUNT(*)
        FROM catalog_issues issue
        WHERE issue.origin = ?
           OR EXISTS(
             SELECT 1 FROM collection_entries entry
             WHERE entry.issue_id = issue.id
           )
           OR EXISTS(
             SELECT 1 FROM copies copy WHERE copy.issue_id = issue.id
           )
           OR EXISTS(
             SELECT 1 FROM barcode_mappings mapping
             WHERE mapping.issue_id = issue.id
           )
      ''',
        [customOrigin],
      ),
    );
    return (localState ?? 0) > 0;
  }

  /// Migration review records are never silently treated as ordinary sync
  /// success. `blocked` rows have identifiers that cannot be represented by
  /// the wire protocol; audit-only rows were safely normalized while their
  /// original JSON remains available in `sync_quarantine`.
  Future<({int total, int blocked})> syncMigrationReviewSummary() async {
    final db = await database;
    final totals = await db.rawQuery('''
      SELECT COUNT(*) AS total,
             SUM(
               CASE WHEN entity_type IN ('issue', 'copy', 'barcode_mapping')
                    THEN 1 ELSE 0 END
             ) AS blocked
      FROM sync_quarantine
    ''');
    final row = totals.single;
    return (
      total: (row['total'] as num?)?.toInt() ?? 0,
      blocked: (row['blocked'] as num?)?.toInt() ?? 0,
    );
  }

  /// Atomically applies acknowledgements, ordered remote snapshots, entity
  /// revisions and the server cursor. A crash therefore cannot advance the
  /// cursor without the corresponding domain state.
  Future<void> applySyncV2(SyncV2Exchange exchange) async {
    final db = await database;
    await db.transaction((transaction) async {
      final state = await _ensureSyncState(transaction);
      if (state.serverId.isNotEmpty && state.serverId != exchange.serverId) {
        throw StateError(
          'Sync server changed from ${state.serverId} to ${exchange.serverId}.',
        );
      }
      if (exchange.nextCursor < state.cursor) {
        throw StateError(
          'Sync cursor moved backwards: ${state.cursor} -> '
          '${exchange.nextCursor}.',
        );
      }
      var expectedRevision = state.cursor + 1;
      for (final group in exchange.changeGroups) {
        if (group.revision != expectedRevision) {
          throw FormatException(
            'Sync revision gap: expected $expectedRevision, '
            'received ${group.revision}.',
          );
        }
        expectedRevision++;
      }
      if (exchange.changeGroups.isEmpty &&
          exchange.nextCursor != state.cursor) {
        throw const FormatException(
          'Sync cursor advanced without applying change groups.',
        );
      }
      if (exchange.hasMore && exchange.changeGroups.isEmpty) {
        throw const FormatException(
          'Sync continuation did not contain a change group.',
        );
      }

      for (final acknowledgement in exchange.acknowledgements) {
        if (acknowledgement.revision <= state.cursor ||
            (acknowledgement.revision > exchange.nextCursor &&
                !exchange.hasMore)) {
          throw const FormatException(
            'Sync acknowledgement references an invalid revision.',
          );
        }
        final pendingRows = await transaction.query(
          'sync_outbox',
          columns: ['mutation_id', 'ack_revision', 'ack_status'],
          where: 'mutation_id = ?',
          whereArgs: [acknowledgement.mutationId],
          limit: 1,
        );
        if (pendingRows.isEmpty) {
          throw const FormatException(
            'Sync acknowledgement references an unknown mutation.',
          );
        }
        final pending = pendingRows.single;
        final existingRevision = (pending['ack_revision'] as num?)?.toInt();
        final existingStatus = pending['ack_status'] as String?;
        if ((existingRevision != null &&
                existingRevision != acknowledgement.revision) ||
            (existingStatus != null &&
                existingStatus != acknowledgement.status)) {
          throw const FormatException(
            'Sync acknowledgement changed after it was recorded.',
          );
        }
        final revisionOwner = await transaction.query(
          'sync_outbox',
          columns: ['mutation_id'],
          where: 'ack_revision = ? AND mutation_id <> ?',
          whereArgs: [acknowledgement.revision, acknowledgement.mutationId],
          limit: 1,
        );
        if (revisionOwner.isNotEmpty) {
          throw const FormatException(
            'Sync revision acknowledged more than one mutation.',
          );
        }
        final updated = await transaction.update(
          'sync_outbox',
          {
            'ack_revision': acknowledgement.revision,
            'ack_status': acknowledgement.status,
          },
          where: 'mutation_id = ?',
          whereArgs: [acknowledgement.mutationId],
        );
        if (updated != 1) {
          throw const FormatException(
            'Sync acknowledgement could not be persisted.',
          );
        }
      }
      if (!exchange.hasMore) {
        final acknowledgementsBeyondPage = await transaction.query(
          'sync_outbox',
          columns: ['mutation_id'],
          where: 'ack_revision > ?',
          whereArgs: [exchange.nextCursor],
          limit: 1,
        );
        if (acknowledgementsBeyondPage.isNotEmpty) {
          throw const FormatException(
            'Final sync page ended before an acknowledged revision.',
          );
        }
      }

      final copyIssues = <String>{};
      for (final group in exchange.changeGroups) {
        if (group.revision <= state.cursor) continue;
        final acknowledgedRows = await transaction.rawQuery(
          '''SELECT mutation_id, ack_revision
             FROM sync_outbox
             WHERE ack_revision IS NOT NULL
               AND (ack_revision = ? OR mutation_id = ?)''',
          [group.revision, group.mutationId],
        );
        for (final acknowledged in acknowledgedRows) {
          if (acknowledged['mutation_id'] != group.mutationId ||
              (acknowledged['ack_revision'] as num).toInt() != group.revision) {
            throw const FormatException(
              'Acknowledged mutation does not match its change group.',
            );
          }
        }
        for (final change in group.changes) {
          final knownRevision = await _entityRevision(transaction, change);
          if (knownRevision >= group.revision) continue;
          final protectLocal = await _hasNewerLocalMutation(
            transaction,
            change,
            group.revision,
          );
          if (!protectLocal) {
            final copyIssue = await _applyRemoteChange(
              transaction,
              change,
              exchange.serverTime,
            );
            if (copyIssue != null) copyIssues.add(copyIssue);
          }
          await _saveEntityRevision(transaction, change, group.revision);
        }
      }
      for (final issueId in copyIssues) {
        await _recomputeCollectionFlags(
          transaction,
          issueId,
          exchange.serverTime,
        );
      }

      await transaction.update('sync_state', {
        'server_id': exchange.serverId,
        'cursor': exchange.nextCursor,
        if (!exchange.hasMore) 'baseline_complete': 1,
        if (!exchange.hasMore && exchange.nextCursor > 0) 'bootstrapped': 1,
        'last_success_at': exchange.serverTime,
      }, where: 'id = 1');
      await transaction.delete(
        'sync_outbox',
        where: 'ack_revision IS NOT NULL AND ack_revision <= ?',
        whereArgs: [exchange.nextCursor],
      );
    });
  }

  /// Forgets only the remote synchronization identity. Domain rows and the
  /// stable device id remain intact; the next prepare performs a full
  /// baseline against the newly confirmed server.
  Future<void> resetSyncV2Binding() async {
    final db = await database;
    await db.transaction((transaction) async {
      await _ensureSyncState(transaction);
      // Mutation ids and entity snapshots are device-scoped, not
      // server-scoped. Preserve them, but clear acknowledgements issued by the
      // old server so every pending mutation can be safely retried.
      await transaction.update('sync_outbox', {
        'ack_revision': null,
        'ack_status': null,
      });
      await transaction.delete('sync_entity_versions');
      final updated = await transaction.update('sync_state', {
        'server_id': '',
        'cursor': 0,
        'bootstrapped': 0,
        'legacy_seeded': 0,
        'baseline_complete': 0,
        'force_full_export': 1,
        'legacy_cursor': 0,
        'v1_fallback_pending': 0,
        'v1_fallback_cursor': 0,
        'v1_fallback_outbox_sequence': 0,
        'last_success_at': null,
      }, where: 'id = 1');
      if (updated != 1) {
        throw StateError('Sync binding could not be reset.');
      }
    });
  }

  Future<bool> hasPendingV1Fallback() async {
    final state = await _ensureSyncState(await database);
    return state.v1FallbackPending;
  }

  /// Atomically snapshots the legacy upload and its v2 outbox high-water.
  /// Writes which happen while the HTTP request is in flight receive a newer
  /// sequence and can therefore never be deleted by completion of this batch.
  /// A durable pending marker forces crash recovery to retry v1 before v2.
  Future<LegacyFallbackBatch> prepareV1Fallback(int settingsCursor) async {
    if (settingsCursor < 0) {
      throw ArgumentError.value(
        settingsCursor,
        'settingsCursor',
        'must not be negative',
      );
    }
    final db = await database;
    return db.transaction((transaction) async {
      final state = await _ensureSyncState(transaction);
      if (state.serverId.isNotEmpty || state.baselineComplete) {
        throw StateError('Pinned sync v2 state cannot enter the v1 fallback.');
      }
      final since = state.v1FallbackPending
          ? state.v1FallbackCursor
          : settingsCursor > state.legacyCursor
          ? settingsCursor
          : state.legacyCursor;
      final threshold = since == 0 ? -1 : since;
      final rows = await transaction.rawQuery(
        '''$_comicProjection
           WHERE entry.issue_id IS NOT NULL
             AND (
               entry.updated_at > ?
               OR EXISTS(
                 SELECT 1
                 FROM sync_outbox_entities pending
                 WHERE pending.entity_id = issue.id
                   AND pending.entity_type IN (
                     'custom_issue', 'collection_entry'
                   )
               )
               OR EXISTS(
                 SELECT 1
                 FROM sync_outbox_entities pending
                 JOIN copies pending_copy
                   ON pending.entity_type = 'copy'
                  AND pending.entity_id = pending_copy.id
                 WHERE pending_copy.issue_id = issue.id
               )
             )
           ORDER BY entry.updated_at, issue.id''',
        [threshold],
      );
      final outboxSequence =
          Sqflite.firstIntValue(
            await transaction.rawQuery(
              'SELECT COALESCE(MAX(sequence), 0) FROM sync_outbox',
            ),
          ) ??
          0;
      final updated = await transaction.update('sync_state', {
        'v1_fallback_pending': 1,
        'v1_fallback_cursor': since,
        'v1_fallback_outbox_sequence': outboxSequence,
      }, where: 'id = 1');
      if (updated != 1) {
        throw StateError('Legacy fallback marker could not be persisted.');
      }
      return (
        since: since,
        outboxSequence: outboxSequence,
        changes: rows.map(Comic.fromMap).toList(growable: false),
      );
    });
  }

  /// Commits the successful v1 reconciliation, outbox rebase and durable
  /// legacy cursor in one SQLite transaction. Shared preferences may lag this
  /// value after a crash; the next cutover always uses the larger cursor.
  Future<void> completeV1Fallback(
    Iterable<Comic> remote,
    int serverTime,
  ) async {
    if (serverTime < 0) {
      throw ArgumentError.value(
        serverTime,
        'serverTime',
        'must not be negative',
      );
    }
    final db = await database;
    await db.transaction((transaction) async {
      final state = await _ensureSyncState(transaction);
      if (!state.v1FallbackPending ||
          state.serverId.isNotEmpty ||
          state.baselineComplete) {
        throw StateError('No unbound legacy fallback is pending.');
      }
      await _mergeRemoteIntoTransaction(
        transaction,
        remote,
        enqueueSyncV2: false,
      );
      await transaction.delete(
        'sync_outbox',
        where: 'sequence <= ?',
        whereArgs: [state.v1FallbackOutboxSequence],
      );
      await transaction.delete('sync_entity_versions');
      final updated = await transaction.update('sync_state', {
        'cursor': 0,
        'bootstrapped': 0,
        'legacy_seeded': 0,
        'baseline_complete': 0,
        'force_full_export': 0,
        'legacy_cursor': serverTime > state.legacyCursor
            ? serverTime
            : state.legacyCursor,
        'v1_fallback_pending': 0,
        'v1_fallback_cursor': 0,
        'v1_fallback_outbox_sequence': 0,
        'last_success_at': null,
      }, where: 'id = 1');
      if (updated != 1) {
        throw StateError('Legacy fallback completion could not be persisted.');
      }
    });
  }

  /// Promotes an interrupted v1 attempt to a v2 baseline when the server has
  /// become v2-read-only in the meantime. No outbox row is removed: both the
  /// uncertain retry and writes made while it was in flight remain durable
  /// until v2 acknowledges their canonical mutations.
  Future<void> promotePendingV1FallbackToV2() async {
    final db = await database;
    await db.transaction((transaction) async {
      final state = await _ensureSyncState(transaction);
      if (!state.v1FallbackPending ||
          state.serverId.isNotEmpty ||
          state.baselineComplete) {
        throw StateError('No unbound legacy fallback can be promoted.');
      }
      await transaction.delete('sync_entity_versions');
      final updated = await transaction.update('sync_state', {
        'cursor': 0,
        'bootstrapped': 0,
        'legacy_seeded': 0,
        'baseline_complete': 0,
        'force_full_export': 0,
        'legacy_cursor': state.v1FallbackCursor > state.legacyCursor
            ? state.v1FallbackCursor
            : state.legacyCursor,
        'v1_fallback_pending': 0,
        'v1_fallback_cursor': 0,
        'v1_fallback_outbox_sequence': 0,
        'last_success_at': null,
      }, where: 'id = 1');
      if (updated != 1) {
        throw StateError('Legacy fallback could not be promoted to v2.');
      }
    });
  }

  Future<_SyncState> _ensureSyncState(DatabaseExecutor database) async {
    final rows = await database.query('sync_state', where: 'id = 1', limit: 1);
    if (rows.isNotEmpty) return _SyncState.fromMap(rows.single);

    final deviceId = _idGenerator().trim();
    if (deviceId.isEmpty) {
      throw StateError('The generated sync device id is empty.');
    }
    const state = _SyncState(
      deviceId: '',
      serverId: '',
      cursor: 0,
      bootstrapped: false,
      legacySeeded: false,
      baselineComplete: false,
      forceFullExport: false,
      legacyCursor: 0,
      v1FallbackPending: false,
      v1FallbackCursor: 0,
      v1FallbackOutboxSequence: 0,
    );
    final created = state.copyWith(deviceId: deviceId);
    await database.insert('sync_state', created.toMap());
    return created;
  }

  Future<void> _seedLegacyCutover(
    DatabaseExecutor database,
    int legacyCursor,
  ) async {
    final selectedByIssue = <String, Set<String>>{};
    void select(String issueId, SyncEntityType type, String entityId) {
      selectedByIssue
          .putIfAbsent(issueId, () => <String>{})
          .add('${type.wireName}\u0000$entityId');
    }

    final dirtyIssues = await database.query(
      'catalog_issues',
      columns: ['id'],
      where: 'origin = ? AND metadata_updated_at > ?',
      whereArgs: [customOrigin, legacyCursor],
      orderBy: 'id',
    );
    for (final row in dirtyIssues) {
      final issueId = row['id'] as String;
      select(issueId, SyncEntityType.customIssue, issueId);
    }

    final dirtyEntries = await database.query(
      'collection_entries',
      columns: ['issue_id'],
      where: 'updated_at > ?',
      whereArgs: [legacyCursor],
      orderBy: 'issue_id',
    );
    for (final row in dirtyEntries) {
      final issueId = row['issue_id'] as String;
      select(issueId, SyncEntityType.collectionEntry, issueId);
    }

    final copies = await database.query(
      'copies',
      columns: [
        'id',
        'issue_id',
        'condition_grade',
        'purchase_price',
        'estimated_value',
        'loaned_to',
        'updated_at',
      ],
      orderBy: 'issue_id, ordinal, id',
    );
    for (final row in copies) {
      final copyId = row['id'] as String;
      final issueId = row['issue_id'] as String;
      final legacyPrimary = migratedCopyId(issueId, 0);
      final legacySecondary = migratedCopyId(issueId, 1);
      final isV2OnlyIdentity =
          copyId != legacyPrimary && copyId != legacySecondary;
      final hasV2OnlySecondaryDetails =
          copyId == legacySecondary &&
          ((row['condition_grade'] as String).isNotEmpty ||
              row['purchase_price'] != null ||
              row['estimated_value'] != null ||
              (row['loaned_to'] as String).isNotEmpty);
      if ((row['updated_at'] as num).toInt() > legacyCursor ||
          isV2OnlyIdentity ||
          hasV2OnlySecondaryDetails) {
        select(issueId, SyncEntityType.comicCopy, copyId);
      }
    }

    for (final entry in selectedByIssue.entries) {
      final snapshot = await _issueWireSnapshot(database, entry.key);
      await _enqueueMissingChanges(
        database,
        snapshot.where(
          (change) => entry.value.contains(_wireEntityKey(change)),
        ),
      );
    }

    // Barcode overrides never existed in v1, so every mapping is local v2
    // state regardless of its legacy timestamp.
    final barcodeRows = await database.query(
      'barcode_mappings',
      columns: ['barcode'],
      orderBy: 'barcode',
    );
    for (final row in barcodeRows) {
      final snapshot = await _barcodeWireSnapshot(
        database,
        row['barcode'] as String,
      );
      if (snapshot != null) {
        await _enqueueMissingChanges(database, [snapshot]);
      }
    }
  }

  Future<void> _seedFullLocalSnapshot(DatabaseExecutor database) async {
    final issueRows = await database.rawQuery(
      '''
      SELECT issue.id
      FROM catalog_issues issue
      WHERE issue.origin = ?
         OR EXISTS(
           SELECT 1 FROM collection_entries entry
           WHERE entry.issue_id = issue.id
         )
         OR EXISTS(
           SELECT 1 FROM copies copy
           WHERE copy.issue_id = issue.id
         )
      ORDER BY issue.id
    ''',
      [customOrigin],
    );
    for (final row in issueRows) {
      await _enqueueMissingChanges(
        database,
        await _issueWireSnapshot(database, row['id'] as String),
      );
    }
    final barcodeRows = await database.query(
      'barcode_mappings',
      columns: ['barcode'],
      orderBy: 'barcode',
    );
    for (final row in barcodeRows) {
      final snapshot = await _barcodeWireSnapshot(
        database,
        row['barcode'] as String,
      );
      if (snapshot != null) {
        await _enqueueMissingChanges(database, [snapshot]);
      }
    }
  }

  Future<void> _enqueueMissingChanges(
    DatabaseExecutor database,
    Iterable<SyncEntityChange> changes,
  ) async {
    final missing = <SyncEntityChange>[];
    for (final change in changes) {
      final queued = await database.rawQuery(
        '''SELECT 1
           FROM sync_outbox_entities
           WHERE entity_type = ? AND entity_id = ?
           LIMIT 1''',
        [change.entityType.wireName, change.entityId],
      );
      if (queued.isEmpty) missing.add(change);
    }
    await _insertOutboxMutations(database, missing);
  }

  Future<void> _enqueueIssueDifference(
    DatabaseExecutor database,
    String issueId,
    List<SyncEntityChange> before,
  ) async {
    final after = await _issueWireSnapshot(database, issueId);
    await _insertOutboxMutations(database, _wireDifference(before, after));
  }

  Future<List<SyncEntityChange>> _issueWireSnapshot(
    DatabaseExecutor database,
    String issueId,
  ) async {
    if (await _isQuarantined(database, 'issue', issueId)) return const [];
    final issues = await database.query(
      'catalog_issues',
      where: 'id = ?',
      whereArgs: [issueId],
      limit: 1,
    );
    if (issues.isEmpty) return const [];
    final issue = issues.single;
    final hint = _issueHint(issue);
    final changes = <SyncEntityChange>[];

    if (issue['origin'] == customOrigin) {
      changes.add(
        SyncEntityChange(
          entityType: SyncEntityType.customIssue,
          entityId: issueId,
          operation: SyncOperation.upsert,
          data: {
            'series': issue['series'],
            'edition': issue['edition'],
            'number': issue['number'],
            'title': issue['title'],
            'publisher': issue['publisher'],
            'year': issue['year'],
            'page_count': issue['page_count'],
            'writer': issue['writer'],
            'artist': issue['artist'],
          },
        ),
      );
    }

    final entries = await database.query(
      'collection_entries',
      where: 'issue_id = ?',
      whereArgs: [issueId],
      limit: 1,
    );
    if (entries.isNotEmpty) {
      final entry = entries.single;
      final entryDeleted = _optionalBool(entry['deleted']);
      changes.add(
        SyncEntityChange(
          entityType: SyncEntityType.collectionEntry,
          entityId: issueId,
          operation: entryDeleted ? SyncOperation.delete : SyncOperation.upsert,
          data: {
            'issue_id': issueId,
            'owned': _optionalBool(entry['owned']),
            'is_wanted': _optionalBool(entry['is_wanted']),
            'is_read': _optionalBool(entry['is_read']),
            'is_duplicate': _optionalBool(entry['is_duplicate']),
            'rating': entry['rating'],
            'notes': entry['notes'],
            'deleted': entryDeleted,
            'updated_at': entry['updated_at'],
            'issue_hint': hint,
          },
        ),
      );
    }

    final copies = await database.query(
      'copies',
      where: 'issue_id = ?',
      whereArgs: [issueId],
      orderBy: 'ordinal, id',
    );
    for (final copy in copies) {
      final copyId = copy['id'] as String;
      if (await _isQuarantined(database, 'copy', copyId)) continue;
      final copyDeleted = _optionalBool(copy['deleted']);
      changes.add(
        SyncEntityChange(
          entityType: SyncEntityType.comicCopy,
          entityId: copyId,
          operation: copyDeleted ? SyncOperation.delete : SyncOperation.upsert,
          data: {
            'issue_id': issueId,
            'ordinal': copy['ordinal'],
            'active': _optionalBool(copy['active']),
            'condition_grade': copy['condition_grade'],
            'purchase_price': copy['purchase_price'],
            'estimated_value': copy['estimated_value'],
            'loaned_to': copy['loaned_to'],
            'deleted': copyDeleted,
            'updated_at': copy['updated_at'],
            'issue_hint': hint,
          },
        ),
      );
    }
    return changes;
  }

  Future<SyncEntityChange?> _barcodeWireSnapshot(
    DatabaseExecutor database,
    String barcode,
  ) async {
    if (await _isQuarantined(database, 'barcode_mapping', barcode)) {
      return null;
    }
    final mappings = await database.query(
      'barcode_mappings',
      where: 'barcode = ?',
      whereArgs: [barcode],
      limit: 1,
    );
    if (mappings.isEmpty) return null;
    final mapping = mappings.single;
    final issues = await database.query(
      'catalog_issues',
      where: 'id = ?',
      whereArgs: [mapping['issue_id']],
      limit: 1,
    );
    if (issues.isEmpty) {
      throw StateError('Barcode $barcode references an unknown issue.');
    }
    final mappingDeleted = _optionalBool(mapping['deleted']);
    return SyncEntityChange(
      entityType: SyncEntityType.barcodeMapping,
      entityId: barcode,
      operation: mappingDeleted ? SyncOperation.delete : SyncOperation.upsert,
      data: {
        'issue_id': mapping['issue_id'],
        'deleted': mappingDeleted,
        'updated_at': mapping['updated_at'],
        'issue_hint': _issueHint(issues.single),
      },
    );
  }

  Future<bool> _isQuarantined(
    DatabaseExecutor database,
    String entityType,
    String entityId,
  ) async {
    final rows = await database.query(
      'sync_quarantine',
      columns: ['id'],
      where: 'entity_type = ? AND entity_id = ?',
      whereArgs: [entityType, entityId],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  Future<void> _insertOutboxMutations(
    DatabaseExecutor database,
    List<SyncEntityChange> changes,
  ) async {
    if (changes.isEmpty) return;
    // A collection tombstone is an observed-remove operation. If an issue has
    // more copies than fit in one protocol mutation, every observed copy must
    // be tombstoned before the aggregate entry is deleted. Otherwise an early
    // entry tombstone is correctly canonicalized back to an upsert while a
    // later copy-only chunk has no instruction left to delete the entry.
    final orderedChanges = [
      for (final change in changes)
        if (!_isCollectionTombstone(change)) change,
      for (final change in changes)
        if (_isCollectionTombstone(change)) change,
    ];
    for (var start = 0; start < orderedChanges.length;) {
      final remaining = orderedChanges.length - start;
      final chunkLength = remaining < _maximumChangesPerMutation
          ? remaining
          : _maximumChangesPerMutation;
      final chunk = orderedChanges.sublist(start, start + chunkLength);
      final mutation = SyncMutation(
        mutationId: _idGenerator(),
        createdAt: _nowMilliseconds(),
        changes: chunk,
      );
      SyncV2UploadValidator.validateMutation(mutation.toJson());
      await database.insert('sync_outbox', {
        'mutation_id': mutation.mutationId,
        'created_at': mutation.createdAt,
        'changes_json': jsonEncode(mutation.toJson()),
        'ack_revision': null,
        'ack_status': null,
      });
      for (final change in mutation.changes) {
        await database.insert('sync_outbox_entities', {
          'mutation_id': mutation.mutationId,
          'entity_type': change.entityType.wireName,
          'entity_id': change.entityId,
        });
      }
      start += chunkLength;
    }
  }

  Future<int> _entityRevision(
    DatabaseExecutor database,
    SyncEntityChange change,
  ) async {
    final rows = await database.query(
      'sync_entity_versions',
      columns: ['revision'],
      where: 'entity_type = ? AND entity_id = ?',
      whereArgs: [change.entityType.wireName, change.entityId],
      limit: 1,
    );
    return rows.isEmpty ? 0 : (rows.single['revision'] as num).toInt();
  }

  Future<bool> _hasNewerLocalMutation(
    DatabaseExecutor database,
    SyncEntityChange change,
    int remoteRevision,
  ) async {
    final rows = await database.rawQuery(
      '''SELECT 1
         FROM sync_outbox_entities entity
         JOIN sync_outbox outbox
           ON outbox.mutation_id = entity.mutation_id
         WHERE entity.entity_type = ?
           AND entity.entity_id = ?
           AND (outbox.ack_revision IS NULL OR outbox.ack_revision > ?)
         LIMIT 1''',
      [change.entityType.wireName, change.entityId, remoteRevision],
    );
    return rows.isNotEmpty;
  }

  Future<void> _saveEntityRevision(
    DatabaseExecutor database,
    SyncEntityChange change,
    int revision,
  ) async {
    await database.insert('sync_entity_versions', {
      'entity_type': change.entityType.wireName,
      'entity_id': change.entityId,
      'revision': revision,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
    await database.update(
      'sync_entity_versions',
      {'revision': revision},
      where: 'entity_type = ? AND entity_id = ? AND revision < ?',
      whereArgs: [change.entityType.wireName, change.entityId, revision],
    );
  }

  Future<String?> _applyRemoteChange(
    DatabaseExecutor database,
    SyncEntityChange change,
    int serverTime,
  ) => switch (change.entityType) {
    SyncEntityType.customIssue => _applyRemoteCustomIssue(
      database,
      change,
      serverTime,
    ),
    SyncEntityType.collectionEntry => _applyRemoteCollectionEntry(
      database,
      change,
      serverTime,
    ),
    SyncEntityType.comicCopy => _applyRemoteCopy(database, change, serverTime),
    SyncEntityType.barcodeMapping => _applyRemoteBarcode(
      database,
      change,
      serverTime,
    ),
  };

  Future<String?> _applyRemoteCustomIssue(
    DatabaseExecutor database,
    SyncEntityChange change,
    int serverTime,
  ) async {
    final current = await database.query(
      'catalog_issues',
      where: 'id = ?',
      whereArgs: [change.entityId],
      limit: 1,
    );
    if (change.operation == SyncOperation.delete) {
      if (current.isEmpty || current.single['origin'] == bundledOrigin) {
        return null;
      }
      final entries = await database.query(
        'collection_entries',
        where: 'issue_id = ?',
        whereArgs: [change.entityId],
        limit: 1,
      );
      final entry = entries.isEmpty
          ? CollectionEntry(issueId: change.entityId, updatedAt: serverTime)
          : CollectionEntry.fromMap(entries.single);
      await _upsertCollectionEntry(
        database,
        entry.copyWith(
          owned: false,
          wanted: false,
          deleted: true,
          updatedAt: serverTime,
        ),
      );
      await database.update(
        'copies',
        {'active': 0, 'deleted': 1, 'updated_at': serverTime},
        where: 'issue_id = ?',
        whereArgs: [change.entityId],
      );
      return change.entityId;
    }
    if (current.isNotEmpty && current.single['origin'] == bundledOrigin) {
      return null;
    }
    final data = change.data;
    final values = <String, Object?>{
      'id': change.entityId,
      'series': _requiredText(data, 'series'),
      'edition': _requiredText(data, 'edition'),
      'number': _requiredInt(data, 'number'),
      'title': _requiredText(data, 'title'),
      'publisher': _optionalText(data['publisher']),
      'year': _optionalInt(data['year']),
      'page_count': _optionalInt(data['page_count']),
      'writer': _optionalText(data['writer']),
      'artist': _optionalText(data['artist']),
      'origin': customOrigin,
      'source_edition': '',
      'metadata_updated_at': serverTime,
    };
    if (current.isEmpty) {
      values['cover_asset'] = '';
      await database.insert('catalog_issues', values);
    } else {
      values
        ..remove('id')
        ..remove('cover_asset');
      await database.update(
        'catalog_issues',
        values,
        where: 'id = ?',
        whereArgs: [change.entityId],
      );
    }
    return null;
  }

  Future<String?> _applyRemoteCollectionEntry(
    DatabaseExecutor database,
    SyncEntityChange change,
    int serverTime,
  ) async {
    final issueId = _optionalText(
      change.data['issue_id'],
      fallback: change.entityId,
    );
    await _ensureRemoteIssue(database, issueId, change.data, serverTime);
    final currentRows = await database.query(
      'collection_entries',
      where: 'issue_id = ?',
      whereArgs: [issueId],
      limit: 1,
    );
    final current = currentRows.isEmpty
        ? CollectionEntry(issueId: issueId, updatedAt: serverTime)
        : CollectionEntry.fromMap(currentRows.single);
    final data = change.data;
    final deleted = change.operation == SyncOperation.delete
        ? true
        : _optionalBool(data['deleted'], fallback: current.deleted);
    await _upsertCollectionEntry(
      database,
      current.copyWith(
        owned: _optionalBool(data['owned'], fallback: current.owned),
        wanted: _optionalBool(data['is_wanted'], fallback: current.wanted),
        read: _optionalBool(data['is_read'], fallback: current.read),
        duplicate: _optionalBool(
          data['is_duplicate'],
          fallback: current.duplicate,
        ),
        rating: _optionalInt(data['rating']) ?? current.rating,
        notes: _optionalText(data['notes'], fallback: current.notes),
        deleted: deleted,
        updatedAt: _optionalInt(data['updated_at']) ?? serverTime,
      ),
    );
    return null;
  }

  Future<String?> _applyRemoteCopy(
    DatabaseExecutor database,
    SyncEntityChange change,
    int serverTime,
  ) async {
    final issueId = _requiredText(change.data, 'issue_id');
    await _ensureRemoteIssue(database, issueId, change.data, serverTime);
    final currentRows = await database.query(
      'copies',
      where: 'id = ?',
      whereArgs: [change.entityId],
      limit: 1,
    );
    final current = currentRows.isEmpty
        ? ComicCopy(
            id: change.entityId,
            issueId: issueId,
            ordinal:
                _optionalInt(change.data['ordinal']) ??
                await _nextCopyOrdinal(database, issueId),
            updatedAt: serverTime,
          )
        : ComicCopy.fromMap(currentRows.single);
    final deleted = change.operation == SyncOperation.delete
        ? true
        : _optionalBool(change.data['deleted'], fallback: current.deleted);
    await _upsertCopy(
      database,
      current.copyWith(
        issueId: issueId,
        ordinal: _optionalInt(change.data['ordinal']) ?? current.ordinal,
        active: deleted
            ? false
            : _optionalBool(change.data['active'], fallback: current.active),
        condition: _optionalText(
          change.data['condition_grade'],
          fallback: current.condition,
        ),
        purchasePrice: change.data.containsKey('purchase_price')
            ? _optionalDouble(change.data['purchase_price'])
            : current.purchasePrice,
        estimatedValue: change.data.containsKey('estimated_value')
            ? _optionalDouble(change.data['estimated_value'])
            : current.estimatedValue,
        loanedTo: _optionalText(
          change.data['loaned_to'],
          fallback: current.loanedTo,
        ),
        deleted: deleted,
        updatedAt: _optionalInt(change.data['updated_at']) ?? serverTime,
      ),
    );
    return issueId;
  }

  Future<String?> _applyRemoteBarcode(
    DatabaseExecutor database,
    SyncEntityChange change,
    int serverTime,
  ) async {
    final issueId = _requiredText(change.data, 'issue_id');
    await _ensureRemoteIssue(database, issueId, change.data, serverTime);
    final deleted = change.operation == SyncOperation.delete
        ? 1
        : _optionalBool(change.data['deleted'])
        ? 1
        : 0;
    await database.insert('barcode_mappings', {
      'barcode': change.entityId,
      'issue_id': issueId,
      'deleted': deleted,
      'updated_at': _optionalInt(change.data['updated_at']) ?? serverTime,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
    await database.update(
      'barcode_mappings',
      {
        'issue_id': issueId,
        'deleted': deleted,
        'updated_at': _optionalInt(change.data['updated_at']) ?? serverTime,
      },
      where: 'barcode = ?',
      whereArgs: [change.entityId],
    );
    return null;
  }

  Future<void> _ensureRemoteIssue(
    DatabaseExecutor database,
    String issueId,
    Map<String, Object?> data,
    int serverTime,
  ) async {
    final existing = await database.query(
      'catalog_issues',
      columns: ['id'],
      where: 'id = ?',
      whereArgs: [issueId],
      limit: 1,
    );
    if (existing.isNotEmpty) return;
    final hintValue = data['issue_hint'];
    if (hintValue is! Map) {
      throw FormatException('Missing issue_hint for $issueId.');
    }
    final hint = Map<String, Object?>.from(hintValue);
    await database.insert('catalog_issues', {
      'id': issueId,
      'series': _requiredText(hint, 'series'),
      'edition': _requiredText(hint, 'edition'),
      'number': _requiredInt(hint, 'number'),
      'title': _requiredText(hint, 'title'),
      'publisher': _optionalText(hint['publisher']),
      'year': _optionalInt(hint['year']),
      'cover_asset': '',
      'page_count': null,
      'writer': '',
      'artist': '',
      'origin': hint['origin'] == customOrigin ? customOrigin : bundledOrigin,
      'source_edition': _sourceEdition(issueId),
      'metadata_updated_at': serverTime,
    });
  }

  Future<int> _nextCopyOrdinal(
    DatabaseExecutor database,
    String issueId,
  ) async {
    final rows = await database.rawQuery(
      'SELECT MAX(ordinal) AS max_ordinal FROM copies WHERE issue_id = ?',
      [issueId],
    );
    final maximum = (rows.single['max_ordinal'] as num?)?.toInt();
    return maximum == null ? 0 : maximum + 1;
  }

  Future<void> _recomputeCollectionFlags(
    DatabaseExecutor database,
    String issueId,
    int serverTime,
  ) async {
    final counts = await database.rawQuery(
      '''SELECT COUNT(*) AS active_count
         FROM copies
         WHERE issue_id = ? AND active = 1 AND deleted = 0''',
      [issueId],
    );
    final activeCount = (counts.single['active_count'] as num).toInt();
    final rows = await database.query(
      'collection_entries',
      where: 'issue_id = ?',
      whereArgs: [issueId],
      limit: 1,
    );
    final current = rows.isEmpty
        ? CollectionEntry(issueId: issueId, updatedAt: serverTime)
        : CollectionEntry.fromMap(rows.single);
    await _upsertCollectionEntry(
      database,
      current.copyWith(
        owned: activeCount > 0,
        wanted: activeCount == 0 && !current.deleted,
        duplicate: activeCount > 1,
        updatedAt: current.updatedAt > serverTime
            ? current.updatedAt
            : serverTime,
      ),
    );
  }

  Future<void> mergeRemote(Iterable<Comic> remote) async {
    final db = await database;
    await db.transaction((transaction) async {
      await _mergeRemoteIntoTransaction(
        transaction,
        remote,
        enqueueSyncV2: true,
      );
    });
  }

  Future<void> _mergeRemoteIntoTransaction(
    DatabaseExecutor transaction,
    Iterable<Comic> remote, {
    required bool enqueueSyncV2,
  }) async {
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
        final before = enqueueSyncV2
            ? await _issueWireSnapshot(transaction, comic.id)
            : const <SyncEntityChange>[];
        final localCover = localState.isEmpty
            ? ''
            : (localState.single['cover_asset'] as String? ?? '');
        final merged = comic.coverAsset.isEmpty && localCover.isNotEmpty
            ? comic.copyWith(coverAsset: localCover)
            : comic;
        await _upsertComic(transaction, merged);
        if (enqueueSyncV2) {
          await _enqueueIssueDifference(transaction, comic.id, before);
        }
      }
    }
  }

  Future<void> close() async {
    final db = _db;
    _db = null;
    await db?.close();
  }
}

final class _SyncState {
  const _SyncState({
    required this.deviceId,
    required this.serverId,
    required this.cursor,
    required this.bootstrapped,
    required this.legacySeeded,
    required this.baselineComplete,
    required this.forceFullExport,
    required this.legacyCursor,
    required this.v1FallbackPending,
    required this.v1FallbackCursor,
    required this.v1FallbackOutboxSequence,
    this.lastSuccessAt,
  });

  factory _SyncState.fromMap(Map<String, Object?> map) => _SyncState(
    deviceId: map['device_id'] as String,
    serverId: map['server_id'] as String,
    cursor: (map['cursor'] as num).toInt(),
    bootstrapped: (map['bootstrapped'] as num) != 0,
    legacySeeded: (map['legacy_seeded'] as num) != 0,
    baselineComplete: (map['baseline_complete'] as num) != 0,
    forceFullExport: (map['force_full_export'] as num) != 0,
    legacyCursor: (map['legacy_cursor'] as num).toInt(),
    v1FallbackPending: (map['v1_fallback_pending'] as num) != 0,
    v1FallbackCursor: (map['v1_fallback_cursor'] as num).toInt(),
    v1FallbackOutboxSequence: (map['v1_fallback_outbox_sequence'] as num)
        .toInt(),
    lastSuccessAt: (map['last_success_at'] as num?)?.toInt(),
  );

  final String deviceId;
  final String serverId;
  final int cursor;
  final bool bootstrapped;
  final bool legacySeeded;
  final bool baselineComplete;
  final bool forceFullExport;
  final int legacyCursor;
  final bool v1FallbackPending;
  final int v1FallbackCursor;
  final int v1FallbackOutboxSequence;
  final int? lastSuccessAt;

  _SyncState copyWith({
    String? deviceId,
    String? serverId,
    int? cursor,
    bool? bootstrapped,
    bool? legacySeeded,
    bool? baselineComplete,
    bool? forceFullExport,
    int? legacyCursor,
    bool? v1FallbackPending,
    int? v1FallbackCursor,
    int? v1FallbackOutboxSequence,
    int? lastSuccessAt,
  }) => _SyncState(
    deviceId: deviceId ?? this.deviceId,
    serverId: serverId ?? this.serverId,
    cursor: cursor ?? this.cursor,
    bootstrapped: bootstrapped ?? this.bootstrapped,
    legacySeeded: legacySeeded ?? this.legacySeeded,
    baselineComplete: baselineComplete ?? this.baselineComplete,
    forceFullExport: forceFullExport ?? this.forceFullExport,
    legacyCursor: legacyCursor ?? this.legacyCursor,
    v1FallbackPending: v1FallbackPending ?? this.v1FallbackPending,
    v1FallbackCursor: v1FallbackCursor ?? this.v1FallbackCursor,
    v1FallbackOutboxSequence:
        v1FallbackOutboxSequence ?? this.v1FallbackOutboxSequence,
    lastSuccessAt: lastSuccessAt ?? this.lastSuccessAt,
  );

  Map<String, Object?> toMap() => {
    'id': 1,
    'device_id': deviceId,
    'server_id': serverId,
    'cursor': cursor,
    'bootstrapped': bootstrapped ? 1 : 0,
    'legacy_seeded': legacySeeded ? 1 : 0,
    'baseline_complete': baselineComplete ? 1 : 0,
    'force_full_export': forceFullExport ? 1 : 0,
    'legacy_cursor': legacyCursor,
    'v1_fallback_pending': v1FallbackPending ? 1 : 0,
    'v1_fallback_cursor': v1FallbackCursor,
    'v1_fallback_outbox_sequence': v1FallbackOutboxSequence,
    'last_success_at': lastSuccessAt,
  };
}

SyncMutation _decodeMutation(String encoded) {
  final decoded = jsonDecode(encoded);
  if (decoded is! Map) {
    throw const FormatException('Stored sync mutation is not an object.');
  }
  return SyncMutation.fromJson(Map<String, Object?>.from(decoded));
}

bool _isCollectionTombstone(SyncEntityChange change) =>
    change.entityType == SyncEntityType.collectionEntry &&
    change.operation == SyncOperation.delete;

List<SyncEntityChange> _wireDifference(
  List<SyncEntityChange> before,
  List<SyncEntityChange> after,
) {
  final previous = <String, SyncEntityChange>{
    for (final change in before) _wireEntityKey(change): change,
  };
  final changed = [
    for (final change in after)
      if (!_sameWireEntity(previous[_wireEntityKey(change)], change)) change,
  ];
  final copyIssues = changed
      .where((change) => change.entityType == SyncEntityType.comicCopy)
      .map((change) => change.data['issue_id'])
      .whereType<String>()
      .toSet();
  return [
    for (final change in changed)
      if (change.entityType != SyncEntityType.collectionEntry ||
          !copyIssues.contains(change.entityId) ||
          !_onlyDerivedCollectionStateChanged(
            previous[_wireEntityKey(change)],
            change,
          ))
        change,
  ];
}

bool _onlyDerivedCollectionStateChanged(
  SyncEntityChange? before,
  SyncEntityChange after,
) {
  if (after.operation != SyncOperation.upsert) return false;
  final afterData = after.data;
  if (before == null) {
    return afterData['is_read'] == false &&
        afterData['rating'] == 0 &&
        afterData['notes'] == '' &&
        afterData['deleted'] == false;
  }
  if (before.operation != after.operation) return false;
  const nonDerivedFields = {
    'issue_id',
    'is_read',
    'rating',
    'notes',
    'deleted',
  };
  for (final field in nonDerivedFields) {
    if (!_sameJsonValue(before.data[field], afterData[field])) return false;
  }
  return true;
}

String _wireEntityKey(SyncEntityChange change) =>
    '${change.entityType.wireName}\u0000${change.entityId}';

bool _sameWireEntity(SyncEntityChange? before, SyncEntityChange after) {
  if (before == null || before.operation != after.operation) return false;
  final beforeData = Map<String, Object?>.from(before.data)
    ..remove('updated_at')
    ..remove('issue_hint');
  final afterData = Map<String, Object?>.from(after.data)
    ..remove('updated_at')
    ..remove('issue_hint');
  return _sameJsonValue(beforeData, afterData);
}

bool _sameJsonValue(Object? left, Object? right) {
  if (left is Map && right is Map) {
    if (left.length != right.length) return false;
    for (final entry in left.entries) {
      if (!right.containsKey(entry.key) ||
          !_sameJsonValue(entry.value, right[entry.key])) {
        return false;
      }
    }
    return true;
  }
  if (left is List && right is List) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index++) {
      if (!_sameJsonValue(left[index], right[index])) return false;
    }
    return true;
  }
  return left == right;
}

Map<String, Object?> _issueHint(Map<String, Object?> issue) => {
  'id': issue['id'],
  'series': issue['series'],
  'edition': issue['edition'],
  'number': issue['number'],
  'title': issue['title'],
  'publisher': issue['publisher'],
  'year': issue['year'],
  'origin': issue['origin'],
};

String _requiredText(Map<String, Object?> data, String key) {
  final value = data[key];
  if (value is! String) throw FormatException('$key must be text.');
  return value;
}

String _optionalText(Object? value, {String fallback = ''}) => switch (value) {
  null => fallback,
  String text => text,
  _ => throw const FormatException('Expected text.'),
};

int _requiredInt(Map<String, Object?> data, String key) {
  final value = _optionalInt(data[key]);
  if (value == null) throw FormatException('$key must be an integer.');
  return value;
}

int? _optionalInt(Object? value) => switch (value) {
  null => null,
  int number => number,
  num number when number.isFinite && number == number.truncate() =>
    number.toInt(),
  _ => throw const FormatException('Expected an integer.'),
};

double? _optionalDouble(Object? value) => switch (value) {
  null => null,
  num number when number.isFinite => number.toDouble(),
  _ => throw const FormatException('Expected a number.'),
};

bool _optionalBool(Object? value, {bool fallback = false}) => switch (value) {
  null => fallback,
  bool flag => flag,
  num number when number == 0 => false,
  num number when number == 1 => true,
  _ => throw const FormatException('Expected a boolean.'),
};

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
               selected_copy.ordinal,
               selected_copy.id
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
  final currentPrimaryRows = await database.query(
    'copies',
    columns: ['id', 'ordinal'],
    where: 'issue_id = ?',
    whereArgs: [comic.id],
    orderBy:
        'CASE WHEN active = 1 AND deleted = 0 THEN 0 ELSE 1 END, ordinal, id',
    limit: 1,
  );
  final primaryId = currentPrimaryRows.isEmpty
      ? migratedCopyId(comic.id, 0)
      : currentPrimaryRows.single['id'] as String;
  final primaryOrdinal = currentPrimaryRows.isEmpty
      ? 0
      : (currentPrimaryRows.single['ordinal'] as num).toInt();
  await _upsertCopy(
    database,
    ComicCopy(
      id: primaryId,
      issueId: comic.id,
      ordinal: primaryOrdinal,
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
      where: 'issue_id = ? AND id <> ?',
      whereArgs: [comic.id, primaryId],
      orderBy: 'ordinal, id',
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
      where: 'issue_id = ? AND id <> ?',
      whereArgs: [comic.id, primaryId],
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
    columns: ['id', 'issue_id'],
    where: 'id = ?',
    whereArgs: [copy.id],
    limit: 1,
  );
  if (byId.isEmpty) {
    await database.insert('copies', copy.toMap());
    return;
  }
  final existingIssueId = byId.single['issue_id'] as String;
  if (existingIssueId != copy.issueId) {
    throw StateError(
      'Copy ${copy.id} belongs to $existingIssueId and cannot be moved to '
      '${copy.issueId}.',
    );
  }

  final values = Map<String, Object?>.from(copy.toMap())
    ..remove('id')
    ..remove('issue_id');
  final updated = await database.update(
    'copies',
    values,
    where: 'id = ?',
    whereArgs: [copy.id],
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
