class Comic {
  Comic({
    required this.id,
    required this.series,
    required this.edition,
    required this.number,
    required this.title,
    this.publisher = '',
    this.year,
    this.owned = true,
    this.read = false,
    this.condition = 'F',
    this.purchasePrice,
    this.estimatedValue,
    this.duplicate = false,
    this.loanedTo = '',
    this.notes = '',
    this.coverAsset = '',
    this.rating = 0,
    this.pageCount,
    this.writer = '',
    this.artist = '',
    this.deleted = false,
    required this.updatedAt,
  });

  final String id;
  final String series;
  final String edition;
  final int number;
  final String title;
  final String publisher;
  final int? year;
  final bool owned;
  final bool read;
  final String condition;
  final double? purchasePrice;
  final double? estimatedValue;
  final bool duplicate;
  final String loanedTo;
  final String notes;
  final String coverAsset;
  final int rating;
  final int? pageCount;
  final String writer;
  final String artist;
  final bool deleted;
  final int updatedAt;

  Comic copyWith({
    String? series,
    String? edition,
    int? number,
    String? title,
    String? publisher,
    int? year,
    bool? owned,
    bool? read,
    String? condition,
    double? purchasePrice,
    double? estimatedValue,
    bool? duplicate,
    String? loanedTo,
    String? notes,
    String? coverAsset,
    int? rating,
    int? pageCount,
    String? writer,
    String? artist,
    bool? deleted,
    int? updatedAt,
  }) => Comic(
    id: id,
    series: series ?? this.series,
    edition: edition ?? this.edition,
    number: number ?? this.number,
    title: title ?? this.title,
    publisher: publisher ?? this.publisher,
    year: year ?? this.year,
    owned: owned ?? this.owned,
    read: read ?? this.read,
    condition: condition ?? this.condition,
    purchasePrice: purchasePrice ?? this.purchasePrice,
    estimatedValue: estimatedValue ?? this.estimatedValue,
    duplicate: duplicate ?? this.duplicate,
    loanedTo: loanedTo ?? this.loanedTo,
    notes: notes ?? this.notes,
    coverAsset: coverAsset ?? this.coverAsset,
    rating: rating ?? this.rating,
    pageCount: pageCount ?? this.pageCount,
    writer: writer ?? this.writer,
    artist: artist ?? this.artist,
    deleted: deleted ?? this.deleted,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  Map<String, Object?> toMap() => {
    'id': id,
    'series': series,
    'edition': edition,
    'number': number,
    'title': title,
    'publisher': publisher,
    'year': year,
    'owned': owned ? 1 : 0,
    'is_read': read ? 1 : 0,
    'condition_grade': condition,
    'purchase_price': purchasePrice,
    'estimated_value': estimatedValue,
    'is_duplicate': duplicate ? 1 : 0,
    'loaned_to': loanedTo,
    'notes': notes,
    'cover_asset': coverAsset,
    'rating': rating,
    'page_count': pageCount,
    'writer': writer,
    'artist': artist,
    'deleted': deleted ? 1 : 0,
    'updated_at': updatedAt,
  };

  Map<String, Object?> toJson() => toMap();

  factory Comic.fromMap(Map<String, Object?> m) => Comic(
    id: m['id'] as String,
    series: (m['series'] ?? '') as String,
    edition: (m['edition'] ?? '') as String,
    number: (m['number'] as num).toInt(),
    title: (m['title'] ?? '') as String,
    publisher: (m['publisher'] ?? '') as String,
    year: (m['year'] as num?)?.toInt(),
    owned: (m['owned'] as num? ?? 0) != 0,
    read: (m['is_read'] as num? ?? 0) != 0,
    condition: (m['condition_grade'] ?? 'F') as String,
    purchasePrice: (m['purchase_price'] as num?)?.toDouble(),
    estimatedValue: (m['estimated_value'] as num?)?.toDouble(),
    duplicate: (m['is_duplicate'] as num? ?? 0) != 0,
    loanedTo: (m['loaned_to'] ?? '') as String,
    notes: (m['notes'] ?? '') as String,
    coverAsset: (m['cover_asset'] ?? '') as String,
    rating: (m['rating'] as num? ?? 0).toInt(),
    pageCount: (m['page_count'] as num?)?.toInt(),
    writer: (m['writer'] ?? '') as String,
    artist: (m['artist'] ?? '') as String,
    deleted: (m['deleted'] as num? ?? 0) != 0,
    updatedAt: (m['updated_at'] as num).toInt(),
  );
}
