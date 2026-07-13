import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

import '../app_controller.dart';
import '../data/catalog_repository.dart';
import '../models/catalog_issue.dart';
import '../services/visual_signature.dart';

const _scannerRed = Color(0xFFC6291E);
const _scannerInk = Color(0xFF131412);
const _scannerTan = Color(0xFFB7A88F);

Future<void> _deleteTemporaryFile(File file) async {
  try {
    await file.delete();
  } on FileSystemException {
    // Cache cleanup is best effort.
  }
}

class SmartScannerPage extends StatefulWidget {
  const SmartScannerPage({super.key, required this.controller});

  final AppController controller;

  @override
  State<SmartScannerPage> createState() => _SmartScannerPageState();
}

class _SmartScannerPageState extends State<SmartScannerPage>
    with WidgetsBindingObserver {
  final BarcodeScanner _barcodeScanner = BarcodeScanner(
    formats: const [
      BarcodeFormat.ean13,
      BarcodeFormat.ean8,
      BarcodeFormat.upca,
      BarcodeFormat.upce,
      BarcodeFormat.code128,
    ],
  );
  final TextRecognizer _textRecognizer = TextRecognizer(
    script: TextRecognitionScript.latin,
  );
  final ImagePicker _imagePicker = ImagePicker();

  CameraController? _camera;
  CameraDescription? _description;
  DateTime _lastAnalysis = DateTime.fromMillisecondsSinceEpoch(0);
  bool _analyzing = false;
  bool _capturingShelf = false;
  bool _flash = false;
  String _message = 'Uperi u barkod ili jednu naslovnicu';
  String? _stableCandidate;
  int _stableFrames = 0;
  FrameSignature? _lastSignature;
  FrameSignature? _lockedSignature;
  String? _lastUnknownBarcode;
  String? _pendingBarcode;
  final List<CatalogIssue> _scanned = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_initializeCamera());
    unawaited(_restoreLostGalleryImage());
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
      final cameras = await availableCameras();
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
      setState(() {
        _message = error.code == 'CameraAccessDenied'
            ? 'Dopusti pristup kameri u postavkama uređaja.'
            : 'Kamera se ne može otvoriti: ${error.description ?? error.code}';
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _message = 'Kamera se ne može otvoriti: $error');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final camera = _camera;
    if (camera == null || !camera.value.isInitialized) return;
    if (state == AppLifecycleState.inactive) {
      _camera = null;
      unawaited(camera.dispose());
    } else if (state == AppLifecycleState.resumed && _description != null) {
      unawaited(_initializeCamera(_description));
    }
  }

  void _onFrame(CameraImage image) {
    final now = DateTime.now();
    if (_analyzing ||
        _capturingShelf ||
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
      final barcodes = await _barcodeScanner.processImage(input);
      for (final barcode in barcodes) {
        final value = barcode.rawValue?.trim();
        if (value == null || value.isEmpty) continue;
        final issue = widget.controller.catalog.byBarcode(value);
        if (issue != null) {
          _accept(issue, 'Barkod prepoznat');
        } else if (_lastUnknownBarcode != value && mounted) {
          _lastUnknownBarcode = value;
          _pendingBarcode = value;
          setState(() {
            _message = 'Barkod $value nije povezan s lokalnim katalogom';
          });
        }
        return;
      }

      final signature = VisualSignatureExtractor.fromNv21(
        image,
        rotationDegrees: description.sensorOrientation,
      );
      final previous = _lastSignature;
      _lastSignature = signature;
      final locked = _lockedSignature;
      if (locked != null) {
        if (signature.distanceTo(locked) < 15) {
          if (mounted) {
            setState(() => _message = 'Pomakni sljedeći strip u kadar');
          }
          return;
        }
        _lockedSignature = null;
      }
      final matches = widget.controller.catalog.matchVisual(
        visualHash: signature.visualHash,
        colorSignature: signature.colorSignature,
      );
      if (matches.isEmpty) return;
      final best = matches.first;
      final margin = matches.length < 2 ? 1.0 : best.score - matches[1].score;
      final frameStable =
          previous != null && signature.distanceTo(previous) < 11;
      final confident =
          best.score >= 0.70 && (margin >= 0.018 || best.score >= 0.82);
      if (!frameStable || !confident) {
        _stableCandidate = null;
        _stableFrames = 0;
        if (mounted) {
          setState(() => _message = 'Drži jednu naslovnicu mirno u okviru');
        }
        return;
      }
      if (_stableCandidate == best.issue.id) {
        _stableFrames++;
      } else {
        _stableCandidate = best.issue.id;
        _stableFrames = 1;
      }
      if (mounted) {
        setState(() {
          _message = 'Prepoznajem ${best.issue.series} #${best.issue.number}…';
        });
      }
      if (_stableFrames >= 2) {
        _lockedSignature = signature;
        _stableFrames = 0;
        _accept(best.issue, 'Naslovnica prepoznata');
      }
    } on Object {
      // Pojedini uređaji mogu preskočiti frame ili vratiti drugi format.
      // Kamera nastavlja raditi i sljedeći frame ponovno pokušava analizu.
    }
  }

  void _accept(CatalogIssue issue, String source) {
    if (_scanned.any((item) => item.id == issue.id)) {
      if (mounted) setState(() => _message = '${issue.title} je već u popisu');
      return;
    }
    if (!mounted) return;
    setState(() {
      _scanned.add(issue);
      _message = '$source · ${issue.series} #${issue.number}';
      _flash = true;
    });
    unawaited(
      Future<void>.delayed(const Duration(milliseconds: 450), () {
        if (mounted) setState(() => _flash = false);
      }),
    );
  }

  Future<void> _captureShelf() async {
    final camera = _camera;
    if (camera == null || !camera.value.isInitialized || _capturingShelf) {
      return;
    }
    setState(() {
      _capturingShelf = true;
      _message = 'Fotografiram i čitam hrptove…';
    });
    XFile? photo;
    try {
      if (camera.value.isStreamingImages) await camera.stopImageStream();
      photo = await camera.takePicture();
      final issues = await _recognizeShelf(photo.path);
      for (final issue in issues) {
        if (_scanned.every((item) => item.id != issue.id)) _scanned.add(issue);
      }
      if (!mounted) return;
      setState(() {
        _message = issues.isEmpty
            ? 'Nisam pouzdano pronašao brojeve — pokušaj bliže i bez odsjaja'
            : 'Pronađeno ${issues.length} stripova';
      });
      if (issues.isNotEmpty) await _openReview();
    } on Object catch (error) {
      if (mounted) setState(() => _message = 'Polica nije obrađena: $error');
    } finally {
      if (photo != null) unawaited(_deleteTemporaryFile(File(photo.path)));
      if (mounted) {
        setState(() => _capturingShelf = false);
        if (!camera.value.isStreamingImages) {
          unawaited(camera.startImageStream(_onFrame));
        }
      }
    }
  }

  Future<void> _pickFromGallery() async {
    if (_capturingShelf) return;
    if (mounted) {
      setState(() {
        _capturingShelf = true;
        _message = 'Odaberi naslovnicu ili fotografiju police…';
      });
    }
    try {
      final photo = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        requestFullMetadata: false,
      );
      if (photo == null) {
        if (mounted) setState(() => _message = 'Odabir slike je otkazan');
        return;
      }
      await _processGalleryImage(photo);
    } on Object catch (error) {
      if (mounted) {
        setState(() => _message = 'Slika iz galerije nije obrađena: $error');
      }
    } finally {
      if (mounted) setState(() => _capturingShelf = false);
    }
  }

  Future<void> _processGalleryImage(XFile photo) async {
    if (!mounted) return;
    setState(() => _message = 'Prepoznajem sadržaj slike…');
    final found = <String, CatalogIssue>{};
    final decoded = img.decodeImage(await photo.readAsBytes());
    if (decoded != null) {
      final signature = VisualSignatureExtractor.fromImage(decoded);
      final matches = widget.controller.catalog.matchVisual(
        visualHash: signature.visualHash,
        colorSignature: signature.colorSignature,
      );
      if (matches.isNotEmpty) {
        final best = matches.first;
        final margin = matches.length < 2 ? 1.0 : best.score - matches[1].score;
        if (best.score >= .70 && (margin >= .018 || best.score >= .82)) {
          found[best.issue.id] = best.issue;
        }
      }
    }

    for (final issue in await _recognizeShelf(photo.path)) {
      found[issue.id] = issue;
    }
    for (final issue in found.values) {
      if (_scanned.every((item) => item.id != issue.id)) _scanned.add(issue);
    }
    if (!mounted) return;
    setState(() {
      _message = found.isEmpty
          ? 'Nisam pouzdano prepoznao stripove na odabranoj slici'
          : 'Iz galerije pronađeno ${found.length} stripova';
    });
    if (found.isNotEmpty) await _openReview();
  }

  Future<void> _linkPendingBarcode() async {
    final barcode = _pendingBarcode;
    if (barcode == null || !mounted) return;
    var query = '';
    final issue = await showModalBottomSheet<CatalogIssue>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) {
          final normalized = CatalogRepository.normalize(query);
          final matches = widget.controller.catalog.issues
              .where((item) {
                if (normalized.isEmpty) return true;
                return CatalogRepository.normalize(
                  '${item.series} ${item.edition} ${item.number} ${item.title}',
                ).contains(normalized);
              })
              .take(50)
              .toList();
          return SafeArea(
            child: SizedBox(
              height: MediaQuery.sizeOf(context).height * .78,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(14),
                    child: TextField(
                      autofocus: true,
                      onChanged: (value) => setSheetState(() => query = value),
                      decoration: InputDecoration(
                        labelText: 'Poveži barkod $barcode',
                        prefixIcon: const Icon(Icons.search),
                      ),
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      itemCount: matches.length,
                      itemBuilder: (context, index) {
                        final item = matches[index];
                        return ListTile(
                          leading: item.coverAsset == null
                              ? const Icon(Icons.menu_book)
                              : Image.asset(
                                  item.coverAsset!,
                                  width: 38,
                                  height: 52,
                                  fit: BoxFit.cover,
                                ),
                          title: Text('${item.series} #${item.number}'),
                          subtitle: Text('${item.edition} · ${item.title}'),
                          onTap: () => Navigator.pop(sheetContext, item),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    if (issue == null) return;
    await widget.controller.linkBarcode(barcode, issue);
    _pendingBarcode = null;
    _accept(issue, 'Barkod povezan i prepoznat');
  }

  Future<List<CatalogIssue>> _recognizeShelf(String path) async {
    final paths = <String>[path];
    final temporary = <File>[];
    try {
      final decoded = img.decodeImage(await File(path).readAsBytes());
      if (decoded != null) {
        final oriented = img.bakeOrientation(decoded);
        for (final angle in const [90.0, 270.0]) {
          final rotated = img.copyRotate(oriented, angle: angle);
          final file = File(
            '${Directory.systemTemp.path}/comicollect-shelf-${DateTime.now().microsecondsSinceEpoch}-${angle.toInt()}.jpg',
          );
          await file.writeAsBytes(img.encodeJpg(rotated, quality: 88));
          paths.add(file.path);
          temporary.add(file);
        }
      }
      final lines = <String>{};
      for (final candidatePath in paths) {
        final text = await _textRecognizer.processImage(
          InputImage.fromFilePath(candidatePath),
        );
        for (final block in text.blocks) {
          for (final line in block.lines) {
            if (line.text.trim().isNotEmpty) lines.add(line.text.trim());
          }
        }
      }
      return _catalogIssuesFromLines(lines);
    } finally {
      for (final file in temporary) {
        unawaited(_deleteTemporaryFile(file));
      }
    }
  }

  List<CatalogIssue> _catalogIssuesFromLines(Iterable<String> lines) {
    final found = <String, CatalogIssue>{};
    final catalog = widget.controller.catalog;
    for (final line in lines) {
      final normalized = CatalogRepository.normalize(line);
      final hasSeries = normalized.contains('DYLAN DOG');
      if (hasSeries) {
        for (final match in RegExp(
          r'(?<!\d)(\d{1,3})(?!\d)',
        ).allMatches(normalized)) {
          final number = int.parse(match.group(1)!);
          final candidates = catalog.issues
              .where(
                (issue) =>
                    issue.series == 'Dylan Dog' && issue.number == number,
              )
              .toList();
          if (candidates.length == 1) {
            found[candidates.first.id] = candidates.first;
          } else if (candidates.isNotEmpty) {
            final special = normalized.contains('SPECIJAL');
            final selected = candidates.firstWhere(
              (issue) => issue.edition.contains('Specijal') == special,
              orElse: () => candidates.first,
            );
            found[selected.id] = selected;
          }
        }
      }
      final textMatches = catalog.matchText(line, limit: 2);
      for (final issue in textMatches) {
        final title = CatalogRepository.normalize(issue.title);
        if (title.length >= 5 && normalized.contains(title)) {
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

  Future<void> _openReview() async {
    if (_scanned.isEmpty || !mounted) return;
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => ScanReviewPage(
          controller: widget.controller,
          issues: List<CatalogIssue>.of(_scanned),
        ),
      ),
    );
    if (saved == true && mounted) Navigator.pop(context);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    final camera = _camera;
    if (camera != null) unawaited(camera.dispose());
    unawaited(_barcodeScanner.close());
    unawaited(_textRecognizer.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final camera = _camera;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (camera != null && camera.value.isInitialized)
            CameraPreview(camera)
          else
            const ColoredBox(
              color: Color(0xFF080909),
              child: Center(child: CircularProgressIndicator()),
            ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: .58),
                  Colors.transparent,
                  Colors.black.withValues(alpha: .78),
                ],
                stops: const [0, .25, 1],
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    children: [
                      IconButton.filledTonal(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close),
                      ),
                      const Expanded(
                        child: Text(
                          'PAMETNO SKENIRANJE',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1,
                          ),
                        ),
                      ),
                      IconButton.filledTonal(
                        onPressed: camera == null
                            ? null
                            : () async {
                                final next =
                                    camera.value.flashMode == FlashMode.torch
                                    ? FlashMode.off
                                    : FlashMode.torch;
                                await camera.setFlashMode(next);
                                if (mounted) setState(() {});
                              },
                        icon: Icon(
                          camera?.value.flashMode == FlashMode.torch
                              ? Icons.flash_on
                              : Icons.flash_off,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Center(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      width: 230,
                      height: 307,
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: _flash ? const Color(0xFF3EC63E) : _scannerRed,
                          width: 4,
                        ),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: _flash
                          ? const Icon(
                              Icons.check_circle_outline,
                              color: Color(0xFF3EC63E),
                              size: 70,
                            )
                          : null,
                    ),
                  ),
                ),
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 18),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 9,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: .62),
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(
                    _message,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontSize: 12.5),
                  ),
                ),
                const SizedBox(height: 12),
                if (_pendingBarcode != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: OutlinedButton.icon(
                      onPressed: _linkPendingBarcode,
                      icon: const Icon(Icons.link),
                      label: const Text('POVEŽI NEPOZNATI BARKOD'),
                    ),
                  ),
                Column(
                  children: [
                    FilledButton.icon(
                      onPressed: _capturingShelf ? null : _captureShelf,
                      icon: _capturingShelf
                          ? const SizedBox.square(
                              dimension: 17,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.photo_camera_outlined),
                      label: const Text('FOTOGRAFIRAJ POLICU'),
                    ),
                    const SizedBox(height: 6),
                    TextButton.icon(
                      onPressed: _capturingShelf ? null : _pickFromGallery,
                      icon: const Icon(Icons.photo_library_outlined),
                      label: const Text('UČITAJ IZ GALERIJE'),
                    ),
                  ],
                ),
                if (_scanned.isNotEmpty)
                  _ScanTray(issues: _scanned, onReview: _openReview),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ScanTray extends StatelessWidget {
  const _ScanTray({required this.issues, required this.onReview});
  final List<CatalogIssue> issues;
  final VoidCallback onReview;

  @override
  Widget build(BuildContext context) {
    final last = issues.last;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: _scannerInk.withValues(alpha: .96),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white24),
      ),
      child: Row(
        children: [
          if (last.coverAsset != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Image.asset(
                last.coverAsset!,
                width: 37,
                height: 50,
                fit: BoxFit.cover,
              ),
            ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${issues.length} ${issues.length == 1 ? 'strip' : 'stripova'} u popisu',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                Text(
                  'Zadnji: #${last.number} · ${last.title}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: _scannerTan, fontSize: 12),
                ),
              ],
            ),
          ),
          TextButton(onPressed: onReview, child: const Text('PREGLEDAJ')),
        ],
      ),
    );
  }
}

class ScanReviewPage extends StatefulWidget {
  const ScanReviewPage({
    super.key,
    required this.controller,
    required this.issues,
  });

  final AppController controller;
  final List<CatalogIssue> issues;

  @override
  State<ScanReviewPage> createState() => _ScanReviewPageState();
}

class _ScanReviewPageState extends State<ScanReviewPage> {
  late final Map<String, bool> _included = {
    for (final issue in widget.issues) issue.id: true,
  };
  late final Map<String, bool> _owned = {
    for (final issue in widget.issues) issue.id: true,
  };
  bool _saving = false;

  Future<void> _save() async {
    final results = <CatalogIssue, bool>{};
    for (final issue in widget.issues) {
      if (_included[issue.id] ?? false) {
        results[issue] = _owned[issue.id] ?? true;
      }
    }
    if (results.isEmpty) return;
    setState(() => _saving = true);
    await widget.controller.saveScanResults(results);
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text('PRONAĐENO ${widget.issues.length}'),
      actions: [
        TextButton(
          onPressed: () => setState(() {
            for (final issue in widget.issues) {
              _owned[issue.id] = true;
              _included[issue.id] = true;
            }
          }),
          child: const Text('SVE IMAM'),
        ),
      ],
    ),
    body: ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 100),
      itemCount: widget.issues.length,
      itemBuilder: (context, index) {
        final issue = widget.issues[index];
        final included = _included[issue.id] ?? true;
        final owned = _owned[issue.id] ?? true;
        return Card(
          margin: const EdgeInsets.only(bottom: 9),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              children: [
                Checkbox(
                  value: included,
                  onChanged: (value) => setState(() {
                    _included[issue.id] = value ?? false;
                  }),
                ),
                ClipRRect(
                  borderRadius: BorderRadius.circular(7),
                  child: issue.coverAsset == null
                      ? const SizedBox(
                          width: 48,
                          height: 64,
                          child: ColoredBox(color: Color(0xFF292A28)),
                        )
                      : Image.asset(
                          issue.coverAsset!,
                          width: 48,
                          height: 64,
                          fit: BoxFit.cover,
                        ),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${issue.series} #${issue.number}',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      Text(
                        issue.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: _scannerTan,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 5),
                      SegmentedButton<bool>(
                        segments: const [
                          ButtonSegment(value: true, label: Text('IMAM')),
                          ButtonSegment(value: false, label: Text('NEMAM')),
                        ],
                        selected: {owned},
                        onSelectionChanged: included
                            ? (selection) => setState(() {
                                _owned[issue.id] = selection.first;
                              })
                            : null,
                        showSelectedIcon: false,
                        style: const ButtonStyle(
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: _saving ? null : _save,
      backgroundColor: _scannerRed,
      foregroundColor: Colors.white,
      icon: _saving
          ? const SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.check),
      label: const Text('SPREMI ODABRANO'),
    ),
  );
}
