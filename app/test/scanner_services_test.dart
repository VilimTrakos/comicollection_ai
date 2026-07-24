import 'dart:typed_data';

import 'package:comicollect/data/catalog_repository.dart';
import 'package:comicollect/models/catalog_issue.dart';
import 'package:comicollect/services/cover_recognition_service.dart';
import 'package:comicollect/services/image_signature.dart';
import 'package:comicollect/services/shelf_recognition_service.dart';
import 'package:comicollect/features/scanner/smart_scanner_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_support.dart';

void main() {
  group('SmartScannerController', () {
    test('coordinates capture and unknown-barcode state', () {
      final controller = SmartScannerController();
      addTearDown(controller.dispose);

      expect(controller.beginCapture('Obrađujem…'), isTrue);
      expect(controller.capturing, isTrue);
      expect(controller.message, 'Obrađujem…');
      expect(controller.beginCapture('Ponovno'), isFalse);

      controller.endCapture();
      controller.reportUnknownBarcode(' 123456 ');
      expect(controller.capturing, isFalse);
      expect(controller.pendingBarcode, '123456');
      expect(controller.message, contains('123456'));

      controller.clearPendingBarcode();
      expect(controller.pendingBarcode, isNull);
    });

    test('deduplicates accepted and merged issues and clears flash', () async {
      final controller = SmartScannerController(flashDuration: Duration.zero);
      addTearDown(controller.dispose);
      final first = testIssue(1, title: 'Morgana');
      final second = testIssue(2, title: 'Demoni');

      expect(controller.accept(first, 'Naslovnica prepoznata'), isTrue);
      expect(controller.flash, isTrue);
      expect(controller.scanned, [first]);
      expect(controller.accept(first, 'Ponovno'), isFalse);
      expect(controller.message, 'Morgana je već u popisu');
      expect(controller.merge([first, second, second]), 1);
      expect(controller.scanned, [first, second]);

      await Future<void>.delayed(Duration.zero);
      expect(controller.flash, isFalse);
    });

    test('new session discards every unsaved recognition result', () {
      final controller = SmartScannerController();
      addTearDown(controller.dispose);
      final issue = testIssue(5, title: 'Kuća sjećanja');

      controller.accept(issue, 'Naslovnica prepoznata');
      controller.reportUnknownBarcode('123456');
      controller.setOldBoyNeedsSelection(true);

      controller.startNewSession();

      expect(controller.scanned, isEmpty);
      expect(controller.pendingBarcode, isNull);
      expect(controller.oldBoyNeedsSelection, isFalse);
      expect(controller.flash, isFalse);
      expect(controller.capturing, isFalse);
      expect(controller.message, 'Uperi u barkod ili jednu naslovnicu');
      expect(controller.accept(issue, 'Naslovnica prepoznata'), isTrue);
    });
  });

  group('CoverFrameTracker', () {
    test('requires stable confident frames and locks an accepted cover', () {
      final issue = testIssue(7);
      final match = CoverMatch(issue: issue, score: .9);
      final signature = _signature('0000000000000000');
      final tracker = CoverFrameTracker();

      expect(
        tracker.evaluate(signature, [match]).status,
        CoverFrameStatus.holdSteady,
      );
      expect(
        tracker.evaluate(signature, [match]).status,
        CoverFrameStatus.candidate,
      );
      final accepted = tracker.evaluate(signature, [match]);
      expect(accepted.status, CoverFrameStatus.accepted);
      expect(accepted.issue, issue);
      expect(
        tracker.evaluate(signature, [match]).status,
        CoverFrameStatus.moveToNext,
      );

      expect(
        tracker.evaluate(_signature('ffffffffffffffff'), [match]).status,
        CoverFrameStatus.holdSteady,
      );
    });

    test('rejects ambiguous matches and resets its candidate', () {
      final first = testIssue(1);
      final second = testIssue(2);
      final signature = _signature('1234567890abcdef');
      final tracker = CoverFrameTracker();
      final ambiguous = [
        CoverMatch(issue: first, score: .75),
        CoverMatch(issue: second, score: .74),
      ];

      expect(
        tracker.evaluate(signature, ambiguous).status,
        CoverFrameStatus.holdSteady,
      );
      expect(
        tracker.evaluate(signature, ambiguous).status,
        CoverFrameStatus.holdSteady,
      );
    });
  });

  group('CoverRecognitionService', () {
    test('uses an injected signature reader and confidence rules', () async {
      final first = testIssue(1);
      final second = testIssue(2);
      final catalog = _MatchCatalog();
      var requestedPath = '';
      final service = CoverRecognitionService(
        catalog: catalog,
        signatureReader: (path) async {
          requestedPath = path;
          return _signature('0123456789abcdef');
        },
      );

      catalog.matches = [CoverMatch(issue: first, score: .83)];
      expect(await service.recognizeFile('/fake/cover.jpg'), first);
      expect(requestedPath, '/fake/cover.jpg');

      catalog.matches = [
        CoverMatch(issue: first, score: .75),
        CoverMatch(issue: second, score: .74),
      ];
      expect(await service.recognizeFile('/fake/ambiguous.jpg'), isNull);
    });

    test('returns null when an injected reader cannot decode the image', () {
      final service = CoverRecognitionService(
        catalog: _MatchCatalog(),
        signatureReader: (_) async => null,
      );

      expect(service.recognizeFile('/fake/not-an-image'), completion(isNull));
    });
  });

  group('ShelfRecognitionService', () {
    test(
      'matches combined OCR lines and removes every temporary image',
      () async {
        final regular = testIssue(5, title: 'Kuća sjećanja');
        final catalog = _IssueCatalog([regular]);
        final recognizer = _FakeShelfTextRecognizer({
          'original.jpg': ['OLD BOY'],
          'rotated-90.jpg': ['KUCA SJECANJA'],
          'rotated-270.jpg': ['KUCA SJECANJA'],
        });
        final deleted = <String>[];
        final service = ShelfRecognitionService(
          catalog: catalog,
          textRecognizer: recognizer,
          preprocessor: (_) async => const ShelfImageBatch(
            candidatePaths: [
              'original.jpg',
              'rotated-90.jpg',
              'rotated-270.jpg',
            ],
            temporaryPaths: ['rotated-90.jpg', 'rotated-270.jpg'],
          ),
          temporaryPathDeleter: (path) async => deleted.add(path),
        );
        addTearDown(service.close);

        final result = await service.recognizeFile('original.jpg');

        expect(result.issues, [regular]);
        expect(result.oldBoyNeedsSelection, isTrue);
        expect(recognizer.requestedPaths, [
          'original.jpg',
          'rotated-90.jpg',
          'rotated-270.jpg',
        ]);
        expect(deleted, containsAll(['rotated-90.jpg', 'rotated-270.jpg']));
      },
    );

    test('still removes temporary images when OCR fails', () async {
      final recognizer = _FakeShelfTextRecognizer(
        const {},
        failure: StateError('OCR failed'),
      );
      final deleted = <String>[];
      final service = ShelfRecognitionService(
        catalog: _IssueCatalog(const []),
        textRecognizer: recognizer,
        preprocessor: (_) async => const ShelfImageBatch(
          candidatePaths: ['original.jpg'],
          temporaryPaths: ['temporary-a.jpg', 'temporary-b.jpg'],
        ),
        temporaryPathDeleter: (path) async => deleted.add(path),
      );
      addTearDown(service.close);

      await expectLater(
        service.recognizeFile('original.jpg'),
        throwsA(isA<StateError>()),
      );
      expect(deleted, containsAll(['temporary-a.jpg', 'temporary-b.jpg']));
    });
  });
}

FrameSignature _signature(String hash) => FrameSignature(
  visualHash: hash,
  colorSignature: Uint8List.fromList(List<int>.filled(48, 128)),
);

class _MatchCatalog extends CatalogRepository {
  List<CoverMatch> matches = const [];

  @override
  List<CoverMatch> matchVisual({
    required String visualHash,
    required Uint8List colorSignature,
    int limit = 3,
  }) => matches;
}

class _IssueCatalog extends CatalogRepository {
  _IssueCatalog(this.catalogIssues);

  final List<CatalogIssue> catalogIssues;

  @override
  List<CatalogIssue> get issues => catalogIssues;
}

class _FakeShelfTextRecognizer implements ShelfTextRecognizer {
  _FakeShelfTextRecognizer(this.linesByPath, {this.failure});

  final Map<String, List<String>> linesByPath;
  final Object? failure;
  final List<String> requestedPaths = [];
  bool closed = false;

  @override
  Future<Iterable<String>> recognizeLines(String path) async {
    requestedPaths.add(path);
    if (failure case final error?) throw error;
    return linesByPath[path] ?? const [];
  }

  @override
  Future<void> close() async => closed = true;
}
