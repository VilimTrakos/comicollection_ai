import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import 'data/catalog_repository.dart';
import 'data/collection_repository.dart';
import 'data/local_database.dart';
import 'data/settings_repository.dart';
import 'data/sync_service.dart';
import 'models/catalog_issue.dart';
import 'models/comic.dart';
import 'services/catalog_service.dart';
import 'services/sync_coordinator.dart';

/// UI-facing application state.
///
/// Persistence, preferences, catalogue bootstrapping and synchronization
/// scheduling are delegated to dedicated collaborators. The public API stays
/// intentionally small and backwards-compatible with existing widgets.
class AppController extends ChangeNotifier {
  AppController({
    LocalDatabase? db,
    CatalogRepository? catalog,
    SyncService? syncService,
    CollectionRepository? collectionRepository,
    SettingsRepository? settingsRepository,
    CatalogService? catalogService,
    SyncCoordinator? syncCoordinator,
    int Function()? nowMilliseconds,
    String Function()? idGenerator,
    Duration syncInterval = const Duration(minutes: 5),
  }) : _nowMilliseconds =
           nowMilliseconds ?? (() => DateTime.now().millisecondsSinceEpoch),
       _idGenerator = idGenerator ?? const Uuid().v4,
       db =
           db ??
           collectionRepository?.database ??
           catalogService?.collections.database ??
           syncCoordinator?.collections.database ??
           LocalDatabase(),
       catalog = catalog ?? catalogService?.catalog ?? CatalogRepository() {
    this.collectionRepository =
        collectionRepository ??
        catalogService?.collections ??
        syncCoordinator?.collections ??
        CollectionRepository(this.db);
    this.settingsRepository =
        settingsRepository ??
        catalogService?.settings ??
        syncCoordinator?.settings ??
        const SettingsRepository();
    this.catalogService =
        catalogService ??
        CatalogService(
          catalog: this.catalog,
          collections: this.collectionRepository,
          settings: this.settingsRepository,
          nowMilliseconds: _nowMilliseconds,
        );
    this.syncService =
        syncService ?? syncCoordinator?.syncService ?? SyncService(this.db);
    this.syncCoordinator =
        syncCoordinator ??
        SyncCoordinator(
          syncService: this.syncService,
          collections: this.collectionRepository,
          settings: this.settingsRepository,
          interval: syncInterval,
        );
  }

  final LocalDatabase db;
  final CatalogRepository catalog;
  final int Function() _nowMilliseconds;
  final String Function() _idGenerator;

  late final CollectionRepository collectionRepository;
  late final SettingsRepository settingsRepository;
  late final CatalogService catalogService;
  late final SyncService syncService;
  late final SyncCoordinator syncCoordinator;

  List<Comic> comics = [];
  bool loading = true;
  bool syncing = false;
  bool online = false;
  String? startupError;
  String syncMessage = 'Lokalna pohrana';
  bool darkMode = true;
  String accent = 'red';
  bool comicTitles = false;
  bool showStatistics = true;
  bool autoSync = true;
  bool newIssueNotifications = true;
  DateTime? lastSyncAt;

  Future<void> init() async {
    loading = true;
    startupError = null;
    notifyListeners();
    try {
      _applySettings(await settingsRepository.load());
      await catalogService.initialize();
      comics = await collectionRepository.load();
      if (autoSync) unawaited(sync());
      _scheduleAutoSync();
    } on Object catch (error, stackTrace) {
      startupError = error.toString();
      syncMessage = 'Greška lokalnih podataka';
      debugPrint('Pokretanje aplikacije nije uspjelo: $error');
      debugPrintStack(stackTrace: stackTrace);
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> save(Comic comic) async {
    final fresh = comic.copyWith(updatedAt: _nowMilliseconds());
    _publishOptimistic(fresh);
    try {
      await collectionRepository.upsert(fresh);
    } on Object {
      await reload();
      rethrow;
    }
    unawaited(sync());
  }

  Future<void> saveScanResults(Map<CatalogIssue, bool> results) async {
    final now = _nowMilliseconds();
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
    await collectionRepository.replaceAll(changes);
    await reload();
    unawaited(sync());
  }

  Future<void> saveAll(Iterable<Comic> changes) async {
    final now = _nowMilliseconds();
    final fresh = changes
        .map((comic) => comic.copyWith(updatedAt: now))
        .toList(growable: false);
    final byId = {for (final comic in comics) comic.id: comic};
    for (final comic in fresh) {
      if (comic.deleted) {
        byId.remove(comic.id);
      } else {
        byId[comic.id] = comic;
      }
    }
    comics = byId.values.toList(growable: false);
    notifyListeners();
    try {
      await collectionRepository.replaceAll(fresh);
    } on Object {
      await reload();
      rethrow;
    }
    unawaited(sync());
  }

  Future<void> linkBarcode(String barcode, CatalogIssue issue) =>
      catalogService.linkBarcode(barcode, issue);

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
    int rating = 0,
    int? pageCount,
    String writer = '',
    String artist = '',
  }) async {
    await save(
      Comic(
        id: _idGenerator(),
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
        rating: rating,
        pageCount: pageCount,
        writer: writer.trim(),
        artist: artist.trim(),
        updatedAt: _nowMilliseconds(),
      ),
    );
  }

  Future<void> remove(Comic comic) => save(comic.copyWith(deleted: true));

  Future<void> reload() async {
    comics = await collectionRepository.load();
    notifyListeners();
  }

  Future<void> sync({bool force = false}) async {
    if ((!autoSync && !force) || syncing || syncCoordinator.running) return;
    syncing = true;
    notifyListeners();
    try {
      final execution = await syncCoordinator.synchronize(
        enabled: autoSync,
        force: force,
      );
      if (execution == null) return;
      online = execution.result.ok;
      syncMessage = execution.result.message;
      if (execution.result.ok) {
        comics = execution.comics ?? await collectionRepository.load();
        if (execution.lastSyncAt != null) {
          lastSyncAt = execution.lastSyncAt;
        }
      }
    } finally {
      syncing = false;
      notifyListeners();
    }
  }

  Future<void> updatePreferences({
    bool? darkMode,
    String? accent,
    bool? comicTitles,
    bool? showStatistics,
    bool? autoSync,
    bool? newIssueNotifications,
  }) async {
    final updated = await settingsRepository.update(
      _currentSettings,
      darkMode: darkMode,
      accent: accent,
      comicTitles: comicTitles,
      showStatistics: showStatistics,
      autoSync: autoSync,
      newIssueNotifications: newIssueNotifications,
    );
    _applySettings(updated);
    if (autoSync != null) {
      if (autoSync) {
        unawaited(sync());
      } else {
        syncMessage = 'Automatska sinkronizacija isključena';
      }
      _scheduleAutoSync();
    }
    notifyListeners();
  }

  AppSettings get _currentSettings => AppSettings(
    darkMode: darkMode,
    accent: accent,
    comicTitles: comicTitles,
    showStatistics: showStatistics,
    autoSync: autoSync,
    newIssueNotifications: newIssueNotifications,
    lastSyncAt: lastSyncAt,
  );

  void _applySettings(AppSettings settings) {
    darkMode = settings.darkMode;
    accent = settings.accent;
    comicTitles = settings.comicTitles;
    showStatistics = settings.showStatistics;
    autoSync = settings.autoSync;
    newIssueNotifications = settings.newIssueNotifications;
    lastSyncAt = settings.lastSyncAt;
  }

  void _publishOptimistic(Comic fresh) {
    final next = List<Comic>.of(comics);
    final index = next.indexWhere((item) => item.id == fresh.id);
    if (fresh.deleted) {
      next.removeWhere((item) => item.id == fresh.id);
    } else if (index < 0) {
      next.add(fresh);
    } else {
      next[index] = fresh;
    }
    comics = next;
    notifyListeners();
  }

  void _scheduleAutoSync() {
    syncCoordinator.schedule(enabled: autoSync, action: sync);
  }

  @override
  void dispose() {
    syncCoordinator.dispose();
    super.dispose();
  }
}
