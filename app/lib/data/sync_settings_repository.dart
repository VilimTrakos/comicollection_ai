import 'package:shared_preferences/shared_preferences.dart';

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

/// Boundary for secret persistence.
///
/// The default implementation keeps backwards compatibility with existing
/// installations. Before production release, inject an implementation backed
/// by Android Keystore / iOS Keychain without changing the sync or UI layers.
abstract interface class ApiTokenStore {
  Future<String> read();

  Future<void> write(String token);
}

class SharedPreferencesApiTokenStore implements ApiTokenStore {
  const SharedPreferencesApiTokenStore();

  static const _key = 'api_token';

  @override
  Future<String> read() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getString(_key) ?? '';
  }

  @override
  Future<void> write(String token) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_key, token);
  }
}

/// Typed persistence boundary for server connection settings and sync cursor.
class SyncSettingsRepository {
  const SyncSettingsRepository({
    this.apiTokenStore = const SharedPreferencesApiTokenStore(),
  });

  static const suggestedServerUrl = 'http://192.168.1.50:8787';
  static const _serverUrlKey = 'server_url';
  static const _cursorKey = 'last_sync';
  static const _lastSuccessfulSyncKey = 'last_successful_sync_v2';

  final ApiTokenStore apiTokenStore;

  Future<SyncSettings> load() async {
    final preferences = await SharedPreferences.getInstance();
    return SyncSettings(
      serverUrl: preferences.getString(_serverUrlKey) ?? '',
      apiToken: await apiTokenStore.read(),
      cursor: preferences.getInt(_cursorKey) ?? 0,
      lastSuccessfulSyncAt: switch (preferences.getInt(
        _lastSuccessfulSyncKey,
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
    await preferences.setString(_serverUrlKey, serverUrl.trim());
    await apiTokenStore.write(apiToken.trim());
  }

  Future<void> saveCursor(int cursor) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setInt(_cursorKey, cursor);
  }

  /// Records user-facing v2 success time without changing the legacy v1
  /// `last_sync` cursor. The authoritative v2 revision cursor lives in SQLite.
  Future<void> saveLastSuccessfulSyncAt(DateTime timestamp) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setInt(
      _lastSuccessfulSyncKey,
      timestamp.millisecondsSinceEpoch,
    );
  }

  Future<void> clearLastSuccessfulSyncAt() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_lastSuccessfulSyncKey);
  }

  /// Clears every server-scoped cursor when the user explicitly selects a
  /// different server. Connection values and local application data remain.
  Future<void> resetForNewServer() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_cursorKey);
    await preferences.remove(_lastSuccessfulSyncKey);
  }
}
