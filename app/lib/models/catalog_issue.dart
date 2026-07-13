import 'dart:convert';
import 'dart:typed_data';

import 'comic.dart';

class CatalogIssue {
  const CatalogIssue({
    required this.id,
    required this.sourceEdition,
    required this.series,
    required this.edition,
    required this.number,
    required this.title,
    required this.publisher,
    this.year,
    this.coverAsset,
    this.visualHash,
    this.colorSignature,
    this.barcodes = const [],
  });

  final String id;
  final String sourceEdition;
  final String series;
  final String edition;
  final int number;
  final String title;
  final String publisher;
  final int? year;
  final String? coverAsset;
  final String? visualHash;
  final Uint8List? colorSignature;
  final List<String> barcodes;

  factory CatalogIssue.fromJson(Map<String, Object?> json) {
    final encodedColor = json['colorSignature'] as String?;
    return CatalogIssue(
      id: json['id'] as String,
      sourceEdition: json['sourceEdition'] as String,
      series: json['series'] as String,
      edition: json['edition'] as String,
      number: (json['number'] as num).toInt(),
      title: json['title'] as String,
      publisher: json['publisher'] as String,
      year: (json['year'] as num?)?.toInt(),
      coverAsset: json['coverAsset'] as String?,
      visualHash: json['visualHash'] as String?,
      colorSignature: encodedColor == null ? null : base64Decode(encodedColor),
      barcodes: (json['barcodes'] as List<Object?>? ?? const [])
          .whereType<String>()
          .toList(growable: false),
    );
  }

  Comic toComic() => Comic(
    id: id,
    series: series,
    edition: edition,
    number: number,
    title: title,
    publisher: publisher,
    year: year,
    owned: false,
    read: false,
    condition: 'F',
    notes: 'BSP katalog · $sourceEdition',
    coverAsset: coverAsset ?? '',
    updatedAt: 0,
  );
}
