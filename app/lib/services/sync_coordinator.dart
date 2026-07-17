import 'dart:async';

import '../data/collection_repository.dart';
import '../data/settings_repository.dart';
import '../data/sync_service.dart';
import '../models/comic.dart';

class SyncExecution {
  const SyncExecution({required this.result, this.comics, this.lastSyncAt});

  final SyncResult result;
  final List<Comic>? comics;
  final DateTime? lastSyncAt;
}

class SyncCoordinator {
  SyncCoordinator({
    required this.syncService,
    required this.collections,
    required this.settings,
    this.interval = const Duration(minutes: 5),
    this.continuationDelay = const Duration(seconds: 2),
  });

  final SyncService syncService;
  final CollectionRepository collections;
  final SettingsRepository settings;
  final Duration interval;
  final Duration continuationDelay;

  Timer? _timer;
  Timer? _continuationTimer;
  bool _running = false;
  bool _acceptingWork = true;
  Future<SyncExecution?>? _activeSynchronization;

  bool get running => _running;

  Future<SyncExecution?> synchronize({
    required bool enabled,
    bool force = false,
  }) {
    if ((!enabled && !force) || !_acceptingWork || _running) {
      return Future.value(null);
    }
    _running = true;
    late final Future<SyncExecution?> operation;
    operation = _executeSynchronization().whenComplete(() {
      _running = false;
      if (identical(_activeSynchronization, operation)) {
        _activeSynchronization = null;
      }
    });
    _activeSynchronization = operation;
    return operation;
  }

  Future<SyncExecution?> _executeSynchronization() async {
    final result = await syncService.sync();
    if (!result.ok) return SyncExecution(result: result);
    return SyncExecution(
      result: result,
      comics: await collections.load(),
      lastSyncAt: await settings.loadLastSyncAt(),
    );
  }

  void schedule({
    required bool enabled,
    required Future<void> Function() action,
  }) {
    _timer?.cancel();
    _timer = enabled && _acceptingWork
        ? Timer.periodic(interval, (_) => unawaited(action()))
        : null;
    if (!enabled) {
      _continuationTimer?.cancel();
      _continuationTimer = null;
    }
  }

  void scheduleContinuation({
    required bool enabled,
    required Future<void> Function() action,
  }) {
    _continuationTimer?.cancel();
    _continuationTimer = enabled && _acceptingWork
        ? Timer(continuationDelay, () => unawaited(action()))
        : null;
  }

  /// Stops new work and waits until the current synchronization has released
  /// every database and authentication dependency owned by this runtime.
  Future<void> quiesce() async {
    _acceptingWork = false;
    _cancelTimers();
    await _activeSynchronization;
  }

  void dispose() {
    _acceptingWork = false;
    _cancelTimers();
  }

  void _cancelTimers() {
    _timer?.cancel();
    _timer = null;
    _continuationTimer?.cancel();
    _continuationTimer = null;
  }
}
