import 'package:comicollect/data/auth/account_lifecycle_api.dart';
import 'package:comicollect/data/auth/account_lifecycle_repository.dart';
import 'package:comicollect/models/account.dart';
import 'package:comicollect/models/auth_failure.dart';
import 'package:comicollect/services/auth/access_token_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('refreshes once and reuses the confirmation request id', () async {
    final api = _LifecycleApi()..expireFirstConfirmation = true;
    final tokens = _Tokens();
    final repository = AccountLifecycleRepository(
      api: api,
      accessTokens: tokens,
      requestIdGenerator: () => 'stable-request-id',
    );

    final account = await repository.confirmEmailVerification(' token ');

    expect(account.emailVerified, isTrue);
    expect(tokens.forcedRefreshes, 1);
    expect(api.verificationAccessTokens, ['access-old', 'access-new']);
    expect(api.verificationTokens, ['token', 'token']);
    expect(api.verificationRequestIds, [
      'stable-request-id',
      'stable-request-id',
    ]);
  });

  test('does not refresh a rejected lifecycle action token', () async {
    final api = _LifecycleApi()..rejectConfirmation = true;
    final tokens = _Tokens();
    final repository = AccountLifecycleRepository(
      api: api,
      accessTokens: tokens,
    );

    await expectLater(
      repository.confirmEmailVerification('invalid-token'),
      throwsA(
        isA<AuthException>().having(
          (error) => error.kind,
          'kind',
          AuthFailureKind.actionTokenInvalid,
        ),
      ),
    );
    expect(tokens.forcedRefreshes, 0);
    expect(api.verificationAccessTokens, ['access-old']);
  });

  test(
    'normalizes public reset input and validates before transport',
    () async {
      final api = _LifecycleApi();
      final repository = AccountLifecycleRepository(
        api: api,
        accessTokens: _Tokens(),
        requestIdGenerator: () => 'reset-request-id',
      );

      await repository.requestPasswordReset(' Collector@Example.Test ');
      await repository.confirmPasswordReset(
        token: ' reset-token ',
        newPassword: 'long-new-password',
      );

      expect(api.resetEmails, ['collector@example.test']);
      expect(api.resetTokens, ['reset-token']);
      expect(api.resetPasswords, ['long-new-password']);
      expect(api.resetRequestIds, ['reset-request-id']);

      await expectLater(
        repository.requestPasswordReset('not-an-email'),
        throwsA(isA<AuthException>()),
      );
      await expectLater(
        repository.confirmPasswordReset(token: 'token', newPassword: 'short'),
        throwsA(
          isA<AuthException>().having(
            (error) => error.kind,
            'kind',
            AuthFailureKind.passwordPolicy,
          ),
        ),
      );
      expect(api.resetEmails, hasLength(1));
      expect(api.resetTokens, hasLength(1));
    },
  );
}

final class _Tokens implements AccessTokenProvider {
  int forcedRefreshes = 0;

  @override
  Future<String> accessToken({bool forceRefresh = false}) async {
    if (forceRefresh) {
      forcedRefreshes++;
      return 'access-new';
    }
    return 'access-old';
  }
}

final class _LifecycleApi implements AccountLifecycleApi {
  bool expireFirstConfirmation = false;
  bool rejectConfirmation = false;
  final verificationAccessTokens = <String>[];
  final verificationTokens = <String>[];
  final verificationRequestIds = <String>[];
  final resetEmails = <String>[];
  final resetTokens = <String>[];
  final resetPasswords = <String>[];
  final resetRequestIds = <String>[];

  @override
  Future<Account> confirmEmailVerification({
    required String accessToken,
    required String token,
    required String requestId,
  }) async {
    verificationAccessTokens.add(accessToken);
    verificationTokens.add(token);
    verificationRequestIds.add(requestId);
    if (expireFirstConfirmation && verificationAccessTokens.length == 1) {
      throw const AuthException(
        kind: AuthFailureKind.sessionExpired,
        code: 'access_expired',
        statusCode: 401,
      );
    }
    if (rejectConfirmation) {
      throw const AuthException(
        kind: AuthFailureKind.actionTokenInvalid,
        code: 'action_token_invalid',
        statusCode: 400,
      );
    }
    return _verifiedAccount;
  }

  @override
  Future<void> confirmPasswordReset({
    required String token,
    required String newPassword,
    required String requestId,
  }) async {
    resetTokens.add(token);
    resetPasswords.add(newPassword);
    resetRequestIds.add(requestId);
  }

  @override
  Future<void> requestEmailVerification({required String accessToken}) async {}

  @override
  Future<void> requestPasswordReset({required String email}) async {
    resetEmails.add(email);
  }
}

const _verifiedAccount = Account(
  id: 'account-1',
  email: 'collector@example.test',
  displayName: 'Collector',
  emailVerified: true,
);
