import 'dart:io';

import 'local_database.dart';
import 'sync_settings_repository.dart';
import 'sync_transport.dart';

class SyncResult {
  const SyncResult(this.ok, this.message);
  final bool ok;
  final String message;
}

class SyncService {
  SyncService(
    this.db, {
    SyncSettingsRepository? settingsRepository,
    SyncTransport? transport,
    HttpClient Function()? clientFactory,
  }) : settingsRepository =
           settingsRepository ?? const SyncSettingsRepository(),
       transport = transport ?? HttpSyncTransport(clientFactory: clientFactory);

  final LocalDatabase db;
  final SyncSettingsRepository settingsRepository;
  final SyncTransport transport;

  Future<SyncResult> sync() async {
    final settings = await settingsRepository.load();
    if (!settings.isConfigured) {
      return const SyncResult(false, 'Server nije podešen');
    }
    final changes = await db.changedSince(settings.cursor);
    try {
      final exchange = await transport.exchange(
        serverUrl: settings.normalizedServerUrl,
        apiToken: settings.apiToken.trim(),
        since: settings.cursor,
        changes: changes,
      );
      await db.mergeRemote(exchange.changes);
      await settingsRepository.saveCursor(exchange.serverTime);
      return const SyncResult(true, 'Sinkronizirano');
    } on SyncServerException catch (error) {
      return SyncResult(false, 'Server: ${error.statusCode}');
    } on FormatException {
      return const SyncResult(false, 'Offline · spremljeno lokalno');
    } on ArgumentError {
      return const SyncResult(false, 'Offline · spremljeno lokalno');
    } on Exception {
      return const SyncResult(false, 'Offline · spremljeno lokalno');
    }
  }
}
