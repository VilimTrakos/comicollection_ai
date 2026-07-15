import 'package:shared_preferences/shared_preferences.dart';

/// Persists the small, ordered list of queries shown on the search screen.
class SearchHistoryRepository {
  const SearchHistoryRepository({this.maximumEntries = 6});

  static const _key = 'recent_searches';

  final int maximumEntries;

  Future<List<String>> load() async {
    final preferences = await SharedPreferences.getInstance();
    return List.unmodifiable(preferences.getStringList(_key) ?? const []);
  }

  Future<List<String>> remember(String query) async {
    final normalized = query.trim();
    if (normalized.isEmpty) return load();

    final current = await load();
    final next = <String>[
      normalized,
      ...current.where(
        (item) => item.toLowerCase() != normalized.toLowerCase(),
      ),
    ].take(maximumEntries).toList(growable: false);
    final preferences = await SharedPreferences.getInstance();
    await preferences.setStringList(_key, next);
    return List.unmodifiable(next);
  }
}
