import 'dart:typed_data';

import 'package:image/image.dart' as img;

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

typedef RgbSample = ({int r, int g, int b});

/// Pure-Dart signature extraction shared by Flutter recognition and catalogue
/// build tooling. This file intentionally has no camera or Flutter imports.
class ImageSignatureExtractor {
  const ImageSignatureExtractor._();

  static FrameSignature fromImage(img.Image source) {
    final image = img.bakeOrientation(source);
    final width = image.width;
    final height = image.height;
    const targetAspect = 3 / 4;
    final currentAspect = width / height;
    final cropWidth = currentAspect > targetAspect
        ? height * targetAspect
        : width.toDouble();
    final cropHeight = currentAspect > targetAspect
        ? height.toDouble()
        : width / targetAspect;
    final cropLeft = (width - cropWidth) / 2;
    final cropTop = (height - cropHeight) / 2;

    RgbSample sample(int gridX, int gridY) {
      final x = (cropLeft + cropWidth * gridX / 8)
          .round()
          .clamp(0, width - 1)
          .toInt();
      final y = (cropTop + cropHeight * gridY / 7)
          .round()
          .clamp(0, height - 1)
          .toInt();
      final pixel = image.getPixel(x, y);
      return (r: pixel.r.toInt(), g: pixel.g.toInt(), b: pixel.b.toInt());
    }

    return fromSampler(sample);
  }

  static FrameSignature fromSampler(
    RgbSample Function(int gridX, int gridY) sample,
  ) {
    final pixels = <RgbSample>[];
    for (var y = 0; y < 8; y++) {
      for (var x = 0; x < 9; x++) {
        pixels.add(sample(x, y));
      }
    }
    RgbSample at(int x, int y) => pixels[y * 9 + x];

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
}
