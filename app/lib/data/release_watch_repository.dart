import 'package:shared_preferences/shared_preferences.dart';

/// Stores the catalogue issue IDs for which the user wants notifications.
class ReleaseWatchRepository {
  const ReleaseWatchRepository({this.namespace = ''});

  static const _key = 'release_watch_ids';

  final String namespace;

  Future<Set<String>> load() async {
    final preferences = await SharedPreferences.getInstance();
    return Set.unmodifiable(
      preferences.getStringList(_namespacedKey) ?? const [],
    );
  }

  Future<Set<String>> toggle(String issueId, Set<String> current) async {
    final next = {...current};
    if (!next.add(issueId)) next.remove(issueId);

    final preferences = await SharedPreferences.getInstance();
    await preferences.setStringList(
      _namespacedKey,
      next.toList(growable: false),
    );
    return Set.unmodifiable(next);
  }

  String get _namespacedKey => namespace.isEmpty ? _key : '$namespace.$_key';
}
