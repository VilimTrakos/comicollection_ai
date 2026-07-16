import 'dart:convert';

import 'package:comicollect/models/sync_v2.dart';
import 'package:comicollect/models/sync_v2_response_validator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('accepts and canonicalizes every inbound entity contract', () {
    final exchange = SyncV2Exchange.fromJson(_response());

    expect(exchange.changeGroups.single.changes, hasLength(4));
    expect(
      exchange.changeGroups.single.changes.map((change) => change.entityType),
      SyncEntityType.values,
    );
    expect(exchange.changeGroups.single.changes[2].data['purchase_price'], 3.0);
    expect(exchange.changeGroups.single.changes[3].data['issue_hint'], isNull);
  });

  test('requires exact envelope, acknowledgement, group and change keys', () {
    final cases = <_InvalidCase>[
      _InvalidCase('unknown fields', (response) => response['extra'] = true),
      _InvalidCase(
        'acknowledgements[0] has unknown fields',
        (response) => _ack(response)['message'] = 'ok',
      ),
      _InvalidCase(
        'change_groups[0] has unknown fields',
        (response) => _group(response)['created_at'] = 1,
      ),
      _InvalidCase(
        'changes[0] has unknown fields',
        (response) => _change(response, 0)['timestamp'] = 1,
      ),
      _InvalidCase(
        'data has unknown fields',
        (response) => _data(response, 0)['cover_asset'] = 'remote.jpg',
      ),
      _InvalidCase(
        'data is missing: deleted',
        (response) => _data(response, 0).remove('deleted'),
      ),
    ];

    _expectInvalidCases(cases);
  });

  test('rejects untrimmed, controlled, oversized and invalid Unicode ids', () {
    final cases = <_InvalidCase>[
      _InvalidCase('trimmed string', (response) {
        response['server_id'] = ' server-1';
      }),
      _InvalidCase('invalid or exceeds', (response) {
        _group(response)['mutation_id'] = 'remote\u0001mutation';
      }),
      _InvalidCase('128 UTF-8 bytes', (response) {
        _ack(response)['mutation_id'] = List.filled(65, 'ž').join();
      }),
      _InvalidCase('invalid Unicode', (response) {
        _change(response, 1)['entity_id'] = 'issue-\uD800';
      }),
      _InvalidCase('512 UTF-8 bytes', (response) {
        _change(response, 3)['entity_id'] = List.filled(257, 'ž').join();
      }),
    ];

    _expectInvalidCases(cases);
  });

  test('rejects loose numeric types, int64 overflow and field ranges', () {
    final cases = <_InvalidCase>[
      _InvalidCase('must be an integer', (response) {
        response['next_cursor'] = 1.0;
      }),
      _InvalidCase('between 0 and', (response) {
        response['server_time'] =
            SyncV2ResponseValidator.maximumSignedInt64 + 1;
      }),
      _InvalidCase('between 1 and', (response) {
        _ack(response)['revision'] = 0;
      }),
      _InvalidCase('between 0 and 5', (response) {
        _data(response, 1)['rating'] = 6;
      }),
      _InvalidCase('between 0 and 3000', (response) {
        (_data(response, 1)['issue_hint']! as Map)['year'] = 3001;
      }),
      _InvalidCase('finite non-negative', (response) {
        _data(response, 2)['estimated_value'] = -0.1;
      }),
      _InvalidCase('must be a boolean', (response) {
        _data(response, 1)['owned'] = 1;
      }),
    ];

    _expectInvalidCases(cases);
  });

  test('enforces delete semantics and entity relationships', () {
    final cases = <_InvalidCase>[
      _InvalidCase('must agree', (response) {
        _change(response, 0)['operation'] = 'delete';
      }),
      _InvalidCase('must agree', (response) {
        _data(response, 2)['deleted'] = true;
      }),
      _InvalidCase('must equal response.change_groups', (response) {
        _change(response, 1)['entity_id'] = 'different-issue';
      }),
      _InvalidCase('id must equal issue_id', (response) {
        (_data(response, 2)['issue_hint']! as Map)['id'] = 'different-issue';
      }),
      _InvalidCase('origin must be bundled or custom', (response) {
        (_data(response, 2)['issue_hint']! as Map)['origin'] = 'server';
      }),
      _InvalidCase('condition_grade is invalid', (response) {
        _data(response, 2)['condition_grade'] = 'NM';
      }),
    ];

    _expectInvalidCases(cases);
  });

  test('rejects duplicate acknowledgements and entities within a group', () {
    var response = _clone(_response());
    (response['acknowledgements']! as List).add(
      Map<String, dynamic>.from(_ack(response)),
    );
    expect(
      () => SyncV2Exchange.fromJson(response),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message.toString(),
          'message',
          contains('must be unique'),
        ),
      ),
    );

    response = _clone(_response());
    (_group(response)['changes']! as List).add(
      Map<String, dynamic>.from(_change(response, 1)),
    );
    expect(
      () => SyncV2Exchange.fromJson(response),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message.toString(),
          'message',
          contains('only once'),
        ),
      ),
    );
  });

  test('enforces response collection and encoded byte limits', () {
    var response = _clone(_response());
    response['acknowledgements'] = List.generate(
      SyncV2ResponseValidator.maximumAcknowledgements + 1,
      (index) => {
        'mutation_id': 'mutation-$index',
        'revision': 1,
        'status': 'duplicate',
      },
    );
    expect(
      () => SyncV2Exchange.fromJson(response),
      throwsA(isA<FormatException>()),
    );

    response = _clone(_response());
    _data(response, 1)['notes'] = List.filled(10001, 'a').join();
    expect(
      () => SyncV2Exchange.fromJson(response),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message.toString(),
          'message',
          contains('10000 UTF-8 bytes'),
        ),
      ),
    );

    response = _clone(_response());
    _group(response)['changes'] = List.generate(
      SyncV2ResponseValidator.maximumChangesPerGroup + 1,
      (index) => {
        'entity_type': 'custom_issue',
        'entity_id': 'issue-$index',
        'operation': 'upsert',
        'data': {
          'series': 'Dylan Dog',
          'edition': '',
          'number': index,
          'title': 'Broj $index',
          'publisher': '',
          'year': null,
          'page_count': null,
          'writer': '',
          'artist': '',
          'deleted': false,
        },
      },
    );
    expect(
      () => SyncV2Exchange.fromJson(response),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message.toString(),
          'message',
          contains('at most 1000 items'),
        ),
      ),
    );

    response = _clone(_response());
    _group(response)['changes'] = List.generate(
      700,
      (index) => {
        'entity_type': 'collection_entry',
        'entity_id': 'large-issue-$index',
        'operation': 'upsert',
        'data': {
          'issue_id': 'large-issue-$index',
          'owned': false,
          'is_wanted': true,
          'is_read': false,
          'is_duplicate': false,
          'rating': 0,
          'notes': List.filled(10000, 'x').join(),
          'deleted': false,
          'updated_at': 1,
          'issue_hint': null,
        },
      },
    );
    expect(
      () => SyncV2Exchange.fromJson(response),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message.toString(),
          'message',
          contains(
            'response exceeds '
            '${SyncV2ResponseValidator.maximumResponseBytes}',
          ),
        ),
      ),
    );
  });
}

class _InvalidCase {
  const _InvalidCase(this.message, this.mutate);

  final String message;
  final void Function(Map<String, dynamic>) mutate;
}

void _expectInvalidCases(List<_InvalidCase> cases) {
  for (final invalidCase in cases) {
    final response = _clone(_response());
    invalidCase.mutate(response);
    expect(
      () => SyncV2Exchange.fromJson(response),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message.toString(),
          'message',
          contains(invalidCase.message),
        ),
      ),
      reason: invalidCase.message,
    );
  }
}

Map<String, dynamic> _clone(Map<String, Object?> source) =>
    jsonDecode(jsonEncode(source)) as Map<String, dynamic>;

Map<String, dynamic> _ack(Map<String, dynamic> response) =>
    (response['acknowledgements']! as List).first as Map<String, dynamic>;

Map<String, dynamic> _group(Map<String, dynamic> response) =>
    (response['change_groups']! as List).first as Map<String, dynamic>;

Map<String, dynamic> _change(Map<String, dynamic> response, int index) =>
    (_group(response)['changes']! as List)[index] as Map<String, dynamic>;

Map<String, dynamic> _data(Map<String, dynamic> response, int index) =>
    _change(response, index)['data']! as Map<String, dynamic>;

Map<String, Object?> _response() => {
  'protocol': 2,
  'server_id': 'server-1',
  'request_id': 'request-1',
  'server_time': 500,
  'next_cursor': 1,
  'has_more': false,
  'acknowledgements': [
    {'mutation_id': 'mutation-1', 'revision': 1, 'status': 'applied'},
  ],
  'change_groups': [
    {
      'revision': 1,
      'mutation_id': 'mutation-1',
      'changes': [
        {
          'entity_type': 'custom_issue',
          'entity_id': 'issue-1',
          'operation': 'upsert',
          'data': {
            'series': 'Dylan Dog',
            'edition': 'Extra',
            'number': 25,
            'title': 'Morgana',
            'publisher': 'Ludens',
            'year': 2002,
            'page_count': 98,
            'writer': 'Tiziano Sclavi',
            'artist': 'Angelo Stano',
            'deleted': false,
          },
        },
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
            'updated_at': 100,
            'issue_hint': _hint('issue-1'),
          },
        },
        {
          'entity_type': 'copy',
          'entity_id': 'copy-1',
          'operation': 'upsert',
          'data': {
            'issue_id': 'issue-1',
            'ordinal': 0,
            'active': true,
            'condition_grade': 'VF',
            'purchase_price': 3,
            'estimated_value': 7.0,
            'loaned_to': '',
            'deleted': false,
            'updated_at': 100,
            'issue_hint': _hint('issue-1'),
          },
        },
        {
          'entity_type': 'barcode_mapping',
          'entity_id': '9789530000000',
          'operation': 'upsert',
          'data': {'issue_id': 'issue-1', 'deleted': false, 'updated_at': 100},
        },
      ],
    },
  ],
};

Map<String, Object?> _hint(String id) => {
  'id': id,
  'series': 'Dylan Dog',
  'edition': 'Extra',
  'number': 25,
  'title': 'Morgana',
  'publisher': 'Ludens',
  'year': 2002,
  'origin': 'bundled',
};
