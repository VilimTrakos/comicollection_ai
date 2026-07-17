import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persistence boundary for the self-hosted guest sync credential.
abstract interface class ApiTokenStore {
  Future<String> read();

  Future<void> write(String token);
}

/// Small boundary which keeps secure-storage migration deterministic in tests.
abstract interface class SecureTokenValues {
  Future<String?> read(String key);

  Future<void> write(String key, String value);

  Future<void> delete(String key);
}

final class FlutterSecureTokenValues implements SecureTokenValues {
  const FlutterSecureTokenValues({this.storage = const FlutterSecureStorage()});

  final FlutterSecureStorage storage;

  @override
  Future<String?> read(String key) => storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => storage.delete(key: key);
}

/// Boundary around the one plaintext preference used by older app versions.
abstract interface class LegacyApiTokenPreferences {
  Future<String?> read();

  Future<void> delete();
}

final class SharedPreferencesLegacyApiTokenPreferences
    implements LegacyApiTokenPreferences {
  const SharedPreferencesLegacyApiTokenPreferences();

  static const key = 'api_token';

  @override
  Future<String?> read() async =>
      (await SharedPreferences.getInstance()).getString(key);

  @override
  Future<void> delete() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(key);
    if (preferences.containsKey(key)) {
      throw StateError('Legacy API token could not be removed');
    }
  }
}

/// Stores the guest sync token in Android Keystore / iOS Keychain storage.
///
/// Migration is ordered so a legacy token is never deleted before its secure
/// copy is written. If legacy deletion fails, the operation fails and the next
/// read retries cleanup while retaining the secure copy.
final class SecureApiTokenStore implements ApiTokenStore {
  const SecureApiTokenStore({
    this.values = const FlutterSecureTokenValues(),
    this.legacy = const SharedPreferencesLegacyApiTokenPreferences(),
  });

  static const secureStorageKey = 'comicollect.sync.guest.api_token.v1';

  final SecureTokenValues values;
  final LegacyApiTokenPreferences legacy;

  @override
  Future<String> read() async {
    final secureToken = await values.read(secureStorageKey);
    final legacyToken = await legacy.read();
    if (secureToken != null) {
      if (legacyToken != null) await legacy.delete();
      return secureToken;
    }
    if (legacyToken == null) return '';
    if (legacyToken.isEmpty) {
      await legacy.delete();
      return '';
    }

    await values.write(secureStorageKey, legacyToken);
    await legacy.delete();
    return legacyToken;
  }

  @override
  Future<void> write(String token) async {
    if (token.isEmpty) {
      // Remove the plaintext fallback first. Otherwise a failed legacy cleanup
      // could resurrect that credential on the next migration read.
      if (await legacy.read() != null) await legacy.delete();
      await values.delete(secureStorageKey);
      return;
    }
    await values.write(secureStorageKey, token);
    if (await legacy.read() != null) await legacy.delete();
  }
}
