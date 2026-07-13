import 'package:comicollect/data/catalog_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('bundled BSP catalog and visual signatures are complete', () async {
    final catalog = CatalogRepository();
    await catalog.load();

    expect(catalog.issues, hasLength(190));
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
}
