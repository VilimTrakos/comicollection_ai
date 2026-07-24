import 'package:comicollect/features/scanner/smart_scanner_controller.dart';
import 'package:comicollect/screens/smart_scanner_page.dart';
import 'package:comicollect/services/shelf_text_matcher.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ShelfTextMatcher', () {
    final regular = testIssue(5, id: 'regular-5', title: 'Kuća sjećanja');
    final special = testIssue(
      5,
      id: 'special-5',
      sourceEdition: 'DSLU',
      edition: 'Specijal (L)',
      title: 'Demonova utvrda',
    );
    final maxi = testIssue(
      5,
      id: 'maxi-5',
      sourceEdition: 'DMLU',
      edition: 'Maxi (L)',
      title: 'Projekt Hicks',
    );
    final catalogue = [regular, special, maxi];

    test('requires the series name before treating OCR numbers as issues', () {
      expect(ShelfTextMatcher.matchLines(['broj 5'], catalogue), isEmpty);
      expect(
        ShelfTextMatcher.matchLines(['DYLAN DOG 5'], catalogue).single,
        regular,
      );
    });

    test('uses spine keywords to disambiguate special and Maxi editions', () {
      expect(ShelfTextMatcher.matchLines(['Dylan Dog specijal 5'], catalogue), [
        special,
      ]);
      expect(ShelfTextMatcher.matchLines(['Dylan Dog MAXI 5'], catalogue), [
        maxi,
      ]);
      expect(ShelfTextMatcher.matchLines(['Dylan Dog Old Boy 5'], catalogue), [
        maxi,
      ]);
    });

    test('matches exact and noisy titles even when a number is unreadable', () {
      expect(ShelfTextMatcher.matchLines(['KUCA SJECANJA'], catalogue), [
        regular,
      ]);
      expect(ShelfTextMatcher.matchLines(['DEMONOV UTVRDA'], catalogue), [
        special,
      ]);
      expect(ShelfTextMatcher.matchLines(['PROJEKT HICKX'], catalogue), [maxi]);
    });

    test('deduplicates repeated OCR lines and sorts by edition and number', () {
      final other = testIssue(2, id: 'regular-2', title: 'Morgana');
      final result = ShelfTextMatcher.matchLines(
        ['Dylan Dog 5', 'KUĆA SJEĆANJA', 'MORGANA', 'MORGANA'],
        [...catalogue, other],
      );
      expect(result.map((issue) => issue.id), ['regular-2', 'regular-5']);
    });

    test('fuzzy helpers enforce OCR tolerance without accepting noise', () {
      expect(ShelfTextMatcher.containsFuzzyTitle('', 'MORGANA'), isFalse);
      expect(ShelfTextMatcher.containsFuzzyTitle('MORGANB', 'MORGANA'), isTrue);
      expect(
        ShelfTextMatcher.containsFuzzyTitle('PROJEKT', 'PROJEKT HICKS'),
        isFalse,
      );
      expect(ShelfTextMatcher.wordsAreClose('MORGANA', 'MORGANB'), isTrue);
      expect(
        ShelfTextMatcher.wordsAreClose('PREPOZNAVANJE', 'PREPOZNAVNJE'),
        isTrue,
      );
      expect(ShelfTextMatcher.wordsAreClose('MORGANA', 'MOR'), isFalse);
      expect(ShelfTextMatcher.editDistance('STRIP', 'STRIP'), 0);
      expect(ShelfTextMatcher.editDistance('STRIP', 'SKRIP'), 1);
      expect(ShelfTextMatcher.editDistance('', 'ABC'), 3);
    });

    test('ignores titles too short to be safe OCR identifiers', () {
      final short = testIssue(9, id: 'short', title: 'Rat');
      expect(ShelfTextMatcher.matchLines(['RAT'], [short]), isEmpty);
    });
  });

  testWidgets('scanner remains usable when camera plugins are unavailable', (
    tester,
  ) async {
    final controller = RecordingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _app(
        SmartScannerPage(
          controller: controller,
          cameraLoader: () async => const [],
          pickGalleryImage: () async => null,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('PAMETNO SKENIRANJE'), findsOneWidget);
    expect(find.text('FOTOGRAFIRAJ POLICU'), findsOneWidget);
    expect(find.text('UČITAJ IZ GALERIJE'), findsOneWidget);
    expect(find.textContaining('Kamera se ne može otvoriti:'), findsOneWidget);

    await tester.tap(find.text('UČITAJ IZ GALERIJE'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Odabir slike je otkazan'), findsOneWidget);
  });

  testWidgets('leaving review discards the unsaved scanning session', (
    tester,
  ) async {
    final controller = RecordingController();
    final scanner = SmartScannerController(flashDuration: Duration.zero);
    addTearDown(controller.dispose);
    addTearDown(scanner.dispose);
    final issue = testIssue(5, title: 'Kuća sjećanja');

    await tester.pumpWidget(
      _app(
        SmartScannerPage(
          controller: controller,
          scannerController: scanner,
          cameraLoader: () async => const [],
        ),
      ),
    );
    scanner.accept(issue, 'Naslovnica prepoznata');
    await tester.pump();

    expect(find.text('1 strip u popisu'), findsOneWidget);
    await tester.tap(find.text('PREGLEDAJ'));
    await tester.pumpAndSettle();
    expect(find.text('PRONAĐENO 1'), findsOneWidget);

    await tester.pageBack();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(scanner.scanned, isEmpty);
    expect(find.text('1 strip u popisu'), findsNothing);
    expect(scanner.merge([issue]), 1);
    expect(scanner.scanned, [issue]);
  });

  testWidgets('scan review excludes issues and records owned status', (
    tester,
  ) async {
    final controller = RecordingController();
    addTearDown(controller.dispose);
    final issues = [testIssue(1), testIssue(2)];
    await tester.pumpWidget(
      _app(ScanReviewPage(controller: controller, issues: issues)),
    );

    final first = _issueCard(1);
    final second = _issueCard(2);
    await tester.tap(
      find.descendant(of: first, matching: find.byType(Checkbox)),
    );
    await tester.tap(find.descendant(of: second, matching: find.text('NEMAM')));
    await tester.pump();
    await tester.tap(find.text('SPREMI ODABRANO'));
    await tester.pump();

    expect(controller.scanBatches, hasLength(1));
    expect(controller.scanBatches.single, {issues[1]: false});
  });

  testWidgets('scan review can reset every result to owned', (tester) async {
    final controller = RecordingController();
    addTearDown(controller.dispose);
    final issues = [testIssue(1), testIssue(2)];
    await tester.pumpWidget(
      _app(ScanReviewPage(controller: controller, issues: issues)),
    );

    await tester.tap(
      find.descendant(of: _issueCard(1), matching: find.byType(Checkbox)),
    );
    await tester.tap(
      find.descendant(of: _issueCard(2), matching: find.text('NEMAM')),
    );
    await tester.tap(find.text('SVE IMAM'));
    await tester.pump();
    await tester.tap(find.text('SPREMI ODABRANO'));
    await tester.pump();

    expect(controller.scanBatches.single, {issues[0]: true, issues[1]: true});
  });

  testWidgets('scan review refuses to save an empty selection', (tester) async {
    final controller = RecordingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _app(
        ScanReviewPage(
          controller: controller,
          issues: [testIssue(1), testIssue(2)],
        ),
      ),
    );

    for (final checkbox in find.byType(Checkbox).evaluate().toList()) {
      await tester.tap(find.byWidget(checkbox.widget));
    }
    await tester.pump();
    await tester.tap(find.text('SPREMI ODABRANO'));
    await tester.pump();
    expect(controller.scanBatches, isEmpty);
  });
}

Finder _issueCard(int number) => find.ancestor(
  of: find.text('Dylan Dog #$number'),
  matching: find.byType(Card),
);

MaterialApp _app(Widget home) =>
    MaterialApp(theme: ThemeData.dark(useMaterial3: true), home: home);
