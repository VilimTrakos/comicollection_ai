import 'package:flutter/material.dart';

/// Safe release fallback when the API origin was not configured at build time.
class ConfigurationErrorApp extends StatelessWidget {
  const ConfigurationErrorApp({super.key});

  @override
  Widget build(BuildContext context) => const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Aplikacija nije ispravno konfigurirana. Obratite se podršci.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    ),
  );
}
