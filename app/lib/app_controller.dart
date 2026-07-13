import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'data/local_database.dart';
import 'data/catalog_repository.dart';
import 'data/sync_service.dart';
import 'models/comic.dart';
import 'models/catalog_issue.dart';

class AppController extends ChangeNotifier {
  final db = LocalDatabase();
  final catalog = CatalogRepository();
  late final SyncService syncService = SyncService(db);
  List<Comic> comics = [];
  bool loading = true;
  bool syncing = false;
  bool online = false;
  String syncMessage = 'Lokalna pohrana';
  Timer? _timer;

  Future<void> init() async {
    await catalog.load();
    await _seedStarterCatalog();
    final mappings = await db.barcodeMappings();
    for (final entry in mappings.entries) {
      final issue = catalog.byId(entry.value);
      if (issue != null) catalog.registerBarcode(entry.key, issue);
    }
    comics = await db.all();
    loading = false;
    notifyListeners();
    unawaited(sync());
    _timer = Timer.periodic(const Duration(minutes: 5), (_) => sync());
  }

  Future<void> _seedStarterCatalog() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('starter_catalog_v2') ?? false) return;
    final now = DateTime.now().millisecondsSinceEpoch;
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

    // Starter catalogue follows the publisher/number ranges documented by BSP.
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

    await db.upsertCatalogAll(issues);
    await prefs.setBool('starter_catalog_v1', true);
    await prefs.setBool('starter_catalog_v2', true);
  }

  Future<void> save(Comic comic) async {
    final fresh = comic.copyWith(
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
    await db.upsert(fresh);
    await reload();
    unawaited(sync());
  }

  Future<void> saveScanResults(Map<CatalogIssue, bool> results) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final currentById = {for (final comic in comics) comic.id: comic};
    final changes = <Comic>[];
    for (final entry in results.entries) {
      final existing = currentById[entry.key.id] ?? entry.key.toComic();
      changes.add(
        existing.copyWith(
          owned: entry.value,
          coverAsset: entry.key.coverAsset ?? existing.coverAsset,
          updatedAt: now,
        ),
      );
    }
    await db.replaceAll(changes);
    await reload();
    unawaited(sync());
  }

  Future<void> linkBarcode(String barcode, CatalogIssue issue) async {
    await db.saveBarcodeMapping(barcode.trim(), issue.id);
    catalog.registerBarcode(barcode, issue);
  }

  Future<void> add({
    required String series,
    required String edition,
    required int number,
    required String title,
    String publisher = '',
    int? year,
    bool owned = true,
    bool read = false,
    String condition = 'F',
    double? purchasePrice,
    double? estimatedValue,
    bool duplicate = false,
    String loanedTo = '',
    String notes = '',
  }) async {
    await save(
      Comic(
        id: const Uuid().v4(),
        series: series.trim(),
        edition: edition.trim(),
        number: number,
        title: title.trim(),
        publisher: publisher.trim(),
        year: year,
        owned: owned,
        read: read,
        condition: condition,
        purchasePrice: purchasePrice,
        estimatedValue: estimatedValue,
        duplicate: duplicate,
        loanedTo: loanedTo.trim(),
        notes: notes.trim(),
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }

  Future<void> remove(Comic comic) => save(comic.copyWith(deleted: true));

  Future<void> reload() async {
    comics = await db.all();
    notifyListeners();
  }

  Future<void> sync() async {
    if (syncing) return;
    syncing = true;
    notifyListeners();
    final result = await syncService.sync();
    syncing = false;
    online = result.ok;
    syncMessage = result.message;
    if (result.ok) comics = await db.all();
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
