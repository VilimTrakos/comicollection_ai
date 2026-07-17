import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';

import 'app/app_runtime_factory.dart';
import 'app/comicollect_app.dart';
import 'app/configuration_error_app.dart';
import 'config/app_environment.dart';
import 'data/auth/auth_repository.dart';
import 'data/auth/http_auth_api.dart';
import 'data/auth/secure_auth_session_store.dart';
import 'services/auth/auth_session_controller.dart';
import 'services/auth/installation_id_repository.dart';

export 'comicollect.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterError.onError = FlutterError.presentError;
  PlatformDispatcher.instance.onError = (error, stackTrace) {
    debugPrint('Comicollect neobrađena startup greška: $error');
    debugPrintStack(stackTrace: stackTrace);
    return false;
  };

  final environment = AppEnvironment.fromDefines();
  late final Uri apiBaseUri;
  try {
    apiBaseUri = environment.apiBaseUri;
  } on Object {
    runApp(const ConfigurationErrorApp());
    return;
  }
  final authRepository = AuthRepository(
    api: HttpAuthApi(baseUri: apiBaseUri),
    store: const SecureAuthSessionStore(),
    installationIds: InstallationIdRepository(),
  );
  final authController = AuthSessionController(authRepository);
  final runtimeFactory = AppRuntimeFactory(
    productionServerUrl: apiBaseUri.toString(),
    accessTokens: authRepository,
    currentAccountId: () => authRepository.account?.id,
  );
  runApp(
    ComicollectApp(
      authController: authController,
      runtimeFactory: runtimeFactory,
    ),
  );
  WidgetsBinding.instance.addPostFrameCallback((_) {
    unawaited(authController.restore());
  });
}
