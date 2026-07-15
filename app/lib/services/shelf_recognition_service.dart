import 'dart:io';
import 'dart:isolate';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image/image.dart' as img;

import '../data/catalog_repository.dart';
import '../models/catalog_issue.dart';
import 'shelf_text_matcher.dart';

class ShelfImageBatch {
  const ShelfImageBatch({
    required this.candidatePaths,
    this.temporaryPaths = const [],
  });

  final List<String> candidatePaths;
  final List<String> temporaryPaths;
}

class ShelfRecognitionResult {
  const ShelfRecognitionResult({
    required this.issues,
    required this.oldBoyNeedsSelection,
  });

  final List<CatalogIssue> issues;
  final bool oldBoyNeedsSelection;
}

abstract interface class ShelfTextRecognizer {
  Future<Iterable<String>> recognizeLines(String path);
  Future<void> close();
}

class MlKitShelfTextRecognizer implements ShelfTextRecognizer {
  MlKitShelfTextRecognizer({TextRecognizer? recognizer})
    : _recognizer =
          recognizer ?? TextRecognizer(script: TextRecognitionScript.latin);

  final TextRecognizer _recognizer;

  @override
  Future<Iterable<String>> recognizeLines(String path) async {
    final text = await _recognizer.processImage(InputImage.fromFilePath(path));
    final lines = <String>[];
    for (final block in text.blocks) {
      final blockText = block.text.trim();
      if (blockText.isNotEmpty) lines.add(blockText);
      for (final line in block.lines) {
        final lineText = line.text.trim();
        if (lineText.isNotEmpty) lines.add(lineText);
      }
    }
    return lines;
  }

  @override
  Future<void> close() => _recognizer.close();
}

typedef ShelfImagePreprocessor = Future<ShelfImageBatch> Function(String path);
typedef TemporaryPathDeleter = Future<void> Function(String path);

/// Coordinates shelf preprocessing, OCR, matching, and temporary-file cleanup.
class ShelfRecognitionService {
  ShelfRecognitionService({
    required this.catalog,
    ShelfTextRecognizer? textRecognizer,
    this.preprocessor = preprocessShelfImageInBackground,
    this.temporaryPathDeleter = deleteTemporaryPath,
  }) : _textRecognizer = textRecognizer ?? MlKitShelfTextRecognizer();

  final CatalogRepository catalog;
  final ShelfTextRecognizer _textRecognizer;
  final ShelfImagePreprocessor preprocessor;
  final TemporaryPathDeleter temporaryPathDeleter;

  Future<ShelfRecognitionResult> recognizeFile(String path) async {
    final batch = await preprocessor(path);
    try {
      final lines = <String>{};
      for (final candidatePath in batch.candidatePaths) {
        lines.addAll(await _textRecognizer.recognizeLines(candidatePath));
      }
      final issues = ShelfTextMatcher.matchLines(lines, catalog.issues);
      final hasOldBoy = lines.any(
        (line) => CatalogRepository.normalize(line).contains('OLD BOY'),
      );
      return ShelfRecognitionResult(
        issues: issues,
        oldBoyNeedsSelection:
            hasOldBoy && !issues.any((issue) => issue.sourceEdition == 'DMLU'),
      );
    } finally {
      await Future.wait(
        batch.temporaryPaths.map(temporaryPathDeleter),
        eagerError: false,
      );
    }
  }

  Future<void> close() => _textRecognizer.close();
}

/// Decodes, orients, rotates, and JPEG-encodes shelf candidates away from the
/// Flutter UI isolate.
Future<ShelfImageBatch> preprocessShelfImageInBackground(String path) =>
    Isolate.run(() => _preprocessShelfImage(path));

Future<ShelfImageBatch> _preprocessShelfImage(String path) async {
  final temporaryPaths = <String>[];
  try {
    final decoded = img.decodeImage(await File(path).readAsBytes());
    if (decoded == null) {
      return ShelfImageBatch(candidatePaths: [path]);
    }
    final oriented = img.bakeOrientation(decoded);
    final unique = DateTime.now().microsecondsSinceEpoch;
    for (final angle in const [90.0, 270.0]) {
      final rotated = img.copyRotate(oriented, angle: angle);
      final outputPath =
          '${Directory.systemTemp.path}/comicollect-shelf-$unique-${angle.toInt()}.jpg';
      await File(
        outputPath,
      ).writeAsBytes(img.encodeJpg(rotated, quality: 88), flush: true);
      temporaryPaths.add(outputPath);
    }
    return ShelfImageBatch(
      candidatePaths: [path, ...temporaryPaths],
      temporaryPaths: temporaryPaths,
    );
  } on Object {
    await Future.wait(temporaryPaths.map(deleteTemporaryPath));
    rethrow;
  }
}

Future<void> deleteTemporaryPath(String path) async {
  try {
    await File(path).delete();
  } on FileSystemException {
    // Cache cleanup is best effort and must never break recognition.
  }
}
