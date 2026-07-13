import 'dart:convert';

import 'package:flutter/services.dart';

import '../models/catalog_issue.dart';

class CoverMatch {
  const CoverMatch({required this.issue, required this.score});
  final CatalogIssue issue;
  final double score;
}

class CatalogRepository {
  List<CatalogIssue> _issues = const [];
  Map<String, CatalogIssue> _byId = const {};
  Map<String, CatalogIssue> _byBarcode = const {};

  List<CatalogIssue> get issues => _issues;

  Future<void> load() async {
    if (_issues.isNotEmpty) return;
    final source = await rootBundle.loadString(
      'assets/catalog/bsp_catalog.json',
    );
    final payload = jsonDecode(source) as Map<String, dynamic>;
    _issues = (payload['issues'] as List<dynamic>)
        .map(
          (item) => CatalogIssue.fromJson(
            Map<String, Object?>.from(item as Map<dynamic, dynamic>),
          ),
        )
        .toList(growable: false);
    _byId = {for (final issue in _issues) issue.id: issue};
    _byBarcode = {
      for (final issue in _issues)
        for (final barcode in issue.barcodes) barcode: issue,
    };
  }

  CatalogIssue? byId(String id) => _byId[id];

  CatalogIssue? byBarcode(String value) => _byBarcode[value.trim()];

  void registerBarcode(String value, CatalogIssue issue) {
    final normalized = value.trim();
    if (normalized.isNotEmpty) _byBarcode[normalized] = issue;
  }

  List<CatalogIssue> matchText(String rawText, {int limit = 12}) {
    final normalized = normalize(rawText);
    if (normalized.isEmpty) return const [];
    final numbers = RegExp(
      r'(?<!\d)(\d{1,3})(?!\d)',
    ).allMatches(normalized).map((match) => int.parse(match.group(1)!)).toSet();
    final hasDylanDog = normalized.contains('DYLAN DOG');
    final candidates = <({CatalogIssue issue, double score})>[];
    for (final issue in _issues) {
      var score = 0.0;
      if (numbers.contains(issue.number)) score += 0.62;
      if (hasDylanDog && normalize(issue.series) == 'DYLAN DOG') score += 0.18;
      final title = normalize(issue.title);
      if (title.isNotEmpty && normalized.contains(title)) {
        score += 0.45;
      } else {
        final words = title
            .split(' ')
            .where((word) => word.length >= 4)
            .toSet();
        if (words.isNotEmpty) {
          final matched = words.where(normalized.contains).length;
          score += 0.3 * matched / words.length;
        }
      }
      if (score > 0.16) candidates.add((issue: issue, score: score));
    }
    candidates.sort((a, b) => b.score.compareTo(a.score));
    return candidates.take(limit).map((entry) => entry.issue).toList();
  }

  List<CoverMatch> matchVisual({
    required String visualHash,
    required Uint8List colorSignature,
    int limit = 3,
  }) {
    final queryHash = BigInt.parse(visualHash, radix: 16);
    final matches = <CoverMatch>[];
    for (final issue in _issues) {
      if (issue.visualHash == null || issue.colorSignature == null) continue;
      final hash = BigInt.parse(issue.visualHash!, radix: 16);
      final hamming = _bitCount(queryHash ^ hash);
      final color = _colorDistance(colorSignature, issue.colorSignature!);
      final score = (1 - hamming / 64) * 0.72 + (1 - color) * 0.28;
      matches.add(
        CoverMatch(issue: issue, score: score.clamp(0, 1).toDouble()),
      );
    }
    matches.sort((a, b) => b.score.compareTo(a.score));
    return matches.take(limit).toList(growable: false);
  }

  static String normalize(String value) => value
      .toUpperCase()
      .replaceAll('Č', 'C')
      .replaceAll('Ć', 'C')
      .replaceAll('Đ', 'D')
      .replaceAll('Š', 'S')
      .replaceAll('Ž', 'Z')
      .replaceAll(RegExp(r'[^A-Z0-9]+'), ' ')
      .trim();

  static int _bitCount(BigInt value) {
    var count = 0;
    var remaining = value;
    while (remaining != BigInt.zero) {
      remaining &= remaining - BigInt.one;
      count++;
    }
    return count;
  }

  static double _colorDistance(Uint8List left, Uint8List right) {
    final length = left.length < right.length ? left.length : right.length;
    if (length == 0) return 1;
    var total = 0.0;
    for (var i = 0; i < length; i++) {
      total += (left[i] - right[i]).abs() / 255;
    }
    return (total / length).clamp(0, 1).toDouble();
  }
}
