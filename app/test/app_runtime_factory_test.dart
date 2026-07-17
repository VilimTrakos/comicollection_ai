import 'dart:io';

import 'package:comicollect/app/account_database_path_resolver.dart';
import 'package:comicollect/app/app_runtime.dart';
import 'package:comicollect/app/app_runtime_factory.dart';
import 'package:comicollect/data/sync_v2_transport.dart';
import 'package:comicollect/models/account.dart';
import 'package:comicollect/models/comic.dart';
import 'package:comicollect/services/auth/access_token_provider.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({
      'auto_sync': false,
      'account.account-1.auto_sync': false,
    });
  });

  test(
    'factory isolates guest/account storage and wires production v2',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'comicollect-runtime-',
      );
      AppRuntime? guest;
      AppRuntime? accountRuntime;
      addTearDown(() async {
        await accountRuntime?.close();
        await guest?.close();
        if (await directory.exists()) await directory.delete(recursive: true);
      });
      const account = Account(
        id: 'account-1',
        email: 'collector@example.test',
        displayName: 'Collector',
        emailVerified: true,
      );
      final factory = AppRuntimeFactory(
        productionServerUrl: 'https://sync.example.test',
        accessTokens: _StaticTokens(),
        currentAccountId: () => account.id,
        paths: AccountDatabasePathResolver(
          directoryProvider: () async => directory.path,
        ),
      );

      guest = await factory.createGuest();
      accountRuntime = await factory.createAccount(account);
      await guest.controller.save(
        Comic(
          id: 'guest-only',
          series: 'Dylan Dog',
          edition: 'Extra',
          number: 999,
          title: 'Gostujući zapis',
          owned: true,
          updatedAt: 1,
        ),
      );

      expect(guest.account, isNull);
      expect(accountRuntime.account, account);
      expect(guest.controller.settingsRepository.namespace, isEmpty);
      expect(
        accountRuntime.controller.settingsRepository.namespace,
        'account.account-1',
      );
      expect(guest.controller.searchHistoryRepository.namespace, isEmpty);
      expect(guest.controller.releaseWatchRepository.namespace, isEmpty);
      expect(
        accountRuntime.controller.searchHistoryRepository.namespace,
        'account.account-1',
      );
      expect(
        accountRuntime.controller.releaseWatchRepository.namespace,
        'account.account-1',
      );
      await guest.controller.searchHistoryRepository.remember('guest query');
      await accountRuntime.controller.searchHistoryRepository.remember(
        'account query',
      );
      await guest.controller.releaseWatchRepository.toggle(
        'guest-issue',
        const {},
      );
      await accountRuntime.controller.releaseWatchRepository.toggle(
        'account-issue',
        const {},
      );
      expect(await guest.controller.searchHistoryRepository.load(), [
        'guest query',
      ]);
      expect(await accountRuntime.controller.searchHistoryRepository.load(), [
        'account query',
      ]);
      expect(await guest.controller.releaseWatchRepository.load(), {
        'guest-issue',
      });
      expect(await accountRuntime.controller.releaseWatchRepository.load(), {
        'account-issue',
      });
      expect(
        accountRuntime.controller.syncService.productionServerUrl,
        'https://sync.example.test',
      );
      expect(
        accountRuntime.controller.syncService.v2Transport,
        isA<HttpSyncV2Transport>(),
      );
      expect(
        (await guest.database.all()).any((comic) => comic.id == 'guest-only'),
        isTrue,
      );
      expect(
        (await accountRuntime.database.all()).any(
          (comic) => comic.id == 'guest-only',
        ),
        isFalse,
      );
    },
  );
}

final class _StaticTokens implements AccessTokenProvider {
  @override
  Future<String> accessToken({bool forceRefresh = false}) async =>
      'account-token';
}
