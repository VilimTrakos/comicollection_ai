import 'package:comicollect/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('comic cover renders its label', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: ComicCover(label: 'Dylan Dog', seed: 7)),
      ),
    );
    expect(find.text('DYLAN DOG'), findsOneWidget);
  });
}
