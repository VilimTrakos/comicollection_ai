import 'package:shared_preferences/shared_preferences.dart';

/// Stores the catalogue issue IDs for which the user wants notifications.
class ReleaseWatchRepository {
  const ReleaseWatchRepository();

  static const _key = 'release_watch_ids';

  Future<Set<String>> load() async {
    final preferences = await SharedPreferences.getInstance();
    return Set.unmodifiable(preferences.getStringList(_key) ?? const []);
  }

  Future<Set<String>> toggle(String issueId, Set<String> current) async {
    final next = {...current};
    if (!next.add(issueId)) next.remove(issueId);

    final preferences = await SharedPreferences.getInstance();
    await preferences.setStringList(_key, next.toList(growable: false));
    return Set.unmodifiable(next);
  }
}
