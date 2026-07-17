import '../../models/account.dart';
import '../../models/auth_session.dart';

abstract interface class AuthApi {
  Future<AuthApiSession> register({
    required String email,
    required String password,
    required String displayName,
    required String installationId,
  });

  Future<AuthApiSession> login({
    required String email,
    required String password,
    required String installationId,
  });

  Future<AuthApiSession> refresh({
    required String refreshToken,
    required String installationId,
    required String requestId,
  });

  Future<void> logout({required String accessToken});

  Future<Account> me({required String accessToken});
}
