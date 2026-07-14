import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';

import 'app/comicollect_app.dart';
import 'app_controller.dart';

export 'comicollect.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
  };
  PlatformDispatcher.instance.onError = (error, stackTrace) {
    debugPrint('Comicollect neobrađena startup greška: $error');
    debugPrintStack(stackTrace: stackTrace);
    return false;
  };
  debugPrint('Comicollect startup: main() je pokrenut');
  final controller = AppController();
  runApp(ComicollectApp(controller: controller));
  WidgetsBinding.instance.addPostFrameCallback((_) {
    debugPrint('Comicollect startup: prvi Flutter frame je prikazan');
    unawaited(controller.init());
  });
}
