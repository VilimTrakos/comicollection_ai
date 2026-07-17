import '../app_controller.dart';
import '../data/local_database.dart';
import '../models/account.dart';

final class AppRuntime {
  AppRuntime({required this.controller, required this.database, this.account});

  final AppController controller;
  final LocalDatabase database;
  final Account? account;
  Future<void>? _closing;

  Future<void> close() => _closing ??= _close();

  Future<void> _close() async {
    try {
      await controller.quiesce();
    } finally {
      controller.dispose();
      await database.close();
    }
  }
}
