import 'account.dart';

final class AuthApiSession {
  const AuthApiSession({
    required this.account,
    required this.accessToken,
    required this.accessExpiresAt,
    required this.refreshToken,
    required this.refreshExpiresAt,
  });

  final Account account;
  final String accessToken;
  final DateTime accessExpiresAt;
  final String refreshToken;
  final DateTime refreshExpiresAt;

  @override
  String toString() => 'AuthApiSession(account: ${account.id})';
}

final class StoredAuthSession {
  const StoredAuthSession({
    required this.account,
    required this.refreshToken,
    required this.refreshExpiresAt,
    this.refreshRequestId,
  });

  final Account account;
  final String refreshToken;
  final DateTime refreshExpiresAt;
  final String? refreshRequestId;

  StoredAuthSession copyWith({String? refreshRequestId}) => StoredAuthSession(
    account: account,
    refreshToken: refreshToken,
    refreshExpiresAt: refreshExpiresAt,
    refreshRequestId: refreshRequestId,
  );

  Map<String, Object?> toJson() => {
    'version': 1,
    'account': account.toJson(),
    'refresh_token': refreshToken,
    'refresh_expires_at': refreshExpiresAt.millisecondsSinceEpoch,
    'refresh_request_id': refreshRequestId,
  };

  @override
  String toString() => 'StoredAuthSession(account: ${account.id})';
}
