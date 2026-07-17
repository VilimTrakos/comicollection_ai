import 'package:comicollect/comicollect.dart';
import 'package:comicollect/models/comic.dart';
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

  testWidgets('golden home in the red dark theme', (tester) async {
    final controller = RecordingController(
      comics: [
        testComic(1, estimatedValue: 7, coverAsset: ''),
        testComic(2, read: true, estimatedValue: 5, coverAsset: ''),
        testComic(3, owned: false, coverAsset: ''),
      ],
    );
    addTearDown(controller.dispose);
    await _openShell(tester, controller);

    await expectLater(
      find.byType(Scaffold).first,
      matchesGoldenFile('goldens/home_red_dark.png'),
    );
  });

  testWidgets('golden shelf in the yellow dark theme', (tester) async {
    final controller = RecordingController(
      comics: [
        testComic(1, duplicate: true, loanedTo: 'Ana', coverAsset: ''),
        testComic(2, read: true, coverAsset: ''),
        testComic(3, owned: false, coverAsset: ''),
      ],
    )..accent = 'yellow';
    addTearDown(controller.dispose);
    await _openShell(tester, controller);
    await tester.tap(find.text('Polica'));
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(Scaffold).first,
      matchesGoldenFile('goldens/shelf_yellow_dark.png'),
    );
  });

  testWidgets('golden settings in the blue light theme', (tester) async {
    final controller = RecordingController()
      ..accent = 'blue'
      ..darkMode = false;
    addTearDown(controller.dispose);
    await _openShell(tester, controller);
    await tester.tap(find.text('Postavke'));
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(Scaffold).first,
      matchesGoldenFile('goldens/settings_blue_light.png'),
    );
  });

  testWidgets('golden condition review workflow', (tester) async {
    await _setPhoneSize(tester);
    final comics = <Comic>[
      testComic(1, title: 'Kuća sjećanja', coverAsset: ''),
      testComic(2, title: 'Demonova utvrda', coverAsset: ''),
      testComic(3, title: 'Projekt Hicks', coverAsset: ''),
    ];
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData.dark(useMaterial3: true).copyWith(
          colorScheme: ColorScheme.fromSeed(
            seedColor: red,
            brightness: Brightness.dark,
          ),
        ),
        home: BatchConditionPage(comics: comics),
      ),
    );
    await tester.pump();

    await expectLater(
      find.byType(Scaffold),
      matchesGoldenFile('goldens/condition_review.png'),
    );
  });
}

Future<void> _openShell(
  WidgetTester tester,
  RecordingController controller,
) async {
  await _setPhoneSize(tester);
  await tester.pumpWidget(ComicollectApp(controller: controller));
  await tester.tap(find.text('Nastavi kao gost'));
  await tester.pumpAndSettle();
}

Future<void> _setPhoneSize(WidgetTester tester) async {
  tester.view.physicalSize = const Size(420, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}
