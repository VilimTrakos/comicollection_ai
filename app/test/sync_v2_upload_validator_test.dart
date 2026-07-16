import 'dart:convert';

import 'package:comicollect/models/sync_v2_upload_validator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('accepts the complete request shape produced by real snapshots', () {
    expect(
      () => SyncV2UploadValidator.validateRequest(_validRequest()),
      returnsNormally,
    );
  });

  test('rejects invalid ids, types, ranges, bytes and entity contracts', () {
    final cases = <_InvalidCase>[
      _InvalidCase('request_id', (request) => request['request_id'] = ' bad'),
      _InvalidCase(
        'entity_id',
        (request) => _change(request, 0)['entity_id'] = 'bad\u0001id',
      ),
      _InvalidCase('cursor', (request) => request['cursor'] = 0.0),
      _InvalidCase('created_at', (request) {
        _mutation(request)['created_at'] =
            SyncV2UploadValidator.maximumSignedInt64 + 1;
      }),
      _InvalidCase('owned', (request) => _data(request, 1)['owned'] = 1),
      _InvalidCase('rating', (request) => _data(request, 1)['rating'] = 6),
      _InvalidCase(
        'condition_grade',
        (request) => _data(request, 2)['condition_grade'] = 'NM',
      ),
      _InvalidCase(
        'purchase_price',
        (request) => _data(request, 2)['purchase_price'] = -0.01,
      ),
      _InvalidCase(
        'title',
        (request) => _data(request, 0)['title'] = List.filled(251, 'ž').join(),
      ),
      _InvalidCase(
        'deleted',
        (request) => _change(request, 2)['operation'] = 'delete',
      ),
      _InvalidCase(
        'must equal',
        (request) => _change(request, 1)['entity_id'] = 'another-issue',
      ),
      _InvalidCase(
        'issue_hint.id',
        (request) =>
            (_data(request, 1)['issue_hint']! as Map)['id'] = 'another-issue',
      ),
      _InvalidCase(
        'issue_hint.origin',
        (request) =>
            (_data(request, 1)['issue_hint']! as Map)['origin'] = 'remote',
      ),
      _InvalidCase(
        'unknown fields',
        (request) => _data(request, 0)['deleted'] = false,
      ),
    ];

    for (final invalidCase in cases) {
      final request = _clone(_validRequest());
      invalidCase.mutate(request);
      expect(
        () => SyncV2UploadValidator.validateRequest(request),
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
  });

  test('enforces mutation, request and duplicate-entity limits', () {
    var request = _validRequest();
    _mutation(request)['changes'] = List.generate(
      SyncV2UploadValidator.maximumChangesPerMutation + 1,
      (index) => _customChange('issue-$index'),
    );
    expect(
      () => SyncV2UploadValidator.validateRequest(request),
      throwsA(isA<FormatException>()),
    );

    request = _validRequest();
    request['mutations'] = List.generate(
      SyncV2UploadValidator.maximumMutations + 1,
      (index) => {
        'mutation_id': 'mutation-$index',
        'created_at': index,
        'changes': [_customChange('issue-$index')],
      },
    );
    expect(
      () => SyncV2UploadValidator.validateRequest(request),
      throwsA(isA<FormatException>()),
    );

    request = _validRequest();
    _mutation(request)['changes'] = [
      _customChange('same-issue'),
      _customChange('same-issue'),
    ];
    expect(
      () => SyncV2UploadValidator.validateRequest(request),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message.toString(),
          'message',
          contains('only once'),
        ),
      ),
    );
  });
}

class _InvalidCase {
  const _InvalidCase(this.message, this.mutate);

  final String message;
  final void Function(Map<String, dynamic> request) mutate;
}

Map<String, dynamic> _clone(Map<String, Object?> source) =>
    jsonDecode(jsonEncode(source)) as Map<String, dynamic>;

Map<String, dynamic> _mutation(Map<String, dynamic> request) =>
    (request['mutations']! as List).first as Map<String, dynamic>;

Map<String, dynamic> _change(Map<String, dynamic> request, int index) =>
    (_mutation(request)['changes']! as List)[index] as Map<String, dynamic>;

Map<String, dynamic> _data(Map<String, dynamic> request, int index) =>
    _change(request, index)['data']! as Map<String, dynamic>;

Map<String, Object?> _validRequest() => {
  'protocol': 2,
  'request_id': 'request-1',
  'device_id': 'device-1',
  'server_id': 'server-1',
  'cursor': 0,
  'limit': 100,
  'mutations': [
    {
      'mutation_id': 'mutation-1',
      'created_at': 100,
      'changes': [
        _customChange('issue-1'),
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
            'purchase_price': 3.5,
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
          'data': {
            'issue_id': 'issue-1',
            'deleted': false,
            'updated_at': 100,
            'issue_hint': _hint('issue-1'),
          },
        },
      ],
    },
  ],
};

Map<String, Object?> _customChange(String id) => {
  'entity_type': 'custom_issue',
  'entity_id': id,
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
  },
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
