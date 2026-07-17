import 'package:shared_preferences/shared_preferences.dart';

import 'api_token_store.dart';

export 'api_token_store.dart';

class SyncSettings {
  const SyncSettings({
    this.serverUrl = '',
    this.apiToken = '',
    this.cursor = 0,
    this.lastSuccessfulSyncAt,
  });

  final String serverUrl;
  final String apiToken;
  final int cursor;
  final DateTime? lastSuccessfulSyncAt;

  bool get isConfigured =>
      serverUrl.trim().isNotEmpty && apiToken.trim().isNotEmpty;

  String get normalizedServerUrl =>
      serverUrl.trim().replaceFirst(RegExp(r'/+$'), '');
}

/// Typed persistence boundary for server connection settings and sync cursor.
class SyncSettingsRepository {
  const SyncSettingsRepository({
    this.apiTokenStore = const SecureApiTokenStore(),
    this.namespace = '',
  });

  static const suggestedServerUrl = 'https://sync.example.com';
  static const _serverUrlKey = 'server_url';
  static const _cursorKey = 'last_sync';
  static const _lastSuccessfulSyncKey = 'last_successful_sync_v2';

  final ApiTokenStore apiTokenStore;
  final String namespace;

  Future<SyncSettings> load({bool includeApiToken = true}) async {
    final preferences = await SharedPreferences.getInstance();
    return SyncSettings(
      serverUrl: preferences.getString(_key(_serverUrlKey)) ?? '',
      apiToken: includeApiToken ? await apiTokenStore.read() : '',
      cursor: preferences.getInt(_key(_cursorKey)) ?? 0,
      lastSuccessfulSyncAt: switch (preferences.getInt(
        _key(_lastSuccessfulSyncKey),
      )) {
        final milliseconds? => DateTime.fromMillisecondsSinceEpoch(
          milliseconds,
        ),
        null => null,
      },
    );
  }

  Future<void> saveConnection({
    required String serverUrl,
    required String apiToken,
  }) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_key(_serverUrlKey), serverUrl.trim());
    await apiTokenStore.write(apiToken.trim());
  }

  Future<void> saveCursor(int cursor) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setInt(_key(_cursorKey), cursor);
  }

  /// Records user-facing v2 success time without changing the legacy v1
  /// `last_sync` cursor. The authoritative v2 revision cursor lives in SQLite.
  Future<void> saveLastSuccessfulSyncAt(DateTime timestamp) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setInt(
      _key(_lastSuccessfulSyncKey),
      timestamp.millisecondsSinceEpoch,
    );
  }

  Future<void> clearLastSuccessfulSyncAt() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_key(_lastSuccessfulSyncKey));
  }

  /// Clears every server-scoped cursor when the user explicitly selects a
  /// different server. Connection values and local application data remain.
  Future<void> resetForNewServer() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_key(_cursorKey));
    await preferences.remove(_key(_lastSuccessfulSyncKey));
  }

  String _key(String value) => namespace.isEmpty ? value : '$namespace.$value';
}
