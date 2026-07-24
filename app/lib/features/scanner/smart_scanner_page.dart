import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_commons/google_mlkit_commons.dart';
import 'package:image_picker/image_picker.dart';

import '../../app_controller.dart';
import '../../models/catalog_issue.dart';
import '../../services/barcode_recognition_service.dart';
import '../../services/cover_recognition_service.dart';
import '../../services/shelf_recognition_service.dart';
import '../../services/visual_signature.dart';
import 'catalog_issue_picker.dart';
import 'scan_review_page.dart';
import 'smart_scanner_controller.dart';
import 'smart_scanner_view.dart';

class SmartScannerPage extends StatefulWidget {
  const SmartScannerPage({
    super.key,
    required this.controller,
    this.cameraLoader = availableCameras,
    this.pickGalleryImage,
    this.imagePicker,
    this.scannerController,
    this.barcodeRecognitionService,
    this.coverRecognitionService,
    this.shelfRecognitionService,
  });

  final AppController controller;
  final Future<List<CameraDescription>> Function() cameraLoader;
  final Future<XFile?> Function()? pickGalleryImage;
  final ImagePicker? imagePicker;
  final SmartScannerController? scannerController;
  final BarcodeRecognitionService? barcodeRecognitionService;
  final CoverRecognitionService? coverRecognitionService;
  final ShelfRecognitionService? shelfRecognitionService;

  @override
  State<SmartScannerPage> createState() => _SmartScannerPageState();
}

class _SmartScannerPageState extends State<SmartScannerPage>
    with WidgetsBindingObserver {
  late final SmartScannerController _scanner;
  late final BarcodeRecognitionService _barcodeRecognition;
  late final CoverRecognitionService _coverRecognition;
  late final ShelfRecognitionService _shelfRecognition;
  late final ImagePicker _imagePicker;
  late final bool _ownsScanner;
  late final bool _ownsBarcodeRecognition;
  late final bool _ownsShelfRecognition;
  final CoverFrameTracker _coverTracker = CoverFrameTracker();

  CameraController? _camera;
  CameraDescription? _description;
  DateTime _lastAnalysis = DateTime.fromMillisecondsSinceEpoch(0);
  bool _analyzing = false;

  @override
  void initState() {
    super.initState();
    _ownsScanner = widget.scannerController == null;
    _scanner = widget.scannerController ?? SmartScannerController();
    _scanner.startNewSession();
    _ownsBarcodeRecognition = widget.barcodeRecognitionService == null;
    _barcodeRecognition =
        widget.barcodeRecognitionService ?? MlKitBarcodeRecognitionService();
    _coverRecognition =
        widget.coverRecognitionService ??
        CoverRecognitionService(catalog: widget.controller.catalog);
    _ownsShelfRecognition = widget.shelfRecognitionService == null;
    _shelfRecognition =
        widget.shelfRecognitionService ??
        ShelfRecognitionService(catalog: widget.controller.catalog);
    _imagePicker = widget.imagePicker ?? ImagePicker();
    _scanner.addListener(_onScannerStateChanged);
    WidgetsBinding.instance.addObserver(this);
    unawaited(_initializeCamera());
    unawaited(_restoreLostGalleryImage());
  }

  void _onScannerStateChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _restoreLostGalleryImage() async {
    try {
      final response = await _imagePicker.retrieveLostData();
      final file = response.files?.firstOrNull;
      if (file != null) await _processGalleryImage(file);
    } on Object {
      // Ako Android nije sačuvao odabir, skener normalno nastavlja raditi.
    }
  }

  Future<void> _initializeCamera([CameraDescription? preferred]) async {
    try {
      final cameras = await widget.cameraLoader();
      if (cameras.isEmpty) throw StateError('Kamera nije pronađena.');
      final description =
          preferred ??
          cameras.firstWhere(
            (camera) => camera.lensDirection == CameraLensDirection.back,
            orElse: () => cameras.first,
          );
      final controller = CameraController(
        description,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.nv21,
      );
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      _description = description;
      _camera = controller;
      setState(() {});
      await controller.startImageStream(_onFrame);
    } on CameraException catch (error) {
      if (!mounted) return;
      _scanner.setMessage(
        error.code == 'CameraAccessDenied'
            ? 'Dopusti pristup kameri u postavkama uređaja.'
            : 'Kamera se ne može otvoriti: ${error.description ?? error.code}',
      );
    } on Object catch (error) {
      if (!mounted) return;
      _scanner.setMessage('Kamera se ne može otvoriti: $error');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final camera = _camera;
    if (camera == null || !camera.value.isInitialized) return;
    if (state == AppLifecycleState.inactive) {
      _camera = null;
      _coverTracker.reset();
      unawaited(camera.dispose());
    } else if (state == AppLifecycleState.resumed && _description != null) {
      unawaited(_initializeCamera(_description));
    }
  }

  void _onFrame(CameraImage image) {
    final now = DateTime.now();
    if (_analyzing ||
        _scanner.capturing ||
        now.difference(_lastAnalysis) < const Duration(milliseconds: 420)) {
      return;
    }
    _lastAnalysis = now;
    _analyzing = true;
    unawaited(_analyzeFrame(image).whenComplete(() => _analyzing = false));
  }

  Future<void> _analyzeFrame(CameraImage image) async {
    final description = _description;
    if (description == null || image.planes.length != 1) return;
    try {
      final rotation =
          InputImageRotationValue.fromRawValue(description.sensorOrientation) ??
          InputImageRotation.rotation0deg;
      final input = InputImage.fromBytes(
        bytes: image.planes.first.bytes,
        metadata: InputImageMetadata(
          size: Size(image.width.toDouble(), image.height.toDouble()),
          rotation: rotation,
          format: InputImageFormat.nv21,
          bytesPerRow: image.planes.first.bytesPerRow,
        ),
      );
      for (final value in await _barcodeRecognition.recognize(input)) {
        final issue = widget.controller.catalog.byBarcode(value);
        if (issue != null) {
          _scanner.accept(issue, 'Barkod prepoznat');
        } else {
          _scanner.reportUnknownBarcode(value);
        }
        return;
      }

      final signature = VisualSignatureExtractor.fromNv21(
        image,
        rotationDegrees: description.sensorOrientation,
      );
      final decision = _coverTracker.evaluate(
        signature,
        widget.controller.catalog.matchVisual(
          visualHash: signature.visualHash,
          colorSignature: signature.colorSignature,
        ),
      );
      switch (decision.status) {
        case CoverFrameStatus.noMatch:
          return;
        case CoverFrameStatus.moveToNext:
          _scanner.setMessage('Pomakni sljedeći strip u kadar');
          return;
        case CoverFrameStatus.holdSteady:
          _scanner.setMessage('Drži jednu naslovnicu mirno u okviru');
          return;
        case CoverFrameStatus.candidate:
          final issue = decision.issue!;
          _scanner.setMessage('Prepoznajem ${issue.series} #${issue.number}…');
          return;
        case CoverFrameStatus.accepted:
          _scanner.accept(decision.issue!, 'Naslovnica prepoznata');
          return;
      }
    } on Object {
      // Pojedini uređaji mogu preskočiti frame ili vratiti drugi format.
      // Kamera nastavlja raditi i sljedeći frame ponovno pokušava analizu.
    }
  }

  Future<void> _captureShelf() async {
    final camera = _camera;
    if (camera == null ||
        !camera.value.isInitialized ||
        !_scanner.beginCapture('Fotografiram i čitam hrptove…')) {
      return;
    }
    XFile? photo;
    try {
      if (camera.value.isStreamingImages) await camera.stopImageStream();
      photo = await camera.takePicture();
      final result = await _shelfRecognition.recognizeFile(photo.path);
      _scanner.setOldBoyNeedsSelection(result.oldBoyNeedsSelection);
      _scanner.merge(result.issues);
      if (!mounted) return;
      _scanner.setMessage(
        result.issues.isEmpty
            ? result.oldBoyNeedsSelection
                  ? 'Old Boy je vidljiv, ali broj ili naslov treba odabrati'
                  : 'Nisam pouzdano pronašao brojeve — pokušaj bliže i bez odsjaja'
            : 'Pronađeno ${result.issues.length} stripova',
      );
      if (result.issues.isNotEmpty) await _openReview();
    } on Object catch (error) {
      if (mounted) _scanner.setMessage('Polica nije obrađena: $error');
    } finally {
      if (photo != null) unawaited(deleteTemporaryPath(photo.path));
      if (mounted) {
        _scanner.endCapture();
        if (!camera.value.isStreamingImages) {
          unawaited(camera.startImageStream(_onFrame));
        }
      }
    }
  }

  Future<void> _pickFromGallery() async {
    if (!_scanner.beginCapture('Odaberi naslovnicu ili fotografiju police…')) {
      return;
    }
    try {
      final photo =
          await (widget.pickGalleryImage?.call() ??
              _imagePicker.pickImage(
                source: ImageSource.gallery,
                requestFullMetadata: false,
              ));
      if (photo == null) {
        if (mounted) _scanner.setMessage('Odabir slike je otkazan');
        return;
      }
      await _processGalleryImage(photo);
    } on Object catch (error) {
      if (mounted) {
        _scanner.setMessage('Slika iz galerije nije obrađena: $error');
      }
    } finally {
      if (mounted) _scanner.endCapture();
    }
  }

  Future<void> _processGalleryImage(XFile photo) async {
    if (!mounted) return;
    _scanner.setMessage('Prepoznajem sadržaj slike…');
    final found = <String, CatalogIssue>{};
    final cover = await _coverRecognition.recognizeFile(photo.path);
    if (cover != null) found[cover.id] = cover;

    final shelf = await _shelfRecognition.recognizeFile(photo.path);
    _scanner.setOldBoyNeedsSelection(shelf.oldBoyNeedsSelection);
    for (final issue in shelf.issues) {
      found[issue.id] = issue;
    }
    _scanner.merge(found.values);
    if (!mounted) return;
    _scanner.setMessage(
      found.isEmpty
          ? shelf.oldBoyNeedsSelection
                ? 'Old Boy je vidljiv, ali broj ili naslov treba odabrati'
                : 'Nisam pouzdano prepoznao stripove na odabranoj slici'
          : shelf.oldBoyNeedsSelection
          ? 'Pronađeno ${found.length}; Old Boy treba ručno potvrditi'
          : 'Iz galerije pronađeno ${found.length} stripova',
    );
    if (found.isNotEmpty) await _openReview();
  }

  Future<void> _linkPendingBarcode() async {
    final barcode = _scanner.pendingBarcode;
    if (barcode == null || !mounted) return;
    final issue = await showCatalogIssuePicker(
      context: context,
      issues: widget.controller.catalog.issues,
      labelText: 'Poveži barkod $barcode',
      searchableText: (item) =>
          '${item.series} ${item.edition} ${item.number} ${item.title}',
      title: (item) => '${item.series} #${item.number}',
      subtitle: (item) => '${item.edition} · ${item.title}',
      limit: 50,
    );
    if (issue == null) return;
    await widget.controller.linkBarcode(barcode, issue);
    _scanner.clearPendingBarcode();
    _scanner.accept(issue, 'Barkod povezan i prepoznat');
  }

  Future<void> _selectOldBoyIssue() async {
    if (!mounted) return;
    final issue = await showCatalogIssuePicker(
      context: context,
      issues: widget.controller.catalog.issues.where(
        (item) => item.sourceEdition == 'DMLU',
      ),
      labelText: 'Broj ili naslov Maxi / Old Boy izdanja',
      searchableText: (item) => '${item.number} ${item.title}',
      title: (item) => 'Maxi #${item.number}',
      subtitle: (item) => item.title,
    );
    if (issue == null) return;
    _scanner.setOldBoyNeedsSelection(false);
    _scanner.accept(issue, 'Old Boy ručno potvrđen');
  }

  Future<void> _openReview() async {
    if (_scanner.scanned.isEmpty || !mounted) return;
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => ScanReviewPage(
          controller: widget.controller,
          issues: List<CatalogIssue>.of(_scanner.scanned),
        ),
      ),
    );
    if (!mounted) return;
    if (saved == true) {
      Navigator.pop(context);
      return;
    }
    _scanner.startNewSession();
  }

  Future<void> _toggleFlash() async {
    final camera = _camera;
    if (camera == null) return;
    final next = camera.value.flashMode == FlashMode.torch
        ? FlashMode.off
        : FlashMode.torch;
    await camera.setFlashMode(next);
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scanner.removeListener(_onScannerStateChanged);
    final camera = _camera;
    if (camera != null) unawaited(camera.dispose());
    if (_ownsBarcodeRecognition) unawaited(_barcodeRecognition.close());
    if (_ownsShelfRecognition) unawaited(_shelfRecognition.close());
    if (_ownsScanner) _scanner.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    body: SmartScannerView(
      camera: _camera,
      message: _scanner.message,
      flash: _scanner.flash,
      capturingShelf: _scanner.capturing,
      pendingBarcode: _scanner.pendingBarcode,
      oldBoyNeedsSelection: _scanner.oldBoyNeedsSelection,
      scanned: _scanner.scanned,
      onClose: () => Navigator.pop(context),
      onToggleFlash: _toggleFlash,
      onLinkPendingBarcode: _linkPendingBarcode,
      onSelectOldBoy: _selectOldBoyIssue,
      onCaptureShelf: _captureShelf,
      onPickFromGallery: _pickFromGallery,
      onReview: _openReview,
    ),
  );
}
