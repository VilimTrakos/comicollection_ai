import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../../models/catalog_issue.dart';

const _scannerRed = Color(0xFFC6291E);
const _scannerInk = Color(0xFF131412);
const _scannerTan = Color(0xFFB7A88F);

class SmartScannerView extends StatelessWidget {
  const SmartScannerView({
    super.key,
    required this.camera,
    required this.message,
    required this.flash,
    required this.capturingShelf,
    required this.pendingBarcode,
    required this.oldBoyNeedsSelection,
    required this.scanned,
    required this.onClose,
    required this.onToggleFlash,
    required this.onLinkPendingBarcode,
    required this.onSelectOldBoy,
    required this.onCaptureShelf,
    required this.onPickFromGallery,
    required this.onReview,
  });

  final CameraController? camera;
  final String message;
  final bool flash;
  final bool capturingShelf;
  final String? pendingBarcode;
  final bool oldBoyNeedsSelection;
  final List<CatalogIssue> scanned;
  final VoidCallback onClose;
  final VoidCallback onToggleFlash;
  final VoidCallback onLinkPendingBarcode;
  final VoidCallback onSelectOldBoy;
  final VoidCallback onCaptureShelf;
  final VoidCallback onPickFromGallery;
  final VoidCallback onReview;

  @override
  Widget build(BuildContext context) {
    final activeCamera = camera;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (activeCamera != null && activeCamera.value.isInitialized)
          CameraPreview(activeCamera)
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
                      onPressed: onClose,
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
                      onPressed: activeCamera == null ? null : onToggleFlash,
                      icon: Icon(
                        activeCamera?.value.flashMode == FlashMode.torch
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
                        color: flash ? const Color(0xFF3EC63E) : _scannerRed,
                        width: 4,
                      ),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: flash
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
                  message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 12.5),
                ),
              ),
              const SizedBox(height: 12),
              if (pendingBarcode != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: OutlinedButton.icon(
                    onPressed: onLinkPendingBarcode,
                    icon: const Icon(Icons.link),
                    label: const Text('POVEŽI NEPOZNATI BARKOD'),
                  ),
                ),
              if (oldBoyNeedsSelection)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: OutlinedButton.icon(
                    onPressed: onSelectOldBoy,
                    icon: const Icon(Icons.auto_stories_outlined),
                    label: const Text('ODABERI OLD BOY IZDANJE'),
                  ),
                ),
              Column(
                children: [
                  FilledButton.icon(
                    onPressed: capturingShelf ? null : onCaptureShelf,
                    icon: capturingShelf
                        ? const SizedBox.square(
                            dimension: 17,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.photo_camera_outlined),
                    label: const Text('FOTOGRAFIRAJ POLICU'),
                  ),
                  const SizedBox(height: 6),
                  TextButton.icon(
                    onPressed: capturingShelf ? null : onPickFromGallery,
                    icon: const Icon(Icons.photo_library_outlined),
                    label: const Text('UČITAJ IZ GALERIJE'),
                  ),
                ],
              ),
              if (scanned.isNotEmpty)
                ScanTray(issues: scanned, onReview: onReview),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ],
    );
  }
}

class ScanTray extends StatelessWidget {
  const ScanTray({super.key, required this.issues, required this.onReview});

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
