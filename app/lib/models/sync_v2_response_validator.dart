import 'dart:convert';

/// Strictly validates and canonicalizes server-to-client sync v2 envelopes.
///
/// Treat the sync server as an untrusted network boundary. A response accepted
/// here is safe for the DTO layer to materialize and is the only response shape
/// that may reach the local database.
abstract final class SyncV2ResponseValidator {
  static const maximumAcknowledgements = 100;
  static const maximumChangeGroups = 100;
  static const maximumChangesPerGroup = 1000;
  static const maximumResponseBytes = 6 * 1024 * 1024;
  static const maximumChangeGroupBytes = 5 * 1024 * 1024;
  static const maximumSignedInt64 = 0x7FFFFFFFFFFFFFFF;

  static const _entityTypes = {
    'custom_issue',
    'collection_entry',
    'copy',
    'barcode_mapping',
  };
  static const _operations = {'upsert', 'delete'};
  static const _acknowledgementStatuses = {'applied', 'duplicate'};
  static const _conditionGrades = {'', 'M', 'VF', 'F', 'G', 'P'};

  /// Returns a fresh canonical object graph; no caller-owned mutable map or
  /// list is retained.
  static Map<String, Object?> validateAndNormalize(
    Map<String, Object?> response,
  ) {
    _requireEncodedSize(response, maximumResponseBytes, 'response');
    const keys = {
      'protocol',
      'server_id',
      'request_id',
      'server_time',
      'next_cursor',
      'has_more',
      'acknowledgements',
      'change_groups',
    };
    _requireKeys(response, keys, keys, 'response');
    if (response['protocol'] is! int || response['protocol'] != 2) {
      throw const FormatException('response.protocol must be the integer 2');
    }

    final acknowledgements = _objectList(
      response['acknowledgements'],
      'response.acknowledgements',
    );
    if (acknowledgements.length > maximumAcknowledgements) {
      throw FormatException(
        'response.acknowledgements may contain at most '
        '$maximumAcknowledgements items',
      );
    }
    final normalizedAcknowledgements = <Map<String, Object?>>[];
    final acknowledgementIds = <String>{};
    for (var index = 0; index < acknowledgements.length; index++) {
      final acknowledgement = _normalizeAcknowledgement(
        _stringMap(
          acknowledgements[index],
          'response.acknowledgements[$index]',
        ),
        'response.acknowledgements[$index]',
      );
      if (!acknowledgementIds.add(acknowledgement['mutation_id']! as String)) {
        throw const FormatException(
          'response acknowledgement mutation_id values must be unique',
        );
      }
      normalizedAcknowledgements.add(acknowledgement);
    }

    final groups = _objectList(
      response['change_groups'],
      'response.change_groups',
    );
    if (groups.length > maximumChangeGroups) {
      throw FormatException(
        'response.change_groups may contain at most '
        '$maximumChangeGroups items',
      );
    }
    final normalizedGroups = <Map<String, Object?>>[];
    for (var index = 0; index < groups.length; index++) {
      final rawGroup = _stringMap(
        groups[index],
        'response.change_groups[$index]',
      );
      normalizedGroups.add(
        _normalizeGroup(rawGroup, 'response.change_groups[$index]'),
      );
    }

    return {
      'protocol': 2,
      'server_id': _identifier(
        response['server_id'],
        'response.server_id',
        128,
      ),
      'request_id': _identifier(
        response['request_id'],
        'response.request_id',
        128,
      ),
      'server_time': _integer(
        response['server_time'],
        'response.server_time',
        minimum: 0,
        maximum: maximumSignedInt64,
      ),
      'next_cursor': _integer(
        response['next_cursor'],
        'response.next_cursor',
        minimum: 0,
        maximum: maximumSignedInt64,
      ),
      'has_more': _boolean(response['has_more'], 'response.has_more'),
      'acknowledgements': normalizedAcknowledgements,
      'change_groups': normalizedGroups,
    };
  }

  static Map<String, Object?> _normalizeAcknowledgement(
    Map<String, Object?> acknowledgement,
    String label,
  ) {
    const keys = {'mutation_id', 'revision', 'status'};
    _requireKeys(acknowledgement, keys, keys, label);
    final status = acknowledgement['status'];
    if (status is! String || !_acknowledgementStatuses.contains(status)) {
      throw FormatException('$label.status is unsupported');
    }
    return {
      'mutation_id': _identifier(
        acknowledgement['mutation_id'],
        '$label.mutation_id',
        128,
      ),
      'revision': _integer(
        acknowledgement['revision'],
        '$label.revision',
        minimum: 1,
        maximum: maximumSignedInt64,
      ),
      'status': status,
    };
  }

  static Map<String, Object?> _normalizeGroup(
    Map<String, Object?> group,
    String label,
  ) {
    const keys = {'revision', 'mutation_id', 'changes'};
    _requireKeys(group, keys, keys, label);
    final changes = _objectList(group['changes'], '$label.changes');
    if (changes.isEmpty) {
      throw FormatException('$label.changes must be a non-empty array');
    }
    if (changes.length > maximumChangesPerGroup) {
      throw FormatException(
        '$label.changes may contain at most $maximumChangesPerGroup items',
      );
    }
    // The server's 5 MiB invariant is defined over changes_json, not over the
    // revision/mutation wrapper stored beside it.
    _requireEncodedSize(changes, maximumChangeGroupBytes, '$label.changes');

    final normalizedChanges = <Map<String, Object?>>[];
    final entityKeys = <(String, String)>{};
    for (var index = 0; index < changes.length; index++) {
      final change = _normalizeChange(
        _stringMap(changes[index], '$label.changes[$index]'),
        '$label.changes[$index]',
      );
      final entityKey = (
        change['entity_type']! as String,
        change['entity_id']! as String,
      );
      if (!entityKeys.add(entityKey)) {
        throw FormatException(
          '$label may contain ${entityKey.$1}/${entityKey.$2} only once',
        );
      }
      normalizedChanges.add(change);
    }
    return {
      'revision': _integer(
        group['revision'],
        '$label.revision',
        minimum: 1,
        maximum: maximumSignedInt64,
      ),
      'mutation_id': _identifier(
        group['mutation_id'],
        '$label.mutation_id',
        128,
      ),
      'changes': normalizedChanges,
    };
  }

  static Map<String, Object?> _normalizeChange(
    Map<String, Object?> change,
    String label,
  ) {
    const keys = {'entity_type', 'entity_id', 'operation', 'data'};
    _requireKeys(change, keys, keys, label);
    final entityType = change['entity_type'];
    if (entityType is! String || !_entityTypes.contains(entityType)) {
      throw FormatException('$label.entity_type is unsupported');
    }
    final entityId = _identifier(
      change['entity_id'],
      '$label.entity_id',
      entityType == 'barcode_mapping' ? 512 : 128,
    );
    final operation = change['operation'];
    if (operation is! String || !_operations.contains(operation)) {
      throw FormatException('$label.operation is unsupported');
    }
    final rawData = _stringMap(change['data'], '$label.data');
    late final Map<String, Object?> data;
    switch (entityType) {
      case 'custom_issue':
        data = _customIssueData(rawData, '$label.data');
      case 'collection_entry':
        data = _collectionData(rawData, '$label.data');
        if (entityId != data['issue_id']) {
          throw FormatException(
            '$label.entity_id must equal $label.data.issue_id',
          );
        }
      case 'copy':
        data = _copyData(rawData, '$label.data');
      case 'barcode_mapping':
        data = _barcodeData(rawData, '$label.data');
    }
    if (data['deleted'] != (operation == 'delete')) {
      throw FormatException(
        '$label.data.deleted must agree with $label.operation',
      );
    }
    return {
      'entity_type': entityType,
      'entity_id': entityId,
      'operation': operation,
      'data': data,
    };
  }

  static Map<String, Object?> _customIssueData(
    Map<String, Object?> data,
    String label,
  ) {
    const keys = {
      'series',
      'edition',
      'number',
      'title',
      'publisher',
      'year',
      'page_count',
      'writer',
      'artist',
      'deleted',
    };
    _requireKeys(data, keys, keys, label);
    return {
      'series': _text(data['series'], '$label.series', 200, nonempty: true),
      'edition': _text(data['edition'], '$label.edition', 200),
      'number': _integer(
        data['number'],
        '$label.number',
        minimum: 0,
        maximum: 1000000000,
      ),
      'title': _text(data['title'], '$label.title', 500, nonempty: true),
      'publisher': _text(data['publisher'], '$label.publisher', 200),
      'year': _nullableInteger(data['year'], '$label.year', 0, 3000),
      'page_count': _nullableInteger(
        data['page_count'],
        '$label.page_count',
        0,
        100000,
      ),
      'writer': _text(data['writer'], '$label.writer', 300),
      'artist': _text(data['artist'], '$label.artist', 300),
      'deleted': _boolean(data['deleted'], '$label.deleted'),
    };
  }

  static Map<String, Object?> _collectionData(
    Map<String, Object?> data,
    String label,
  ) {
    const required = {
      'issue_id',
      'owned',
      'is_wanted',
      'is_read',
      'is_duplicate',
      'rating',
      'notes',
      'deleted',
      'updated_at',
    };
    _requireKeys(data, required, {...required, 'issue_hint'}, label);
    final issueId = _identifier(data['issue_id'], '$label.issue_id', 128);
    return {
      'issue_id': issueId,
      'owned': _boolean(data['owned'], '$label.owned'),
      'is_wanted': _boolean(data['is_wanted'], '$label.is_wanted'),
      'is_read': _boolean(data['is_read'], '$label.is_read'),
      'is_duplicate': _boolean(data['is_duplicate'], '$label.is_duplicate'),
      'rating': _integer(
        data['rating'],
        '$label.rating',
        minimum: 0,
        maximum: 5,
      ),
      'notes': _text(data['notes'], '$label.notes', 10000),
      'deleted': _boolean(data['deleted'], '$label.deleted'),
      'updated_at': _integer(
        data['updated_at'],
        '$label.updated_at',
        minimum: 0,
        maximum: maximumSignedInt64,
      ),
      'issue_hint': _issueHint(
        data['issue_hint'],
        issueId,
        '$label.issue_hint',
      ),
    };
  }

  static Map<String, Object?> _copyData(
    Map<String, Object?> data,
    String label,
  ) {
    const required = {
      'issue_id',
      'ordinal',
      'active',
      'condition_grade',
      'purchase_price',
      'estimated_value',
      'loaned_to',
      'deleted',
      'updated_at',
    };
    _requireKeys(data, required, {...required, 'issue_hint'}, label);
    final issueId = _identifier(data['issue_id'], '$label.issue_id', 128);
    final condition = _text(
      data['condition_grade'],
      '$label.condition_grade',
      8,
    );
    if (!_conditionGrades.contains(condition)) {
      throw FormatException('$label.condition_grade is invalid');
    }
    return {
      'issue_id': issueId,
      'ordinal': _integer(
        data['ordinal'],
        '$label.ordinal',
        minimum: 0,
        maximum: 1000000,
      ),
      'active': _boolean(data['active'], '$label.active'),
      'condition_grade': condition,
      'purchase_price': _nullableNumber(
        data['purchase_price'],
        '$label.purchase_price',
      ),
      'estimated_value': _nullableNumber(
        data['estimated_value'],
        '$label.estimated_value',
      ),
      'loaned_to': _text(data['loaned_to'], '$label.loaned_to', 300),
      'deleted': _boolean(data['deleted'], '$label.deleted'),
      'updated_at': _integer(
        data['updated_at'],
        '$label.updated_at',
        minimum: 0,
        maximum: maximumSignedInt64,
      ),
      'issue_hint': _issueHint(
        data['issue_hint'],
        issueId,
        '$label.issue_hint',
      ),
    };
  }

  static Map<String, Object?> _barcodeData(
    Map<String, Object?> data,
    String label,
  ) {
    const required = {'issue_id', 'deleted', 'updated_at'};
    _requireKeys(data, required, {...required, 'issue_hint'}, label);
    final issueId = _identifier(data['issue_id'], '$label.issue_id', 128);
    return {
      'issue_id': issueId,
      'deleted': _boolean(data['deleted'], '$label.deleted'),
      'updated_at': _integer(
        data['updated_at'],
        '$label.updated_at',
        minimum: 0,
        maximum: maximumSignedInt64,
      ),
      'issue_hint': _issueHint(
        data['issue_hint'],
        issueId,
        '$label.issue_hint',
      ),
    };
  }

  static Map<String, Object?>? _issueHint(
    Object? raw,
    String issueId,
    String label,
  ) {
    if (raw == null) return null;
    final hint = _stringMap(raw, label);
    const keys = {
      'id',
      'series',
      'edition',
      'number',
      'title',
      'publisher',
      'year',
      'origin',
    };
    _requireKeys(hint, keys, keys, label);
    final hintedId = _identifier(hint['id'], '$label.id', 128);
    if (hintedId != issueId) {
      throw FormatException('$label.id must equal issue_id');
    }
    final origin = hint['origin'];
    if (origin != 'bundled' && origin != 'custom') {
      throw FormatException('$label.origin must be bundled or custom');
    }
    return {
      'id': hintedId,
      'series': _text(hint['series'], '$label.series', 200, nonempty: true),
      'edition': _text(hint['edition'], '$label.edition', 200),
      'number': _integer(
        hint['number'],
        '$label.number',
        minimum: 0,
        maximum: 1000000000,
      ),
      'title': _text(hint['title'], '$label.title', 500, nonempty: true),
      'publisher': _text(hint['publisher'], '$label.publisher', 200),
      'year': _nullableInteger(hint['year'], '$label.year', 0, 3000),
      'origin': origin,
    };
  }

  static void _requireKeys(
    Map<String, Object?> value,
    Set<String> required,
    Set<String> allowed,
    String label,
  ) {
    final keys = value.keys.toSet();
    final missing = required.difference(keys);
    final unknown = keys.difference(allowed);
    if (missing.isNotEmpty) {
      final fields = missing.toList()..sort();
      throw FormatException('$label is missing: ${fields.join(', ')}');
    }
    if (unknown.isNotEmpty) {
      final fields = unknown.toList()..sort();
      throw FormatException('$label has unknown fields: ${fields.join(', ')}');
    }
  }

  static Map<String, Object?> _stringMap(Object? value, String label) {
    if (value is! Map) throw FormatException('$label must be an object');
    final result = <String, Object?>{};
    for (final entry in value.entries) {
      if (entry.key is! String) {
        throw FormatException('$label keys must be strings');
      }
      result[entry.key as String] = entry.value;
    }
    return result;
  }

  static List<Object?> _objectList(Object? value, String label) {
    if (value is! List) throw FormatException('$label must be an array');
    return List<Object?>.from(value);
  }

  static String _identifier(Object? value, String label, int maximumBytes) {
    if (value is! String || value.isEmpty || value != value.trim()) {
      throw FormatException('$label must be a non-empty trimmed string');
    }
    if (value.codeUnits.any((unit) => unit < 0x20 || unit == 0x7F) ||
        _utf8Length(value, label) > maximumBytes) {
      throw FormatException(
        '$label is invalid or exceeds $maximumBytes UTF-8 bytes',
      );
    }
    return value;
  }

  static String _text(
    Object? value,
    String label,
    int maximumBytes, {
    bool nonempty = false,
  }) {
    if (value is! String) throw FormatException('$label must be a string');
    if (nonempty && value.trim().isEmpty) {
      throw FormatException('$label must not be empty');
    }
    if (_utf8Length(value, label) > maximumBytes) {
      throw FormatException('$label exceeds $maximumBytes UTF-8 bytes');
    }
    return value;
  }

  static int _utf8Length(String value, String label) {
    for (var index = 0; index < value.length; index++) {
      final unit = value.codeUnitAt(index);
      if (unit >= 0xD800 && unit <= 0xDBFF) {
        if (index + 1 >= value.length) {
          throw FormatException('$label contains invalid Unicode');
        }
        final trailing = value.codeUnitAt(++index);
        if (trailing < 0xDC00 || trailing > 0xDFFF) {
          throw FormatException('$label contains invalid Unicode');
        }
      } else if (unit >= 0xDC00 && unit <= 0xDFFF) {
        throw FormatException('$label contains invalid Unicode');
      }
    }
    return utf8.encode(value).length;
  }

  static int _integer(
    Object? value,
    String label, {
    required int minimum,
    required int maximum,
  }) {
    if (value is! int) throw FormatException('$label must be an integer');
    if (value < minimum || value > maximum) {
      throw FormatException('$label must be between $minimum and $maximum');
    }
    return value;
  }

  static int? _nullableInteger(
    Object? value,
    String label,
    int minimum,
    int maximum,
  ) => value == null
      ? null
      : _integer(value, label, minimum: minimum, maximum: maximum);

  static double? _nullableNumber(Object? value, String label) {
    if (value == null) return null;
    if (value is! num) {
      throw FormatException(
        '$label must be a finite non-negative number or null',
      );
    }
    final result = value.toDouble();
    if (!result.isFinite || result < 0) {
      throw FormatException(
        '$label must be a finite non-negative number or null',
      );
    }
    return result;
  }

  static bool _boolean(Object? value, String label) {
    if (value is! bool) throw FormatException('$label must be a boolean');
    return value;
  }

  static void _requireEncodedSize(
    Object? value,
    int maximumBytes,
    String label,
  ) {
    late final int bytes;
    try {
      bytes = utf8.encode(jsonEncode(value)).length;
    } on Object {
      throw FormatException('$label is not JSON-compatible');
    }
    if (bytes > maximumBytes) {
      throw FormatException('$label exceeds $maximumBytes UTF-8 bytes');
    }
  }
}
