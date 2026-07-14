import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../features/auth/login_gate.dart';
import '../ui/app_theme.dart';

class ComicollectApp extends StatelessWidget {
  const ComicollectApp({super.key, required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      final accent = accentColor(controller.accent);
      final accentDeep = accentDeepColor(controller.accent);
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Comicollect',
        themeMode: controller.darkMode ? ThemeMode.dark : ThemeMode.light,
        theme: buildAppTheme(
          brightness: Brightness.light,
          accent: accent,
          accentDeep: accentDeep,
          comicTitles: controller.comicTitles,
        ),
        darkTheme: buildAppTheme(
          brightness: Brightness.dark,
          accent: accent,
          accentDeep: accentDeep,
          comicTitles: controller.comicTitles,
        ),
        home: LoginGate(controller: controller),
      );
    },
  );
}
