import '../models/comic.dart';
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

  Future<Map<String, String>> barcodeMappings() => database.barcodeMappings();

  Future<void> saveBarcodeMapping(String barcode, String comicId) =>
      database.saveBarcodeMapping(barcode, comicId);
}
