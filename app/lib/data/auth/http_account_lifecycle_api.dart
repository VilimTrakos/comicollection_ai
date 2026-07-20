import 'dart:convert';
import 'dart:io';

import '../../models/account.dart';
import '../../models/auth_failure.dart';
import 'account_lifecycle_api.dart';
import 'auth_http_transport.dart';
import 'auth_response_parser.dart';

final class HttpAccountLifecycleApi implements AccountLifecycleApi {
  HttpAccountLifecycleApi({
    required this.baseUri,
    AuthHttpTransport? transport,
    this.parser = const AuthResponseParser(),
  }) : transport = transport ?? DartIoAuthHttpTransport();

  final Uri baseUri;
  final AuthHttpTransport transport;
  final AuthResponseParser parser;

  @override
  Future<void> requestEmailVerification({required String accessToken}) async {
    final response = await _request(
      '/api/v1/account/email-verification/request',
      body: const {},
      bearerToken: accessToken,
      expectedStatus: HttpStatus.accepted,
    );
    _expectAccepted(response.body);
  }

  @override
  Future<Account> confirmEmailVerification({
    required String accessToken,
    required String token,
    required String requestId,
  }) async {
    final response = await _request(
      '/api/v1/account/email-verification/confirm',
      body: {'token': token, 'request_id': requestId},
      bearerToken: accessToken,
      expectedStatus: HttpStatus.ok,
    );
    try {
      return parser.accountEnvelope(response.body);
    } on FormatException {
      throw const AuthException(kind: AuthFailureKind.invalidResponse);
    } on RangeError {
      throw const AuthException(kind: AuthFailureKind.invalidResponse);
    }
  }

  @override
  Future<void> requestPasswordReset({required String email}) async {
    final response = await _request(
      '/api/v1/auth/password-reset/request',
      body: {'email': email},
      expectedStatus: HttpStatus.accepted,
    );
    _expectAccepted(response.body);
  }

  @override
  Future<void> confirmPasswordReset({
    required String token,
    required String newPassword,
    required String requestId,
  }) async {
    await _request(
      '/api/v1/auth/password-reset/confirm',
      body: {
        'token': token,
        'new_password': newPassword,
        'request_id': requestId,
      },
      expectedStatus: HttpStatus.noContent,
    );
  }

  Future<AuthHttpResponse> _request(
    String path, {
    required Map<String, Object?> body,
    required int expectedStatus,
    String? bearerToken,
  }) async {
    final response = await transport.send(
      method: 'POST',
      uri: baseUri.resolve(path),
      body: body,
      bearerToken: bearerToken,
    );
    if (response.statusCode == expectedStatus) {
      return response;
    }
    if (response.statusCode >= 200 && response.statusCode < 300) {
      throw const AuthException(kind: AuthFailureKind.invalidResponse);
    }
    throw _failure(response);
  }

  void _expectAccepted(String source) {
    try {
      final decoded = jsonDecode(source);
      if (decoded is! Map ||
          decoded.length != 1 ||
          decoded['accepted'] != true) {
        throw const FormatException('Invalid accepted response');
      }
    } on FormatException {
      throw const AuthException(kind: AuthFailureKind.invalidResponse);
    }
  }

  AuthException _failure(AuthHttpResponse response) {
    String? code;
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map && decoded['code'] is String) {
        code = decoded['code'] as String;
      }
    } on FormatException {
      // Error details are optional and are never surfaced verbatim.
    }
    final retrySeconds = int.tryParse(response.headers['retry-after'] ?? '');
    final kind = switch (response.statusCode) {
      HttpStatus.badRequest when code == 'password_policy_failed' =>
        AuthFailureKind.passwordPolicy,
      HttpStatus.badRequest when code == 'action_token_invalid' =>
        AuthFailureKind.actionTokenInvalid,
      HttpStatus.unauthorized
          when code == 'access_expired' || code == 'invalid_token' =>
        AuthFailureKind.sessionExpired,
      HttpStatus.tooManyRequests => AuthFailureKind.rateLimited,
      >= 500 => AuthFailureKind.server,
      _ => AuthFailureKind.invalidResponse,
    };
    return AuthException(
      kind: kind,
      code: code,
      statusCode: response.statusCode,
      retryAfter: retrySeconds == null ? null : Duration(seconds: retrySeconds),
    );
  }
}
