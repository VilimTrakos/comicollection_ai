import 'package:comicollect/data/api_token_store.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
  });

  test('default store migrates and removes the plaintext preference', () async {
    SharedPreferences.setMockInitialValues({'api_token': 'legacy-secret'});
    const store = SecureApiTokenStore();

    expect(await store.read(), 'legacy-secret');

    final preferences = await SharedPreferences.getInstance();
    expect(preferences.containsKey('api_token'), isFalse);
    expect(
      await const FlutterSecureStorage().read(
        key: SecureApiTokenStore.secureStorageKey,
      ),
      'legacy-secret',
    );
  });

  test('secure token wins and stale plaintext is erased', () async {
    final secure = _MemorySecureTokenValues('current-secret');
    final legacy = _MemoryLegacyPreferences('stale-secret');
    final store = SecureApiTokenStore(values: secure, legacy: legacy);

    expect(await store.read(), 'current-secret');
    expect(legacy.value, isNull);
    expect(legacy.deleteCalls, 1);
  });

  test('failed secure write leaves the legacy token intact', () async {
    final secure = _MemorySecureTokenValues()..writeError = StateError('disk');
    final legacy = _MemoryLegacyPreferences('legacy-secret');
    final store = SecureApiTokenStore(values: secure, legacy: legacy);

    await expectLater(store.read(), throwsStateError);

    expect(legacy.value, 'legacy-secret');
    expect(legacy.deleteCalls, 0);
  });

  test('failed legacy cleanup is retried without losing secure copy', () async {
    final secure = _MemorySecureTokenValues();
    final legacy = _MemoryLegacyPreferences('legacy-secret')
      ..deleteError = StateError('preferences');
    final store = SecureApiTokenStore(values: secure, legacy: legacy);

    await expectLater(store.read(), throwsStateError);
    expect(secure.value, 'legacy-secret');
    expect(legacy.value, 'legacy-secret');

    legacy.deleteError = null;
    expect(await store.read(), 'legacy-secret');
    expect(legacy.value, isNull);
  });

  test('new tokens never remain in plaintext preferences', () async {
    final secure = _MemorySecureTokenValues();
    final legacy = _MemoryLegacyPreferences('old-secret');
    final store = SecureApiTokenStore(values: secure, legacy: legacy);

    await store.write('new-secret');

    expect(secure.value, 'new-secret');
    expect(legacy.value, isNull);
  });

  test('clearing a token removes secure and legacy values', () async {
    final secure = _MemorySecureTokenValues('secure-secret');
    final legacy = _MemoryLegacyPreferences('legacy-secret');
    final store = SecureApiTokenStore(values: secure, legacy: legacy);

    await store.write('');

    expect(secure.value, isNull);
    expect(legacy.value, isNull);
  });

  test('failed plaintext cleanup cannot resurrect a cleared token', () async {
    final secure = _MemorySecureTokenValues('secure-secret');
    final legacy = _MemoryLegacyPreferences('legacy-secret')
      ..deleteError = StateError('preferences');
    final store = SecureApiTokenStore(values: secure, legacy: legacy);

    await expectLater(store.write(''), throwsStateError);
    expect(secure.value, 'secure-secret');
    expect(legacy.value, 'legacy-secret');

    legacy.deleteError = null;
    await store.write('');
    expect(secure.value, isNull);
    expect(legacy.value, isNull);
  });
}

final class _MemorySecureTokenValues implements SecureTokenValues {
  _MemorySecureTokenValues([this.value]);

  String? value;
  Object? writeError;

  @override
  Future<String?> read(String key) async => value;

  @override
  Future<void> write(String key, String value) async {
    final error = writeError;
    if (error != null) throw error;
    this.value = value;
  }

  @override
  Future<void> delete(String key) async => value = null;
}

final class _MemoryLegacyPreferences implements LegacyApiTokenPreferences {
  _MemoryLegacyPreferences(this.value);

  String? value;
  Object? deleteError;
  int deleteCalls = 0;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> delete() async {
    deleteCalls++;
    final error = deleteError;
    if (error != null) throw error;
    value = null;
  }
}
