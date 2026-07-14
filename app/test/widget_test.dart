import 'package:comicollect/app_controller.dart';
import 'package:comicollect/comicollect.dart';
import 'package:comicollect/models/comic.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('reference onboarding reaches demo login', (tester) async {
    await tester.pumpWidget(ComicollectApp(controller: AppController()));
    expect(find.text('UĐI U KOLEKCIJU'), findsOneWidget);
    await tester.tap(find.text('UĐI U KOLEKCIJU'));
    await tester.pump();
    expect(find.text('TKO SI?'), findsOneWidget);
    await tester.tap(find.text('Osobna kolekcija'));
    await tester.pump();
    expect(find.text('PRIJAVA'), findsOneWidget);
    expect(find.text('PRIJAVI SE'), findsOneWidget);
  });

  testWidgets('comic cover renders its label', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: ComicCover(label: 'Dylan Dog', seed: 7)),
      ),
    );
    expect(find.text('DYLAN DOG'), findsOneWidget);
  });

  testWidgets('series progress refreshes while returning from an edition', (
    tester,
  ) async {
    final controller = _TestAppController()
      ..replaceComics([_comic(1, owned: true), _comic(2, owned: true)]);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: SeriesPage(name: 'Dylan Dog', controller: controller),
      ),
    );
    expect(find.text('2/2'), findsOneWidget);

    controller.replaceComics([
      _comic(1, owned: false),
      _comic(2, owned: false),
    ]);
    await tester.pump();

    expect(find.text('0/2'), findsOneWidget);
  });

  testWidgets('collection shelf exposes all dashboard actions', (tester) async {
    final controller = _TestAppController()
      ..replaceComics([_comic(1, owned: true), _comic(2, owned: false)]);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(body: ShelfPage(controller: controller)),
      ),
    );

    expect(find.text('STATISTIKA'), findsOneWidget);
    expect(find.text('NIJE ČITANO'), findsOneWidget);
    expect(find.text('TRAŽIM'), findsOneWidget);
    expect(find.text('DUPLI'), findsOneWidget);
    expect(find.text('POSUĐENO'), findsOneWidget);
    expect(find.text('U NAJAVI'), findsOneWidget);
    expect(find.text('EXPORT CSV'), findsOneWidget);
  });

  testWidgets('range entry counts excluded issues immediately', (tester) async {
    final controller = _TestAppController()
      ..replaceComics([_comic(1, owned: false), _comic(2, owned: false)]);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: RangeEntryPage(controller: controller),
      ),
    );

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('range-review-conditions')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('ODABERI STANJE ZA 2 BROJA'), findsOneWidget);
    expect(find.text('DODAJ 2 BROJA BEZ STANJA'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const ValueKey('range-number-2')));
    await tester.tap(find.byKey(const ValueKey('range-number-2')));
    await tester.pump();
    await tester.ensureVisible(
      find.byKey(const ValueKey('range-review-conditions')),
    );
    expect(find.text('ODABERI STANJE ZA 1 BROJ'), findsOneWidget);
    expect(find.text('DODAJ 1 BROJ BEZ STANJA'), findsOneWidget);
  });

  testWidgets('condition review shows covers and supports next back and skip', (
    tester,
  ) async {
    final comics = [
      _comic(1, owned: false),
      _comic(2, owned: false),
      _comic(3, owned: false),
    ];
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: BatchConditionPage(comics: comics),
      ),
    );

    expect(find.byKey(const ValueKey('condition-cover')), findsOneWidget);
    expect(find.text('Test 1'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('condition-M')));
    await tester.pump();
    expect(find.text('Test 1'), findsOneWidget);
    final selectedMaterial = tester.widget<Material>(
      find.descendant(
        of: find.byKey(const ValueKey('condition-M')),
        matching: find.byType(Material),
      ),
    );
    expect(
      selectedMaterial.color,
      Theme.of(
        tester.element(find.byKey(const ValueKey('condition-M'))),
      ).colorScheme.primary,
    );
    await tester.pump(const Duration(milliseconds: 349));
    expect(find.text('Test 1'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1));
    expect(find.text('Test 2'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('condition-next')));
    await tester.pump();
    expect(find.text('Test 3'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('condition-previous')));
    await tester.pump();
    expect(find.text('Test 2'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('condition-VF')));
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.text('Test 3'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('condition-none')));
    await tester.pump();
    expect(find.text('SVE JE PREGLEDANO'), findsOneWidget);
    expect(find.text('2 sa stanjem · 1 bez stanja'), findsOneWidget);
    expect(find.byKey(const ValueKey('condition-finish')), findsOneWidget);
  });

  testWidgets('settings contain appearance sync account and server options', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final controller = _TestAppController();
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: SettingsPage(
            controller: controller,
            accountEmail: 'kolekcionar@email.com',
            onLogout: () {},
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Tema'), findsOneWidget);
    expect(find.text('Automatska sinkronizacija'), findsOneWidget);
    expect(find.text('Obavijesti o novim brojevima'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Kolekcionar'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Kolekcionar'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Lokalni sync server'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Lokalni sync server'), findsOneWidget);
  });

  test('comic metadata survives local and sync serialization', () {
    final original = Comic(
      id: 'metadata',
      series: 'Dylan Dog',
      edition: 'Extra',
      number: 14,
      title: 'Kuća sjećanja',
      rating: 4,
      pageCount: 98,
      writer: 'Tiziano Sclavi',
      artist: 'Angelo Stano',
      updatedAt: 123,
    );

    final restored = Comic.fromMap(original.toMap());
    expect(restored.rating, 4);
    expect(restored.pageCount, 98);
    expect(restored.writer, 'Tiziano Sclavi');
    expect(restored.artist, 'Angelo Stano');
  });

  test('prototype accent colors stay exact and are not tone-mapped', () {
    expect(accentColor('red'), const Color(0xFFC6291E));
    expect(accentColor('yellow'), const Color(0xFFB7892E));
    expect(accentColor('blue'), const Color(0xFF2A5FA8));
    expect(accentDeepColor('red'), const Color(0xFF8E1410));
    expect(accentDeepColor('yellow'), const Color(0xFF7C5A18));
    expect(accentDeepColor('blue'), const Color(0xFF173E74));
  });

  testWidgets('selected accent is applied exactly to Material controls', (
    tester,
  ) async {
    final controller = _TestAppController()..accent = 'blue';
    await tester.pumpWidget(ComicollectApp(controller: controller));
    final theme = Theme.of(tester.element(find.byType(LoginGate)));

    expect(theme.colorScheme.primary, const Color(0xFF2A5FA8));
    expect(
      theme.switchTheme.trackColor!.resolve({WidgetState.selected}),
      const Color(0xFF2A5FA8),
    );
    expect(
      theme.filledButtonTheme.style!.backgroundColor!.resolve({}),
      const Color(0xFF2A5FA8),
    );
  });

  test('comic can be stored explicitly without a condition grade', () {
    final comic = _comic(9, owned: true).copyWith(condition: '');
    final restored = Comic.fromMap(comic.toMap());
    expect(restored.condition, isEmpty);
  });
}

Comic _comic(int number, {required bool owned}) => Comic(
  id: 'test-$number',
  series: 'Dylan Dog',
  edition: 'Regularna (L)',
  number: number,
  title: 'Test $number',
  owned: owned,
  read: false,
  condition: 'F',
  updatedAt: number,
);

class _TestAppController extends AppController {
  void replaceComics(List<Comic> value) {
    comics = value;
    notifyListeners();
  }
}
