enum AuthFailureKind {
  credentials,
  emailInUse,
  passwordPolicy,
  actionTokenInvalid,
  registrationDisabled,
  sessionExpired,
  rateLimited,
  network,
  storage,
  server,
  invalidResponse,
}

final class AuthException implements Exception {
  const AuthException({
    required this.kind,
    this.code,
    this.statusCode,
    this.retryAfter,
  });

  final AuthFailureKind kind;
  final String? code;
  final int? statusCode;
  final Duration? retryAfter;

  bool get invalidatesSession =>
      kind == AuthFailureKind.sessionExpired || code == 'invalid_token';

  @override
  String toString() => 'AuthException(kind: $kind, code: $code)';
}
