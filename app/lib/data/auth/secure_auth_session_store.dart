import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../models/auth_session.dart';
import 'auth_response_parser.dart';
import 'auth_session_store.dart';

final class FlutterSecureValueStore implements SecureValueStore {
  const FlutterSecureValueStore({this.storage = const FlutterSecureStorage()});

  final FlutterSecureStorage storage;

  @override
  Future<String?> read(String key) => storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => storage.delete(key: key);
}

final class SecureAuthSessionStore implements AuthSessionStore {
  const SecureAuthSessionStore({
    this.values = const FlutterSecureValueStore(),
    this.parser = const AuthResponseParser(),
  });

  static const sessionKey = 'comicollect.auth.session.v1';

  final SecureValueStore values;
  final AuthResponseParser parser;

  @override
  Future<StoredAuthSession?> read() async {
    final source = await values.read(sessionKey);
    if (source == null || source.isEmpty) return null;
    try {
      final decoded = jsonDecode(source);
      if (decoded is! Map) throw const FormatException('Invalid session');
      final payload = Map<String, Object?>.from(decoded);
      const keys = {
        'version',
        'account',
        'refresh_token',
        'refresh_expires_at',
        'refresh_request_id',
      };
      if (payload.keys.toSet().difference(keys).isNotEmpty ||
          keys.difference(payload.keys.toSet()).isNotEmpty ||
          payload['version'] != 1 ||
          payload['refresh_token'] is! String ||
          (payload['refresh_token'] as String).isEmpty ||
          payload['refresh_expires_at'] is! int ||
          (payload['refresh_expires_at'] as int) <= 0) {
        throw const FormatException('Invalid session');
      }
      return StoredAuthSession(
        account: parser.accountObject(payload['account']),
        refreshToken: payload['refresh_token'] as String,
        refreshExpiresAt: DateTime.fromMillisecondsSinceEpoch(
          payload['refresh_expires_at'] as int,
          isUtc: true,
        ),
        refreshRequestId: switch (payload['refresh_request_id']) {
          final String value when value.isNotEmpty => value,
          null => null,
          _ => throw const FormatException('Invalid refresh request id'),
        },
      );
    } on Object {
      await clear();
      return null;
    }
  }

  @override
  Future<void> write(StoredAuthSession session) =>
      values.write(sessionKey, jsonEncode(session.toJson()));

  @override
  Future<void> clear() => values.delete(sessionKey);
}
