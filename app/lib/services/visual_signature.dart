import 'dart:typed_data';

import 'package:camera/camera.dart';

class FrameSignature {
  const FrameSignature({
    required this.visualHash,
    required this.colorSignature,
  });

  final String visualHash;
  final Uint8List colorSignature;

  int distanceTo(FrameSignature other) {
    var value =
        BigInt.parse(visualHash, radix: 16) ^
        BigInt.parse(other.visualHash, radix: 16);
    var count = 0;
    while (value != BigInt.zero) {
      value &= value - BigInt.one;
      count++;
    }
    return count;
  }
}

class VisualSignatureExtractor {
  const VisualSignatureExtractor._();

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

    final pixels = <({int r, int g, int b})>[];
    for (var y = 0; y < 8; y++) {
      for (var x = 0; x < 9; x++) {
        pixels.add(sample(x, y));
      }
    }
    ({int r, int g, int b}) at(int x, int y) => pixels[y * 9 + x];

    var bits = BigInt.zero;
    var bitIndex = 0;
    for (var y = 0; y < 8; y++) {
      for (var x = 0; x < 8; x++) {
        final left = at(x, y);
        final right = at(x + 1, y);
        final leftLuma = 299 * left.r + 587 * left.g + 114 * left.b;
        final rightLuma = 299 * right.r + 587 * right.g + 114 * right.b;
        if (leftLuma > rightLuma) {
          bits |= BigInt.one << bitIndex;
        }
        bitIndex++;
      }
    }

    final colors = Uint8List(48);
    var colorIndex = 0;
    for (final y in const [0, 2, 4, 6]) {
      for (final x in const [1, 3, 5, 7]) {
        final pixel = at(x, y);
        colors[colorIndex++] = pixel.r;
        colors[colorIndex++] = pixel.g;
        colors[colorIndex++] = pixel.b;
      }
    }
    return FrameSignature(
      visualHash: bits.toRadixString(16).padLeft(16, '0'),
      colorSignature: colors,
    );
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
