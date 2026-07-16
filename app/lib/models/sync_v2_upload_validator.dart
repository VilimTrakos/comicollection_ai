import 'dart:convert';

/// Validates only client-to-server sync v2 payloads.
///
/// Inbound change groups deliberately do not pass through this validator. The
/// server adds fields such as `custom_issue.data.deleted` to its canonical
/// response, while that field is not legal in an upload request.
abstract final class SyncV2UploadValidator {
  static const maximumMutations = 100;
  static const maximumChangesPerMutation = 500;
  static const maximumChangesPerRequest = 500;
  static const maximumLimit = 100;
  static const maximumRequestBytes = 8 * 1024 * 1024;
  static const maximumMutationGroupBytes = 5 * 1024 * 1024;
  static const maximumSignedInt64 = 0x7FFFFFFFFFFFFFFF;

  static const _entityTypes = {
    'custom_issue',
    'collection_entry',
    'copy',
    'barcode_mapping',
  };
  static const _operations = {'upsert', 'delete'};
  static const _conditionGrades = {'', 'M', 'VF', 'F', 'G', 'P'};

  /// Validates a mutation before it is persisted in the durable outbox.
  static void validateMutation(
    Map<String, Object?> mutation, {
    String label = 'mutation',
  }) {
    _normalizeMutation(mutation, label);
  }

  /// Validates decoded durable mutations and installation metadata before a
  /// batch can cross the transport boundary.
  static void validateBatch({
    required Object? deviceId,
    required Object? serverId,
    required Object? cursor,
    required Iterable<Map<String, Object?>> mutations,
  }) {
    _identifier(deviceId, 'device_id', 128);
    if (serverId != '') _identifier(serverId, 'server_id', 128);
    _integer(cursor, 'cursor', minimum: 0);
    _validateMutations(mutations.toList(growable: false));
  }

  /// Validates the exact serialized request, including its configured page
  /// limit and the HTTP server's maximum accepted request size.
  static void validateRequest(Map<String, Object?> request) {
    const required = {
      'protocol',
      'request_id',
      'device_id',
      'cursor',
      'limit',
      'mutations',
    };
    _requireKeys(request, required, {...required, 'server_id'}, 'request');
    if (request['protocol'] is! int || request['protocol'] != 2) {
      throw const FormatException('request.protocol must be the integer 2');
    }
    _identifier(request['request_id'], 'request_id', 128);
    _identifier(request['device_id'], 'device_id', 128);
    if (request.containsKey('server_id')) {
      final serverId = request['server_id'];
      if (serverId != '') _identifier(serverId, 'server_id', 128);
    }
    _integer(request['cursor'], 'cursor', minimum: 0);
    _integer(request['limit'], 'limit', minimum: 1, maximum: maximumLimit);
    final mutations = _objectList(request['mutations'], 'mutations')
        .asMap()
        .entries
        .map((entry) => _stringMap(entry.value, 'mutations[${entry.key}]'))
        .toList(growable: false);
    _validateMutations(mutations);

    final encodedBytes = utf8.encode(jsonEncode(request)).length;
    if (encodedBytes > maximumRequestBytes) {
      throw FormatException(
        'request exceeds the $maximumRequestBytes-byte upload limit',
      );
    }
  }

  static void _validateMutations(List<Map<String, Object?>> mutations) {
    if (mutations.length > maximumMutations) {
      throw FormatException(
        'mutations may contain at most $maximumMutations items',
      );
    }
    final mutationIds = <String>{};
    var totalChanges = 0;
    for (var index = 0; index < mutations.length; index++) {
      final label = 'mutations[$index]';
      final normalized = _normalizeMutation(mutations[index], label);
      final mutationId = normalized['mutation_id']! as String;
      if (!mutationIds.add(mutationId)) {
        throw const FormatException(
          'mutation_id must be unique within a request',
        );
      }
      totalChanges += (normalized['changes']! as List<Object?>).length;
      if (totalChanges > maximumChangesPerRequest) {
        throw FormatException(
          'request may contain at most $maximumChangesPerRequest changes',
        );
      }
    }
  }

  static Map<String, Object?> _normalizeMutation(
    Map<String, Object?> mutation,
    String label,
  ) {
    const keys = {'mutation_id', 'created_at', 'changes'};
    _requireKeys(mutation, keys, keys, label);
    final mutationId = _identifier(
      mutation['mutation_id'],
      '$label.mutation_id',
      128,
    );
    final createdAt = _integer(
      mutation['created_at'],
      '$label.created_at',
      minimum: 0,
      maximum: maximumSignedInt64,
    );
    final changes = _objectList(mutation['changes'], '$label.changes');
    if (changes.isEmpty) {
      throw FormatException('$label.changes must be a non-empty array');
    }
    if (changes.length > maximumChangesPerMutation) {
      throw FormatException(
        '$label.changes may contain at most '
        '$maximumChangesPerMutation items',
      );
    }

    final normalizedChanges = <Map<String, Object?>>[];
    final entityKeys = <(String, String)>{};
    for (var index = 0; index < changes.length; index++) {
      final normalized = _normalizeChange(
        _stringMap(changes[index], '$label.changes[$index]'),
        '$label.changes[$index]',
      );
      final key = (
        normalized['entity_type']! as String,
        normalized['entity_id']! as String,
      );
      if (!entityKeys.add(key)) {
        throw FormatException(
          '$label may change ${key.$1}/${key.$2} only once',
        );
      }
      normalizedChanges.add(normalized);
    }
    final groupBytes = utf8.encode(jsonEncode(normalizedChanges)).length;
    if (groupBytes > maximumMutationGroupBytes) {
      throw FormatException(
        '$label produces a change group larger than '
        '$maximumMutationGroupBytes bytes',
      );
    }
    return {
      'mutation_id': mutationId,
      'created_at': createdAt,
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
        data = _issueData(rawData, '$label.data');
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
    if (entityType != 'custom_issue') {
      final expectedDeleted = operation == 'delete';
      if (data['deleted'] != expectedDeleted) {
        throw FormatException(
          '$label.data.deleted must agree with $label.operation',
        );
      }
    }

    // This is the server's canonical outbound group shape used solely for the
    // 5 MiB atomic-group byte check. Upload issue data itself must not contain
    // `deleted`; the server adds it to downloaded custom_issue snapshots.
    final canonicalData = entityType == 'custom_issue'
        ? <String, Object?>{...data, 'deleted': operation == 'delete'}
        : data;
    return {
      'entity_type': entityType,
      'entity_id': entityId,
      'operation': operation,
      'data': canonicalData,
    };
  }

  static Map<String, Object?> _issueData(
    Map<String, Object?> data,
    String label,
  ) {
    const required = {'series', 'edition', 'number', 'title'};
    const allowed = {
      ...required,
      'publisher',
      'year',
      'page_count',
      'writer',
      'artist',
    };
    _requireKeys(data, required, allowed, label);
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
      'publisher': _text(data['publisher'] ?? '', '$label.publisher', 200),
      'year': _nullableInteger(data['year'], '$label.year', 0, 3000),
      'page_count': _nullableInteger(
        data['page_count'],
        '$label.page_count',
        0,
        100000,
      ),
      'writer': _text(data['writer'] ?? '', '$label.writer', 300),
      'artist': _text(data['artist'] ?? '', '$label.artist', 300),
    };
  }

  static Map<String, Object?>? _issueHint(
    Object? raw,
    String issueId,
    String label,
  ) {
    if (raw == null) return null;
    final data = _stringMap(raw, label);
    const required = {'series', 'edition', 'number', 'title', 'origin'};
    const allowed = {...required, 'id', 'publisher', 'year'};
    _requireKeys(data, required, allowed, label);
    final hintedId = data.containsKey('id')
        ? _identifier(data['id'], '$label.id', 128)
        : issueId;
    if (hintedId != issueId) {
      throw FormatException('$label.id must equal issue_id');
    }
    final origin = data['origin'];
    if (origin != 'bundled' && origin != 'custom') {
      throw FormatException('$label.origin must be bundled or custom');
    }
    return {
      'id': issueId,
      'series': _text(data['series'], '$label.series', 200, nonempty: true),
      'edition': _text(data['edition'], '$label.edition', 200),
      'number': _integer(
        data['number'],
        '$label.number',
        minimum: 0,
        maximum: 1000000000,
      ),
      'title': _text(data['title'], '$label.title', 500, nonempty: true),
      'publisher': _text(data['publisher'] ?? '', '$label.publisher', 200),
      'year': _nullableInteger(data['year'], '$label.year', 0, 3000),
      'origin': origin,
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

  static void _requireKeys(
    Map<String, Object?> value,
    Set<String> required,
    Set<String> allowed,
    String label,
  ) {
    final missing = required.difference(value.keys.toSet());
    final unknown = value.keys.toSet().difference(allowed);
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
    int? minimum,
    int? maximum,
  }) {
    if (value is! int) throw FormatException('$label must be an integer');
    if (minimum != null && value < minimum) {
      throw FormatException('$label must be at least $minimum');
    }
    if (maximum != null && value > maximum) {
      throw FormatException('$label must be at most $maximum');
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
    final number = value.toDouble();
    if (!number.isFinite || number < 0) {
      throw FormatException(
        '$label must be a finite non-negative number or null',
      );
    }
    return number;
  }

  static bool _boolean(Object? value, String label) {
    if (value is! bool) throw FormatException('$label must be a boolean');
    return value;
  }
}
