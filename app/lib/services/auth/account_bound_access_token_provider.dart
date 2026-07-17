import '../../models/auth_failure.dart';
import 'access_token_provider.dart';

/// Restricts token lookups to the account that owns an application runtime.
///
/// The identity is checked both before and after an asynchronous refresh. This
/// prevents a request prepared from account A's database from receiving an
/// account B token when logout/login occurs while the refresh is in flight.
final class AccountBoundAccessTokenProvider implements AccessTokenProvider {
  AccountBoundAccessTokenProvider({
    required this.delegate,
    required this.expectedAccountId,
    required this.currentAccountId,
  });

  final AccessTokenProvider delegate;
  final String expectedAccountId;
  final String? Function() currentAccountId;

  @override
  Future<String> accessToken({bool forceRefresh = false}) async {
    _assertAccount();
    final token = await delegate.accessToken(forceRefresh: forceRefresh);
    _assertAccount();
    return token;
  }

  void _assertAccount() {
    if (currentAccountId() != expectedAccountId) {
      throw const AuthException(
        kind: AuthFailureKind.sessionExpired,
        code: 'account_changed',
      );
    }
  }
}
