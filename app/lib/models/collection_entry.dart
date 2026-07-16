class CollectionEntry {
  const CollectionEntry({
    required this.issueId,
    this.owned = false,
    this.wanted = false,
    this.read = false,
    this.duplicate = false,
    this.rating = 0,
    this.notes = '',
    this.deleted = false,
    required this.updatedAt,
  });

  final String issueId;
  final bool owned;
  final bool wanted;
  final bool read;
  final bool duplicate;
  final int rating;
  final String notes;
  final bool deleted;
  final int updatedAt;

  CollectionEntry copyWith({
    String? issueId,
    bool? owned,
    bool? wanted,
    bool? read,
    bool? duplicate,
    int? rating,
    String? notes,
    bool? deleted,
    int? updatedAt,
  }) => CollectionEntry(
    issueId: issueId ?? this.issueId,
    owned: owned ?? this.owned,
    wanted: wanted ?? this.wanted,
    read: read ?? this.read,
    duplicate: duplicate ?? this.duplicate,
    rating: rating ?? this.rating,
    notes: notes ?? this.notes,
    deleted: deleted ?? this.deleted,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  Map<String, Object?> toMap() => {
    'issue_id': issueId,
    'owned': owned ? 1 : 0,
    'is_wanted': wanted ? 1 : 0,
    'is_read': read ? 1 : 0,
    'is_duplicate': duplicate ? 1 : 0,
    'rating': rating,
    'notes': notes,
    'deleted': deleted ? 1 : 0,
    'updated_at': updatedAt,
  };

  factory CollectionEntry.fromMap(Map<String, Object?> map) => CollectionEntry(
    issueId: map['issue_id'] as String,
    owned: (map['owned'] as num? ?? 0) != 0,
    wanted: (map['is_wanted'] as num? ?? 0) != 0,
    read: (map['is_read'] as num? ?? 0) != 0,
    duplicate: (map['is_duplicate'] as num? ?? 0) != 0,
    rating: (map['rating'] as num? ?? 0).toInt(),
    notes: (map['notes'] ?? '') as String,
    deleted: (map['deleted'] as num? ?? 0) != 0,
    updatedAt: (map['updated_at'] as num).toInt(),
  );
}
