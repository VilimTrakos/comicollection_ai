import 'package:comicollect/comicollect.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('manual form validates required series and number', (
    tester,
  ) async {
    final controller = RecordingController();
    addTearDown(controller.dispose);
    await _setPhoneSize(tester);
    await tester.pumpWidget(_app(ComicForm(controller: controller)));

    await _scrollTo(tester, find.text('SPREMI U KOLEKCIJU'));
    await tester.tap(find.text('SPREMI U KOLEKCIJU'));
    await tester.pump();

    expect(find.text('Serijal i broj su obavezni.'), findsOneWidget);
    expect(controller.additions, isEmpty);
  });

  testWidgets('manual form forwards every entered value and state', (
    tester,
  ) async {
    final controller = RecordingController();
    addTearDown(controller.dispose);
    await _setPhoneSize(tester);
    await tester.pumpWidget(_app(ComicForm(controller: controller)));

    await tester.enterText(_field('Serijal *'), 'Dylan Dog');
    await tester.enterText(_field('Edicija'), 'Extra');
    await tester.enterText(_field('Broj *'), '14');
    await tester.enterText(_field('Godina'), '2002');
    await tester.enterText(_field('Naslov'), 'Kuća sjećanja');
    await tester.enterText(_field('Izdavač'), 'Ludens');

    await _scrollTo(tester, find.text('Bez stanja'));
    await tester.tap(find.text('Bez stanja'));
    await tester.enterText(_field('Plaćeno €'), '3,50');
    await tester.enterText(_field('Vrijednost €'), '8.25');
    await tester.tap(find.widgetWithText(SwitchListTile, 'Imam u kolekciji'));
    await tester.tap(find.widgetWithText(SwitchListTile, 'Pročitano'));
    await tester.tap(find.widgetWithText(SwitchListTile, 'Dupli primjerak'));
    await tester.enterText(_field('Posuđeno kome'), 'Ana');
    await tester.enterText(_field('Bilješke'), 'Moja bilješka');

    await _scrollTo(tester, _field('Scenarij'));
    await tester.enterText(_field('Scenarij'), 'Tiziano Sclavi');
    await tester.enterText(_field('Crtež'), 'Angelo Stano');
    await tester.enterText(_field('Broj stranica'), '98');
    await tester.tap(find.byTooltip('4/5'));
    await _scrollTo(tester, find.text('SPREMI U KOLEKCIJU'));
    await tester.tap(find.text('SPREMI U KOLEKCIJU'));
    await tester.pump();

    final call = controller.additions.single;
    expect(call.series, 'Dylan Dog');
    expect(call.edition, 'Extra');
    expect(call.number, 14);
    expect(call.title, 'Kuća sjećanja');
    expect(call.publisher, 'Ludens');
    expect(call.year, 2002);
    expect(call.owned, isFalse);
    expect(call.read, isTrue);
    expect(call.condition, isEmpty);
    expect(call.purchasePrice, 3.5);
    expect(call.estimatedValue, 8.25);
    expect(call.duplicate, isTrue);
    expect(call.loanedTo, 'Ana');
    expect(call.notes, 'Moja bilješka');
    expect(call.rating, 4);
    expect(call.pageCount, 98);
    expect(call.writer, 'Tiziano Sclavi');
    expect(call.artist, 'Angelo Stano');
  });

  testWidgets('manual form recognizes catalog issue and next missing number', (
    tester,
  ) async {
    final first = testComic(1, owned: true);
    final missing = testComic(
      2,
      owned: false,
      title: 'Automatski naslov',
      year: 2003,
    );
    final controller = RecordingController(comics: [first, missing]);
    addTearDown(controller.dispose);
    await _setPhoneSize(tester);
    await tester.pumpWidget(_app(ComicForm(controller: controller)));

    expect(find.textContaining('Sljedeći broj koji nemaš: #2'), findsOneWidget);
    await tester.tap(find.textContaining('Sljedeći broj koji nemaš: #2'));
    await tester.pump();
    expect(
      find.text('Podaci su automatski popunjeni iz lokalnog kataloga.'),
      findsOneWidget,
    );
    expect(_text(_field('Naslov')), 'Automatski naslov');
    expect(_text(_field('Godina')), '2003');

    await _scrollTo(tester, find.text('SPREMI U KOLEKCIJU'));
    await tester.tap(find.text('SPREMI U KOLEKCIJU'));
    await tester.pump();
    expect(controller.additions, isEmpty);
    expect(controller.saved.single.id, missing.id);
    expect(controller.saved.single.owned, isTrue);
  });

  testWidgets('edit form preloads and saves changed copy metadata', (
    tester,
  ) async {
    final comic = testComic(
      7,
      condition: 'VF',
      notes: 'Staro',
      rating: 2,
      pageCount: 90,
    );
    final controller = RecordingController(comics: [comic]);
    addTearDown(controller.dispose);
    await _setPhoneSize(tester);
    await tester.pumpWidget(
      _app(ComicForm(controller: controller, comic: comic)),
    );

    expect(find.text('UREDI STRIP'), findsOneWidget);
    await _scrollTo(tester, _field('Bilješke'));
    await tester.enterText(_field('Bilješke'), 'Novo');
    await tester.tap(find.text('M'));
    await _scrollTo(tester, find.text('SPREMI PROMJENE'));
    await tester.tap(find.text('SPREMI PROMJENE'));
    await tester.pump();

    expect(controller.saved.single.id, comic.id);
    expect(controller.saved.single.notes, 'Novo');
    expect(controller.saved.single.condition, 'M');
  });

  testWidgets(
    'range form validates order and saves excluded numbers without grade',
    (tester) async {
      final controller = RecordingController(
        comics: [testComic(1, owned: false), testComic(2, owned: false)],
      );
      addTearDown(controller.dispose);
      await _setPhoneSize(tester);
      await tester.pumpWidget(_app(RangeEntryPage(controller: controller)));

      await tester.enterText(_field('Od broja'), '5');
      await tester.enterText(_field('Do broja'), '1');
      await tester.pump();
      await _scrollTo(
        tester,
        find.byKey(const ValueKey('range-save-without-condition')),
      );
      final invalid = tester.widget<OutlinedButton>(
        find.byKey(const ValueKey('range-save-without-condition')),
      );
      expect(invalid.onPressed, isNull);

      await tester.enterText(_field('Od broja'), '1');
      await tester.enterText(_field('Do broja'), '3');
      await tester.pump();
      await _scrollTo(tester, find.byKey(const ValueKey('range-number-2')));
      await tester.tap(find.byKey(const ValueKey('range-number-2')));
      await _scrollTo(
        tester,
        find.byKey(const ValueKey('range-save-without-condition')),
      );
      expect(find.text('DODAJ 2 BROJA BEZ STANJA'), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey('range-save-without-condition')),
      );
      await tester.pump();

      final batch = controller.savedBatches.single;
      expect(batch, hasLength(3));
      expect(batch.firstWhere((comic) => comic.number == 1).owned, isTrue);
      expect(batch.firstWhere((comic) => comic.number == 1).condition, isEmpty);
      expect(batch.firstWhere((comic) => comic.number == 2).owned, isFalse);
      expect(batch.firstWhere((comic) => comic.number == 3).owned, isTrue);
    },
  );

  testWidgets('condition review can add all without grade after confirmation', (
    tester,
  ) async {
    await _setPhoneSize(tester);
    BatchConditionResult? result;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () async {
                result = await Navigator.push<BatchConditionResult>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => BatchConditionPage(
                      comics: [testComic(1), testComic(2)],
                    ),
                  ),
                );
              },
              child: const Text('OTVORI'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('OTVORI'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('condition-all-without')));
    await tester.pump();
    expect(find.text('Dodati sve bez stanja?'), findsOneWidget);
    await tester.tap(find.text('BEZ STANJA').last);
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.conditions.values, everyElement(isEmpty));
  });

  testWidgets(
    'condition summary returns selected values and supports correction',
    (tester) async {
      await _setPhoneSize(tester);
      BatchConditionResult? result;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: Builder(
            builder: (context) => Scaffold(
              body: FilledButton(
                onPressed: () async {
                  result = await Navigator.push<BatchConditionResult>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => BatchConditionPage(
                        comics: [testComic(1), testComic(2)],
                      ),
                    ),
                  );
                },
                child: const Text('OTVORI'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('OTVORI'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('condition-M')));
      await tester.pump(const Duration(milliseconds: 350));
      await tester.tap(find.byKey(const ValueKey('condition-none')));
      await tester.pump();
      await tester.tap(
        find.byKey(const ValueKey('condition-summary-previous')),
      );
      await tester.pump();
      expect(find.text('Test 2'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('condition-VF')));
      await tester.pump(const Duration(milliseconds: 350));
      await tester.tap(find.byKey(const ValueKey('condition-finish')));
      await tester.pumpAndSettle();

      expect(result!.conditions[testComic(1).id], 'M');
      expect(result!.conditions[testComic(2).id], 'VF');
    },
  );

  testWidgets(
    'settings persist controls, server configuration and forced sync',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'server_url': 'http://old',
        'api_token': 'old-token',
      });
      final controller = RecordingController();
      addTearDown(controller.dispose);
      await _setPhoneSize(tester);
      await tester.pumpWidget(
        _app(
          Scaffold(
            body: SettingsPage(
              controller: controller,
              accountEmail: '',
              onLogout: () {},
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('Svijetla'));
      await tester.tap(find.bySemanticsLabel('Plava boja'));
      await tester.tap(find.text('Comic'));
      await tester.tap(find.text('Ne'));
      await tester.tap(
        find.widgetWithText(SwitchListTile, 'Automatska sinkronizacija'),
      );
      await tester.tap(
        find.widgetWithText(SwitchListTile, 'Obavijesti o novim brojevima'),
      );
      expect(controller.darkMode, isFalse);
      expect(controller.accent, 'blue');
      expect(controller.comicTitles, isTrue);
      expect(controller.showStatistics, isFalse);
      expect(controller.autoSync, isTrue);
      expect(controller.newIssueNotifications, isFalse);

      await _scrollTo(tester, find.text('Lokalni sync server'));
      await tester.tap(find.text('Lokalni sync server'));
      await tester.pump();
      await tester.enterText(
        _field('Adresa servera'),
        ' https://server.test/ ',
      );
      await tester.enterText(_field('API token'), ' secret ');
      await _scrollTo(tester, find.text('SPREMI I SINKRONIZIRAJ'));
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'SPREMI I SINKRONIZIRAJ'),
          )
          .onPressed!();
      await tester.pump();
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('server_url'), 'https://server.test/');
      expect(prefs.containsKey('api_token'), isFalse);
      expect(
        await const FlutterSecureStorage().read(
          key: SecureApiTokenStore.secureStorageKey,
        ),
        'secret',
      );
      expect(controller.lastSyncForced, isTrue);
    },
  );

  testWidgets('settings require confirmation before rebinding sync server', (
    tester,
  ) async {
    final controller = RecordingController();
    addTearDown(controller.dispose);
    await _setPhoneSize(tester);
    await tester.pumpWidget(
      _app(
        Scaffold(
          body: SettingsPage(
            controller: controller,
            accountEmail: '',
            onLogout: () {},
          ),
        ),
      ),
    );
    await tester.pump();
    await _scrollTo(tester, find.text('Lokalni sync server'));
    await tester.tap(find.text('Lokalni sync server'));
    await tester.pump();
    await tester.enterText(_field('Adresa servera'), 'https://new.test');
    await tester.enterText(_field('API token'), 'new-secret');
    const buttonLabel = 'POVEŽI DRUGI ILI NOVI SERVER';
    final rebindButton = find.widgetWithText(OutlinedButton, buttonLabel);
    await _scrollTo(tester, rebindButton);

    tester.widget<OutlinedButton>(rebindButton).onPressed!();
    await tester.pump();
    expect(find.text('Povezati novi server?'), findsOneWidget);
    await tester.tap(find.text('ODUSTANI'));
    await tester.pumpAndSettle();
    expect(controller.syncResetCalls, 0);

    await _scrollTo(tester, rebindButton);
    tester.widget<OutlinedButton>(rebindButton).onPressed!();
    await tester.pumpAndSettle();
    await tester.tap(find.text('POVEŽI'));
    await tester.pumpAndSettle();

    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getString('server_url'), 'https://new.test');
    expect(preferences.containsKey('api_token'), isFalse);
    expect(
      await const FlutterSecureStorage().read(
        key: SecureApiTokenStore.secureStorageKey,
      ),
      'new-secret',
    );
    expect(controller.syncResetCalls, 1);
    expect(controller.lastSyncForced, isTrue);
  });

  testWidgets('account settings can safely repair production sync state', (
    tester,
  ) async {
    final controller = RecordingController();
    addTearDown(controller.dispose);
    await _setPhoneSize(tester);
    await tester.pumpWidget(
      _app(
        Scaffold(
          body: SettingsPage(
            controller: controller,
            accountEmail: 'collector@example.test',
            onLogout: () {},
          ),
        ),
      ),
    );
    await tester.pump();
    await _scrollTo(tester, find.text('Popravi sinkronizaciju'));

    await tester.tap(find.text('Popravi sinkronizaciju'));
    await tester.pump();
    expect(find.text('Popraviti sinkronizaciju?'), findsOneWidget);
    await tester.tap(find.text('ODUSTANI'));
    await tester.pumpAndSettle();
    expect(controller.syncResetCalls, 0);

    await tester.tap(find.text('Popravi sinkronizaciju'));
    await tester.pump();
    await tester.tap(find.text('POPRAVI'));
    await tester.pumpAndSettle();

    expect(controller.syncResetCalls, 1);
    expect(controller.lastSyncForced, isTrue);
  });

  testWidgets('guest sync settings sanitize secure-storage failures', (
    tester,
  ) async {
    final controller = RecordingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LegacySyncSettingsPanel(
            controller: controller,
            repository: SyncSettingsRepository(
              apiTokenStore: _FailingApiTokenStore(),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('Lokalni sync server'));
    await tester.pump();

    expect(
      find.text('Postavke sinkronizacije trenutačno nisu dostupne.'),
      findsOneWidget,
    );
  });

  testWidgets('settings logout requires confirmation', (tester) async {
    var loggedOut = false;
    final controller = RecordingController();
    addTearDown(controller.dispose);
    await _setPhoneSize(tester);
    await tester.pumpWidget(
      _app(
        Scaffold(
          body: SettingsPage(
            controller: controller,
            accountEmail: '',
            onLogout: () => loggedOut = true,
          ),
        ),
      ),
    );
    await tester.pump();
    await _scrollTo(tester, find.text('Odjava'));
    expect(find.text('lokalni korisnik'), findsOneWidget);
    await tester.tap(find.text('Odjava'));
    await tester.pump();
    await tester.tap(find.text('ODUSTANI'));
    await tester.pump();
    expect(loggedOut, isFalse);

    await tester.tap(find.text('Odjava'));
    await tester.pump();
    await tester.tap(find.text('ODJAVA'));
    await tester.pump();
    expect(loggedOut, isTrue);
  });
}

final class _FailingApiTokenStore implements ApiTokenStore {
  @override
  Future<String> read() => throw Exception('secure storage unavailable');

  @override
  Future<void> write(String token) async {}
}

Finder _field(String label) => find.widgetWithText(TextField, label);

String _text(Finder finder) => testerTextController(finder).text;

TextEditingController testerTextController(Finder finder) =>
    (finder.evaluate().single.widget as TextField).controller!;

Future<void> _setPhoneSize(WidgetTester tester) async {
  tester.view.physicalSize = const Size(500, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

Future<void> _scrollTo(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    300,
    scrollable: find
        .descendant(
          of: find.byType(ListView).first,
          matching: find.byType(Scrollable),
        )
        .first,
  );
  await tester.pump();
}

MaterialApp _app(Widget home) =>
    MaterialApp(theme: ThemeData.dark(useMaterial3: true), home: home);
