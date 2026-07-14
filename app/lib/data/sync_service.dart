import 'dart:convert';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/comic.dart';
import 'local_database.dart';

class SyncResult {
  const SyncResult(this.ok, this.message);
  final bool ok;
  final String message;
}

class SyncService {
  SyncService(this.db, {HttpClient Function()? clientFactory})
    : _clientFactory = clientFactory ?? HttpClient.new;
  final LocalDatabase db;
  final HttpClient Function() _clientFactory;

  Future<SyncResult> sync() async {
    final prefs = await SharedPreferences.getInstance();
    final server = (prefs.getString('server_url') ?? '').replaceAll(
      RegExp(r'/$'),
      '',
    );
    final token = prefs.getString('api_token') ?? '';
    if (server.isEmpty || token.isEmpty) {
      return const SyncResult(false, 'Server nije podešen');
    }
    final since = prefs.getInt('last_sync') ?? 0;
    final changes = await db.changedSince(since);
    final client = _clientFactory()
      ..connectionTimeout = const Duration(seconds: 5);
    try {
      final request = await client.postUrl(Uri.parse('$server/api/v1/sync'));
      request.headers.contentType = ContentType.json;
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      request.write(
        jsonEncode({
          'since': since,
          'changes': changes.map((e) => e.toJson()).toList(),
        }),
      );
      final response = await request.close().timeout(
        const Duration(seconds: 10),
      );
      final body = await utf8.decoder.bind(response).join();
      if (response.statusCode != 200) {
        return SyncResult(false, 'Server: ${response.statusCode}');
      }
      final payload = jsonDecode(body) as Map<String, dynamic>;
      final remote = (payload['changes'] as List).map(
        (e) => Comic.fromMap(Map<String, Object?>.from(e as Map)),
      );
      await db.mergeRemote(remote);
      await prefs.setInt('last_sync', (payload['server_time'] as num).toInt());
      return const SyncResult(true, 'Sinkronizirano');
    } on FormatException {
      return const SyncResult(false, 'Offline · spremljeno lokalno');
    } on ArgumentError {
      return const SyncResult(false, 'Offline · spremljeno lokalno');
    } on Exception {
      return const SyncResult(false, 'Offline · spremljeno lokalno');
    } finally {
      client.close(force: true);
    }
  }
}
