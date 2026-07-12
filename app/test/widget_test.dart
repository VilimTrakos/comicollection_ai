import 'package:comicollect/app_controller.dart';
import 'package:comicollect/main.dart';
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
}
