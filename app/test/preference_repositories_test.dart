import 'package:comicollect/data/release_watch_repository.dart';
import 'package:comicollect/data/search_history_repository.dart';
import 'package:comicollect/data/sync_settings_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

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

      final settings = await repository.load();
      expect(settings.serverUrl, 'https://server.test/');
      expect(settings.apiToken, 'secret');
      expect(settings.cursor, 1234);
      expect(
        (await SharedPreferences.getInstance()).containsKey('api_token'),
        isFalse,
      );
    });

    test('default token store preserves legacy preferences', () async {
      const repository = SyncSettingsRepository();

      await repository.saveConnection(
        serverUrl: 'http://localhost',
        apiToken: 'legacy-token',
      );

      final preferences = await SharedPreferences.getInstance();
      expect(preferences.getString('api_token'), 'legacy-token');
      expect((await repository.load()).apiToken, 'legacy-token');
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
