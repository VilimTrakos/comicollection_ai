import 'sync_v2_upload_validator.dart';
import 'sync_v2_response_validator.dart';

enum SyncEntityType {
  customIssue('custom_issue'),
  collectionEntry('collection_entry'),
  comicCopy('copy'),
  barcodeMapping('barcode_mapping');

  const SyncEntityType(this.wireName);

  final String wireName;

  static SyncEntityType fromWire(Object? value) => values.firstWhere(
    (type) => type.wireName == value,
    orElse: () => throw FormatException('Unknown sync entity type: $value'),
  );
}

enum SyncOperation {
  upsert('upsert'),
  delete('delete');

  const SyncOperation(this.wireName);

  final String wireName;

  static SyncOperation fromWire(Object? value) => values.firstWhere(
    (operation) => operation.wireName == value,
    orElse: () => throw FormatException('Unknown sync operation: $value'),
  );
}

class SyncEntityChange {
  SyncEntityChange({
    required this.entityType,
    required this.entityId,
    required this.operation,
    required Map<String, Object?> data,
  }) : data = _immutableJsonMap(data) {
    _requireNonEmpty(entityId, 'entity_id');
  }

  final SyncEntityType entityType;
  final String entityId;
  final SyncOperation operation;
  final Map<String, Object?> data;

  Map<String, Object?> toJson() => {
    'entity_type': entityType.wireName,
    'entity_id': entityId,
    'operation': operation.wireName,
    'data': data,
  };

  factory SyncEntityChange.fromJson(Map<String, Object?> json) =>
      SyncEntityChange(
        entityType: SyncEntityType.fromWire(json['entity_type']),
        entityId: _requiredString(json, 'entity_id'),
        operation: SyncOperation.fromWire(json['operation']),
        data: _requiredMap(json, 'data'),
      );
}

class SyncMutation {
  SyncMutation({
    required this.mutationId,
    required this.createdAt,
    required Iterable<SyncEntityChange> changes,
  }) : changes = List.unmodifiable(changes) {
    _requireNonEmpty(mutationId, 'mutation_id');
    _requireNonNegative(createdAt, 'created_at');
    if (this.changes.isEmpty) {
      throw ArgumentError.value(changes, 'changes', 'must not be empty');
    }
  }

  final String mutationId;
  final int createdAt;
  final List<SyncEntityChange> changes;

  Map<String, Object?> toJson() => {
    'mutation_id': mutationId,
    'created_at': createdAt,
    'changes': changes.map((change) => change.toJson()).toList(growable: false),
  };

  factory SyncMutation.fromJson(Map<String, Object?> json) => SyncMutation(
    mutationId: _requiredString(json, 'mutation_id'),
    createdAt: _requiredInteger(json, 'created_at'),
    changes: _requiredObjectList(
      json,
      'changes',
    ).map(_asStringKeyedMap).map(SyncEntityChange.fromJson),
  );
}

class SyncAcknowledgement {
  SyncAcknowledgement({
    required this.mutationId,
    required this.revision,
    required this.status,
  }) {
    _requireNonEmpty(mutationId, 'mutation_id');
    _requireNonNegative(revision, 'revision');
    if (!_acknowledgementStatuses.contains(status)) {
      throw ArgumentError.value(status, 'status', 'is not supported');
    }
  }

  static const _acknowledgementStatuses = {'applied', 'duplicate'};

  final String mutationId;
  final int revision;
  final String status;

  Map<String, Object?> toJson() => {
    'mutation_id': mutationId,
    'revision': revision,
    'status': status,
  };

  factory SyncAcknowledgement.fromJson(Map<String, Object?> json) =>
      SyncAcknowledgement(
        mutationId: _requiredString(json, 'mutation_id'),
        revision: _requiredInteger(json, 'revision'),
        status: _requiredString(json, 'status'),
      );
}

class SyncChangeGroup {
  SyncChangeGroup({
    required this.revision,
    required this.mutationId,
    required Iterable<SyncEntityChange> changes,
  }) : changes = List.unmodifiable(changes) {
    _requireNonNegative(revision, 'revision');
    _requireNonEmpty(mutationId, 'mutation_id');
    if (this.changes.isEmpty) {
      throw ArgumentError.value(changes, 'changes', 'must not be empty');
    }
  }

  final int revision;
  final String mutationId;
  final List<SyncEntityChange> changes;

  Map<String, Object?> toJson() => {
    'revision': revision,
    'mutation_id': mutationId,
    'changes': changes.map((change) => change.toJson()).toList(growable: false),
  };

  factory SyncChangeGroup.fromJson(Map<String, Object?> json) =>
      SyncChangeGroup(
        revision: _requiredInteger(json, 'revision'),
        mutationId: _requiredString(json, 'mutation_id'),
        changes: _requiredObjectList(
          json,
          'changes',
        ).map(_asStringKeyedMap).map(SyncEntityChange.fromJson),
      );
}

class SyncV2Exchange {
  SyncV2Exchange({
    required this.serverId,
    required this.requestId,
    required this.serverTime,
    required this.nextCursor,
    required this.hasMore,
    required Iterable<SyncAcknowledgement> acknowledgements,
    required Iterable<SyncChangeGroup> changeGroups,
  }) : acknowledgements = List.unmodifiable(acknowledgements),
       changeGroups = List.unmodifiable(changeGroups) {
    _requireNonEmpty(serverId, 'server_id');
    _requireNonEmpty(requestId, 'request_id');
    _requireNonNegative(serverTime, 'server_time');
    _requireNonNegative(nextCursor, 'next_cursor');
    var lastRevision = -1;
    for (final group in this.changeGroups) {
      if (group.revision <= lastRevision) {
        throw ArgumentError.value(
          changeGroups,
          'changeGroups',
          'revisions must be strictly increasing',
        );
      }
      if (group.revision > nextCursor) {
        throw ArgumentError.value(
          group.revision,
          'changeGroups',
          'revision exceeds next cursor',
        );
      }
      lastRevision = group.revision;
    }
    if (this.changeGroups.isNotEmpty && lastRevision != nextCursor) {
      throw ArgumentError.value(
        nextCursor,
        'nextCursor',
        'must equal the last change-group revision',
      );
    }
  }

  final String serverId;
  final String requestId;
  final int serverTime;
  final int nextCursor;
  final bool hasMore;
  final List<SyncAcknowledgement> acknowledgements;
  final List<SyncChangeGroup> changeGroups;

  Map<String, Object?> toJson() => {
    'protocol': 2,
    'server_id': serverId,
    'request_id': requestId,
    'server_time': serverTime,
    'next_cursor': nextCursor,
    'has_more': hasMore,
    'acknowledgements': acknowledgements
        .map((acknowledgement) => acknowledgement.toJson())
        .toList(growable: false),
    'change_groups': changeGroups
        .map((group) => group.toJson())
        .toList(growable: false),
  };

  factory SyncV2Exchange.fromJson(Map<String, Object?> json) {
    final normalized = SyncV2ResponseValidator.validateAndNormalize(json);
    return SyncV2Exchange(
      serverId: _requiredString(normalized, 'server_id'),
      requestId: _requiredString(normalized, 'request_id'),
      serverTime: _requiredInteger(normalized, 'server_time'),
      nextCursor: _requiredInteger(normalized, 'next_cursor'),
      hasMore: _requiredBool(normalized, 'has_more'),
      acknowledgements: _requiredObjectList(
        normalized,
        'acknowledgements',
      ).map(_asStringKeyedMap).map(SyncAcknowledgement.fromJson),
      changeGroups: _requiredObjectList(
        normalized,
        'change_groups',
      ).map(_asStringKeyedMap).map(SyncChangeGroup.fromJson),
    );
  }
}

class SyncUploadBatch {
  SyncUploadBatch({
    required this.deviceId,
    required this.serverId,
    required this.cursor,
    required Iterable<SyncMutation> mutations,
  }) : mutations = List.unmodifiable(mutations) {
    _requireNonEmpty(deviceId, 'device_id');
    _requireNonNegative(cursor, 'cursor');
    final mutationIds = this.mutations
        .map((mutation) => mutation.mutationId)
        .toSet();
    if (mutationIds.length != this.mutations.length) {
      throw ArgumentError.value(
        mutations,
        'mutations',
        'mutation ids must be unique',
      );
    }
    SyncV2UploadValidator.validateBatch(
      deviceId: deviceId,
      serverId: serverId,
      cursor: cursor,
      mutations: this.mutations.map((mutation) => mutation.toJson()),
    );
  }

  final String deviceId;
  final String serverId;
  final int cursor;
  final List<SyncMutation> mutations;

  Map<String, Object?> toRequestJson({
    required String requestId,
    required int limit,
  }) {
    _requireNonEmpty(requestId, 'request_id');
    if (limit <= 0) {
      throw ArgumentError.value(limit, 'limit', 'must be positive');
    }
    final request = <String, Object?>{
      'protocol': 2,
      'request_id': requestId,
      'device_id': deviceId,
      if (serverId.isNotEmpty) 'server_id': serverId,
      'cursor': cursor,
      'limit': limit,
      'mutations': mutations
          .map((mutation) => mutation.toJson())
          .toList(growable: false),
    };
    SyncV2UploadValidator.validateRequest(request);
    return request;
  }
}

Map<String, Object?> _requiredMap(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! Map) throw FormatException('$key must be an object');
  return _asStringKeyedMap(value);
}

List<Object?> _requiredObjectList(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! List) throw FormatException('$key must be an array');
  return List<Object?>.from(value);
}

Map<String, Object?> _asStringKeyedMap(Object? value) {
  if (value is! Map) throw const FormatException('Expected an object');
  final result = <String, Object?>{};
  for (final entry in value.entries) {
    if (entry.key is! String) {
      throw const FormatException('Object keys must be strings');
    }
    result[entry.key as String] = entry.value;
  }
  return result;
}

String _requiredString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('$key must be a non-empty string');
  }
  return value;
}

int _requiredInteger(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! num || !value.isFinite || value != value.truncate()) {
    throw FormatException('$key must be an integer');
  }
  final result = value.toInt();
  if (result < 0) throw FormatException('$key must not be negative');
  return result;
}

bool _requiredBool(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! bool) throw FormatException('$key must be a boolean');
  return value;
}

void _requireNonEmpty(String value, String name) {
  if (value.trim().isEmpty) {
    throw ArgumentError.value(value, name, 'must not be empty');
  }
}

void _requireNonNegative(int value, String name) {
  if (value < 0) throw ArgumentError.value(value, name, 'must not be negative');
}

Map<String, Object?> _immutableJsonMap(Map<String, Object?> source) {
  final result = <String, Object?>{};
  for (final entry in source.entries) {
    result[entry.key] = _immutableJsonValue(entry.value);
  }
  return Map.unmodifiable(result);
}

Object? _immutableJsonValue(Object? value) => switch (value) {
  null || String() || bool() => value,
  num() when value.isFinite => value,
  num() => throw ArgumentError.value(value, 'data', 'must be finite'),
  List() => List.unmodifiable(value.map(_immutableJsonValue)),
  Map() => _immutableJsonMap(_asStringKeyedMap(value)),
  _ => throw ArgumentError.value(value, 'data', 'is not JSON-compatible'),
};
