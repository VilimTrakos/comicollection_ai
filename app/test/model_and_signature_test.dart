import 'dart:convert';

import 'package:camera/camera.dart';
import 'package:comicollect/models/catalog_issue.dart';
import 'package:comicollect/models/comic.dart';
import 'package:comicollect/services/visual_signature.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  group('Comic', () {
    test('constructor exposes documented defaults', () {
      final comic = Comic(
        id: 'one',
        series: 'Dylan Dog',
        edition: 'Extra',
        number: 1,
        title: 'Naslov',
        updatedAt: 1,
      );

      expect(comic.publisher, isEmpty);
      expect(comic.year, isNull);
      expect(comic.owned, isTrue);
      expect(comic.read, isFalse);
      expect(comic.condition, 'F');
      expect(comic.purchasePrice, isNull);
      expect(comic.estimatedValue, isNull);
      expect(comic.duplicate, isFalse);
      expect(comic.loanedTo, isEmpty);
      expect(comic.notes, isEmpty);
      expect(comic.coverAsset, isEmpty);
      expect(comic.rating, 0);
      expect(comic.pageCount, isNull);
      expect(comic.writer, isEmpty);
      expect(comic.artist, isEmpty);
      expect(comic.deleted, isFalse);
    });

    test('copyWith replaces every mutable field and preserves id', () {
      final original = _comic();
      final copy = original.copyWith(
        series: 'Tex',
        edition: 'Zlatna',
        number: 99,
        title: 'Novi naslov',
        publisher: 'Izdavač',
        year: 2026,
        owned: false,
        read: true,
        condition: 'M',
        purchasePrice: 1.5,
        estimatedValue: 9.5,
        duplicate: true,
        loanedTo: 'Ivo',
        notes: 'Bilješka',
        coverAsset: 'cover.webp',
        rating: 4,
        pageCount: 128,
        writer: 'Pisac',
        artist: 'Crtač',
        deleted: true,
        updatedAt: 99,
      );

      expect(copy.id, original.id);
      expect(copy.series, 'Tex');
      expect(copy.edition, 'Zlatna');
      expect(copy.number, 99);
      expect(copy.title, 'Novi naslov');
      expect(copy.publisher, 'Izdavač');
      expect(copy.year, 2026);
      expect(copy.owned, isFalse);
      expect(copy.read, isTrue);
      expect(copy.condition, 'M');
      expect(copy.purchasePrice, 1.5);
      expect(copy.estimatedValue, 9.5);
      expect(copy.duplicate, isTrue);
      expect(copy.loanedTo, 'Ivo');
      expect(copy.notes, 'Bilješka');
      expect(copy.coverAsset, 'cover.webp');
      expect(copy.rating, 4);
      expect(copy.pageCount, 128);
      expect(copy.writer, 'Pisac');
      expect(copy.artist, 'Crtač');
      expect(copy.deleted, isTrue);
      expect(copy.updatedAt, 99);
    });

    test('map and JSON serialization preserve all values', () {
      final original = _comic().copyWith(
        owned: false,
        read: true,
        condition: '',
        purchasePrice: 2.25,
        estimatedValue: 7.75,
        duplicate: true,
        deleted: true,
      );

      expect(original.toJson(), original.toMap());
      final restored = Comic.fromMap(original.toMap());
      expect(restored.toMap(), original.toMap());
    });

    test('fromMap applies safe defaults for optional legacy columns', () {
      final comic = Comic.fromMap({
        'id': 'legacy',
        'series': null,
        'edition': null,
        'number': 2,
        'title': null,
        'updated_at': 5,
      });

      expect(comic.series, isEmpty);
      expect(comic.edition, isEmpty);
      expect(comic.title, isEmpty);
      expect(comic.owned, isFalse);
      expect(comic.read, isFalse);
      expect(comic.condition, 'F');
      expect(comic.rating, 0);
    });
  });

  group('CatalogIssue', () {
    test('fromJson decodes optional values, signature and valid barcodes', () {
      final issue = CatalogIssue.fromJson({
        'id': 'issue',
        'sourceEdition': 'DDLU',
        'series': 'Dylan Dog',
        'edition': 'Regularna (L)',
        'number': 61,
        'title': 'Naslov',
        'publisher': 'Ludens',
        'year': 2002,
        'coverAsset': 'cover.webp',
        'visualHash': '0000000000000001',
        'colorSignature': base64Encode([1, 2, 3]),
        'barcodes': <Object?>['123', 7, null, '456'],
      });

      expect(issue.year, 2002);
      expect(issue.coverAsset, 'cover.webp');
      expect(issue.visualHash, '0000000000000001');
      expect(issue.colorSignature, Uint8List.fromList([1, 2, 3]));
      expect(issue.barcodes, ['123', '456']);
    });

    test('fromJson supports absent optional data', () {
      final issue = CatalogIssue.fromJson(_issueJson());

      expect(issue.year, isNull);
      expect(issue.coverAsset, isNull);
      expect(issue.visualHash, isNull);
      expect(issue.colorSignature, isNull);
      expect(issue.barcodes, isEmpty);
    });

    test('toComic creates a non-owned catalog record', () {
      final issue = CatalogIssue.fromJson({
        ..._issueJson(),
        'coverAsset': 'cover.webp',
      });

      final comic = issue.toComic();
      expect(comic.id, issue.id);
      expect(comic.series, issue.series);
      expect(comic.edition, issue.edition);
      expect(comic.number, issue.number);
      expect(comic.title, issue.title);
      expect(comic.publisher, issue.publisher);
      expect(comic.owned, isFalse);
      expect(comic.read, isFalse);
      expect(comic.condition, 'F');
      expect(comic.notes, 'BSP katalog · DDLU');
      expect(comic.coverAsset, 'cover.webp');
      expect(comic.updatedAt, 0);
    });
  });

  group('VisualSignatureExtractor', () {
    test('FrameSignature distance counts differing hash bits', () {
      final first = FrameSignature(
        visualHash: '0000000000000000',
        colorSignature: Uint8List(0),
      );
      final second = FrameSignature(
        visualHash: '000000000000000f',
        colorSignature: Uint8List(0),
      );

      expect(first.distanceTo(first), 0);
      expect(first.distanceTo(second), 4);
      expect(second.distanceTo(first), 4);
    });

    test('fromImage is deterministic and returns expected dimensions', () {
      final image = img.Image(width: 90, height: 120);
      for (var y = 0; y < image.height; y++) {
        for (var x = 0; x < image.width; x++) {
          image.setPixelRgb(x, y, x * 2, y * 2, (x + y) % 256);
        }
      }

      final first = VisualSignatureExtractor.fromImage(image);
      final second = VisualSignatureExtractor.fromImage(image);

      expect(first.visualHash, hasLength(16));
      expect(first.colorSignature, hasLength(48));
      expect(first.visualHash, second.visualHash);
      expect(first.colorSignature, second.colorSignature);
    });

    test('fromImage bakes EXIF orientation before sampling', () {
      final image = img.Image(width: 40, height: 30)
        ..setPixelRgb(0, 0, 255, 0, 0)
        ..exif.imageIfd.orientation = 6;

      final signature = VisualSignatureExtractor.fromImage(image);

      expect(signature.visualHash, hasLength(16));
      expect(signature.colorSignature, hasLength(48));
    });

    test('fromNv21 samples valid frames for every supported rotation', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final image = _nv21Image(width: 8, height: 8);

      for (final rotation in [0, 90, 180, 270, 360, -90]) {
        final signature = VisualSignatureExtractor.fromNv21(
          image,
          rotationDegrees: rotation,
        );
        expect(signature.visualHash, hasLength(16));
        expect(signature.colorSignature, hasLength(48));
      }
    });

    test('fromNv21 rejects empty and truncated camera buffers', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);

      expect(
        () => VisualSignatureExtractor.fromNv21(
          // ignore: deprecated_member_use
          CameraImage.fromPlatformData({
            'format': 17,
            'height': 8,
            'width': 8,
            'planes': <Object?>[],
          }),
          rotationDegrees: 0,
        ),
        throwsStateError,
      );
      expect(
        () => VisualSignatureExtractor.fromNv21(
          // ignore: deprecated_member_use
          CameraImage.fromPlatformData({
            'format': 17,
            'height': 8,
            'width': 8,
            'planes': [
              {
                'bytes': Uint8List(10),
                'bytesPerPixel': 1,
                'bytesPerRow': 8,
                'height': 8,
                'width': 8,
              },
            ],
          }),
          rotationDegrees: 0,
        ),
        throwsStateError,
      );
    });
  });
}

Comic _comic() => Comic(
  id: 'comic',
  series: 'Dylan Dog',
  edition: 'Extra',
  number: 14,
  title: 'Kuća sjećanja',
  publisher: 'Ludens',
  year: 2002,
  owned: true,
  read: false,
  condition: 'VF',
  purchasePrice: 3,
  estimatedValue: 7,
  duplicate: false,
  loanedTo: '',
  notes: 'Bilješka',
  coverAsset: 'cover.webp',
  rating: 3,
  pageCount: 98,
  writer: 'Tiziano Sclavi',
  artist: 'Angelo Stano',
  deleted: false,
  updatedAt: 10,
);

Map<String, Object?> _issueJson() => {
  'id': 'catalog-DDLU-61',
  'sourceEdition': 'DDLU',
  'series': 'Dylan Dog',
  'edition': 'Regularna (L)',
  'number': 61,
  'title': 'Nesmiljeni Hook',
  'publisher': 'Ludens',
};

CameraImage _nv21Image({required int width, required int height}) {
  final size = width * height * 3 ~/ 2;
  final bytes = Uint8List(size);
  for (var i = 0; i < width * height; i++) {
    bytes[i] = 16 + (i % 220);
  }
  for (var i = width * height; i < size; i += 2) {
    bytes[i] = 128;
    if (i + 1 < size) bytes[i + 1] = 128;
  }
  // ignore: deprecated_member_use
  return CameraImage.fromPlatformData({
    'format': 17,
    'height': height,
    'width': width,
    'planes': [
      {
        'bytes': bytes,
        'bytesPerPixel': 1,
        'bytesPerRow': width,
        'height': height,
        'width': width,
      },
    ],
  });
}
