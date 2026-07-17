import 'dart:convert';

import 'package:comicollect/data/auth/auth_session_store.dart';
import 'package:comicollect/data/auth/secure_auth_session_store.dart';
import 'package:comicollect/models/account.dart';
import 'package:comicollect/models/auth_session.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'secure envelope stores refresh state but never an access token',
    () async {
      final values = _MemorySecureValues();
      final store = SecureAuthSessionStore(values: values);
      final session = StoredAuthSession(
        account: const Account(
          id: 'account-1',
          email: 'collector@example.test',
          displayName: 'Collector',
          emailVerified: true,
        ),
        refreshToken: 'ccr_refresh.secret',
        refreshExpiresAt: DateTime.fromMillisecondsSinceEpoch(2100000000000),
        refreshRequestId: 'refresh-request-1',
      );

      await store.write(session);
      final raw = values.data[SecureAuthSessionStore.sessionKey]!;
      expect(raw, contains('ccr_refresh.secret'));
      expect(raw, isNot(contains('access_token')));
      expect((await store.read())!.refreshRequestId, 'refresh-request-1');
    },
  );

  test('corrupt secure envelope is removed instead of being trusted', () async {
    final values = _MemorySecureValues()
      ..data[SecureAuthSessionStore.sessionKey] = jsonEncode({'version': 1});
    final store = SecureAuthSessionStore(values: values);

    expect(await store.read(), isNull);
    expect(values.data, isEmpty);
  });
}

class _MemorySecureValues implements SecureValueStore {
  final data = <String, String>{};

  @override
  Future<void> delete(String key) async => data.remove(key);

  @override
  Future<String?> read(String key) async => data[key];

  @override
  Future<void> write(String key, String value) async => data[key] = value;
}
