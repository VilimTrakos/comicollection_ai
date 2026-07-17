import 'dart:convert';

import 'package:comicollect/data/auth/auth_response_parser.dart';
import 'package:comicollect/models/account.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const parser = AuthResponseParser();

  test('strictly parses the auth session contract in epoch milliseconds', () {
    final session = parser.session(jsonEncode(_sessionPayload()));

    expect(session.account.id, 'account-1');
    expect(session.accessToken, 'cca_access.secret');
    expect(session.refreshToken, 'ccr_refresh.secret');
    expect(session.accessExpiresAt.millisecondsSinceEpoch, 2000000000000);
    expect(session.refreshExpiresAt.millisecondsSinceEpoch, 2100000000000);
    expect(session.toString(), isNot(contains('secret')));
  });

  test('rejects missing, additional, mistyped and second timestamps', () {
    final missing = _sessionPayload()..remove('access_token');
    final additional = {..._sessionPayload(), 'admin': true};
    final mistyped = {..._sessionPayload(), 'account': 'account-1'};
    final seconds = {..._sessionPayload(), 'access_expires_at': 2000000000};

    for (final payload in [missing, additional, mistyped, seconds]) {
      expect(() => parser.session(jsonEncode(payload)), throwsFormatException);
    }
  });

  test('account toString never exposes email PII', () {
    const account = Account(
      id: 'account-1',
      email: 'private@example.test',
      displayName: 'Private',
      emailVerified: true,
    );
    expect(account.toString(), isNot(contains('private@example.test')));
  });
}

Map<String, Object?> _sessionPayload() => {
  'account': {
    'id': 'account-1',
    'email': 'collector@example.test',
    'display_name': 'Collector',
    'email_verified': true,
  },
  'access_token': 'cca_access.secret',
  'access_expires_at': 2000000000000,
  'refresh_token': 'ccr_refresh.secret',
  'refresh_expires_at': 2100000000000,
};
