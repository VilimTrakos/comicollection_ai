import '../../models/account.dart';

/// HTTP-independent contract for account verification and password recovery.
abstract interface class AccountLifecycleApi {
  Future<void> requestEmailVerification({required String accessToken});

  Future<Account> confirmEmailVerification({
    required String accessToken,
    required String token,
    required String requestId,
  });

  Future<void> requestPasswordReset({required String email});

  Future<void> confirmPasswordReset({
    required String token,
    required String newPassword,
    required String requestId,
  });
}
