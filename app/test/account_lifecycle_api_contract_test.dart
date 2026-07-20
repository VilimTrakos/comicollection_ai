import 'dart:convert';
import 'dart:io';

import 'package:comicollect/data/auth/auth_http_transport.dart';
import 'package:comicollect/data/auth/http_account_lifecycle_api.dart';
import 'package:comicollect/models/auth_failure.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('sends exact verification and password-reset contracts', () async {
    final transport = _LifecycleTransport();
    final api = HttpAccountLifecycleApi(
      baseUri: Uri.parse('https://api.example.test'),
      transport: transport,
    );

    await api.requestEmailVerification(accessToken: 'access-1');
    final account = await api.confirmEmailVerification(
      accessToken: 'access-2',
      token: 'verify-token',
      requestId: 'verify-request',
    );
    await api.requestPasswordReset(email: 'collector@example.test');
    await api.confirmPasswordReset(
      token: 'reset-token',
      newPassword: 'new-password-value',
      requestId: 'reset-request',
    );

    expect(account.emailVerified, isTrue);
    expect(transport.requests, [
      const _Request(
        path: '/api/v1/account/email-verification/request',
        body: {},
        bearerToken: 'access-1',
      ),
      const _Request(
        path: '/api/v1/account/email-verification/confirm',
        body: {'token': 'verify-token', 'request_id': 'verify-request'},
        bearerToken: 'access-2',
      ),
      const _Request(
        path: '/api/v1/auth/password-reset/request',
        body: {'email': 'collector@example.test'},
      ),
      const _Request(
        path: '/api/v1/auth/password-reset/confirm',
        body: {
          'token': 'reset-token',
          'new_password': 'new-password-value',
          'request_id': 'reset-request',
        },
      ),
    ]);
  });

  test('rejects malformed accepted and account responses', () async {
    final acceptedApi = HttpAccountLifecycleApi(
      baseUri: Uri.parse('https://api.example.test'),
      transport: _StaticTransport(
        const AuthHttpResponse(
          statusCode: HttpStatus.accepted,
          body: '{"accepted":false}',
          headers: {},
        ),
      ),
    );
    await expectLater(
      acceptedApi.requestPasswordReset(email: 'a@example.test'),
      throwsA(_failure(AuthFailureKind.invalidResponse)),
    );

    final accountApi = HttpAccountLifecycleApi(
      baseUri: Uri.parse('https://api.example.test'),
      transport: _StaticTransport(
        const AuthHttpResponse(
          statusCode: HttpStatus.ok,
          body: '{"account":{}}',
          headers: {},
        ),
      ),
    );
    await expectLater(
      accountApi.confirmEmailVerification(
        accessToken: 'access',
        token: 'token',
        requestId: 'request',
      ),
      throwsA(_failure(AuthFailureKind.invalidResponse)),
    );
  });

  test('maps lifecycle token and throttling failures safely', () async {
    final invalidToken = HttpAccountLifecycleApi(
      baseUri: Uri.parse('https://api.example.test'),
      transport: _StaticTransport(
        const AuthHttpResponse(
          statusCode: HttpStatus.badRequest,
          body: '{"code":"action_token_invalid","detail":"private"}',
          headers: {},
        ),
      ),
    );
    await expectLater(
      invalidToken.confirmPasswordReset(
        token: 'token',
        newPassword: 'new-password-value',
        requestId: 'request',
      ),
      throwsA(
        _failure(AuthFailureKind.actionTokenInvalid).having(
          (error) => error.toString(),
          'safe text',
          isNot(contains('private')),
        ),
      ),
    );

    final throttled = HttpAccountLifecycleApi(
      baseUri: Uri.parse('https://api.example.test'),
      transport: _StaticTransport(
        const AuthHttpResponse(
          statusCode: HttpStatus.tooManyRequests,
          body: '',
          headers: {'retry-after': '19'},
        ),
      ),
    );
    await expectLater(
      throttled.requestPasswordReset(email: 'a@example.test'),
      throwsA(
        _failure(AuthFailureKind.rateLimited).having(
          (error) => error.retryAfter,
          'retry after',
          const Duration(seconds: 19),
        ),
      ),
    );
  });
}

TypeMatcher<AuthException> _failure(AuthFailureKind kind) =>
    isA<AuthException>().having((error) => error.kind, 'kind', kind);

final class _Request {
  const _Request({required this.path, required this.body, this.bearerToken});

  final String path;
  final Map<String, Object?> body;
  final String? bearerToken;

  @override
  bool operator ==(Object other) =>
      other is _Request &&
      path == other.path &&
      jsonEncode(body) == jsonEncode(other.body) &&
      bearerToken == other.bearerToken;

  @override
  int get hashCode => Object.hash(path, jsonEncode(body), bearerToken);
}

final class _LifecycleTransport implements AuthHttpTransport {
  final requests = <_Request>[];

  @override
  Future<AuthHttpResponse> send({
    required String method,
    required Uri uri,
    Map<String, Object?>? body,
    String? bearerToken,
  }) async {
    expect(method, 'POST');
    requests.add(
      _Request(
        path: uri.path,
        body: body ?? const {},
        bearerToken: bearerToken,
      ),
    );
    return switch (uri.path) {
      '/api/v1/account/email-verification/confirm' => AuthHttpResponse(
        statusCode: HttpStatus.ok,
        body: jsonEncode({
          'account': {
            'id': 'account-1',
            'email': 'collector@example.test',
            'display_name': 'Collector',
            'email_verified': true,
          },
        }),
        headers: const {},
      ),
      '/api/v1/auth/password-reset/confirm' => const AuthHttpResponse(
        statusCode: HttpStatus.noContent,
        body: '',
        headers: {},
      ),
      _ => const AuthHttpResponse(
        statusCode: HttpStatus.accepted,
        body: '{"accepted":true}',
        headers: {},
      ),
    };
  }
}

final class _StaticTransport implements AuthHttpTransport {
  const _StaticTransport(this.response);

  final AuthHttpResponse response;

  @override
  Future<AuthHttpResponse> send({
    required String method,
    required Uri uri,
    Map<String, Object?>? body,
    String? bearerToken,
  }) async => response;
}
