import 'package:comicollect/app/account_database_path_resolver.dart';
import 'package:comicollect/data/settings_repository.dart';
import 'package:comicollect/data/sync_settings_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('guest keeps the legacy database while accounts are isolated', () async {
    final resolver = AccountDatabasePathResolver(
      directoryProvider: () async => '/data/databases',
    );

    expect(
      await resolver.guest(),
      path.join('/data/databases', 'comicollect.db'),
    );
    expect(
      await resolver.account('account-1'),
      path.join('/data/databases', 'comicollect_account_account-1.db'),
    );
    expect(
      await resolver.account('account-2'),
      isNot(await resolver.account('account-1')),
    );
    await expectLater(resolver.account('../escape'), throwsArgumentError);
  });

  test(
    'guest sees legacy global preferences and accounts remain scoped',
    () async {
      SharedPreferences.setMockInitialValues({
        'accent': 'blue',
        'account.account-1.accent': 'yellow',
      });

      expect((await const SettingsRepository().load()).accent, 'blue');
      expect(
        (await const SettingsRepository(
          namespace: 'account.account-1',
        ).load()).accent,
        'yellow',
      );
      expect(
        (await const SettingsRepository(
          namespace: 'account.account-2',
        ).load()).accent,
        'red',
      );
    },
  );

  test(
    'sync cursors are scoped and account loads skip the guest token',
    () async {
      SharedPreferences.setMockInitialValues({});
      final tokenStore = _RecordingTokenStore();
      final accountOne = SyncSettingsRepository(
        namespace: 'account.account-1',
        apiTokenStore: tokenStore,
      );
      final accountTwo = SyncSettingsRepository(
        namespace: 'account.account-2',
        apiTokenStore: tokenStore,
      );

      await accountOne.saveCursor(41);
      await accountTwo.saveCursor(7);

      expect((await accountOne.load(includeApiToken: false)).cursor, 41);
      expect((await accountTwo.load(includeApiToken: false)).cursor, 7);
      expect(tokenStore.readCalls, 0);
    },
  );
}

final class _RecordingTokenStore implements ApiTokenStore {
  int readCalls = 0;

  @override
  Future<String> read() async {
    readCalls++;
    return 'guest-secret';
  }

  @override
  Future<void> write(String token) async {}
}
