import 'package:comicollect/comicollect.dart';
import 'package:comicollect/models/comic.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('guest onboarding enters the functional application shell', (
    tester,
  ) async {
    final controller = RecordingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(ComicollectApp(controller: controller));

    await tester.tap(find.text('Nastavi kao gost'));
    await tester.pumpAndSettle();

    expect(find.text('COMICOLLECT'), findsOneWidget);
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Polica'), findsOneWidget);
    expect(find.text('Traži'), findsOneWidget);
    expect(find.text('Postavke'), findsOneWidget);
  });

  testWidgets('enterprise mode explains that it is unavailable', (
    tester,
  ) async {
    final controller = RecordingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(ComicollectApp(controller: controller));
    await tester.tap(find.text('UĐI U KOLEKCIJU'));
    await tester.pump();

    await tester.tap(find.text('Enterprise — poslovnica'));
    await tester.pump();

    expect(
      find.text('Enterprise način nije dio osobne demo verzije.'),
      findsOneWidget,
    );
  });

  testWidgets('login and account creation both enter with supplied email', (
    tester,
  ) async {
    for (final button in ['PRIJAVI SE', 'NAPRAVI NOVI RAČUN']) {
      final controller = RecordingController();
      await tester.pumpWidget(
        MaterialApp(home: LoginGate(controller: controller)),
      );
      await tester.tap(find.text('UĐI U KOLEKCIJU'));
      await tester.pump();
      await tester.tap(find.text('Osobna kolekcija'));
      await tester.pump();
      await tester.enterText(
        find.widgetWithText(TextField, 'E-mail'),
        'test@example.com',
      );
      await tester.tap(find.text(button));
      await tester.pumpAndSettle();
      expect(find.text('COMICOLLECT'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      controller.dispose();
    }
  });

  testWidgets('shell shows loading, startup error and retries initialization', (
    tester,
  ) async {
    final controller = RecordingController()..loading = true;
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _app(Shell(controller: controller, accountEmail: '', onLogout: () {})),
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    controller
      ..loading = false
      ..startupError = 'Baza nije dostupna'
      ..notifyListeners();
    await tester.pump();
    expect(find.text('LOKALNI PODACI SE NE MOGU OTVORITI'), findsOneWidget);
    expect(find.text('Baza nije dostupna'), findsOneWidget);

    await tester.tap(find.text('POKUŠAJ PONOVNO'));
    await tester.pump();
    expect(controller.initCalls, 1);
    expect(find.text('U NAJAVI'), findsOneWidget);
  });

  testWidgets('shell navigation, add sheet and resume synchronization work', (
    tester,
  ) async {
    final controller = RecordingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _app(
        Shell(
          controller: controller,
          accountEmail: 'test@example.com',
          onLogout: () {},
        ),
      ),
    );

    await tester.tap(find.text('Polica'));
    await tester.pump();
    expect(find.text('MOJA KOLEKCIJA'), findsOneWidget);
    await tester.tap(find.text('Postavke'));
    await tester.pump();
    expect(find.text('POSTAVKE'), findsOneWidget);

    await tester.tap(find.byType(FloatingActionButton).first);
    await tester.pumpAndSettle();
    expect(find.text('Pametno skeniranje'), findsOneWidget);
    expect(find.text('Traži po nazivu'), findsOneWidget);
    expect(find.text('Ručni unos'), findsOneWidget);
    expect(find.text('Unos raspona'), findsOneWidget);
    await tester.tap(find.text('Traži po nazivu'));
    await tester.pumpAndSettle();
    expect(find.text('TRAŽI'), findsOneWidget);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(controller.syncCalls, 1);
  });

  testWidgets('sync badge renders offline, online and syncing states', (
    tester,
  ) async {
    final controller = RecordingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(_app(SyncBadge(controller: controller)));
    expect(find.text('Offline'), findsOneWidget);
    expect(find.byIcon(Icons.cloud_off_outlined), findsOneWidget);

    controller
      ..online = true
      ..syncing = false;
    await tester.pumpWidget(_app(SyncBadge(controller: controller)));
    expect(find.text('Sync'), findsOneWidget);
    expect(find.byIcon(Icons.cloud_done_outlined), findsOneWidget);

    controller.syncing = true;
    await tester.pumpWidget(_app(SyncBadge(controller: controller)));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('home calculates collection, value, unread and progress', (
    tester,
  ) async {
    final controller = RecordingController(
      comics: [
        testComic(1, estimatedValue: 4.5),
        testComic(2, read: true, estimatedValue: 5.5),
        testComic(3, owned: false),
      ],
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(_app(HomePage(controller: controller)));

    expect(find.text('2 stripova · 10.00 €'), findsOneWidget);
    expect(find.text('Test 1'), findsWidgets);
    await tester.scrollUntilVisible(
      find.text('2/3'),
      300,
      scrollable: _listScrollable(),
    );
    expect(find.text('2/3'), findsOneWidget);

    final refresh = tester
        .state<RefreshIndicatorState>(find.byType(RefreshIndicator))
        .show();
    await tester.pumpAndSettle();
    await refresh;
    expect(controller.syncCalls, 1);
    expect(controller.lastSyncForced, isTrue);
  });

  testWidgets('home exposes empty collection and all-read states', (
    tester,
  ) async {
    final controller = RecordingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(_app(HomePage(controller: controller)));
    expect(find.text('Sve pročitano — lijep osjećaj.'), findsOneWidget);
    expect(find.textContaining('Otvori Polic'), findsOneWidget);
  });

  testWidgets('shelf calculates dashboard counts and can hide statistics', (
    tester,
  ) async {
    final controller = RecordingController(
      comics: [
        testComic(1, duplicate: true, loanedTo: 'Ana'),
        testComic(2, read: true),
        testComic(3, owned: false),
      ],
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(_app(ShelfPage(controller: controller)));

    expect(find.text('1 čeka'), findsOneWidget);
    expect(find.text('1 nedostaje'), findsOneWidget);
    expect(find.text('1 za zamjenu'), findsOneWidget);
    expect(find.text('1 vani'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('2 imam · 1 pročitano'),
      300,
      scrollable: _listScrollable(),
    );
    expect(find.text('2 imam · 1 pročitano'), findsOneWidget);

    controller.showStatistics = false;
    await tester.pumpWidget(_app(ShelfPage(controller: controller)));
    expect(find.text('STATISTIKA'), findsNothing);
  });

  testWidgets('collection list filters, sorts and completes every action', (
    tester,
  ) async {
    final cases = <(CollectionListType, String, bool Function(Comic))>[
      (CollectionListType.unread, 'OZNAČI PROČITANO', (comic) => comic.read),
      (CollectionListType.wanted, '+ NABAVLJEN', (comic) => comic.owned),
      (
        CollectionListType.duplicates,
        'VIŠE NIJE DUPLI',
        (comic) => !comic.duplicate,
      ),
      (CollectionListType.loaned, 'VRAĆENO', (comic) => comic.loanedTo.isEmpty),
    ];

    for (final entry in cases) {
      final source = switch (entry.$1) {
        CollectionListType.unread => testComic(1),
        CollectionListType.wanted => testComic(1, owned: false),
        CollectionListType.duplicates => testComic(1, duplicate: true),
        CollectionListType.loaned => testComic(1, loanedTo: 'Ana'),
      };
      final controller = RecordingController(comics: [source]);
      await tester.pumpWidget(
        _app(CollectionListPage(controller: controller, type: entry.$1)),
      );
      expect(find.text(entry.$2), findsOneWidget);
      await tester.tap(find.text(entry.$2));
      await tester.pump();
      expect(controller.saved, hasLength(1));
      expect(entry.$3(controller.saved.single), isTrue);
      controller.dispose();
    }
  });

  testWidgets(
    'wanted list copies escaped content and empty lists explain state',
    (tester) async {
      String? clipboard;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'Clipboard.setData') {
              clipboard = (call.arguments as Map)['text'] as String?;
            }
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null),
      );
      final controller = RecordingController(
        comics: [testComic(2, owned: false, title: 'Naslov')],
      );
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        _app(
          CollectionListPage(
            controller: controller,
            type: CollectionListType.wanted,
          ),
        ),
      );
      await tester.tap(find.byTooltip('Kopiraj popis'));
      await tester.pump();
      expect(clipboard, contains('Dylan Dog · Regularna (L) #2 — Naslov'));
      expect(find.text('Popis Tražim je kopiran.'), findsOneWidget);

      controller.replaceComics(const []);
      await tester.pump();
      expect(find.text('Kolekcija je kompletna!'), findsOneWidget);
    },
  );

  testWidgets('statistics show totals, completeness and estimated value', (
    tester,
  ) async {
    final controller = RecordingController(
      comics: [
        testComic(1, read: true, estimatedValue: 10),
        testComic(2, owned: false),
      ],
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(_app(StatisticsPage(controller: controller)));

    expect(find.text('U KOLEKCIJI'), findsOneWidget);
    expect(find.text('PROČITANO'), findsOneWidget);
    expect(find.text('50%'), findsOneWidget);
    expect(find.text('10.00 €'), findsOneWidget);
  });

  testWidgets(
    'upcoming selects highest missing issue and persists watch state',
    (tester) async {
      final watchedId = testComic(3, owned: false).id;
      SharedPreferences.setMockInitialValues({
        'release_watch_ids': [watchedId],
      });
      final controller = RecordingController(
        comics: [
          testComic(1),
          testComic(2, owned: false),
          testComic(3, owned: false),
          testComic(4, edition: 'Extra', owned: false, year: 2025),
        ],
      );
      addTearDown(controller.dispose);
      await tester.pumpWidget(_app(UpcomingPage(controller: controller)));
      await tester.pump();

      expect(find.text('DYLAN DOG #3'), findsOneWidget);
      expect(find.text('DYLAN DOG #4'), findsOneWidget);
      expect(find.byTooltip('Isključi praćenje'), findsOneWidget);
      await tester.tap(find.byTooltip('Isključi praćenje'));
      await tester.pump();
      expect(
        (await SharedPreferences.getInstance()).getStringList(
          'release_watch_ids',
        ),
        isNot(contains(watchedId)),
      );
    },
  );

  testWidgets(
    'search loads history, scopes results, remembers and clears query',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'recent_searches': ['morgana'],
      });
      final controller = RecordingController(
        comics: [
          testComic(1, title: 'Morgana'),
          testComic(2, series: 'Tex', title: 'Rendžer'),
        ],
      );
      addTearDown(controller.dispose);
      await tester.pumpWidget(_app(SearchPage(controller: controller)));
      await tester.pump();
      expect(find.text('morgana'), findsOneWidget);

      await tester.tap(find.text('morgana'));
      await tester.pump();
      expect(find.text('SERIJALI'), findsNothing);
      expect(find.text('BROJEVI'), findsOneWidget);
      expect(find.text('Morgana'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'dylan');
      await tester.pump();
      expect(find.text('SERIJALI'), findsOneWidget);
      expect(find.text('BROJEVI'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'morgana');
      await tester.pump();

      await tester.tap(find.text('Brojevi'));
      await tester.pump();
      expect(find.text('SERIJALI'), findsNothing);
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pump();
      expect(
        (await SharedPreferences.getInstance())
            .getStringList('recent_searches')!
            .first,
        'morgana',
      );

      await tester.tap(find.byTooltip('Očisti'));
      await tester.pump();
      expect(find.text('NEDAVNO TRAŽENO'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'ne postoji');
      await tester.pump();
      expect(find.text('Nema rezultata za „ne postoji”'), findsOneWidget);
    },
  );

  testWidgets('comic tile toggles ownership/read and opens details', (
    tester,
  ) async {
    final comic = testComic(1, condition: '', duplicate: true, loanedTo: 'Ana');
    final controller = RecordingController(comics: [comic]);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _app(ComicTile(comic: comic, controller: controller)),
    );

    expect(find.text('bez stanja'), findsOneWidget);
    expect(find.text('DUPLI'), findsOneWidget);
    expect(find.text('POSUĐENO'), findsOneWidget);
    await tester.tap(find.byTooltip('Označi pročitano'));
    await tester.pump();
    expect(controller.saved.last.read, isTrue);
    await tester.tap(find.byTooltip('Imam — ukloni s police'));
    await tester.pump();
    expect(controller.saved.last.owned, isFalse);

    await tester.tap(find.text('Dylan Dog #1'));
    await tester.pumpAndSettle();
    expect(find.text('DETALJI IZDANJA'), findsOneWidget);
  });
}

MaterialApp _app(Widget home) => MaterialApp(
  theme: ThemeData.dark(useMaterial3: true),
  home: Scaffold(body: home),
);

Finder _listScrollable() => find
    .descendant(
      of: find.byType(ListView).first,
      matching: find.byType(Scrollable),
    )
    .first;
