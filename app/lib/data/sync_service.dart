import 'dart:io';

import '../models/auth_failure.dart';
import '../services/auth/access_token_provider.dart';
import 'local_database.dart';
import 'sync_settings_repository.dart';
import 'sync_transport.dart';
import 'sync_v2_transport.dart';

class SyncResult {
  const SyncResult(this.ok, this.message, {this.hasPending = false});
  final bool ok;
  final String message;
  final bool hasPending;
}

class SyncService {
  SyncService(
    this.db, {
    SyncSettingsRepository? settingsRepository,
    SyncTransport? transport,
    SyncV2Transport? v2Transport,
    HttpClient Function()? clientFactory,
    int Function()? nowMilliseconds,
    this.productionServerUrl,
    this.accessTokenProvider,
    this.maxV2Iterations = 20,
  }) : settingsRepository =
           settingsRepository ?? const SyncSettingsRepository(),
       transport =
           transport ??
           HttpSyncTransport(
             clientFactory: clientFactory,
             accessTokenProvider: accessTokenProvider,
           ),
       v2Transport =
           v2Transport ??
           (transport == null
               ? HttpSyncV2Transport(
                   clientFactory: clientFactory,
                   accessTokenProvider: accessTokenProvider,
                 )
               : null),
       _nowMilliseconds =
           nowMilliseconds ?? (() => DateTime.now().millisecondsSinceEpoch) {
    if (maxV2Iterations <= 0) {
      throw ArgumentError.value(
        maxV2Iterations,
        'maxV2Iterations',
        'must be positive',
      );
    }
  }

  final LocalDatabase db;
  final SyncSettingsRepository settingsRepository;

  /// The v1 boundary is retained for servers which genuinely predate v2.
  /// Supplying only this transport explicitly keeps old tests and custom
  /// integrations on their requested v1 boundary; production defaults to v2.
  final SyncTransport transport;
  final SyncV2Transport? v2Transport;
  final int maxV2Iterations;
  final int Function() _nowMilliseconds;
  final String? productionServerUrl;
  final AccessTokenProvider? accessTokenProvider;

  /// Explicit recovery path for moving this installation to another server.
  /// Collection data and the stable device id stay intact; the next v2 sync
  /// uploads a fresh snapshot and pins the identity returned by that server.
  Future<void> resetServerBinding() async {
    await db.resetSyncV2Binding();
    await settingsRepository.resetForNewServer();
  }

  Future<SyncResult> sync() async {
    try {
      final settings = await settingsRepository.load(
        includeApiToken: accessTokenProvider == null,
      );
      final serverUrl = (productionServerUrl ?? settings.serverUrl)
          .trim()
          .replaceFirst(RegExp(r'/+$'), '');
      if (serverUrl.isEmpty ||
          (accessTokenProvider == null && settings.apiToken.trim().isEmpty)) {
        return const SyncResult(false, 'Server nije podešen');
      }
      final apiToken = accessTokenProvider == null
          ? settings.apiToken.trim()
          : await accessTokenProvider!.accessToken();
      final connection = (serverUrl: serverUrl, apiToken: apiToken);
      final currentV2Transport = v2Transport;
      // Recover an interrupted compatibility exchange before probing v2.
      // Otherwise speculative legacy staging could protect stale state while
      // a newer v2 baseline is being downloaded.
      if (await db.hasPendingV1Fallback()) {
        try {
          return await _syncV1(settings, connection, fallbackFromV2: true);
        } on SyncServerException catch (error) {
          if (error.code != 'v1_read_only' || currentV2Transport == null) {
            rethrow;
          }
          await db.promotePendingV1FallbackToV2();
          return await _syncV2(settings, connection, currentV2Transport);
        }
      }
      var fellBackFromV2 = false;
      if (currentV2Transport != null) {
        try {
          return await _syncV2(settings, connection, currentV2Transport);
        } on _SyncV2Unavailable {
          // A server without the v2 route may still serve the compatibility
          // endpoint. _syncV2 permits this only before a server is pinned.
          fellBackFromV2 = true;
        }
      }
      try {
        return await _syncV1(
          settings,
          connection,
          fallbackFromV2: fellBackFromV2,
        );
      } on SyncServerException catch (error) {
        if (!fellBackFromV2 ||
            error.code != 'v1_read_only' ||
            currentV2Transport == null) {
          rethrow;
        }
        await db.promotePendingV1FallbackToV2();
        return await _syncV2(settings, connection, currentV2Transport);
      }
    } on SyncServerException catch (error) {
      return _serverFailure(error);
    } on AuthException catch (error) {
      if (error.invalidatesSession ||
          error.kind == AuthFailureKind.credentials) {
        return const SyncResult(
          false,
          'Sesija je istekla · prijavite se ponovno',
        );
      }
      return const SyncResult(false, 'Offline · spremljeno lokalno');
    } on FormatException {
      return const SyncResult(false, 'Offline · spremljeno lokalno');
    } on ArgumentError {
      return const SyncResult(false, 'Offline · spremljeno lokalno');
    } on StateError {
      return const SyncResult(
        false,
        'Greška sinkronizacije · spremljeno lokalno',
      );
    } on Exception {
      return const SyncResult(false, 'Offline · spremljeno lokalno');
    }
  }

  SyncResult _serverFailure(SyncServerException error) {
    if (accessTokenProvider != null &&
        error.statusCode == HttpStatus.unauthorized) {
      return const SyncResult(
        false,
        'Sesija je istekla · prijavite se ponovno',
      );
    }
    if (error.code == 'server_mismatch') {
      return SyncResult(
        false,
        accessTokenProvider == null
            ? 'Drugi server · u Postavkama odaberite povezivanje novog servera'
            : 'Vezu sa serverom treba popraviti · otvorite Postavke',
      );
    }
    if (error.code == 'cursor_invalid') {
      return SyncResult(
        false,
        accessTokenProvider == null
            ? 'Server je vraćen na starije stanje · ponovno ga povežite'
            : 'Sync zapis računa treba obnoviti · otvorite Postavke',
      );
    }
    if (error.code == 'mutation_id_reused' ||
        error.code == 'request_id_reused') {
      return const SyncResult(
        false,
        'Sukob identiteta sinkronizacije · promjene su sačuvane',
      );
    }
    if (error.code == 'v1_read_only') {
      return const SyncResult(
        false,
        'Server je nadograđen tijekom stare sinkronizacije · '
        'promjene su sačuvane; ponovno ga povežite u Postavkama',
      );
    }
    return switch (error.statusCode) {
      HttpStatus.badRequest ||
      HttpStatus.unprocessableEntity => const SyncResult(
        false,
        'Server je odbio neispravne podatke · promjene su sačuvane',
      ),
      HttpStatus.unauthorized || HttpStatus.forbidden => const SyncResult(
        false,
        'Prijava na server nije uspjela · provjerite API token',
      ),
      HttpStatus.notFound ||
      HttpStatus.methodNotAllowed ||
      HttpStatus.notImplemented => const SyncResult(
        false,
        'Sinkronizacija v2 nije dostupna na povezanom serveru',
      ),
      HttpStatus.conflict => const SyncResult(
        false,
        'Sukob sinkronizacije · promjene su sačuvane',
      ),
      HttpStatus.requestEntityTooLarge => const SyncResult(
        false,
        'Sinkronizacijski paket je prevelik · promjene su sačuvane',
      ),
      HttpStatus.tooManyRequests => const SyncResult(
        false,
        'Previše zahtjeva · pokušajte ponovno kasnije',
      ),
      >= 500 => const SyncResult(
        false,
        'Server trenutačno nije dostupan · spremljeno lokalno',
      ),
      _ => SyncResult(
        false,
        'Server: ${error.statusCode} · promjene su sačuvane',
      ),
    };
  }

  Future<SyncResult> _syncV1(
    SyncSettings settings,
    ({String serverUrl, String apiToken}) connection, {
    bool fallbackFromV2 = false,
  }) async {
    final fallbackBatch = fallbackFromV2
        ? await db.prepareV1Fallback(settings.cursor)
        : null;
    final changes =
        fallbackBatch?.changes ?? await db.changedSince(settings.cursor);
    final exchange = await transport.exchange(
      serverUrl: connection.serverUrl,
      apiToken: connection.apiToken,
      since: fallbackBatch?.since ?? settings.cursor,
      changes: changes,
    );
    if (fallbackFromV2) {
      await db.completeV1Fallback(exchange.changes, exchange.serverTime);
    } else {
      await db.mergeRemote(exchange.changes);
    }
    await settingsRepository.saveCursor(exchange.serverTime);
    return _completedResult();
  }

  Future<SyncResult> _syncV2(
    SyncSettings settings,
    ({String serverUrl, String apiToken}) connection,
    SyncV2Transport currentTransport,
  ) async {
    var batch = await db.prepareSyncV2(legacyCursor: settings.cursor);
    for (var iteration = 0; iteration < maxV2Iterations; iteration++) {
      late final bool hasMore;
      try {
        final exchange = await currentTransport.exchange(
          serverUrl: connection.serverUrl,
          apiToken: connection.apiToken,
          batch: batch,
        );
        await db.applySyncV2(exchange);
        hasMore = exchange.hasMore;
      } on SyncServerException catch (error) {
        if (iteration == 0 &&
            batch.serverId.isEmpty &&
            _v2UnavailableStatusCodes.contains(error.statusCode)) {
          throw const _SyncV2Unavailable();
        }
        rethrow;
      }

      final pending = await db.hasPendingSyncV2();
      // The response is applied before deciding whether another exchange is
      // needed. Concurrent local writes are therefore picked up immediately.
      if (!hasMore && !pending) {
        await settingsRepository.saveLastSuccessfulSyncAt(
          DateTime.fromMillisecondsSinceEpoch(_nowMilliseconds()),
        );
        return _completedResult();
      }
      batch = await db.prepareSyncV2(legacyCursor: settings.cursor);
    }
    return const SyncResult(
      true,
      'Djelomično sinkronizirano · nastavak slijedi',
      hasPending: true,
    );
  }

  Future<SyncResult> _completedResult() async {
    final review = await db.syncMigrationReviewSummary();
    if (review.blocked > 0) {
      return SyncResult(
        true,
        'Sinkronizirano · ${review.blocked} migriranih zapisa nije poslano',
      );
    }
    if (review.total > 0) {
      return SyncResult(
        true,
        'Sinkronizirano · ${review.total} migriranih zapisa za provjeru',
      );
    }
    return const SyncResult(true, 'Sinkronizirano');
  }
}

const _v2UnavailableStatusCodes = {
  HttpStatus.notFound,
  HttpStatus.methodNotAllowed,
  HttpStatus.notImplemented,
};

class _SyncV2Unavailable implements Exception {
  const _SyncV2Unavailable();
}
