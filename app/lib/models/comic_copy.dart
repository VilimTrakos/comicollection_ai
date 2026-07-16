const _notProvided = Object();

class ComicCopy {
  const ComicCopy({
    required this.id,
    required this.issueId,
    required this.ordinal,
    this.active = true,
    this.condition = '',
    this.purchasePrice,
    this.estimatedValue,
    this.loanedTo = '',
    this.deleted = false,
    required this.updatedAt,
  });

  final String id;
  final String issueId;
  final int ordinal;
  final bool active;
  final String condition;
  final double? purchasePrice;
  final double? estimatedValue;
  final String loanedTo;
  final bool deleted;
  final int updatedAt;

  ComicCopy copyWith({
    String? id,
    String? issueId,
    int? ordinal,
    bool? active,
    String? condition,
    Object? purchasePrice = _notProvided,
    Object? estimatedValue = _notProvided,
    String? loanedTo,
    bool? deleted,
    int? updatedAt,
  }) => ComicCopy(
    id: id ?? this.id,
    issueId: issueId ?? this.issueId,
    ordinal: ordinal ?? this.ordinal,
    active: active ?? this.active,
    condition: condition ?? this.condition,
    purchasePrice: identical(purchasePrice, _notProvided)
        ? this.purchasePrice
        : (purchasePrice as num?)?.toDouble(),
    estimatedValue: identical(estimatedValue, _notProvided)
        ? this.estimatedValue
        : (estimatedValue as num?)?.toDouble(),
    loanedTo: loanedTo ?? this.loanedTo,
    deleted: deleted ?? this.deleted,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  Map<String, Object?> toMap() => {
    'id': id,
    'issue_id': issueId,
    'ordinal': ordinal,
    'active': active ? 1 : 0,
    'condition_grade': condition,
    'purchase_price': purchasePrice,
    'estimated_value': estimatedValue,
    'loaned_to': loanedTo,
    'deleted': deleted ? 1 : 0,
    'updated_at': updatedAt,
  };

  factory ComicCopy.fromMap(Map<String, Object?> map) => ComicCopy(
    id: map['id'] as String,
    issueId: map['issue_id'] as String,
    ordinal: (map['ordinal'] as num).toInt(),
    active: (map['active'] as num? ?? 1) != 0,
    condition: (map['condition_grade'] ?? '') as String,
    purchasePrice: (map['purchase_price'] as num?)?.toDouble(),
    estimatedValue: (map['estimated_value'] as num?)?.toDouble(),
    loanedTo: (map['loaned_to'] ?? '') as String,
    deleted: (map['deleted'] as num? ?? 0) != 0,
    updatedAt: (map['updated_at'] as num).toInt(),
  );
}
