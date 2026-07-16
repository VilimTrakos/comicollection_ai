import '../models/collection_entry.dart';
import '../models/comic.dart';
import '../models/comic_copy.dart';
import '../models/sync_v2.dart';
import 'local_database.dart';

/// Persistence boundary for the user's collection.
///
/// UI state never needs to know which database implementation is used. The
/// concrete SQLite database remains exposed for the sync transport while the
/// controller talks only through this repository.
class CollectionRepository {
  CollectionRepository(this.database);

  final LocalDatabase database;

  Future<List<Comic>> load() => database.all();

  Future<void> upsert(Comic comic) => database.upsert(comic);

  Future<void> replaceAll(Iterable<Comic> comics) =>
      database.replaceAll(comics);

  Future<void> upsertCatalogAll(Iterable<Comic> comics) =>
      database.upsertCatalogAll(comics);

  Future<CollectionEntry?> entryFor(String issueId) =>
      database.collectionEntry(issueId);

  Future<List<ComicCopy>> copiesFor(String issueId) =>
      database.copiesForIssue(issueId);

  Future<void> saveCopy(ComicCopy copy) => database.saveCopy(copy);

  Future<Map<String, String>> barcodeMappings() => database.barcodeMappings();

  Future<void> saveBarcodeMapping(String barcode, String comicId) =>
      database.saveBarcodeMapping(barcode, comicId);

  Future<SyncUploadBatch> prepareSyncV2({
    int limit = 100,
    int legacyCursor = 0,
  }) => database.prepareSyncV2(limit: limit, legacyCursor: legacyCursor);

  Future<bool> hasPendingSyncV2() => database.hasPendingSyncV2();

  Future<void> applySyncV2(SyncV2Exchange exchange) =>
      database.applySyncV2(exchange);

  Future<void> resetSyncV2Binding() => database.resetSyncV2Binding();
}
