import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'data/local_database.dart';
import 'data/sync_service.dart';
import 'models/comic.dart';

class AppController extends ChangeNotifier {
  final db = LocalDatabase();
  late final SyncService syncService = SyncService(db);
  List<Comic> comics = [];
  bool loading = true;
  bool syncing = false;
  bool online = false;
  String syncMessage = 'Lokalna pohrana';
  Timer? _timer;

  Future<void> init() async {
    comics = await db.all();
    loading = false;
    notifyListeners();
    unawaited(sync());
    _timer = Timer.periodic(const Duration(minutes: 5), (_) => sync());
  }

  Future<void> save(Comic comic) async {
    final fresh = comic.copyWith(
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
    await db.upsert(fresh);
    await reload();
    unawaited(sync());
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
