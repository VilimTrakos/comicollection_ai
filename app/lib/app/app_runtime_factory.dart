import '../app_controller.dart';
import '../data/catalog_repository.dart';
import '../data/local_database.dart';
import '../data/settings_repository.dart';
import '../data/sync_service.dart';
import '../data/sync_settings_repository.dart';
import '../models/account.dart';
import '../services/auth/account_bound_access_token_provider.dart';
import '../services/auth/access_token_provider.dart';
import 'account_database_path_resolver.dart';
import 'app_runtime.dart';

abstract interface class AppRuntimeProvider {
  Future<AppRuntime> createAccount(Account account);
  Future<AppRuntime> createGuest();
}

final class AppRuntimeFactory implements AppRuntimeProvider {
  AppRuntimeFactory({
    required this.productionServerUrl,
    required this.accessTokens,
    required this.currentAccountId,
    AccountDatabasePathResolver? paths,
  }) : paths = paths ?? AccountDatabasePathResolver();

  final String productionServerUrl;
  final AccessTokenProvider accessTokens;
  final String? Function() currentAccountId;
  final AccountDatabasePathResolver paths;

  @override
  Future<AppRuntime> createAccount(Account account) => _create(
    path: paths.account(account.id),
    namespace: 'account.${account.id}',
    account: account,
    serverUrl: productionServerUrl,
    tokenProvider: AccountBoundAccessTokenProvider(
      delegate: accessTokens,
      expectedAccountId: account.id,
      currentAccountId: currentAccountId,
    ),
  );

  @override
  Future<AppRuntime> createGuest() =>
      _create(path: paths.guest(), namespace: '');

  Future<AppRuntime> _create({
    required Future<String> path,
    required String namespace,
    Account? account,
    String? serverUrl,
    AccessTokenProvider? tokenProvider,
  }) async {
    final database = LocalDatabase(pathOverride: await path);
    AppController? controller;
    try {
      final settings = SettingsRepository(namespace: namespace);
      final syncSettings = SyncSettingsRepository(namespace: namespace);
      final sync = SyncService(
        database,
        settingsRepository: syncSettings,
        productionServerUrl: serverUrl,
        accessTokenProvider: tokenProvider,
      );
      controller = AppController(
        db: database,
        catalog: CatalogRepository(),
        settingsRepository: settings,
        syncService: sync,
      );
      await controller.init();
      return AppRuntime(
        controller: controller,
        database: database,
        account: account,
      );
    } on Object catch (error, stackTrace) {
      controller?.dispose();
      try {
        await database.close();
      } on Object {
        // Preserve the initialization failure; it is the actionable cause.
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
  }
}
