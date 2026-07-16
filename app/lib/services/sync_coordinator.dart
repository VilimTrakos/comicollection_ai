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

  bool get running => _running;

  Future<SyncExecution?> synchronize({
    required bool enabled,
    bool force = false,
  }) async {
    if ((!enabled && !force) || _running) return null;
    _running = true;
    try {
      final result = await syncService.sync();
      if (!result.ok) return SyncExecution(result: result);
      return SyncExecution(
        result: result,
        comics: await collections.load(),
        lastSyncAt: await settings.loadLastSyncAt(),
      );
    } finally {
      _running = false;
    }
  }

  void schedule({
    required bool enabled,
    required Future<void> Function() action,
  }) {
    _timer?.cancel();
    _timer = enabled
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
    _continuationTimer = enabled
        ? Timer(continuationDelay, () => unawaited(action()))
        : null;
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
    _continuationTimer?.cancel();
    _continuationTimer = null;
  }
}
