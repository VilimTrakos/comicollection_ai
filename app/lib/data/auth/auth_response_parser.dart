import 'dart:convert';

import '../../models/account.dart';
import '../../models/auth_session.dart';

final class AuthResponseParser {
  const AuthResponseParser();

  AuthApiSession session(String source) {
    final payload = _object(jsonDecode(source), 'session');
    _exactKeys(payload, const {
      'account',
      'access_token',
      'access_expires_at',
      'refresh_token',
      'refresh_expires_at',
    });
    return AuthApiSession(
      account: accountObject(payload['account']),
      accessToken: _text(payload['access_token'], 'access_token', 2048),
      accessExpiresAt: _timestamp(
        payload['access_expires_at'],
        'access_expires_at',
      ),
      refreshToken: _text(payload['refresh_token'], 'refresh_token', 2048),
      refreshExpiresAt: _timestamp(
        payload['refresh_expires_at'],
        'refresh_expires_at',
      ),
    );
  }

  Account accountEnvelope(String source) {
    final payload = _object(jsonDecode(source), 'account response');
    _exactKeys(payload, const {'account'});
    return accountObject(payload['account']);
  }

  Account accountObject(Object? value) {
    final payload = _object(value, 'account');
    _exactKeys(payload, const {
      'id',
      'email',
      'display_name',
      'email_verified',
    });
    final verified = payload['email_verified'];
    if (verified is! bool) {
      throw const FormatException('email_verified must be a boolean');
    }
    return Account(
      id: _text(payload['id'], 'id', 128),
      email: _text(payload['email'], 'email', 254),
      displayName: _text(payload['display_name'], 'display_name', 100),
      emailVerified: verified,
    );
  }

  static Map<String, Object?> _object(Object? value, String name) {
    if (value is! Map) throw FormatException('$name must be an object');
    try {
      return Map<String, Object?>.from(value);
    } on Object {
      throw FormatException('$name contains a non-string key');
    }
  }

  static void _exactKeys(Map<String, Object?> value, Set<String> expected) {
    if (value.keys.toSet().difference(expected).isNotEmpty ||
        expected.difference(value.keys.toSet()).isNotEmpty) {
      throw const FormatException('Authentication response fields are invalid');
    }
  }

  static String _text(Object? value, String name, int maximumBytes) {
    if (value is! String || value.trim().isEmpty) {
      throw FormatException('$name must be a non-empty string');
    }
    if (utf8.encode(value).length > maximumBytes) {
      throw FormatException('$name is too long');
    }
    return value;
  }

  static DateTime _timestamp(Object? value, String name) {
    if (value is! int || value <= 0) {
      throw FormatException('$name must be a positive integer');
    }
    if (value < 100000000000) {
      throw FormatException('$name must contain Unix epoch milliseconds');
    }
    return DateTime.fromMillisecondsSinceEpoch(value, isUtc: true);
  }
}
