import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import 'data/catalog_repository.dart';
import 'data/collection_repository.dart';
import 'data/local_database.dart';
import 'data/release_watch_repository.dart';
import 'data/search_history_repository.dart';
import 'data/settings_repository.dart';
import 'data/sync_service.dart';
import 'models/catalog_issue.dart';
import 'models/comic.dart';
import 'services/catalog_service.dart';
import 'services/sync_coordinator.dart';
import 'state/selected_value_listenable.dart';

typedef AppAppearance = ({bool darkMode, String accent, bool comicTitles});
typedef AppStartupStatus = ({bool loading, String? error});
typedef AppSyncStatus = ({
  bool syncing,
  bool online,
  String message,
  DateTime? lastSyncAt,
});
typedef AppPreferenceState = ({
  bool darkMode,
  String accent,
  bool comicTitles,
  bool showStatistics,
  bool autoSync,
  bool newIssueNotifications,
});

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
    ReleaseWatchRepository? releaseWatchRepository,
    SearchHistoryRepository? searchHistoryRepository,
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
    this.releaseWatchRepository =
        releaseWatchRepository ?? const ReleaseWatchRepository();
    this.searchHistoryRepository =
        searchHistoryRepository ?? const SearchHistoryRepository();
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
    appearanceChanges = SelectedValueListenable(
      source: this,
      select: () =>
          (darkMode: darkMode, accent: accent, comicTitles: comicTitles),
    );
    startupChanges = SelectedValueListenable(
      source: this,
      select: () => (loading: loading, error: startupError),
    );
    collectionChanges = SelectedValueListenable(
      source: this,
      select: () => comics,
    );
    syncChanges = SelectedValueListenable(
      source: this,
      select: () => (
        syncing: syncing,
        online: online,
        message: syncMessage,
        lastSyncAt: lastSyncAt,
      ),
    );
    preferenceChanges = SelectedValueListenable(
      source: this,
      select: () => (
        darkMode: darkMode,
        accent: accent,
        comicTitles: comicTitles,
        showStatistics: showStatistics,
        autoSync: autoSync,
        newIssueNotifications: newIssueNotifications,
      ),
    );
  }

  final LocalDatabase db;
  final CatalogRepository catalog;
  final int Function() _nowMilliseconds;
  final String Function() _idGenerator;

  late final CollectionRepository collectionRepository;
  late final ReleaseWatchRepository releaseWatchRepository;
  late final SearchHistoryRepository searchHistoryRepository;
  late final SettingsRepository settingsRepository;
  late final CatalogService catalogService;
  late final SyncService syncService;
  late final SyncCoordinator syncCoordinator;
  late final SelectedValueListenable<AppAppearance> appearanceChanges;
  late final SelectedValueListenable<AppStartupStatus> startupChanges;
  late final SelectedValueListenable<List<Comic>> collectionChanges;
  late final SelectedValueListenable<AppSyncStatus> syncChanges;
  late final SelectedValueListenable<AppPreferenceState> preferenceChanges;

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
  bool _acceptingOperations = true;
  final Set<Future<void>> _activeOperations = {};
  bool _acceptingSync = true;
  Future<void>? _activeSync;

  Future<void> init() => _runOperation(_initialize);

  Future<void> _initialize() async {
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

  Future<void> save(Comic comic) => _runOperation(() => _save(comic));

  Future<void> _save(Comic comic) async {
    final fresh = comic.copyWith(updatedAt: _nowMilliseconds());
    _publishOptimistic(fresh);
    try {
      await collectionRepository.upsert(fresh);
    } on Object {
      await _reload();
      rethrow;
    }
    unawaited(sync());
  }

  Future<void> saveScanResults(Map<CatalogIssue, bool> results) =>
      _runOperation(() => _saveScanResults(results));

  Future<void> _saveScanResults(Map<CatalogIssue, bool> results) async {
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
    await _reload();
    unawaited(sync());
  }

  Future<void> saveAll(Iterable<Comic> changes) =>
      _runOperation(() => _saveAll(changes));

  Future<void> _saveAll(Iterable<Comic> changes) async {
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
      await _reload();
      rethrow;
    }
    unawaited(sync());
  }

  Future<void> linkBarcode(String barcode, CatalogIssue issue) =>
      _runOperation(() => catalogService.linkBarcode(barcode, issue));

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
  }) => _runOperation(
    () => _save(
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
    ),
  );

  Future<void> remove(Comic comic) =>
      _runOperation(() => _save(comic.copyWith(deleted: true)));

  Future<void> reload() => _runOperation(_reload);

  Future<void> _reload() async {
    comics = await collectionRepository.load();
    notifyListeners();
  }

  Future<void> sync({bool force = false}) {
    if (!_acceptingSync ||
        (!autoSync && !force) ||
        syncing ||
        syncCoordinator.running) {
      return Future.value();
    }
    late final Future<void> operation;
    operation = _synchronize(force: force).whenComplete(() {
      if (identical(_activeSync, operation)) _activeSync = null;
    });
    _activeSync = operation;
    return operation;
  }

  Future<void> _synchronize({required bool force}) async {
    syncing = true;
    var continueSync = false;
    notifyListeners();
    try {
      final execution = await syncCoordinator.synchronize(
        enabled: autoSync,
        force: force,
      );
      if (execution == null) return;
      online = execution.result.ok;
      syncMessage = execution.result.message;
      continueSync = execution.result.ok && execution.result.hasPending;
      if (execution.result.ok) {
        comics = execution.comics ?? await collectionRepository.load();
        if (execution.lastSyncAt != null) {
          lastSyncAt = execution.lastSyncAt;
        }
      }
    } finally {
      syncing = false;
      notifyListeners();
      if (continueSync) {
        syncCoordinator.scheduleContinuation(
          enabled: autoSync || force,
          action: () => sync(force: force),
        );
      }
    }
  }

  Future<void> resetSyncServerBinding() =>
      _runOperation(_resetSyncServerBinding);

  Future<void> _resetSyncServerBinding() async {
    if (syncing || syncCoordinator.running) {
      throw StateError('Sinkronizacija je trenutačno aktivna.');
    }
    await syncService.resetServerBinding();
    online = false;
    lastSyncAt = null;
    syncMessage = 'Spremno za povezivanje s novim serverom';
    notifyListeners();
  }

  Future<void> updatePreferences({
    bool? darkMode,
    String? accent,
    bool? comicTitles,
    bool? showStatistics,
    bool? autoSync,
    bool? newIssueNotifications,
  }) => _runOperation(
    () => _updatePreferences(
      darkMode: darkMode,
      accent: accent,
      comicTitles: comicTitles,
      showStatistics: showStatistics,
      autoSync: autoSync,
      newIssueNotifications: newIssueNotifications,
    ),
  );

  Future<void> _updatePreferences({
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

  Future<void> _runOperation(Future<void> Function() action) {
    if (!_acceptingOperations) {
      return Future.error(StateError('Application runtime is shutting down.'));
    }
    late final Future<void> operation;
    operation = Future<void>.sync(action).whenComplete(() {
      _activeOperations.remove(operation);
    });
    _activeOperations.add(operation);
    return operation;
  }

  /// Prevents new work and drains every operation which may still touch this
  /// runtime's database, preferences, authentication or notifier state.
  Future<void> quiesce() async {
    _acceptingOperations = false;
    _acceptingSync = false;
    final activeSync = _activeSync;
    Object? failure;
    StackTrace? failureStack;

    Future<void> drain(Future<dynamic>? operation) async {
      if (operation == null) return;
      try {
        await operation;
      } on Object catch (error, stackTrace) {
        if (failure == null) {
          failure = error;
          failureStack = stackTrace;
        }
      }
    }

    await drain(syncCoordinator.quiesce());
    await drain(activeSync);
    while (_activeOperations.isNotEmpty) {
      final active = List<Future<void>>.of(_activeOperations);
      await Future.wait(active.map(drain));
    }
    if (failure case final error?) {
      Error.throwWithStackTrace(error, failureStack!);
    }
  }

  @override
  void dispose() {
    _acceptingOperations = false;
    _acceptingSync = false;
    syncCoordinator.dispose();
    appearanceChanges.dispose();
    startupChanges.dispose();
    collectionChanges.dispose();
    syncChanges.dispose();
    preferenceChanges.dispose();
    super.dispose();
  }
}
