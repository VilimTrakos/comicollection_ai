import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';

import '../../models/catalog_issue.dart';

/// Owns the camera-independent state of a smart-scanning session.
///
/// Keeping this state outside the widget makes duplicate handling, transient
/// feedback, and capture coordination deterministic and independently
/// testable.
class SmartScannerController extends ChangeNotifier {
  SmartScannerController({
    this.flashDuration = const Duration(milliseconds: 450),
    String initialMessage = 'Uperi u barkod ili jednu naslovnicu',
  }) : _message = initialMessage;

  final Duration flashDuration;
  final List<CatalogIssue> _scanned = [];
  late final UnmodifiableListView<CatalogIssue> _scannedView =
      UnmodifiableListView(_scanned);

  Timer? _flashTimer;
  String _message;
  String? _lastUnknownBarcode;
  String? _pendingBarcode;
  bool _capturing = false;
  bool _flash = false;
  bool _oldBoyNeedsSelection = false;
  bool _disposed = false;

  String get message => _message;
  String? get pendingBarcode => _pendingBarcode;
  bool get capturing => _capturing;
  bool get flash => _flash;
  bool get oldBoyNeedsSelection => _oldBoyNeedsSelection;
  List<CatalogIssue> get scanned => _scannedView;

  void setMessage(String value) {
    if (_message == value) return;
    _message = value;
    notifyListeners();
  }

  bool beginCapture(String message) {
    if (_capturing) return false;
    _capturing = true;
    _message = message;
    notifyListeners();
    return true;
  }

  void endCapture() {
    if (!_capturing) return;
    _capturing = false;
    notifyListeners();
  }

  void reportUnknownBarcode(String barcode) {
    final normalized = barcode.trim();
    if (normalized.isEmpty || _lastUnknownBarcode == normalized) return;
    _lastUnknownBarcode = normalized;
    _pendingBarcode = normalized;
    _message = 'Barkod $normalized nije povezan s lokalnim katalogom';
    notifyListeners();
  }

  void clearPendingBarcode() {
    if (_pendingBarcode == null) return;
    _pendingBarcode = null;
    notifyListeners();
  }

  void setOldBoyNeedsSelection(bool value) {
    if (_oldBoyNeedsSelection == value) return;
    _oldBoyNeedsSelection = value;
    notifyListeners();
  }

  /// Adds [issue] to the session and returns whether it was newly accepted.
  bool accept(CatalogIssue issue, String source) {
    if (_scanned.any((item) => item.id == issue.id)) {
      _message = '${issue.title} je već u popisu';
      notifyListeners();
      return false;
    }
    _scanned.add(issue);
    _message = '$source · ${issue.series} #${issue.number}';
    _flash = true;
    _flashTimer?.cancel();
    _flashTimer = Timer(flashDuration, _clearFlash);
    notifyListeners();
    return true;
  }

  /// Adds unique recognition results without changing the current message.
  int merge(Iterable<CatalogIssue> issues) {
    var added = 0;
    for (final issue in issues) {
      if (_scanned.any((item) => item.id == issue.id)) continue;
      _scanned.add(issue);
      added++;
    }
    if (added > 0) notifyListeners();
    return added;
  }

  void _clearFlash() {
    if (_disposed || !_flash) return;
    _flash = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _flashTimer?.cancel();
    super.dispose();
  }
}
