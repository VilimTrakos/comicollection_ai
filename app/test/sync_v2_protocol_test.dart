import 'package:comicollect/models/sync_v2.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('sync v2 wire DTOs', () {
    test('uses the canonical entity and operation names', () {
      expect(SyncEntityType.values.map((value) => value.wireName), [
        'custom_issue',
        'collection_entry',
        'copy',
        'barcode_mapping',
      ]);
      expect(SyncOperation.values.map((value) => value.wireName), [
        'upsert',
        'delete',
      ]);
      expect(
        () => SyncEntityType.fromWire('comic_copy'),
        throwsFormatException,
      );
    });

    test('encodes an exact upload request and omits an unpinned server id', () {
      final batch = SyncUploadBatch(
        deviceId: 'device-1',
        serverId: '',
        cursor: 7,
        mutations: [_mutation('mutation-1')],
      );

      expect(batch.toRequestJson(requestId: 'request-1', limit: 100), {
        'protocol': 2,
        'request_id': 'request-1',
        'device_id': 'device-1',
        'cursor': 7,
        'limit': 100,
        'mutations': [
          {
            'mutation_id': 'mutation-1',
            'created_at': 123,
            'changes': [
              {
                'entity_type': 'collection_entry',
                'entity_id': 'issue-1',
                'operation': 'upsert',
                'data': {
                  'issue_id': 'issue-1',
                  'owned': true,
                  'is_wanted': false,
                  'is_read': false,
                  'is_duplicate': false,
                  'rating': 0,
                  'notes': '',
                  'deleted': false,
                  'updated_at': 123,
                  'issue_hint': {
                    'id': 'issue-1',
                    'series': 'Dylan Dog',
                    'edition': 'Extra',
                    'number': 1,
                    'title': 'Morgana',
                    'publisher': 'Ludens',
                    'year': 2002,
                    'origin': 'bundled',
                  },
                },
              },
            ],
          },
        ],
      });

      final pinned = SyncUploadBatch(
        deviceId: 'device-1',
        serverId: 'server-1',
        cursor: 7,
        mutations: const [],
      );
      expect(
        pinned.toRequestJson(requestId: 'request-2', limit: 50)['server_id'],
        'server-1',
      );
    });

    test('strictly decodes a response and makes nested data immutable', () {
      final exchange = SyncV2Exchange.fromJson(_responseJson());

      expect(exchange.serverId, 'server-1');
      expect(exchange.nextCursor, 8);
      expect(exchange.acknowledgements.single.status, 'applied');
      expect(
        exchange.changeGroups.single.changes.single.entityType,
        SyncEntityType.collectionEntry,
      );
      expect(
        () => exchange.changeGroups.single.changes.single.data['owned'] = false,
        throwsUnsupportedError,
      );
    });

    test('accepts server-canonical custom issue deletion metadata inbound', () {
      final exchange = SyncV2Exchange.fromJson({
        'protocol': 2,
        'server_id': 'server-1',
        'request_id': 'request-delete',
        'server_time': 500,
        'next_cursor': 9,
        'has_more': false,
        'acknowledgements': <Object?>[],
        'change_groups': [
          {
            'revision': 9,
            'mutation_id': 'remote-delete',
            'changes': [
              {
                'entity_type': 'custom_issue',
                'entity_id': 'custom-1',
                'operation': 'delete',
                'data': {
                  'series': 'Dylan Dog',
                  'edition': 'Custom',
                  'number': 1,
                  'title': 'Obrisan',
                  'publisher': '',
                  'year': null,
                  'page_count': null,
                  'writer': '',
                  'artist': '',
                  'deleted': true,
                },
              },
            ],
          },
        ],
      });

      expect(
        exchange.changeGroups.single.changes.single.data['deleted'],
        isTrue,
      );
    });

    test('rejects malformed protocol values and cursor gaps', () {
      expect(
        () => SyncV2Exchange.fromJson({..._responseJson(), 'protocol': 1}),
        throwsFormatException,
      );
      expect(
        () =>
            SyncV2Exchange.fromJson({..._responseJson(), 'has_more': 'false'}),
        throwsFormatException,
      );
      expect(
        () => SyncV2Exchange.fromJson({..._responseJson(), 'next_cursor': 9}),
        throwsA(anything),
      );
      expect(
        () => SyncV2Exchange.fromJson({
          ..._responseJson(),
          'change_groups': [
            (_responseJson()['change_groups']! as List<Object?>).single,
            {
              'revision': 8,
              'mutation_id': 'mutation-2',
              'changes': [_change().toJson()],
            },
          ],
        }),
        throwsA(anything),
      );
    });

    test('rejects empty mutations, invalid statuses and duplicate ids', () {
      expect(
        () =>
            SyncMutation(mutationId: 'empty', createdAt: 1, changes: const []),
        throwsArgumentError,
      );
      expect(
        () => SyncAcknowledgement(
          mutationId: 'mutation-1',
          revision: 1,
          status: 'rejected',
        ),
        throwsArgumentError,
      );
      expect(
        () => SyncUploadBatch(
          deviceId: 'device-1',
          serverId: '',
          cursor: 0,
          mutations: [_mutation('same'), _mutation('same')],
        ),
        throwsArgumentError,
      );
    });
  });
}

SyncEntityChange _change() => SyncEntityChange(
  entityType: SyncEntityType.collectionEntry,
  entityId: 'issue-1',
  operation: SyncOperation.upsert,
  data: {
    'issue_id': 'issue-1',
    'owned': true,
    'is_wanted': false,
    'is_read': false,
    'is_duplicate': false,
    'rating': 0,
    'notes': '',
    'deleted': false,
    'updated_at': 123,
    'issue_hint': {
      'id': 'issue-1',
      'series': 'Dylan Dog',
      'edition': 'Extra',
      'number': 1,
      'title': 'Morgana',
      'publisher': 'Ludens',
      'year': 2002,
      'origin': 'bundled',
    },
  },
);

SyncMutation _mutation(String id) =>
    SyncMutation(mutationId: id, createdAt: 123, changes: [_change()]);

Map<String, Object?> _responseJson() => {
  'protocol': 2,
  'server_id': 'server-1',
  'request_id': 'request-1',
  'server_time': 456,
  'next_cursor': 8,
  'has_more': false,
  'acknowledgements': [
    {'mutation_id': 'mutation-1', 'revision': 8, 'status': 'applied'},
  ],
  'change_groups': [
    {
      'revision': 8,
      'mutation_id': 'mutation-1',
      'changes': [_change().toJson()],
    },
  ],
};
