import 'package:comicollect/config/app_environment.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('accepts HTTPS origins and canonicalizes a trailing slash', () {
    final uri = const AppEnvironment(
      apiBaseUrl: ' https://api.example.test:8443/ ',
    ).apiBaseUri;

    expect(uri.toString(), 'https://api.example.test:8443');
  });

  test('allows plaintext only for known local debug hosts', () {
    expect(
      const AppEnvironment(apiBaseUrl: 'http://10.0.2.2:8787').apiBaseUri.host,
      '10.0.2.2',
    );
    expect(
      () => const AppEnvironment(
        apiBaseUrl: 'http://192.168.1.20:8787',
      ).apiBaseUri,
      throwsStateError,
    );
  });

  test('rejects credentials, paths, queries, fragments and empty values', () {
    for (final value in [
      '',
      'https://user:secret@api.example.test',
      'https://api.example.test/base',
      'https://api.example.test?token=secret',
      'https://api.example.test/#fragment',
    ]) {
      expect(
        () => AppEnvironment(apiBaseUrl: value).apiBaseUri,
        throwsA(isA<Object>()),
        reason: value,
      );
    }
  });

  test('debug builds have an explicit emulator-only default', () {
    expect(
      AppEnvironment.fromDefines().apiBaseUri.toString(),
      'http://10.0.2.2:8787',
    );
  });
}
