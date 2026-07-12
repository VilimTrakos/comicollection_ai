import 'package:comicollect/app_controller.dart';
import 'package:comicollect/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('demo login is the entry screen', (tester) async {
    await tester.pumpWidget(ComicollectApp(controller: AppController()));
    expect(find.text('PRIJAVA'), findsOneWidget);
    expect(find.text('NASTAVI KAO GOST'), findsOneWidget);
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
