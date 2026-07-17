import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../models/auth_failure.dart';

final class AuthHttpResponse {
  const AuthHttpResponse({
    required this.statusCode,
    required this.body,
    required this.headers,
  });

  final int statusCode;
  final String body;
  final Map<String, String> headers;
}

abstract interface class AuthHttpTransport {
  Future<AuthHttpResponse> send({
    required String method,
    required Uri uri,
    Map<String, Object?>? body,
    String? bearerToken,
  });
}

final class DartIoAuthHttpTransport implements AuthHttpTransport {
  DartIoAuthHttpTransport({
    HttpClient Function()? clientFactory,
    this.connectionTimeout = const Duration(seconds: 5),
    this.responseTimeout = const Duration(seconds: 10),
    this.maximumResponseBytes = 64 * 1024,
  }) : _clientFactory = clientFactory ?? HttpClient.new;

  final HttpClient Function() _clientFactory;
  final Duration connectionTimeout;
  final Duration responseTimeout;
  final int maximumResponseBytes;

  @override
  Future<AuthHttpResponse> send({
    required String method,
    required Uri uri,
    Map<String, Object?>? body,
    String? bearerToken,
  }) async {
    final client = _clientFactory()..connectionTimeout = connectionTimeout;
    try {
      final request = await client
          .openUrl(method, uri)
          .timeout(responseTimeout);
      request.followRedirects = false;
      request.headers
        ..set(HttpHeaders.acceptHeader, ContentType.json.mimeType)
        ..set(HttpHeaders.cacheControlHeader, 'no-store');
      if (bearerToken != null) {
        request.headers.set(
          HttpHeaders.authorizationHeader,
          'Bearer $bearerToken',
        );
      }
      if (body != null) {
        final bytes = utf8.encode(jsonEncode(body));
        request.headers.contentType = ContentType.json;
        request.contentLength = bytes.length;
        request.add(bytes);
      }
      final response = await request.close().timeout(responseTimeout);
      if (response.statusCode >= HttpStatus.internalServerError) {
        throw AuthException(
          kind: AuthFailureKind.server,
          statusCode: response.statusCode,
        );
      }
      final responseBody = await _read(response).timeout(responseTimeout);
      final contentType = response.headers.contentType?.mimeType;
      if (response.statusCode >= HttpStatus.ok &&
          response.statusCode < HttpStatus.multipleChoices &&
          responseBody.isNotEmpty &&
          contentType != ContentType.json.mimeType) {
        throw const AuthException(kind: AuthFailureKind.invalidResponse);
      }
      final headers = <String, String>{};
      response.headers.forEach((name, values) {
        headers[name.toLowerCase()] = values.join(',');
      });
      return AuthHttpResponse(
        statusCode: response.statusCode,
        body: responseBody,
        headers: headers,
      );
    } on AuthException {
      rethrow;
    } on TimeoutException {
      throw const AuthException(kind: AuthFailureKind.network);
    } on SocketException {
      throw const AuthException(kind: AuthFailureKind.network);
    } on HandshakeException {
      throw const AuthException(kind: AuthFailureKind.network);
    } on IOException {
      throw const AuthException(kind: AuthFailureKind.network);
    } finally {
      client.close(force: true);
    }
  }

  Future<String> _read(HttpClientResponse response) async {
    if (response.contentLength > maximumResponseBytes) {
      throw const AuthException(kind: AuthFailureKind.invalidResponse);
    }
    final bytes = <int>[];
    await for (final chunk in response) {
      if (bytes.length + chunk.length > maximumResponseBytes) {
        throw const AuthException(kind: AuthFailureKind.invalidResponse);
      }
      bytes.addAll(chunk);
    }
    try {
      return utf8.decode(bytes);
    } on FormatException {
      throw const AuthException(kind: AuthFailureKind.invalidResponse);
    }
  }
}
