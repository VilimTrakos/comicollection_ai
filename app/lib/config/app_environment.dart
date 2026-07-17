import 'package:flutter/foundation.dart';

final class AppEnvironment {
  const AppEnvironment({required this.apiBaseUrl});

  factory AppEnvironment.fromDefines() {
    const configured = String.fromEnvironment('COMICOLLECT_API_URL');
    final value = configured.isEmpty && !kReleaseMode
        ? 'http://10.0.2.2:8787'
        : configured;
    return AppEnvironment(apiBaseUrl: value);
  }

  final String apiBaseUrl;

  Uri get apiBaseUri {
    final uri = Uri.parse(apiBaseUrl.trim());
    final localDevelopment =
        !kReleaseMode &&
        uri.scheme == 'http' &&
        {'localhost', '127.0.0.1', '10.0.2.2'}.contains(uri.host);
    if (!uri.hasScheme ||
        !uri.hasAuthority ||
        uri.userInfo.isNotEmpty ||
        (uri.path.isNotEmpty && uri.path != '/') ||
        uri.hasQuery ||
        uri.hasFragment ||
        (uri.scheme != 'https' && !localDevelopment)) {
      throw StateError('COMICOLLECT_API_URL must be an HTTPS origin.');
    }
    return uri.replace(path: '', query: null, fragment: null);
  }
}
