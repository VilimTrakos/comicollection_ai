import 'dart:convert';
import 'dart:io';

import 'package:comicollect/data/auth/auth_http_transport.dart';
import 'package:comicollect/data/auth/http_auth_api.dart';
import 'package:comicollect/models/auth_failure.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'register login and refresh send exact installation contracts',
    () async {
      final transport = _RecordingTransport();
      final api = HttpAuthApi(
        baseUri: Uri.parse('https://api.example.test'),
        transport: transport,
      );

      await api.register(
        email: 'a@example.test',
        password: 'password-value',
        displayName: 'A',
        installationId: 'installation-1',
      );
      await api.login(
        email: 'a@example.test',
        password: 'password-value',
        installationId: 'installation-1',
      );
      await api.refresh(
        refreshToken: 'ccr_old.secret',
        installationId: 'installation-1',
        requestId: 'refresh-request-1',
      );

      expect(transport.requests[0].body, {
        'email': 'a@example.test',
        'password': 'password-value',
        'display_name': 'A',
        'installation_id': 'installation-1',
      });
      expect(transport.requests[1].body, {
        'email': 'a@example.test',
        'password': 'password-value',
        'installation_id': 'installation-1',
      });
      expect(transport.requests[2].body, {
        'refresh_token': 'ccr_old.secret',
        'installation_id': 'installation-1',
        'request_id': 'refresh-request-1',
      });
      expect(
        transport.requests.every(
          (request) => !request.body.containsKey('device_id'),
        ),
        isTrue,
      );
    },
  );

  test(
    'maps stable registration failures without exposing server text',
    () async {
      for (final testCase in [
        (409, 'email_in_use', AuthFailureKind.emailInUse),
        (400, 'password_policy_failed', AuthFailureKind.passwordPolicy),
        (403, 'registration_disabled', AuthFailureKind.registrationDisabled),
      ]) {
        final api = HttpAuthApi(
          baseUri: Uri.parse('https://api.example.test'),
          transport: _FailureTransport(testCase.$1, testCase.$2),
        );
        await expectLater(
          api.register(
            email: 'a@example.test',
            password: 'password-value',
            displayName: 'A',
            installationId: 'installation-1',
          ),
          throwsA(
            isA<AuthException>()
                .having((error) => error.kind, 'kind', testCase.$3)
                .having(
                  (error) => error.toString(),
                  'safe message',
                  isNot(contains('private server detail')),
                ),
          ),
        );
      }
    },
  );

  test('sanitizes malformed successful responses as invalidResponse', () async {
    final api = HttpAuthApi(
      baseUri: Uri.parse('https://api.example.test'),
      transport: _MalformedSuccessTransport(),
    );

    await expectLater(
      api.login(
        email: 'a@example.test',
        password: 'password-value',
        installationId: 'installation-1',
      ),
      throwsA(
        isA<AuthException>().having(
          (error) => error.kind,
          'kind',
          AuthFailureKind.invalidResponse,
        ),
      ),
    );
  });

  test(
    'maps documented refresh credential failures as session expiry',
    () async {
      for (final code in [
        'invalid_refresh_token',
        'refresh_expired',
        'refresh_reused',
      ]) {
        final api = HttpAuthApi(
          baseUri: Uri.parse('https://api.example.test'),
          transport: _FailureTransport(HttpStatus.unauthorized, code),
        );

        await expectLater(
          api.refresh(
            refreshToken: 'ccr_old.secret',
            installationId: 'installation-1',
            requestId: 'refresh-request-1',
          ),
          throwsA(
            isA<AuthException>().having(
              (error) => error.kind,
              'kind',
              AuthFailureKind.sessionExpired,
            ),
          ),
        );
      }
    },
  );

  test('maps an HTML proxy 502 response to a server failure', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      await request.drain<void>();
      request.response
        ..statusCode = HttpStatus.badGateway
        ..headers.contentType = ContentType.html
        ..write('<html>temporary upstream failure</html>');
      await request.response.close();
    });
    final api = HttpAuthApi(
      baseUri: Uri.parse('http://127.0.0.1:${server.port}'),
      transport: DartIoAuthHttpTransport(
        clientFactory: () => HttpOverrides.runWithHttpOverrides(
          HttpClient.new,
          _RealHttpOverrides(),
        ),
      ),
    );

    await expectLater(
      api.login(
        email: 'a@example.test',
        password: 'password-value',
        installationId: 'installation-1',
      ),
      throwsA(
        isA<AuthException>()
            .having((error) => error.kind, 'kind', AuthFailureKind.server)
            .having(
              (error) => error.statusCode,
              'status',
              HttpStatus.badGateway,
            ),
      ),
    );
  });

  test('maps an HTML 429 response without trusting its body', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      await request.drain<void>();
      request.response
        ..statusCode = HttpStatus.tooManyRequests
        ..headers.contentType = ContentType.html
        ..headers.set(HttpHeaders.retryAfterHeader, '17')
        ..write('<html>edge rate limit</html>');
      await request.response.close();
    });
    final api = HttpAuthApi(
      baseUri: Uri.parse('http://127.0.0.1:${server.port}'),
      transport: DartIoAuthHttpTransport(
        clientFactory: () => HttpOverrides.runWithHttpOverrides(
          HttpClient.new,
          _RealHttpOverrides(),
        ),
      ),
    );

    await expectLater(
      api.login(
        email: 'a@example.test',
        password: 'password-value',
        installationId: 'installation-1',
      ),
      throwsA(
        isA<AuthException>()
            .having((error) => error.kind, 'kind', AuthFailureKind.rateLimited)
            .having(
              (error) => error.retryAfter,
              'retry-after',
              const Duration(seconds: 17),
            ),
      ),
    );
  });

  test('does not erase a session based on an unstructured 401 page', () async {
    final api = HttpAuthApi(
      baseUri: Uri.parse('https://api.example.test'),
      transport: _HtmlUnauthorizedTransport(),
    );

    await expectLater(
      api.refresh(
        refreshToken: 'ccr_old.secret',
        installationId: 'installation-1',
        requestId: 'request-1',
      ),
      throwsA(
        isA<AuthException>().having(
          (error) => error.kind,
          'kind',
          AuthFailureKind.invalidResponse,
        ),
      ),
    );
  });
}

class _RealHttpOverrides extends HttpOverrides {}

typedef _Request = ({String path, Map<String, Object?> body});

class _RecordingTransport implements AuthHttpTransport {
  final requests = <_Request>[];

  @override
  Future<AuthHttpResponse> send({
    required String method,
    required Uri uri,
    Map<String, Object?>? body,
    String? bearerToken,
  }) async {
    requests.add((path: uri.path, body: body ?? const {}));
    return AuthHttpResponse(
      statusCode: uri.path.endsWith('/register') ? 201 : 200,
      body: jsonEncode(_sessionPayload()),
      headers: const {},
    );
  }
}

class _FailureTransport implements AuthHttpTransport {
  _FailureTransport(this.statusCode, this.code);
  final int statusCode;
  final String code;

  @override
  Future<AuthHttpResponse> send({
    required String method,
    required Uri uri,
    Map<String, Object?>? body,
    String? bearerToken,
  }) async => AuthHttpResponse(
    statusCode: statusCode,
    body: jsonEncode({
      'code': code,
      'error': 'private server detail',
      'request_id': 'request-1',
    }),
    headers: const {},
  );
}

class _MalformedSuccessTransport implements AuthHttpTransport {
  @override
  Future<AuthHttpResponse> send({
    required String method,
    required Uri uri,
    Map<String, Object?>? body,
    String? bearerToken,
  }) async => const AuthHttpResponse(
    statusCode: 200,
    body: '{"account":{},"unexpected":true}',
    headers: {},
  );
}

class _HtmlUnauthorizedTransport implements AuthHttpTransport {
  @override
  Future<AuthHttpResponse> send({
    required String method,
    required Uri uri,
    Map<String, Object?>? body,
    String? bearerToken,
  }) async => const AuthHttpResponse(
    statusCode: HttpStatus.unauthorized,
    body: '<html>proxy authentication required</html>',
    headers: {},
  );
}

Map<String, Object?> _sessionPayload() => {
  'account': {
    'id': 'account-1',
    'email': 'a@example.test',
    'display_name': 'A',
    'email_verified': true,
  },
  'access_token': 'cca_access.secret',
  'access_expires_at': 2000000000000,
  'refresh_token': 'ccr_refresh.secret',
  'refresh_expires_at': 2100000000000,
};
