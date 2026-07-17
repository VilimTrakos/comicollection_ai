import 'dart:convert';
import 'dart:io';

import '../../models/account.dart';
import '../../models/auth_failure.dart';
import '../../models/auth_session.dart';
import 'auth_api.dart';
import 'auth_http_transport.dart';
import 'auth_response_parser.dart';

final class HttpAuthApi implements AuthApi {
  HttpAuthApi({
    required this.baseUri,
    AuthHttpTransport? transport,
    this.parser = const AuthResponseParser(),
  }) : transport = transport ?? DartIoAuthHttpTransport();

  final Uri baseUri;
  final AuthHttpTransport transport;
  final AuthResponseParser parser;

  @override
  Future<AuthApiSession> register({
    required String email,
    required String password,
    required String displayName,
    required String installationId,
  }) async => _parseSession(
    await _request(
      'POST',
      '/api/v1/auth/register',
      body: {
        'email': email,
        'password': password,
        'display_name': displayName,
        'installation_id': installationId,
      },
    ),
  );

  @override
  Future<AuthApiSession> login({
    required String email,
    required String password,
    required String installationId,
  }) async => _parseSession(
    await _request(
      'POST',
      '/api/v1/auth/login',
      body: {
        'email': email,
        'password': password,
        'installation_id': installationId,
      },
    ),
  );

  @override
  Future<AuthApiSession> refresh({
    required String refreshToken,
    required String installationId,
    required String requestId,
  }) async => _parseSession(
    await _request(
      'POST',
      '/api/v1/auth/refresh',
      body: {
        'refresh_token': refreshToken,
        'installation_id': installationId,
        'request_id': requestId,
      },
    ),
  );

  @override
  Future<void> logout({required String accessToken}) async {
    await _request(
      'POST',
      '/api/v1/auth/logout',
      body: const {},
      bearerToken: accessToken,
      allowEmpty: true,
    );
  }

  @override
  Future<Account> me({required String accessToken}) async => _parseAccount(
    await _request('GET', '/api/v1/account/me', bearerToken: accessToken),
  );

  AuthApiSession _parseSession(AuthHttpResponse response) {
    try {
      return parser.session(response.body);
    } on FormatException {
      throw const AuthException(kind: AuthFailureKind.invalidResponse);
    } on RangeError {
      throw const AuthException(kind: AuthFailureKind.invalidResponse);
    }
  }

  Account _parseAccount(AuthHttpResponse response) {
    try {
      return parser.accountEnvelope(response.body);
    } on FormatException {
      throw const AuthException(kind: AuthFailureKind.invalidResponse);
    } on RangeError {
      throw const AuthException(kind: AuthFailureKind.invalidResponse);
    }
  }

  Future<AuthHttpResponse> _request(
    String method,
    String path, {
    Map<String, Object?>? body,
    String? bearerToken,
    bool allowEmpty = false,
  }) async {
    final response = await transport.send(
      method: method,
      uri: baseUri.resolve(path),
      body: body,
      bearerToken: bearerToken,
    );
    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (!allowEmpty && response.body.isEmpty) {
        throw const AuthException(kind: AuthFailureKind.invalidResponse);
      }
      return response;
    }
    throw _failure(response);
  }

  AuthException _failure(AuthHttpResponse response) {
    String? code;
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map && decoded['code'] is String) {
        code = decoded['code'] as String;
      }
    } on FormatException {
      // Error details are optional and never surfaced verbatim.
    }
    final retrySeconds = int.tryParse(response.headers['retry-after'] ?? '');
    final kind = switch (response.statusCode) {
      HttpStatus.conflict when code == 'email_in_use' =>
        AuthFailureKind.emailInUse,
      HttpStatus.badRequest when code == 'password_policy_failed' =>
        AuthFailureKind.passwordPolicy,
      HttpStatus.forbidden when code == 'registration_disabled' =>
        AuthFailureKind.registrationDisabled,
      HttpStatus.unauthorized
          when code == 'access_expired' ||
              code == 'invalid_token' ||
              code == 'invalid_refresh_token' ||
              code == 'refresh_expired' ||
              code == 'refresh_reused' =>
        AuthFailureKind.sessionExpired,
      HttpStatus.forbidden when code == 'account_unavailable' =>
        AuthFailureKind.sessionExpired,
      HttpStatus.unauthorized when code == 'invalid_credentials' =>
        AuthFailureKind.credentials,
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
