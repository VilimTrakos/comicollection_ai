import 'package:shared_preferences/shared_preferences.dart';

class AppSettings {
  const AppSettings({
    this.darkMode = true,
    this.accent = 'red',
    this.comicTitles = false,
    this.showStatistics = true,
    this.autoSync = true,
    this.newIssueNotifications = true,
    this.lastSyncAt,
  });

  final bool darkMode;
  final String accent;
  final bool comicTitles;
  final bool showStatistics;
  final bool autoSync;
  final bool newIssueNotifications;
  final DateTime? lastSyncAt;

  AppSettings copyWith({
    bool? darkMode,
    String? accent,
    bool? comicTitles,
    bool? showStatistics,
    bool? autoSync,
    bool? newIssueNotifications,
  }) => AppSettings(
    darkMode: darkMode ?? this.darkMode,
    accent: accent ?? this.accent,
    comicTitles: comicTitles ?? this.comicTitles,
    showStatistics: showStatistics ?? this.showStatistics,
    autoSync: autoSync ?? this.autoSync,
    newIssueNotifications: newIssueNotifications ?? this.newIssueNotifications,
    lastSyncAt: lastSyncAt,
  );
}

class SettingsRepository {
  const SettingsRepository({this.namespace = ''});

  final String namespace;

  static const _catalogVersionKey = 'catalog_version';
  static const _v2LastSuccessfulSyncKey = 'last_successful_sync_v2';

  Future<AppSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    return AppSettings(
      darkMode: prefs.getBool(_key('dark_mode')) ?? true,
      accent: prefs.getString(_key('accent')) ?? 'red',
      comicTitles: prefs.getBool(_key('comic_titles')) ?? false,
      showStatistics: prefs.getBool(_key('show_statistics')) ?? true,
      autoSync: prefs.getBool(_key('auto_sync')) ?? true,
      newIssueNotifications:
          prefs.getBool(_key('new_issue_notifications')) ?? true,
      lastSyncAt: _dateFromMilliseconds(
        prefs.getInt(_key(_v2LastSuccessfulSyncKey)) ??
            prefs.getInt(_key('last_sync')),
      ),
    );
  }

  Future<AppSettings> update(
    AppSettings current, {
    bool? darkMode,
    String? accent,
    bool? comicTitles,
    bool? showStatistics,
    bool? autoSync,
    bool? newIssueNotifications,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    if (darkMode != null) await prefs.setBool(_key('dark_mode'), darkMode);
    if (accent != null) await prefs.setString(_key('accent'), accent);
    if (comicTitles != null) {
      await prefs.setBool(_key('comic_titles'), comicTitles);
    }
    if (showStatistics != null) {
      await prefs.setBool(_key('show_statistics'), showStatistics);
    }
    if (autoSync != null) await prefs.setBool(_key('auto_sync'), autoSync);
    if (newIssueNotifications != null) {
      await prefs.setBool(
        _key('new_issue_notifications'),
        newIssueNotifications,
      );
    }
    return current.copyWith(
      darkMode: darkMode,
      accent: accent,
      comicTitles: comicTitles,
      showStatistics: showStatistics,
      autoSync: autoSync,
      newIssueNotifications: newIssueNotifications,
    );
  }

  Future<DateTime?> loadLastSyncAt() async {
    final prefs = await SharedPreferences.getInstance();
    return _dateFromMilliseconds(
      prefs.getInt(_key(_v2LastSuccessfulSyncKey)) ??
          prefs.getInt(_key('last_sync')),
    );
  }

  Future<int> loadCatalogVersion() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_key(_catalogVersionKey)) ?? 0;
  }

  Future<void> saveCatalogVersion(int version) async {
    if (version <= 0) {
      throw ArgumentError.value(version, 'version', 'must be positive');
    }
    final prefs = await SharedPreferences.getInstance();
    final saved = await prefs.setInt(_key(_catalogVersionKey), version);
    if (!saved) {
      throw StateError('Catalog version could not be persisted.');
    }
  }

  /// Legacy starter flags retained only for backwards-compatible preference
  /// reads. Catalog refreshes use the stable catalog_version key above.
  Future<bool> isStarterCatalogSeeded() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_key('starter_catalog_v3')) ?? false;
  }

  Future<void> markStarterCatalogSeeded() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key('starter_catalog_v1'), true);
    await prefs.setBool(_key('starter_catalog_v2'), true);
    await prefs.setBool(_key('starter_catalog_v3'), true);
  }

  String _key(String value) => namespace.isEmpty ? value : '$namespace.$value';

  static DateTime? _dateFromMilliseconds(int? value) =>
      value == null ? null : DateTime.fromMillisecondsSinceEpoch(value);
}
