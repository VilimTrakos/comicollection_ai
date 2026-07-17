import '../../models/auth_session.dart';

abstract interface class AuthSessionStore {
  Future<StoredAuthSession?> read();
  Future<void> write(StoredAuthSession session);
  Future<void> clear();
}

abstract interface class SecureValueStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}
