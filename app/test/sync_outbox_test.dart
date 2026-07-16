import 'dart:convert';

import 'package:comicollect/data/database_schema.dart';
import 'package:comicollect/data/local_database.dart';
import 'package:comicollect/models/comic.dart';
import 'package:comicollect/models/sync_v2.dart';
import 'package:comicollect/models/sync_v2_upload_validator.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late LocalDatabase database;
  late int id;
  late int now;

  setUp(() {
    id = 0;
    now = 1000;
    database = LocalDatabase(
      pathOverride: inMemoryDatabasePath,
      idGenerator: () => 'generated-${++id}',
      nowMilliseconds: () => now++,
    );
  });

  tearDown(() => database.close());

  test(
    'first v2 exchange is pull-only and then exposes a complete local snapshot',
    () async {
      await database.upsert(
        _comic(
          'manual-1',
          owned: true,
        ).copyWith(coverAsset: 'assets/device-only.webp'),
      );
      await database.saveBarcodeMapping('978123', 'manual-1');

      final pull = await database.prepareSyncV2();
      expect(pull.deviceId, 'generated-3');
      expect(pull.serverId, isEmpty);
      expect(pull.cursor, 0);
      expect(pull.mutations, isEmpty);
      expect((await database.prepareSyncV2()).mutations, isEmpty);

      await database.applySyncV2(
        _exchange(serverId: 'server-a', nextCursor: 0),
      );
      final batch = await database.prepareSyncV2();
      expect(batch.serverId, 'server-a');
      expect(batch.mutations, hasLength(3));
      final changes = [
        for (final mutation in batch.mutations) ...mutation.changes,
      ];
      expect(changes.map((change) => change.entityType).toSet(), {
        SyncEntityType.customIssue,
        SyncEntityType.collectionEntry,
        SyncEntityType.comicCopy,
        SyncEntityType.barcodeMapping,
      });
      final custom = changes.singleWhere(
        (change) => change.entityType == SyncEntityType.customIssue,
      );
      expect(custom.data, isNot(contains('cover_asset')));
      expect(custom.data['title'], 'Broj 1');
      final entry = changes.singleWhere(
        (change) => change.entityType == SyncEntityType.collectionEntry,
      );
      expect(entry.data['issue_hint'], isA<Map>());
      final barcode = changes.singleWhere(
        (change) => change.entityType == SyncEntityType.barcodeMapping,
      );
      expect(barcode.entityId, '978123');

      final request = batch.toRequestJson(requestId: 'request-1', limit: 100);
      final requestMutations = request['mutations'] as List;
      final requestChanges = [
        for (final mutation in requestMutations)
          ...(_jsonMap(mutation)['changes'] as List).map(_jsonMap),
      ];
      final entryChange = requestChanges.singleWhere(
        (change) => change['entity_type'] == 'collection_entry',
      );
      final entryData = _jsonMap(entryChange['data']);
      expect(entryChange['operation'], 'upsert');
      expect(entryData['owned'], isA<bool>());
      expect(entryData['is_wanted'], isA<bool>());
      expect(entryData['is_read'], isA<bool>());
      expect(entryData['is_duplicate'], isA<bool>());
      expect(entryData['deleted'], isA<bool>());
      expect(entryData['owned'], isTrue);
      expect(entryData['deleted'], isFalse);
      expect(_jsonMap(entryData['issue_hint']), containsPair('id', 'manual-1'));
      expect(
        _jsonMap(entryData['issue_hint']),
        containsPair('origin', 'custom'),
      );

      final copyData = _jsonMap(
        requestChanges.singleWhere(
          (change) => change['entity_type'] == 'copy',
        )['data'],
      );
      expect(copyData['active'], isA<bool>());
      expect(copyData['deleted'], isA<bool>());
      final barcodeChange = requestChanges.singleWhere(
        (change) => change['entity_type'] == 'barcode_mapping',
      );
      final barcodeData = _jsonMap(barcodeChange['data']);
      expect(barcodeChange['operation'], 'upsert');
      expect(barcodeData['deleted'], isA<bool>());
      expect(
        _jsonMap(barcodeData['issue_hint']),
        containsPair('id', 'manual-1'),
      );

      final repeated = await database.prepareSyncV2();
      expect(repeated.deviceId, batch.deviceId);
      expect(
        repeated.mutations.map((mutation) => mutation.mutationId),
        batch.mutations.map((mutation) => mutation.mutationId),
      );
      expect(await database.hasPendingSyncV2(), isTrue);
    },
  );

  test('clean legacy state yields to a newer remote baseline', () async {
    await database.upsert(_comic('legacy-clean', owned: true));
    final sqlite = await database.database;
    await sqlite.delete('sync_outbox');

    final pull = await database.prepareSyncV2(legacyCursor: 100);
    expect(pull.mutations, isEmpty);

    await database.applySyncV2(
      _exchange(
        serverId: 'server-a',
        nextCursor: 1,
        changeGroups: [
          SyncChangeGroup(
            revision: 1,
            mutationId: 'newer-remote-metadata',
            changes: [_remoteCustomIssue('legacy-clean')],
          ),
        ],
      ),
    );

    expect((await database.all()).single.title, 'Udaljeni broj');
    expect(
      (await database.prepareSyncV2(legacyCursor: 100)).mutations,
      isEmpty,
    );
    expect(await database.hasPendingSyncV2(), isFalse);
  });

  test('dirty legacy entry does not protect its clean sibling copy', () async {
    await database.upsert(
      _comic(
        'legacy-siblings',
        owned: true,
      ).copyWith(duplicate: true, notes: 'lokalna bilješka'),
    );
    final sqlite = await database.database;
    await sqlite.delete('sync_outbox');
    await sqlite.update(
      'collection_entries',
      {'updated_at': 200},
      where: 'issue_id = ?',
      whereArgs: ['legacy-siblings'],
    );

    final pull = await database.prepareSyncV2(legacyCursor: 100);
    expect(pull.mutations, isEmpty);
    final secondaryId = migratedCopyId('legacy-siblings', 1);
    await database.applySyncV2(
      _exchange(
        serverId: 'server-a',
        nextCursor: 1,
        changeGroups: [
          SyncChangeGroup(
            revision: 1,
            mutationId: 'newer-remote-copy',
            changes: [
              _remoteCopy(
                secondaryId,
                'legacy-siblings',
                _hint('legacy-siblings'),
                condition: 'G',
                updatedAt: 300,
              ),
            ],
          ),
        ],
      ),
    );

    final secondary = (await database.copiesForIssue(
      'legacy-siblings',
    )).singleWhere((copy) => copy.id == secondaryId);
    expect(secondary.condition, 'G');
    expect((await database.all()).single.notes, 'lokalna bilješka');

    final upload = await database.prepareSyncV2(legacyCursor: 100);
    final changes = [
      for (final mutation in upload.mutations) ...mutation.changes,
    ];
    expect(changes, hasLength(1));
    expect(changes.single.entityType, SyncEntityType.collectionEntry);
    expect(changes.single.entityId, 'legacy-siblings');
  });

  test('empty server exports a complete clean legacy snapshot', () async {
    await database.upsert(_comic('legacy-only', owned: true));
    final sqlite = await database.database;
    await sqlite.delete('sync_outbox');

    final pull = await database.prepareSyncV2(legacyCursor: 100);
    expect(pull.mutations, isEmpty);
    await database.applySyncV2(
      _exchange(serverId: 'empty-server', nextCursor: 0),
    );

    final upload = await database.prepareSyncV2(legacyCursor: 100);
    final changes = [
      for (final mutation in upload.mutations) ...mutation.changes,
    ];
    expect(changes.map((change) => change.entityType).toSet(), {
      SyncEntityType.customIssue,
      SyncEntityType.collectionEntry,
      SyncEntityType.comicCopy,
    });
    expect(changes.map((change) => change.entityId), contains('legacy-only'));
  });

  test(
    'server rebind stages the full snapshot before a non-empty baseline',
    () async {
      await database.upsert(_comic('rebound', owned: true));
      await _settleCurrentBatch(database, serverId: 'old-server');
      await database.resetSyncV2Binding();

      final pull = await database.prepareSyncV2(legacyCursor: 9999);
      expect(pull.serverId, isEmpty);
      expect(pull.mutations, isEmpty);

      await database.applySyncV2(
        _exchange(
          serverId: 'new-server',
          nextCursor: 1,
          changeGroups: [
            SyncChangeGroup(
              revision: 1,
              mutationId: 'new-server-conflict',
              changes: [_remoteCustomIssue('rebound')],
            ),
          ],
        ),
      );

      expect((await database.all()).single.title, 'Broj 1');
      final upload = await database.prepareSyncV2(legacyCursor: 9999);
      final custom =
          [
            for (final mutation in upload.mutations) ...mutation.changes,
          ].singleWhere(
            (change) => change.entityType == SyncEntityType.customIssue,
          );
      expect(custom.entityId, 'rebound');
      expect(custom.data['title'], 'Broj 1');
    },
  );

  test('every baseline page remains pull-only until the final page', () async {
    await database.upsert(_comic('pending-local', owned: true));

    final firstPull = await database.prepareSyncV2();
    expect(firstPull.mutations, isEmpty);
    await database.applySyncV2(
      _exchange(
        serverId: 'paged-server',
        nextCursor: 1,
        hasMore: true,
        changeGroups: [
          SyncChangeGroup(
            revision: 1,
            mutationId: 'baseline-page-1',
            changes: [_remoteCustomIssue('remote-page-1')],
          ),
        ],
      ),
    );

    final secondPull = await database.prepareSyncV2();
    expect(secondPull.cursor, 1);
    expect(secondPull.mutations, isEmpty);
    await database.applySyncV2(
      _exchange(
        serverId: 'paged-server',
        nextCursor: 2,
        changeGroups: [
          SyncChangeGroup(
            revision: 2,
            mutationId: 'baseline-page-2',
            changes: [_remoteCustomIssue('remote-page-2')],
          ),
        ],
      ),
    );

    final upload = await database.prepareSyncV2();
    expect(upload.cursor, 2);
    expect(upload.mutations, isNotEmpty);
    expect(
      upload.mutations
          .expand((mutation) => mutation.changes)
          .map((change) => change.entityId),
      contains('pending-local'),
    );
  });

  test('durable legacy cursor wins if preferences lag after a crash', () async {
    await database.upsert(_comic('durable-v1-cursor', owned: true));
    await database.prepareSyncV2(legacyCursor: 5);
    final fallback = await database.prepareV1Fallback(5);
    expect(fallback.changes.map((comic) => comic.id), ['durable-v1-cursor']);
    await database.completeV1Fallback(const [], 100);

    // Simulate SharedPreferences still containing the pre-request cursor.
    final pull = await database.prepareSyncV2(legacyCursor: 5);
    expect(pull.mutations, isEmpty);
    final state = (await (await database.database).query('sync_state')).single;
    expect(state['legacy_cursor'], 100);
    expect(state['v1_fallback_pending'], 0);
    expect(await (await database.database).query('sync_outbox'), isEmpty);
  });

  test(
    'domain state and immutable outbox insertion roll back together',
    () async {
      await database.close();
      database = LocalDatabase(
        pathOverride: inMemoryDatabasePath,
        idGenerator: () => 'same-mutation-id',
        nowMilliseconds: () => 1000,
      );
      await database.upsert(_comic('one'));

      await expectLater(
        database.upsert(_comic('two')),
        throwsA(isA<DatabaseException>()),
      );

      expect((await database.all()).map((comic) => comic.id), ['one']);
      final db = await database.database;
      expect(await db.query('sync_outbox'), hasLength(1));
      expect(await db.query('sync_outbox_entities'), hasLength(2));
    },
  );

  test(
    'server-invalid domain values roll back both state and outbox',
    () async {
      final cases = <(String, Comic)>[
        ('condition_grade', _comic('bad-condition').copyWith(condition: 'NM')),
        ('purchase_price', _comic('bad-price').copyWith(purchasePrice: -1)),
        (
          'title',
          _comic('bad-title').copyWith(title: List.filled(251, 'ž').join()),
        ),
      ];

      for (final (field, comic) in cases) {
        await expectLater(
          database.upsert(comic),
          throwsA(
            isA<FormatException>().having(
              (error) => error.message.toString(),
              'message',
              contains(field),
            ),
          ),
          reason: field,
        );

        final sqlite = await database.database;
        for (final table in [
          'catalog_issues',
          'collection_entries',
          'copies',
          'sync_outbox',
          'sync_outbox_entities',
        ]) {
          expect(await sqlite.query(table), isEmpty, reason: '$field/$table');
        }
      }
    },
  );

  test('prepare rejects a poisoned mutation already stored on disk', () async {
    await database.upsert(_comic('one', owned: true));
    final pull = await database.prepareSyncV2();
    final sqlite = await database.database;
    final rows = await sqlite.query('sync_outbox');
    final row = rows.singleWhere((candidate) {
      final mutation = jsonDecode(candidate['changes_json']! as String) as Map;
      return (mutation['changes']! as List).cast<Map>().any(
        (change) => change['entity_type'] == 'copy',
      );
    });
    final mutation = jsonDecode(row['changes_json']! as String) as Map;
    final changes = mutation['changes']! as List;
    final copy = changes.cast<Map>().firstWhere(
      (change) => change['entity_type'] == 'copy',
    );
    (copy['data']! as Map)['condition_grade'] = 'NM';
    await sqlite.update(
      'sync_outbox',
      {'changes_json': jsonEncode(mutation)},
      where: 'mutation_id = ?',
      whereArgs: [row['mutation_id']],
    );
    await database.applySyncV2(
      _exchange(serverId: 'server-a', nextCursor: pull.cursor),
    );

    await expectLater(
      database.prepareSyncV2(),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message.toString(),
          'message',
          contains('condition_grade'),
        ),
      ),
    );
    expect(await sqlite.query('sync_outbox'), hasLength(2));
  });

  test('read and rating update queues only collection entry', () async {
    final original = _comic('one', owned: true);
    await database.upsert(original);
    await _settleCurrentBatch(database);

    await database.upsert(
      original.copyWith(read: true, rating: 4, updatedAt: 20),
    );

    final batch = await database.prepareSyncV2();
    expect(batch.mutations, hasLength(1));
    final changes = batch.mutations.single.changes;
    expect(changes, hasLength(1));
    expect(changes.single.entityType, SyncEntityType.collectionEntry);
    expect(changes.single.data['is_read'], isTrue);
    expect(changes.single.data['rating'], 4);
  });

  test(
    'copy update queues only that copy while aggregate flags stay local',
    () async {
      await database.upsert(
        _comic('one', owned: true).copyWith(duplicate: true),
      );
      await _settleCurrentBatch(database);
      final copies = await database.copiesForIssue('one');
      expect(copies, hasLength(2));

      await database.saveCopy(
        copies.first.copyWith(condition: 'G', updatedAt: 20),
      );
      var batch = await database.prepareSyncV2();
      var delta = batch.mutations.last.changes;
      expect(delta, hasLength(1));
      expect(delta.single.entityType, SyncEntityType.comicCopy);
      expect(delta.single.entityId, copies.first.id);
      expect(delta.single.data['condition_grade'], 'G');

      await database.saveCopy(
        copies.last.copyWith(active: false, updatedAt: 30),
      );
      batch = await database.prepareSyncV2();
      delta = batch.mutations.last.changes;
      expect(delta, hasLength(1));
      expect(delta.single.entityType, SyncEntityType.comicCopy);
      expect(delta.single.entityId, copies.last.id);
      final aggregate = (await database.all()).single;
      expect(aggregate.owned, isTrue);
      expect(aggregate.duplicate, isFalse);
      expect(
        delta,
        isNot(
          contains(
            isA<SyncEntityChange>().having(
              (change) => change.entityId,
              'entityId',
              copies.first.id,
            ),
          ),
        ),
      );
      expect(
        delta,
        isNot(
          contains(
            isA<SyncEntityChange>().having(
              (change) => change.entityType,
              'entityType',
              SyncEntityType.customIssue,
            ),
          ),
        ),
      );
    },
  );

  test('semantic no-op and unchanged barcode add no outbox rows', () async {
    final original = _comic('one', owned: true);
    await database.upsert(original);
    await database.saveBarcodeMapping('978123', 'one');
    await _settleCurrentBatch(database);

    await database.upsert(
      original.copyWith(coverAsset: 'assets/local-only.webp', updatedAt: 999),
    );
    await database.saveBarcodeMapping('978123', 'one');

    final batch = await database.prepareSyncV2();
    expect(batch.mutations, isEmpty);
    expect(await database.hasPendingSyncV2(), isFalse);
  });

  test(
    'copy id cannot move between issues and rejected writes roll back',
    () async {
      await database.upsert(_comic('one', owned: true));
      await database.upsert(_comic('two'));
      final settled = await _settleCurrentBatch(database);
      final copy = (await database.copiesForIssue('one')).single;

      await expectLater(
        database.saveCopy(copy.copyWith(issueId: 'two', updatedAt: 20)),
        throwsStateError,
      );
      expect((await database.copiesForIssue('one')).single.id, copy.id);
      expect(
        (await database.copiesForIssue('two')).map((item) => item.id),
        isNot(contains(copy.id)),
      );
      expect((await database.prepareSyncV2()).mutations, isEmpty);

      await expectLater(
        database.applySyncV2(
          _exchange(
            serverId: 'server-a',
            nextCursor: settled.mutations.length + 1,
            changeGroups: [
              SyncChangeGroup(
                revision: settled.mutations.length + 1,
                mutationId: 'illegal-copy-move',
                changes: [_remoteCopy(copy.id, 'two', _hint('two'))],
              ),
            ],
          ),
        ),
        throwsStateError,
      );

      final after = await database.prepareSyncV2();
      expect(after.cursor, settled.mutations.length);
      expect((await database.copiesForIssue('one')).single.id, copy.id);
      final comics = {
        for (final comic in await database.all()) comic.id: comic,
      };
      expect(comics['one']!.owned, isTrue);
      expect(comics['two']!.owned, isFalse);
    },
  );

  test('accepted v1 fallback state queues a newer v2 differential', () async {
    final original = _comic('one', owned: true);
    await database.upsert(original);
    final pullOnly = await database.prepareSyncV2();
    expect(pullOnly.mutations, isEmpty);
    final sqlite = await database.database;
    final beforeCount = (await sqlite.query('sync_outbox')).length;

    await database.mergeRemote([
      original.copyWith(
        title: 'Novije sa starog servera',
        read: true,
        updatedAt: 20,
      ),
    ]);
    expect(await sqlite.query('sync_outbox'), hasLength(beforeCount + 1));

    await database.applySyncV2(_exchange(serverId: 'server-a', nextCursor: 0));
    final batch = await database.prepareSyncV2();
    expect(batch.mutations, isNotEmpty);
    expect(batch.mutations.last.changes.map((change) => change.entityType), [
      SyncEntityType.customIssue,
      SyncEntityType.collectionEntry,
    ]);
    expect(
      batch.mutations.last.changes.first.data['title'],
      'Novije sa starog servera',
    );
    expect(batch.mutations.last.changes.last.data['is_read'], isTrue);
  });

  test(
    'reset sync binding preserves domain data and stable device id',
    () async {
      final original = _comic('one', owned: true);
      await database.upsert(original);
      await database.saveBarcodeMapping('978123', 'one');
      final initial = await _settleCurrentBatch(database);
      await database.upsert(original.copyWith(read: true, updatedAt: 20));

      final sqlite = await database.database;
      final before = (await sqlite.query('sync_state')).single;
      expect(before['server_id'], 'server-a');
      expect(await sqlite.query('sync_outbox'), isNotEmpty);
      expect(await sqlite.query('sync_entity_versions'), isNotEmpty);

      await database.resetSyncV2Binding();

      final reset = (await sqlite.query('sync_state')).single;
      expect(reset['device_id'], initial.deviceId);
      expect(reset['server_id'], isEmpty);
      expect(reset['cursor'], 0);
      expect(reset['bootstrapped'], 0);
      expect(reset['last_success_at'], isNull);
      expect(await sqlite.query('sync_outbox'), isNotEmpty);
      expect(await sqlite.query('sync_outbox_entities'), isNotEmpty);
      expect(await sqlite.query('sync_entity_versions'), isEmpty);
      expect((await database.all()).single.read, isTrue);
      expect(await database.copiesForIssue('one'), hasLength(1));
      expect(await database.barcodeMappings(), {'978123': 'one'});

      final rebuilt = await database.prepareSyncV2();
      expect(rebuilt.deviceId, initial.deviceId);
      expect(rebuilt.serverId, isEmpty);
      expect(rebuilt.cursor, 0);
      expect(rebuilt.mutations, isEmpty);

      await database.applySyncV2(
        _exchange(serverId: 'server-b', nextCursor: 0),
      );
      final upload = await database.prepareSyncV2();
      expect(upload.serverId, 'server-b');
      expect(upload.mutations, isNotEmpty);
    },
  );

  test('prepare splits and packs mutations within protocol limits', () async {
    final regularChanges = SyncV2UploadValidator.maximumChangesPerRequest ~/ 5;
    for (var issue = 0; issue < 6; issue++) {
      await database.upsert(_comic('bulk-$issue', owned: true));
    }
    final sqlite = await database.database;
    await sqlite.transaction((transaction) async {
      for (var issue = 0; issue < 6; issue++) {
        final extraCopies = issue == 0
            ? regularChanges - 2
            : regularChanges - 3;
        for (var ordinal = 1; ordinal <= extraCopies; ordinal++) {
          await transaction.insert('copies', {
            'id': 'bulk-$issue-copy-$ordinal',
            'issue_id': 'bulk-$issue',
            'ordinal': ordinal,
            'active': 1,
            'condition_grade': 'F',
            'purchase_price': null,
            'estimated_value': null,
            'loaned_to': '',
            'deleted': 0,
            'updated_at': 10,
          });
        }
      }
    });

    await _completeEmptyBaseline(database);
    var batch = await database.prepareSyncV2(limit: 1000);
    expect(batch.mutations, isNotEmpty);
    expect(
      batch.mutations.every(
        (mutation) =>
            mutation.changes.length <=
            SyncV2UploadValidator.maximumChangesPerMutation,
      ),
      isTrue,
    );
    expect(
      batch.mutations.fold<int>(
        0,
        (total, mutation) => total + mutation.changes.length,
      ),
      lessThanOrEqualTo(SyncV2UploadValidator.maximumChangesPerRequest),
    );
    expect(await sqlite.query('sync_outbox'), hasLength(12));

    await sqlite.delete('sync_outbox');
    for (
      var mutationIndex = 0;
      mutationIndex < SyncV2UploadValidator.maximumMutations + 1;
      mutationIndex++
    ) {
      final mutation = SyncMutation(
        mutationId: 'stored-$mutationIndex',
        createdAt: mutationIndex,
        changes: [_remoteCustomIssue('stored-$mutationIndex')],
      );
      await sqlite.insert('sync_outbox', {
        'mutation_id': mutation.mutationId,
        'created_at': mutation.createdAt,
        'changes_json': jsonEncode(mutation.toJson()),
        'ack_revision': null,
        'ack_status': null,
      });
      await sqlite.insert('sync_outbox_entities', {
        'mutation_id': mutation.mutationId,
        'entity_type': SyncEntityType.customIssue.wireName,
        'entity_id': 'stored-$mutationIndex',
      });
    }

    batch = await database.prepareSyncV2(limit: 1000);
    expect(batch.mutations, hasLength(SyncV2UploadValidator.maximumMutations));
    expect(
      batch.mutations.fold<int>(
        0,
        (total, mutation) => total + mutation.changes.length,
      ),
      SyncV2UploadValidator.maximumMutations,
    );
  });

  test(
    'bootstrap chunks a pathological issue above the mutation cap',
    () async {
      await database.upsert(_comic('pathological', owned: true));
      final sqlite = await database.database;
      await sqlite.transaction((transaction) async {
        final extraCopies = SyncV2UploadValidator.maximumChangesPerMutation - 2;
        for (var ordinal = 1; ordinal <= extraCopies; ordinal++) {
          await transaction.insert('copies', {
            'id': 'pathological-copy-$ordinal',
            'issue_id': 'pathological',
            'ordinal': ordinal,
            'active': 1,
            'condition_grade': 'F',
            'purchase_price': null,
            'estimated_value': null,
            'loaned_to': '',
            'deleted': 0,
            'updated_at': 10,
          });
        }
      });

      // Isolate the bootstrap chunker from the earlier domain-write delta.
      await sqlite.delete('sync_outbox');
      await _completeEmptyBaseline(database);
      final batch = await database.prepareSyncV2(limit: 1000);
      expect(batch.mutations, hasLength(1));
      expect(
        batch.mutations.single.changes,
        hasLength(SyncV2UploadValidator.maximumChangesPerMutation),
      );
      final storedRows = await sqlite.query(
        'sync_outbox',
        columns: ['changes_json'],
        orderBy: 'sequence',
      );
      expect(storedRows, hasLength(2));
      final storedSizes = storedRows.map((row) {
        final mutation = jsonDecode(row['changes_json'] as String) as Map;
        return (mutation['changes'] as List).length;
      });
      expect(storedSizes, [SyncV2UploadValidator.maximumChangesPerMutation, 1]);
    },
  );

  test(
    'large deletion queues every copy tombstone before the entry tombstone',
    () async {
      final original = _comic('large-delete', owned: true);
      await database.upsert(original);
      await _settleCurrentBatch(database);
      final sqlite = await database.database;
      await sqlite.transaction((transaction) async {
        for (var ordinal = 1; ordinal <= 500; ordinal++) {
          await transaction.insert('copies', {
            'id': 'large-delete-copy-$ordinal',
            'issue_id': 'large-delete',
            'ordinal': ordinal,
            'active': 1,
            'condition_grade': 'F',
            'purchase_price': null,
            'estimated_value': null,
            'loaned_to': '',
            'deleted': 0,
            'updated_at': 10,
          });
        }
      });

      await database.upsert(
        original.copyWith(owned: false, deleted: true, updatedAt: 20),
      );

      final rows = await sqlite.query(
        'sync_outbox',
        columns: ['changes_json'],
        orderBy: 'sequence',
      );
      expect(rows, hasLength(2));
      final changes = [
        for (final row in rows)
          ...((jsonDecode(row['changes_json'] as String) as Map)['changes']
                  as List)
              .map(_jsonMap),
      ];
      expect(
        changes.where((change) => change['entity_type'] == 'copy'),
        hasLength(501),
      );
      expect(changes.last['entity_type'], 'collection_entry');
      expect(changes.last['operation'], 'delete');
      expect(
        changes.take(500).every((change) => change['entity_type'] == 'copy'),
        isTrue,
      );
    },
  );

  test(
    'acked mutations remain until the download cursor reaches revision',
    () async {
      final original = _comic('one', owned: true);
      await database.upsert(original);
      await _settleCurrentBatch(database);
      await database.upsert(original.copyWith(read: true, updatedAt: 20));
      final first = await database.prepareSyncV2();
      final mutationId = first.mutations.single.mutationId;
      final baseRevision = first.cursor;

      await database.applySyncV2(
        _exchange(
          serverId: 'server-a',
          nextCursor: baseRevision + 1,
          hasMore: true,
          acknowledgements: [
            SyncAcknowledgement(
              mutationId: mutationId,
              revision: baseRevision + 2,
              status: 'applied',
            ),
          ],
          changeGroups: [
            SyncChangeGroup(
              revision: baseRevision + 1,
              mutationId: 'remote-before-local',
              changes: [_remoteCustomIssue('remote-before-local')],
            ),
          ],
        ),
      );

      final waiting = await database.prepareSyncV2();
      expect(waiting.serverId, 'server-a');
      expect(waiting.cursor, baseRevision + 1);
      expect(waiting.mutations, isEmpty);
      expect(await database.hasPendingSyncV2(), isTrue);
      expect(
        await (await database.database).query('sync_outbox'),
        hasLength(1),
      );

      await database.applySyncV2(
        _exchange(
          serverId: 'server-a',
          nextCursor: baseRevision + 2,
          changeGroups: [
            SyncChangeGroup(
              revision: baseRevision + 2,
              mutationId: mutationId,
              changes: first.mutations.single.changes,
            ),
          ],
        ),
      );
      expect(await database.hasPendingSyncV2(), isFalse);
      expect(await (await database.database).query('sync_outbox'), isEmpty);
    },
  );

  test(
    'deferred acknowledgement must match its eventual change group',
    () async {
      final original = _comic('ack-binding', owned: true);
      await database.upsert(original);
      await _settleCurrentBatch(database);
      await database.upsert(original.copyWith(read: true, updatedAt: 20));
      final pending = await database.prepareSyncV2();
      final mutation = pending.mutations.single;
      final baseRevision = pending.cursor;

      await database.applySyncV2(
        _exchange(
          serverId: 'server-a',
          nextCursor: baseRevision + 1,
          hasMore: true,
          acknowledgements: [
            SyncAcknowledgement(
              mutationId: mutation.mutationId,
              revision: baseRevision + 2,
              status: 'applied',
            ),
          ],
          changeGroups: [
            SyncChangeGroup(
              revision: baseRevision + 1,
              mutationId: 'unrelated-before-ack',
              changes: [_remoteCustomIssue('unrelated-before-ack')],
            ),
          ],
        ),
      );

      await expectLater(
        database.applySyncV2(
          _exchange(
            serverId: 'server-a',
            nextCursor: baseRevision + 2,
            changeGroups: [
              SyncChangeGroup(
                revision: baseRevision + 2,
                mutationId: 'wrong-mutation-at-ack-revision',
                changes: mutation.changes,
              ),
            ],
          ),
        ),
        throwsFormatException,
      );

      final after = await database.prepareSyncV2();
      expect(after.cursor, baseRevision + 1);
      expect(after.mutations, isEmpty);
      expect(await database.hasPendingSyncV2(), isTrue);
    },
  );

  test(
    'final page cannot end below a previously acknowledged revision',
    () async {
      final original = _comic('ack-high-water', owned: true);
      await database.upsert(original);
      await _settleCurrentBatch(database);
      await database.upsert(original.copyWith(read: true, updatedAt: 20));
      final pending = await database.prepareSyncV2();
      final mutation = pending.mutations.single;
      final baseRevision = pending.cursor;

      await database.applySyncV2(
        _exchange(
          serverId: 'server-a',
          nextCursor: baseRevision + 1,
          hasMore: true,
          acknowledgements: [
            SyncAcknowledgement(
              mutationId: mutation.mutationId,
              revision: baseRevision + 3,
              status: 'applied',
            ),
          ],
          changeGroups: [
            SyncChangeGroup(
              revision: baseRevision + 1,
              mutationId: 'before-high-water',
              changes: [_remoteCustomIssue('before-high-water')],
            ),
          ],
        ),
      );

      await expectLater(
        database.applySyncV2(
          _exchange(
            serverId: 'server-a',
            nextCursor: baseRevision + 2,
            changeGroups: [
              SyncChangeGroup(
                revision: baseRevision + 2,
                mutationId: 'premature-final-page',
                changes: [_remoteCustomIssue('premature-final-page')],
              ),
            ],
          ),
        ),
        throwsFormatException,
      );

      expect((await database.prepareSyncV2()).cursor, baseRevision + 1);
      expect(await database.hasPendingSyncV2(), isTrue);
    },
  );

  test('server identity mismatch rejects the complete exchange', () async {
    await database.upsert(_comic('one'));
    await database.prepareSyncV2();
    await database.applySyncV2(_exchange(serverId: 'server-a', nextCursor: 0));

    await expectLater(
      database.applySyncV2(
        _exchange(
          serverId: 'server-b',
          nextCursor: 1,
          changeGroups: [
            SyncChangeGroup(
              revision: 1,
              mutationId: 'remote',
              changes: [_remoteCustomIssue('remote-1')],
            ),
          ],
        ),
      ),
      throwsStateError,
    );

    final state = await database.prepareSyncV2();
    expect(state.serverId, 'server-a');
    expect(state.cursor, 0);
    expect(
      (await database.all()).map((comic) => comic.id),
      isNot(contains('remote-1')),
    );
  });

  test(
    'remote apply supports concurrent copy ordinals without an outbox echo',
    () async {
      await database.prepareSyncV2();
      final hint = _hint('remote-1');
      await database.applySyncV2(
        _exchange(
          serverId: 'server-a',
          nextCursor: 1,
          changeGroups: [
            SyncChangeGroup(
              revision: 1,
              mutationId: 'remote-mutation',
              changes: [
                _remoteCustomIssue('remote-1'),
                SyncEntityChange(
                  entityType: SyncEntityType.collectionEntry,
                  entityId: 'remote-1',
                  operation: SyncOperation.upsert,
                  data: {
                    'issue_id': 'remote-1',
                    'owned': 1,
                    'is_wanted': 0,
                    'is_read': 0,
                    'is_duplicate': 0,
                    'rating': 0,
                    'notes': '',
                    'deleted': 0,
                    'updated_at': 50,
                    'issue_hint': hint,
                  },
                ),
                _remoteCopy('copy-a', 'remote-1', hint),
                _remoteCopy('copy-b', 'remote-1', hint),
              ],
            ),
          ],
        ),
      );

      final copies = await database.copiesForIssue('remote-1');
      expect(copies, hasLength(2));
      expect(copies.map((copy) => copy.ordinal), [0, 0]);
      final aggregate = (await database.all()).single;
      expect(aggregate.owned, isTrue);
      expect(aggregate.duplicate, isTrue);
      expect(await database.hasPendingSyncV2(), isFalse);
    },
  );

  test('newer unacknowledged local entity protects domain state', () async {
    await database.upsertCatalogAll([_comic('catalog-DDLU-1')]);
    await database.upsert(_comic('catalog-DDLU-1', owned: true));
    await database.prepareSyncV2();

    await database.applySyncV2(
      _exchange(
        serverId: 'server-a',
        nextCursor: 1,
        changeGroups: [
          SyncChangeGroup(
            revision: 1,
            mutationId: 'remote-old-state',
            changes: [
              SyncEntityChange(
                entityType: SyncEntityType.collectionEntry,
                entityId: 'catalog-DDLU-1',
                operation: SyncOperation.upsert,
                data: {
                  'issue_id': 'catalog-DDLU-1',
                  'owned': 0,
                  'is_wanted': 1,
                  'is_read': 0,
                  'is_duplicate': 0,
                  'rating': 0,
                  'notes': 'udaljeno',
                  'deleted': 0,
                  'updated_at': 2,
                  'issue_hint': _hint('catalog-DDLU-1', origin: 'bundled'),
                },
              ),
            ],
          ),
        ],
      ),
    );

    final local = (await database.all()).single;
    expect(local.owned, isTrue);
    expect(local.notes, isEmpty);
    expect((await database.prepareSyncV2()).cursor, 1);
  });

  test('failed remote group rolls domain state and cursor back', () async {
    await database.prepareSyncV2();

    await expectLater(
      database.applySyncV2(
        _exchange(
          serverId: 'server-a',
          nextCursor: 1,
          changeGroups: [
            SyncChangeGroup(
              revision: 1,
              mutationId: 'broken-remote',
              changes: [
                _remoteCustomIssue('created-before-error'),
                SyncEntityChange(
                  entityType: SyncEntityType.comicCopy,
                  entityId: 'bad-copy',
                  operation: SyncOperation.upsert,
                  data: {
                    'issue_id': 'unknown-without-hint',
                    'ordinal': 0,
                    'active': 1,
                    'condition_grade': 'F',
                    'deleted': 0,
                    'updated_at': 1,
                  },
                ),
              ],
            ),
          ],
        ),
      ),
      throwsFormatException,
    );

    expect(await database.all(), isEmpty);
    final batch = await database.prepareSyncV2();
    expect(batch.serverId, isEmpty);
    expect(batch.cursor, 0);
  });
}

Future<SyncUploadBatch> _settleCurrentBatch(
  LocalDatabase database, {
  String serverId = 'server-a',
}) async {
  var batch = await database.prepareSyncV2();
  if (batch.mutations.isEmpty && batch.serverId.isEmpty) {
    await database.applySyncV2(
      _exchange(serverId: serverId, nextCursor: batch.cursor),
    );
    batch = await database.prepareSyncV2();
  }
  final acknowledgements = <SyncAcknowledgement>[];
  final groups = <SyncChangeGroup>[];
  for (var index = 0; index < batch.mutations.length; index++) {
    final mutation = batch.mutations[index];
    final revision = batch.cursor + index + 1;
    acknowledgements.add(
      SyncAcknowledgement(
        mutationId: mutation.mutationId,
        revision: revision,
        status: 'applied',
      ),
    );
    groups.add(
      SyncChangeGroup(
        revision: revision,
        mutationId: mutation.mutationId,
        changes: mutation.changes,
      ),
    );
  }
  await database.applySyncV2(
    _exchange(
      serverId: serverId,
      nextCursor: batch.cursor + batch.mutations.length,
      acknowledgements: acknowledgements,
      changeGroups: groups,
    ),
  );
  return batch;
}

Future<void> _completeEmptyBaseline(
  LocalDatabase database, {
  String serverId = 'server-a',
}) async {
  final pull = await database.prepareSyncV2();
  expect(pull.mutations, isEmpty);
  await database.applySyncV2(
    _exchange(serverId: serverId, nextCursor: pull.cursor),
  );
}

Comic _comic(String id, {bool owned = false}) => Comic(
  id: id,
  series: 'Dylan Dog',
  edition: 'Custom',
  number: 1,
  title: 'Broj 1',
  publisher: 'Ludens',
  owned: owned,
  condition: 'F',
  updatedAt: 10,
);

SyncV2Exchange _exchange({
  required String serverId,
  required int nextCursor,
  bool hasMore = false,
  List<SyncAcknowledgement> acknowledgements = const [],
  List<SyncChangeGroup> changeGroups = const [],
}) => SyncV2Exchange(
  serverId: serverId,
  requestId: 'request-$nextCursor',
  serverTime: 5000 + nextCursor,
  nextCursor: nextCursor,
  hasMore: hasMore,
  acknowledgements: acknowledgements,
  changeGroups: changeGroups,
);

SyncEntityChange _remoteCustomIssue(String id) => SyncEntityChange(
  entityType: SyncEntityType.customIssue,
  entityId: id,
  operation: SyncOperation.upsert,
  data: {
    'series': 'Dylan Dog',
    'edition': 'Custom',
    'number': 1,
    'title': 'Udaljeni broj',
    'publisher': 'Ludens',
    'year': null,
    'page_count': null,
    'writer': '',
    'artist': '',
  },
);

SyncEntityChange _remoteCopy(
  String id,
  String issueId,
  Map<String, Object?> hint, {
  String condition = 'F',
  int updatedAt = 50,
}) => SyncEntityChange(
  entityType: SyncEntityType.comicCopy,
  entityId: id,
  operation: SyncOperation.upsert,
  data: {
    'issue_id': issueId,
    'ordinal': 0,
    'active': 1,
    'condition_grade': condition,
    'purchase_price': null,
    'estimated_value': null,
    'loaned_to': '',
    'deleted': 0,
    'updated_at': updatedAt,
    'issue_hint': hint,
  },
);

Map<String, Object?> _hint(String id, {String origin = 'custom'}) => {
  'id': id,
  'series': 'Dylan Dog',
  'edition': 'Custom',
  'number': 1,
  'title': 'Udaljeni broj',
  'publisher': 'Ludens',
  'year': null,
  'origin': origin,
};

Map<String, Object?> _jsonMap(Object? value) =>
    Map<String, Object?>.from(value! as Map);
