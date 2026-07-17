import 'package:comicollect/data/release_watch_repository.dart';
import 'package:comicollect/data/search_history_repository.dart';
import 'package:comicollect/data/sync_settings_repository.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
  });

  group('SearchHistoryRepository', () {
    test('loads an empty history by default', () async {
      expect(await const SearchHistoryRepository().load(), isEmpty);
    });

    test('trims, de-duplicates and limits remembered queries', () async {
      SharedPreferences.setMockInitialValues({
        'recent_searches': ['Morgana', 'Tex', 'Zagor'],
      });
      const repository = SearchHistoryRepository(maximumEntries: 3);

      final history = await repository.remember('  morgana  ');

      expect(history, ['morgana', 'Tex', 'Zagor']);
      expect(
        (await SharedPreferences.getInstance()).getStringList(
          'recent_searches',
        ),
        history,
      );
    });

    test('ignores a blank query', () async {
      SharedPreferences.setMockInitialValues({
        'recent_searches': ['Dylan Dog'],
      });

      expect(await const SearchHistoryRepository().remember('  '), [
        'Dylan Dog',
      ]);
    });

    test(
      'isolates account histories and preserves the guest legacy key',
      () async {
        SharedPreferences.setMockInitialValues({
          'recent_searches': ['Guest query'],
          'account.one.recent_searches': ['Account one query'],
        });
        const guest = SearchHistoryRepository();
        const accountOne = SearchHistoryRepository(namespace: 'account.one');
        const accountTwo = SearchHistoryRepository(namespace: 'account.two');

        await accountTwo.remember('Account two query');

        expect(await guest.load(), ['Guest query']);
        expect(await accountOne.load(), ['Account one query']);
        expect(await accountTwo.load(), ['Account two query']);
        final preferences = await SharedPreferences.getInstance();
        expect(preferences.getStringList('recent_searches'), ['Guest query']);
        expect(preferences.getStringList('account.one.recent_searches'), [
          'Account one query',
        ]);
        expect(preferences.getStringList('account.two.recent_searches'), [
          'Account two query',
        ]);
      },
    );
  });

  group('ReleaseWatchRepository', () {
    test('loads stored release IDs', () async {
      SharedPreferences.setMockInitialValues({
        'release_watch_ids': ['one', 'two'],
      });

      expect(await const ReleaseWatchRepository().load(), {'one', 'two'});
    });

    test('toggles a release without mutating the supplied set', () async {
      const repository = ReleaseWatchRepository();
      final current = {'one'};

      final added = await repository.toggle('two', current);
      final removed = await repository.toggle('one', added);

      expect(current, {'one'});
      expect(added, {'one', 'two'});
      expect(removed, {'two'});
      expect(
        (await SharedPreferences.getInstance()).getStringList(
          'release_watch_ids',
        ),
        ['two'],
      );
    });

    test(
      'isolates account watches and preserves the guest legacy key',
      () async {
        SharedPreferences.setMockInitialValues({
          'release_watch_ids': ['guest-issue'],
          'account.one.release_watch_ids': ['account-one-issue'],
        });
        const guest = ReleaseWatchRepository();
        const accountOne = ReleaseWatchRepository(namespace: 'account.one');
        const accountTwo = ReleaseWatchRepository(namespace: 'account.two');

        await accountTwo.toggle('account-two-issue', const {});

        expect(await guest.load(), {'guest-issue'});
        expect(await accountOne.load(), {'account-one-issue'});
        expect(await accountTwo.load(), {'account-two-issue'});
        final preferences = await SharedPreferences.getInstance();
        expect(preferences.getStringList('release_watch_ids'), ['guest-issue']);
        expect(preferences.getStringList('account.one.release_watch_ids'), [
          'account-one-issue',
        ]);
        expect(preferences.getStringList('account.two.release_watch_ids'), [
          'account-two-issue',
        ]);
      },
    );
  });

  group('SyncSettingsRepository', () {
    test('loads typed settings through the token boundary', () async {
      SharedPreferences.setMockInitialValues({
        'server_url': ' https://server.test/// ',
        'last_sync': 42,
      });
      final tokens = _MemoryApiTokenStore(' token ');
      final repository = SyncSettingsRepository(apiTokenStore: tokens);

      final settings = await repository.load();

      expect(settings.serverUrl, ' https://server.test/// ');
      expect(settings.apiToken, ' token ');
      expect(settings.cursor, 42);
      expect(settings.isConfigured, isTrue);
      expect(settings.normalizedServerUrl, 'https://server.test');
    });

    test('saves trimmed connection values and the cursor', () async {
      final tokens = _MemoryApiTokenStore();
      final repository = SyncSettingsRepository(apiTokenStore: tokens);

      await repository.saveConnection(
        serverUrl: ' https://server.test/ ',
        apiToken: ' secret ',
      );
      await repository.saveCursor(1234);
      await repository.saveLastSuccessfulSyncAt(
        DateTime.fromMillisecondsSinceEpoch(5678),
      );

      var settings = await repository.load();
      expect(settings.serverUrl, 'https://server.test/');
      expect(settings.apiToken, 'secret');
      expect(settings.cursor, 1234);
      expect(settings.lastSuccessfulSyncAt?.millisecondsSinceEpoch, 5678);
      expect(
        (await SharedPreferences.getInstance()).containsKey('api_token'),
        isFalse,
      );

      await repository.clearLastSuccessfulSyncAt();
      settings = await repository.load();
      expect(settings.lastSuccessfulSyncAt, isNull);
      expect(settings.cursor, 1234);

      await repository.saveLastSuccessfulSyncAt(
        DateTime.fromMillisecondsSinceEpoch(9012),
      );
      await repository.resetForNewServer();
      settings = await repository.load();
      expect(settings.cursor, 0);
      expect(settings.lastSuccessfulSyncAt, isNull);
    });

    test('default token store migrates legacy preferences securely', () async {
      SharedPreferences.setMockInitialValues({'api_token': 'legacy-token'});
      const repository = SyncSettingsRepository();

      final settings = await repository.load();

      final preferences = await SharedPreferences.getInstance();
      expect(preferences.containsKey('api_token'), isFalse);
      expect(settings.apiToken, 'legacy-token');
      expect(
        await const FlutterSecureStorage().read(
          key: SecureApiTokenStore.secureStorageKey,
        ),
        'legacy-token',
      );
    });
  });
}

class _MemoryApiTokenStore implements ApiTokenStore {
  _MemoryApiTokenStore([this.value = '']);

  String value;

  @override
  Future<String> read() async => value;

  @override
  Future<void> write(String token) async => value = token;
}
