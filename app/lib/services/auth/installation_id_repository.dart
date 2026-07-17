import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

final class InstallationIdRepository {
  InstallationIdRepository({String Function()? generator})
    : _generator = generator ?? const Uuid().v4;

  static const _key = 'installation_id_v1';
  final String Function() _generator;

  Future<String> loadOrCreate() async {
    final preferences = await SharedPreferences.getInstance();
    final existing = preferences.getString(_key)?.trim() ?? '';
    if (_valid(existing)) return existing;
    final created = _generator().trim();
    if (!_valid(created)) {
      throw StateError('A valid installation id could not be generated.');
    }
    if (!await preferences.setString(_key, created)) {
      throw StateError('The installation id could not be persisted.');
    }
    return created;
  }

  static bool _valid(String value) =>
      RegExp(r'^[A-Za-z0-9_-]{8,128}$').hasMatch(value);
}
