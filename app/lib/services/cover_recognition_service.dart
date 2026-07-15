import 'dart:io';
import 'dart:isolate';

import 'package:image/image.dart' as img;

import '../data/catalog_repository.dart';
import '../models/catalog_issue.dart';
import 'image_signature.dart';

typedef CoverSignatureReader = Future<FrameSignature?> Function(String path);

enum CoverFrameStatus { noMatch, holdSteady, candidate, accepted, moveToNext }

class CoverFrameDecision {
  const CoverFrameDecision(this.status, {this.issue});

  final CoverFrameStatus status;
  final CatalogIssue? issue;
}

/// Tracks confidence and stability across camera frames.
///
/// This class deliberately knows nothing about cameras or widgets. The caller
/// supplies signatures and catalogue matches, so the same rules are easy to
/// exercise in unit tests.
class CoverFrameTracker {
  CoverFrameTracker({
    this.minimumScore = .70,
    this.minimumMargin = .018,
    this.strongScore = .82,
    this.stableDistance = 11,
    this.lockedDistance = 15,
    this.requiredStableFrames = 2,
  });

  final double minimumScore;
  final double minimumMargin;
  final double strongScore;
  final int stableDistance;
  final int lockedDistance;
  final int requiredStableFrames;

  FrameSignature? _lastSignature;
  FrameSignature? _lockedSignature;
  String? _stableCandidate;
  int _stableFrames = 0;

  CoverFrameDecision evaluate(
    FrameSignature signature,
    List<CoverMatch> matches,
  ) {
    final previous = _lastSignature;
    _lastSignature = signature;

    final locked = _lockedSignature;
    if (locked != null) {
      if (signature.distanceTo(locked) < lockedDistance) {
        return const CoverFrameDecision(CoverFrameStatus.moveToNext);
      }
      _lockedSignature = null;
    }

    if (matches.isEmpty) {
      return const CoverFrameDecision(CoverFrameStatus.noMatch);
    }
    final best = matches.first;
    final margin = matches.length < 2 ? 1.0 : best.score - matches[1].score;
    final frameStable =
        previous != null && signature.distanceTo(previous) < stableDistance;
    final confident =
        best.score >= minimumScore &&
        (margin >= minimumMargin || best.score >= strongScore);
    if (!frameStable || !confident) {
      _stableCandidate = null;
      _stableFrames = 0;
      return const CoverFrameDecision(CoverFrameStatus.holdSteady);
    }

    if (_stableCandidate == best.issue.id) {
      _stableFrames++;
    } else {
      _stableCandidate = best.issue.id;
      _stableFrames = 1;
    }
    if (_stableFrames < requiredStableFrames) {
      return CoverFrameDecision(CoverFrameStatus.candidate, issue: best.issue);
    }

    _lockedSignature = signature;
    _stableFrames = 0;
    return CoverFrameDecision(CoverFrameStatus.accepted, issue: best.issue);
  }

  void reset() {
    _lastSignature = null;
    _lockedSignature = null;
    _stableCandidate = null;
    _stableFrames = 0;
  }
}

/// Recognizes a single cover from an image file.
///
/// Decoding and signature generation use a background isolate by default;
/// only matching the compact signature against the in-memory catalogue stays
/// on the caller isolate.
class CoverRecognitionService {
  CoverRecognitionService({
    required this.catalog,
    this.signatureReader = readCoverSignatureInBackground,
    this.minimumScore = .70,
    this.minimumMargin = .018,
    this.strongScore = .82,
  });

  final CatalogRepository catalog;
  final CoverSignatureReader signatureReader;
  final double minimumScore;
  final double minimumMargin;
  final double strongScore;

  Future<CatalogIssue?> recognizeFile(String path) async {
    final signature = await signatureReader(path);
    if (signature == null) return null;
    final matches = catalog.matchVisual(
      visualHash: signature.visualHash,
      colorSignature: signature.colorSignature,
    );
    return selectConfidentMatch(matches);
  }

  CatalogIssue? selectConfidentMatch(List<CoverMatch> matches) {
    if (matches.isEmpty) return null;
    final best = matches.first;
    final margin = matches.length < 2 ? 1.0 : best.score - matches[1].score;
    return best.score >= minimumScore &&
            (margin >= minimumMargin || best.score >= strongScore)
        ? best.issue
        : null;
  }
}

Future<FrameSignature?> readCoverSignatureInBackground(String path) =>
    Isolate.run(() => _readCoverSignature(path));

Future<FrameSignature?> _readCoverSignature(String path) async {
  final decoded = img.decodeImage(await File(path).readAsBytes());
  return decoded == null ? null : ImageSignatureExtractor.fromImage(decoded);
}
