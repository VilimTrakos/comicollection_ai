import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

final class AccountDatabasePathResolver {
  AccountDatabasePathResolver({Future<String> Function()? directoryProvider})
    : _directoryProvider = directoryProvider ?? getDatabasesPath;

  final Future<String> Function() _directoryProvider;

  Future<String> guest() async =>
      path.join(await _directoryProvider(), 'comicollect.db');

  Future<String> account(String accountId) async {
    final normalized = accountId.trim();
    if (!RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(normalized)) {
      throw ArgumentError.value(accountId, 'accountId', 'is not path-safe');
    }
    return path.join(
      await _directoryProvider(),
      'comicollect_account_$normalized.db',
    );
  }
}
