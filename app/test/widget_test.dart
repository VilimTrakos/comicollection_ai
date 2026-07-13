import 'package:comicollect/app_controller.dart';
import 'package:comicollect/main.dart';
import 'package:comicollect/models/comic.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

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
