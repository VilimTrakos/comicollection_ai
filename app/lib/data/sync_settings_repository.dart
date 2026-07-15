import 'package:shared_preferences/shared_preferences.dart';

class SyncSettings {
  const SyncSettings({
    this.serverUrl = '',
    this.apiToken = '',
    this.cursor = 0,
  });

  final String serverUrl;
  final String apiToken;
  final int cursor;

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

  final ApiTokenStore apiTokenStore;

  Future<SyncSettings> load() async {
    final preferences = await SharedPreferences.getInstance();
    return SyncSettings(
      serverUrl: preferences.getString(_serverUrlKey) ?? '',
      apiToken: await apiTokenStore.read(),
      cursor: preferences.getInt(_cursorKey) ?? 0,
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
}
