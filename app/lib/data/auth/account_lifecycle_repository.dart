import 'dart:convert';
import 'dart:io';

import 'package:uuid/uuid.dart';

import '../../models/account.dart';
import '../../models/auth_failure.dart';
import '../../services/auth/access_token_provider.dart';
import 'account_lifecycle_api.dart';

/// Validates lifecycle commands and retries authenticated calls once after a
/// forced access-token refresh. Confirmation request IDs remain stable across
/// that retry so server-side idempotency is preserved.
final class AccountLifecycleRepository {
  AccountLifecycleRepository({
    required this.api,
    required this.accessTokens,
    String Function()? requestIdGenerator,
  }) : _requestIdGenerator = requestIdGenerator ?? const Uuid().v4;

  final AccountLifecycleApi api;
  final AccessTokenProvider accessTokens;
  final String Function() _requestIdGenerator;

  Future<void> requestEmailVerification() => _authenticated(
    (accessToken) => api.requestEmailVerification(accessToken: accessToken),
  );

  Future<Account> confirmEmailVerification(String token) async {
    final normalizedToken = _token(token);
    final requestId = _requestId();
    return await _authenticated(
      (accessToken) => api.confirmEmailVerification(
        accessToken: accessToken,
        token: normalizedToken,
        requestId: requestId,
      ),
    );
  }

  Future<void> requestPasswordReset(String email) async {
    await api.requestPasswordReset(email: _email(email));
  }

  Future<void> confirmPasswordReset({
    required String token,
    required String newPassword,
  }) async {
    await api.confirmPasswordReset(
      token: _token(token),
      newPassword: _password(newPassword),
      requestId: _requestId(),
    );
  }

  Future<T> _authenticated<T>(
    Future<T> Function(String accessToken) action,
  ) async {
    var accessToken = await accessTokens.accessToken();
    try {
      return await action(accessToken);
    } on AuthException catch (error) {
      if (!_canRefresh(error)) rethrow;
      accessToken = await accessTokens.accessToken(forceRefresh: true);
      return action(accessToken);
    }
  }

  bool _canRefresh(AuthException error) =>
      error.statusCode == HttpStatus.unauthorized &&
      (error.code == 'access_expired' || error.code == 'invalid_token');

  String _requestId() {
    final value = _requestIdGenerator().trim();
    if (!RegExp(r'^[A-Za-z0-9._-]{8,128}$').hasMatch(value)) {
      throw const AuthException(kind: AuthFailureKind.invalidResponse);
    }
    return value;
  }

  static String _email(String value) {
    final normalized = value.trim().toLowerCase();
    final separator = normalized.indexOf('@');
    final domain = separator < 0 ? '' : normalized.substring(separator + 1);
    if (utf8.encode(normalized).length > 254 ||
        separator <= 0 ||
        separator != normalized.lastIndexOf('@') ||
        domain.isEmpty ||
        !domain.contains('.') ||
        normalized.runes.any(
          (character) =>
              character <= 32 || character == 127 || character == 0x00a0,
        )) {
      throw const AuthException(kind: AuthFailureKind.credentials);
    }
    return normalized;
  }

  static String _token(String value) {
    final normalized = value.trim();
    final bytes = utf8.encode(normalized).length;
    if (normalized.isEmpty || bytes > 2048) {
      throw const AuthException(kind: AuthFailureKind.credentials);
    }
    return normalized;
  }

  static String _password(String value) {
    final characters = value.runes.length;
    if (characters < 12 ||
        characters > 128 ||
        utf8.encode(value).length > 1024) {
      throw const AuthException(kind: AuthFailureKind.passwordPolicy);
    }
    return value;
  }
}
