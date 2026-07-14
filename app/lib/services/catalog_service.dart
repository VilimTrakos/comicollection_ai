import '../data/catalog_repository.dart';
import '../data/collection_repository.dart';
import '../data/settings_repository.dart';
import '../models/catalog_issue.dart';
import '../models/comic.dart';

class CatalogService {
  CatalogService({
    required this.catalog,
    required this.collections,
    required this.settings,
    required this.nowMilliseconds,
  });

  final CatalogRepository catalog;
  final CollectionRepository collections;
  final SettingsRepository settings;
  final int Function() nowMilliseconds;

  Future<void> initialize() async {
    await catalog.load();
    await _seedStarterCatalog();
    final mappings = await collections.barcodeMappings();
    for (final entry in mappings.entries) {
      final issue = catalog.byId(entry.value);
      if (issue != null) catalog.registerBarcode(entry.key, issue);
    }
  }

  Future<void> linkBarcode(String barcode, CatalogIssue issue) async {
    final normalized = barcode.trim();
    await collections.saveBarcodeMapping(normalized, issue.id);
    catalog.registerBarcode(normalized, issue);
  }

  Future<void> _seedStarterCatalog() async {
    if (await settings.isStarterCatalogSeeded()) return;
    final now = nowMilliseconds();
    final issues = <Comic>[];

    void edition({
      required String code,
      required String name,
      required String publisher,
      required int first,
      required int last,
      int? firstYear,
    }) {
      for (var number = first; number <= last; number++) {
        issues.add(
          Comic(
            id: 'catalog-$code-$number',
            series: 'Dylan Dog',
            edition: name,
            number: number,
            title: 'Dylan Dog #$number',
            publisher: publisher,
            year: firstYear == null
                ? null
                : firstYear + ((number - first) ~/ 12),
            owned: false,
            read: false,
            condition: 'F',
            notes: 'Početni katalog · BSP oznaka $code',
            updatedAt: now,
          ),
        );
      }
    }

    edition(
      code: 'DESD',
      name: 'Extra (SD)',
      publisher: 'Slobodna Dalmacija',
      first: 1,
      last: 12,
      firstYear: 1999,
    );
    edition(
      code: 'DELU',
      name: 'Extra (L)',
      publisher: 'Ludens',
      first: 13,
      last: 166,
      firstYear: 2002,
    );
    edition(
      code: 'DDSD',
      name: 'Regularna (SD)',
      publisher: 'Slobodna Dalmacija',
      first: 1,
      last: 60,
      firstYear: 1994,
    );
    edition(
      code: 'DDLU',
      name: 'Regularna (L)',
      publisher: 'Ludens',
      first: 61,
      last: 201,
      firstYear: 2002,
    );
    issues.addAll(catalog.issues.map((issue) => issue.toComic()));

    await collections.upsertCatalogAll(issues);
    await settings.markStarterCatalogSeeded();
  }
}
