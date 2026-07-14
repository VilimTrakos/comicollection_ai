import '../data/catalog_repository.dart';
import '../models/catalog_issue.dart';

/// Converts noisy OCR lines from comic spines into deterministic catalogue
/// matches. Kept independent from ML Kit so the recognition rules can be
/// verified without a camera or device plugin.
class ShelfTextMatcher {
  const ShelfTextMatcher._();

  static List<CatalogIssue> matchLines(
    Iterable<String> lines,
    Iterable<CatalogIssue> issues,
  ) {
    final catalogue = issues.toList(growable: false);
    final found = <String, CatalogIssue>{};
    for (final line in lines) {
      final normalized = CatalogRepository.normalize(line);
      final hasSeries = normalized.contains('DYLAN DOG');
      if (hasSeries) {
        for (final match in RegExp(
          r'(?<!\d)(\d{1,3})(?!\d)',
        ).allMatches(normalized)) {
          final number = int.parse(match.group(1)!);
          final candidates = catalogue
              .where(
                (issue) =>
                    issue.series == 'Dylan Dog' && issue.number == number,
              )
              .toList();
          if (candidates.length == 1) {
            found[candidates.first.id] = candidates.first;
          } else if (candidates.isNotEmpty) {
            final special = normalized.contains('SPECIJAL');
            final maxi =
                normalized.contains('MAXI') || normalized.contains('OLD BOY');
            final selected = candidates.firstWhere(
              (issue) => maxi
                  ? issue.edition.contains('Maxi')
                  : issue.edition.contains('Specijal') == special &&
                        !issue.edition.contains('Maxi'),
              orElse: () => candidates.first,
            );
            found[selected.id] = selected;
          }
        }
      }
      for (final issue in catalogue) {
        final title = CatalogRepository.normalize(issue.title);
        if (title.length >= 5 &&
            (normalized.contains(title) ||
                containsFuzzyTitle(normalized, title))) {
          found[issue.id] = issue;
        }
      }
    }
    final result = found.values.toList()
      ..sort((a, b) {
        final edition = a.edition.compareTo(b.edition);
        return edition != 0 ? edition : a.number.compareTo(b.number);
      });
    return result;
  }

  static bool containsFuzzyTitle(String text, String title) {
    final textWords = text
        .split(' ')
        .where((word) => word.length >= 4)
        .toList();
    final titleWords = title
        .split(' ')
        .where((word) => word.length >= 4)
        .toList();
    if (textWords.isEmpty || titleWords.isEmpty) return false;
    var matched = 0;
    for (final expected in titleWords) {
      if (textWords.any((actual) => wordsAreClose(expected, actual))) {
        matched++;
      }
    }
    if (titleWords.length == 1) return matched == 1;
    return matched >= 2 && matched / titleWords.length >= .6;
  }

  static bool wordsAreClose(String expected, String actual) {
    if (expected == actual) return true;
    final allowed = expected.length >= 9 ? 2 : 1;
    if ((expected.length - actual.length).abs() > allowed) return false;
    return editDistance(expected, actual) <= allowed;
  }

  static int editDistance(String left, String right) {
    var previous = List<int>.generate(right.length + 1, (index) => index);
    for (var i = 0; i < left.length; i++) {
      final current = <int>[i + 1];
      for (var j = 0; j < right.length; j++) {
        current.add(
          [
            current[j] + 1,
            previous[j + 1] + 1,
            previous[j] + (left.codeUnitAt(i) == right.codeUnitAt(j) ? 0 : 1),
          ].reduce((a, b) => a < b ? a : b),
        );
      }
      previous = current;
    }
    return previous.last;
  }
}
