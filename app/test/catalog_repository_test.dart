import 'package:comicollect/data/catalog_repository.dart';
import 'package:comicollect/services/visual_signature.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('bundled BSP catalog and visual signatures are complete', () async {
    final catalog = CatalogRepository();
    await catalog.load();

    expect(catalog.catalogVersion, 1);
    expect(catalog.issues, hasLength(228));
    final issue = catalog.byId('catalog-DDLU-61');
    expect(issue, isNotNull);
    expect(issue!.title, 'Nesmiljeni Hook');
    expect(issue.coverAsset, 'assets/catalog/covers/ddlu/0061.webp');

    final matches = catalog.matchVisual(
      visualHash: issue.visualHash!,
      colorSignature: issue.colorSignature!,
    );
    expect(matches.first.issue.id, issue.id);
    expect(matches.first.score, closeTo(1, .0001));
  });

  test('OCR-style text finds an issue by series and number', () async {
    final catalog = CatalogRepository();
    await catalog.load();

    final matches = catalog.matchText('DYLAN DOG 66');
    expect(matches.first.id, 'catalog-DDLU-66');
  });

  test('cover loaded from gallery matches its bundled catalog issue', () async {
    final catalog = CatalogRepository();
    await catalog.load();
    final bytes = await rootBundle.load('assets/catalog/covers/ddlu/0061.webp');
    final image = img.decodeImage(bytes.buffer.asUint8List());

    expect(image, isNotNull);
    final signature = VisualSignatureExtractor.fromImage(image!);
    final matches = catalog.matchVisual(
      visualHash: signature.visualHash,
      colorSignature: signature.colorSignature,
    );

    expect(matches.first.issue.id, 'catalog-DDLU-61');
    expect(matches.first.score, greaterThan(.70));
  });

  test('bundled catalog includes Maxi and Old Boy issues', () async {
    final catalog = CatalogRepository();
    await catalog.load();

    final oldBoy = catalog.byId('catalog-DMLU-25');
    expect(oldBoy, isNotNull);
    expect(oldBoy!.edition, 'Maxi (L)');
    expect(oldBoy.title, 'Halloween Express');
    expect(oldBoy.coverAsset, 'assets/catalog/covers/dmlu/0025.webp');

    final bytes = await rootBundle.load(oldBoy.coverAsset!);
    final image = img.decodeImage(bytes.buffer.asUint8List());
    final signature = VisualSignatureExtractor.fromImage(image!);
    final matches = catalog.matchVisual(
      visualHash: signature.visualHash,
      colorSignature: signature.colorSignature,
    );
    expect(matches.first.issue.id, oldBoy.id);
  });

  test('load is idempotent and unknown ids and barcodes return null', () async {
    final catalog = CatalogRepository();
    await catalog.load();
    final original = catalog.issues;
    await catalog.load();

    expect(identical(catalog.issues, original), isTrue);
    expect(catalog.byId('missing'), isNull);
    expect(catalog.byBarcode('missing'), isNull);
  });

  test(
    'barcode registration trims values, replaces mappings and ignores empty',
    () async {
      final catalog = CatalogRepository();
      await catalog.load();
      final first = catalog.byId('catalog-DDLU-61')!;
      final second = catalog.byId('catalog-DDLU-62')!;

      catalog.registerBarcode(' 123456 ', first);
      expect(catalog.byBarcode('123456'), same(first));
      catalog.registerBarcode('123456', second);
      expect(catalog.byBarcode(' 123456 '), same(second));
      catalog.registerBarcode('  ', first);
      expect(catalog.byBarcode(''), isNull);
    },
  );

  test('normalization removes Croatian diacritics and punctuation', () {
    expect(
      CatalogRepository.normalize(' Čuvar Đavolje šume, žar! '),
      'CUVAR DAVOLJE SUME ZAR',
    );
    expect(CatalogRepository.normalize('---'), isEmpty);
  });

  test('text matching handles empty, title and result limits', () async {
    final catalog = CatalogRepository();
    await catalog.load();

    expect(catalog.matchText(''), isEmpty);
    expect(catalog.matchText('!?!'), isEmpty);
    final byTitle = catalog.matchText('NESMILJENI HOOK');
    expect(byTitle.first.id, 'catalog-DDLU-61');
    expect(catalog.matchText('DYLAN DOG', limit: 2), hasLength(2));
  });

  test(
    'visual matching respects limit and penalizes different signatures',
    () async {
      final catalog = CatalogRepository();
      await catalog.load();
      final issue = catalog.byId('catalog-DDLU-61')!;

      final exact = catalog.matchVisual(
        visualHash: issue.visualHash!,
        colorSignature: issue.colorSignature!,
        limit: 1,
      );
      final different = catalog.matchVisual(
        visualHash: 'ffffffffffffffff',
        colorSignature: Uint8List(48),
        limit: 3,
      );

      expect(exact, hasLength(1));
      expect(exact.single.score, closeTo(1, .0001));
      expect(different, hasLength(3));
      expect(
        different.every((match) => match.score >= 0 && match.score <= 1),
        isTrue,
      );
    },
  );
}
