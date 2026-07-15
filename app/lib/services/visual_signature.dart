import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:image/image.dart' as img;

import 'image_signature.dart';

export 'image_signature.dart' show FrameSignature;

class VisualSignatureExtractor {
  const VisualSignatureExtractor._();

  static FrameSignature fromImage(img.Image source) =>
      ImageSignatureExtractor.fromImage(source);

  static FrameSignature fromNv21(
    CameraImage image, {
    required int rotationDegrees,
  }) {
    if (image.planes.isEmpty) {
      throw StateError('Kamera nije vratila slikovne podatke.');
    }
    final bytes = image.planes.first.bytes;
    final rawWidth = image.width;
    final rawHeight = image.height;
    final expectedLength = rawWidth * rawHeight * 3 ~/ 2;
    if (bytes.length < expectedLength) {
      throw StateError('Kamera ne koristi podržani NV21 format.');
    }

    final rotation = ((rotationDegrees % 360) + 360) % 360;
    final rotated = rotation == 90 || rotation == 270;
    final orientedWidth = rotated ? rawHeight : rawWidth;
    final orientedHeight = rotated ? rawWidth : rawHeight;
    const targetAspect = 3 / 4;
    final currentAspect = orientedWidth / orientedHeight;
    final cropWidth = currentAspect > targetAspect
        ? orientedHeight * targetAspect
        : orientedWidth.toDouble();
    final cropHeight = currentAspect > targetAspect
        ? orientedHeight.toDouble()
        : orientedWidth / targetAspect;
    final cropLeft = (orientedWidth - cropWidth) / 2;
    final cropTop = (orientedHeight - cropHeight) / 2;

    ({int r, int g, int b}) sample(int gridX, int gridY) {
      final orientedX = (cropLeft + cropWidth * gridX / 8)
          .round()
          .clamp(0, orientedWidth - 1)
          .toInt();
      final orientedY = (cropTop + cropHeight * gridY / 7)
          .round()
          .clamp(0, orientedHeight - 1)
          .toInt();
      late final int rawX;
      late final int rawY;
      switch (rotation) {
        case 90:
          rawX = orientedY;
          rawY = rawHeight - 1 - orientedX;
        case 180:
          rawX = rawWidth - 1 - orientedX;
          rawY = rawHeight - 1 - orientedY;
        case 270:
          rawX = rawWidth - 1 - orientedY;
          rawY = orientedX;
        default:
          rawX = orientedX;
          rawY = orientedY;
      }
      return _nv21Pixel(bytes, rawWidth, rawHeight, rawX, rawY);
    }

    return ImageSignatureExtractor.fromSampler(sample);
  }

  static ({int r, int g, int b}) _nv21Pixel(
    Uint8List bytes,
    int width,
    int height,
    int x,
    int y,
  ) {
    final safeX = x.clamp(0, width - 1).toInt();
    final safeY = y.clamp(0, height - 1).toInt();
    final yValue = bytes[safeY * width + safeX];
    final chroma =
        width * height +
        (safeY ~/ 2) * width +
        (safeX.isEven ? safeX : safeX - 1);
    final v = bytes[chroma] - 128;
    final u = bytes[chroma + 1] - 128;
    final luminance = yValue - 16;
    final r = ((298 * luminance + 409 * v + 128) >> 8).clamp(0, 255).toInt();
    final g = ((298 * luminance - 100 * u - 208 * v + 128) >> 8)
        .clamp(0, 255)
        .toInt();
    final b = ((298 * luminance + 516 * u + 128) >> 8).clamp(0, 255).toInt();
    return (r: r, g: g, b: b);
  }
}
