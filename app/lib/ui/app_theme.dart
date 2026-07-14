import 'package:flutter/material.dart';

const red = Color(0xFFC6291E);
const ink = Color(0xFF131412);
const surface = Color(0xFF1C1D1B);
const tan = Color(0xFFB7A88F);

Color accentColor(String key) => switch (key) {
  'yellow' => const Color(0xFFB7892E),
  'blue' => const Color(0xFF2A5FA8),
  _ => red,
};

Color accentDeepColor(String key) => switch (key) {
  'yellow' => const Color(0xFF7C5A18),
  'blue' => const Color(0xFF173E74),
  _ => const Color(0xFF8E1410),
};

ThemeData buildAppTheme({
  required Brightness brightness,
  required Color accent,
  required Color accentDeep,
  required bool comicTitles,
}) {
  final dark = brightness == Brightness.dark;
  final background = dark ? ink : const Color(0xFFF5F2ED);
  final card = dark ? surface : Colors.white;
  final base = ThemeData(brightness: brightness, useMaterial3: true);
  final generated = ColorScheme.fromSeed(
    seedColor: accent,
    brightness: brightness,
    surface: card,
  );
  final colorScheme = generated.copyWith(
    primary: accent,
    onPrimary: Colors.white,
    primaryContainer: accentDeep,
    onPrimaryContainer: Colors.white,
    secondary: accent,
    onSecondary: Colors.white,
    secondaryContainer: accent,
    onSecondaryContainer: Colors.white,
    inversePrimary: accent,
  );
  return base.copyWith(
    scaffoldBackgroundColor: background,
    colorScheme: colorScheme,
    textTheme: base.textTheme.apply(fontFamily: comicTitles ? 'serif' : null),
    appBarTheme: AppBarTheme(backgroundColor: background, elevation: 0),
    cardTheme: CardThemeData(
      color: card,
      elevation: 4,
      margin: EdgeInsets.zero,
    ),
    chipTheme: base.chipTheme.copyWith(
      selectedColor: accent,
      checkmarkColor: Colors.white,
      side: BorderSide(color: dark ? const Color(0xFF3A3936) : Colors.black26),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) return Colors.grey;
        return states.contains(WidgetState.selected)
            ? Colors.white
            : (dark ? const Color(0xFFB8B3AD) : Colors.white);
      }),
      trackColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) {
          return Colors.grey.withValues(alpha: .25);
        }
        return states.contains(WidgetState.selected)
            ? accent
            : (dark ? const Color(0xFF3B3937) : const Color(0xFFBDB8B2));
      }),
      trackOutlineColor: WidgetStateProperty.resolveWith((states) {
        return states.contains(WidgetState.selected)
            ? accentDeep
            : (dark ? const Color(0xFF67615C) : const Color(0xFF8C8782));
      }),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: accent,
        foregroundColor: Colors.white,
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: accent,
      foregroundColor: Colors.white,
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: accent),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: accent,
      selectionHandleColor: accent,
      selectionColor: accent.withValues(alpha: .28),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: card,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: accent),
      ),
    ),
  );
}
