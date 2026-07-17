import 'dart:async';
import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../../models/account.dart';
import '../../models/auth_failure.dart';
import '../../models/auth_session.dart';
import '../../services/auth/access_token_provider.dart';
import '../../services/auth/installation_id_repository.dart';
import 'auth_api.dart';
import 'auth_session_store.dart';

enum AuthRepositoryEvent { sessionExpired }

final class AuthRestoreResult {
  const AuthRestoreResult.signedOut() : account = null, offline = false;
  const AuthRestoreResult.signedIn(this.account, {required this.offline});

  final Account? account;
  final bool offline;
  bool get signedIn => account != null;
}

final class AuthRepository implements AccessTokenProvider {
  AuthRepository({
    required this.api,
    required this.store,
    required this.installationIds,
    DateTime Function()? now,
    String Function()? requestIdGenerator,
    this.refreshSkew = const Duration(seconds: 30),
  }) : _now = now ?? (() => DateTime.now().toUtc()),
       _requestIdGenerator = requestIdGenerator ?? const Uuid().v4;

  final AuthApi api;
  final AuthSessionStore store;
  final InstallationIdRepository installationIds;
  final DateTime Function() _now;
  final Duration refreshSkew;
  final String Function() _requestIdGenerator;
  final _events = StreamController<AuthRepositoryEvent>.broadcast();

  StoredAuthSession? _stored;
  String? _accessToken;
  DateTime? _accessExpiresAt;
  Future<String>? _refreshFuture;
  bool _loggingOut = false;

  Stream<AuthRepositoryEvent> get events => _events.stream;
  Account? get account => _stored?.account;

  Future<AuthRestoreResult> restore() async {
    final stored = await _readStored();
    if (stored == null) return const AuthRestoreResult.signedOut();
    if (!stored.refreshExpiresAt.isAfter(_now())) {
      await _clear(notifyExpired: false);
      return const AuthRestoreResult.signedOut();
    }
    _stored = stored;
    try {
      await accessToken(forceRefresh: true);
      return AuthRestoreResult.signedIn(_stored!.account, offline: false);
    } on AuthException catch (error) {
      if (error.invalidatesSession ||
          error.kind == AuthFailureKind.credentials) {
        await _clear(notifyExpired: false);
        return const AuthRestoreResult.signedOut();
      }
      // A proxy error, rate limit or temporary secure-storage failure is not
      // evidence that the durable refresh credential is invalid. Keep the
      // local account usable and retry refresh when connectivity recovers.
      return AuthRestoreResult.signedIn(stored.account, offline: true);
    }
  }

  Future<Account> login({
    required String email,
    required String password,
  }) async {
    final normalizedEmail = _email(email);
    if (password.isEmpty ||
        password.length > 1024 ||
        _utf8Length(password) > 1024) {
      throw const AuthException(kind: AuthFailureKind.credentials);
    }
    final session = await api.login(
      email: normalizedEmail,
      password: password,
      installationId: await _installationId(),
    );
    await _accept(session);
    return session.account;
  }

  Future<Account> register({
    required String email,
    required String password,
    required String displayName,
  }) async {
    final name = displayName.trim();
    final passwordCharacters = password.runes.length;
    if (name.isEmpty ||
        name.runes.length > 100 ||
        _utf8Length(name) > 200 ||
        passwordCharacters < 12 ||
        passwordCharacters > 128 ||
        _utf8Length(password) > 1024) {
      throw const AuthException(kind: AuthFailureKind.credentials);
    }
    final session = await api.register(
      email: _email(email),
      password: password,
      displayName: name,
      installationId: await _installationId(),
    );
    await _accept(session);
    return session.account;
  }

  @override
  Future<String> accessToken({bool forceRefresh = false}) async {
    if (_loggingOut) {
      throw const AuthException(kind: AuthFailureKind.sessionExpired);
    }
    final token = _accessToken;
    final expiry = _accessExpiresAt;
    if (!forceRefresh &&
        token != null &&
        expiry != null &&
        expiry.isAfter(_now().add(refreshSkew))) {
      return token;
    }
    final pending = _refreshFuture;
    if (pending != null) return pending;
    final created = _refresh();
    _refreshFuture = created;
    try {
      return await created;
    } finally {
      if (identical(_refreshFuture, created)) _refreshFuture = null;
    }
  }

  Future<void> logout() async {
    if (_loggingOut) return;
    _loggingOut = true;
    try {
      try {
        await _refreshFuture;
      } on Object {
        // Local logout continues even when an in-flight refresh failed.
      }
      var access = _accessToken;
      if (_stored != null && access == null) {
        try {
          access = await _refresh();
        } on Object {
          access = null;
        }
      }

      // Local credential deletion is the authoritative logout boundary. Do
      // not revoke the remote session first: if secure storage cannot be
      // cleared, the caller must remain signed in and be able to retry.
      await _clear(notifyExpired: false);

      if (access != null) {
        try {
          await api.logout(accessToken: access);
        } on Object {
          // Revocation is best-effort after local credentials are gone. The
          // server-side session has its own bounded expiry.
        }
      }
    } finally {
      _loggingOut = false;
    }
  }

  Future<String> _refresh() async {
    final stored = _stored ?? await _readStored();
    if (stored == null || !stored.refreshExpiresAt.isAfter(_now())) {
      await _clear(notifyExpired: true);
      throw const AuthException(kind: AuthFailureKind.sessionExpired);
    }
    _stored = stored;
    try {
      final requestId = stored.refreshRequestId ?? _requestIdGenerator().trim();
      if (requestId.isEmpty) {
        throw const AuthException(kind: AuthFailureKind.invalidResponse);
      }
      final pending = stored.refreshRequestId == null
          ? stored.copyWith(refreshRequestId: requestId)
          : stored;
      if (stored.refreshRequestId == null) {
        await _writeStored(pending);
        _stored = pending;
      }
      final session = await api.refresh(
        refreshToken: stored.refreshToken,
        installationId: await _installationId(),
        requestId: requestId,
      );
      if (session.account.id != stored.account.id) {
        throw const AuthException(kind: AuthFailureKind.invalidResponse);
      }
      await _accept(session);
      return session.accessToken;
    } on AuthException catch (error) {
      if (error.invalidatesSession ||
          error.kind == AuthFailureKind.credentials) {
        await _clear(notifyExpired: true);
      }
      rethrow;
    }
  }

  Future<void> _accept(AuthApiSession session) async {
    if (!session.accessExpiresAt.isAfter(_now()) ||
        !session.refreshExpiresAt.isAfter(_now())) {
      throw const AuthException(kind: AuthFailureKind.invalidResponse);
    }
    final stored = StoredAuthSession(
      account: session.account,
      refreshToken: session.refreshToken,
      refreshExpiresAt: session.refreshExpiresAt,
    );
    await _writeStored(stored);
    _stored = stored;
    _accessToken = session.accessToken;
    _accessExpiresAt = session.accessExpiresAt;
  }

  Future<void> _clear({required bool notifyExpired}) async {
    try {
      await store.clear();
    } on Object {
      throw const AuthException(kind: AuthFailureKind.storage);
    }
    _stored = null;
    _accessToken = null;
    _accessExpiresAt = null;
    if (notifyExpired && !_events.isClosed) {
      _events.add(AuthRepositoryEvent.sessionExpired);
    }
  }

  Future<StoredAuthSession?> _readStored() async {
    try {
      return await store.read();
    } on AuthException {
      rethrow;
    } on Object {
      throw const AuthException(kind: AuthFailureKind.storage);
    }
  }

  Future<void> _writeStored(StoredAuthSession session) async {
    try {
      await store.write(session);
    } on AuthException {
      rethrow;
    } on Object {
      throw const AuthException(kind: AuthFailureKind.storage);
    }
  }

  Future<String> _installationId() async {
    try {
      return await installationIds.loadOrCreate();
    } on AuthException {
      rethrow;
    } on Object {
      throw const AuthException(kind: AuthFailureKind.storage);
    }
  }

  static String _email(String value) {
    final normalized = value.trim().toLowerCase();
    if (_utf8Length(normalized) > 254 ||
        !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(normalized)) {
      throw const AuthException(kind: AuthFailureKind.credentials);
    }
    return normalized;
  }

  static int _utf8Length(String value) => utf8.encode(value).length;

  Future<void> dispose() async => _events.close();
}
