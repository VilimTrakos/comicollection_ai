import 'dart:async';

import 'package:comicollect/data/auth/auth_api.dart';
import 'package:comicollect/data/auth/auth_repository.dart';
import 'package:comicollect/data/auth/auth_session_store.dart';
import 'package:comicollect/models/account.dart';
import 'package:comicollect/models/auth_failure.dart';
import 'package:comicollect/models/auth_session.dart';
import 'package:comicollect/services/auth/installation_id_repository.dart';
import 'package:comicollect/services/auth/auth_session_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final now = DateTime.utc(2030);

  setUp(
    () => SharedPreferences.setMockInitialValues({
      'installation_id_v1': 'installation-1',
    }),
  );

  test('rotating refresh is single-flight for concurrent callers', () async {
    final store = _MemorySessionStore(_stored(now));
    final api = _FakeAuthApi(now);
    var nextId = 0;
    final repository = AuthRepository(
      api: api,
      store: store,
      installationIds: InstallationIdRepository(),
      now: () => now,
      requestIdGenerator: () => 'refresh-request-${++nextId}',
    );

    expect((await repository.restore()).signedIn, isTrue);
    final pending = Completer<AuthApiSession>();
    api.pendingRefresh = pending;
    final calls = [
      repository.accessToken(forceRefresh: true),
      repository.accessToken(forceRefresh: true),
      repository.accessToken(forceRefresh: true),
    ];
    await Future<void>.delayed(Duration.zero);
    expect(api.refreshCalls, 2);
    pending.complete(_apiSession(now, access: 'cca_new.secret'));

    expect(await Future.wait(calls), everyElement('cca_new.secret'));
    expect(api.refreshCalls, 2);
    expect(api.requestIds, ['refresh-request-1', 'refresh-request-2']);
    expect(store.value!.refreshRequestId, isNull);
  });

  test(
    'persists and reuses refresh request id after a network crash',
    () async {
      final store = _MemorySessionStore(_stored(now));
      final failingApi = _FakeAuthApi(now)
        ..refreshError = const AuthException(kind: AuthFailureKind.network);
      final first = AuthRepository(
        api: failingApi,
        store: store,
        installationIds: InstallationIdRepository(),
        now: () => now,
        requestIdGenerator: () => 'durable-request',
      );

      final offline = await first.restore();
      expect(offline.offline, isTrue);
      expect(store.value!.refreshRequestId, 'durable-request');

      final retryApi = _FakeAuthApi(now);
      final second = AuthRepository(
        api: retryApi,
        store: store,
        installationIds: InstallationIdRepository(),
        now: () => now,
        requestIdGenerator: () => 'must-not-be-used',
      );
      expect((await second.restore()).signedIn, isTrue);
      expect(retryApi.requestIds.single, 'durable-request');
    },
  );

  test(
    'offline logout refreshes before revocation and always clears locally',
    () async {
      final store = _MemorySessionStore(_stored(now));
      final api = _FakeAuthApi(now)
        ..refreshError = const AuthException(kind: AuthFailureKind.network);
      final restarted = AuthRepository(
        api: api,
        store: store,
        installationIds: InstallationIdRepository(),
        now: () => now,
        requestIdGenerator: () => 'logout-refresh-2',
      );
      expect((await restarted.restore()).offline, isTrue);
      api.refreshError = null;
      await restarted.logout();

      expect(api.logoutCalls, 1);
      expect(store.value, isNull);
    },
  );

  test(
    'logout waits for an in-flight refresh and prevents session resurrection',
    () async {
      final store = _MemorySessionStore(_stored(now));
      final api = _FakeAuthApi(now);
      final repository = AuthRepository(
        api: api,
        store: store,
        installationIds: InstallationIdRepository(),
        now: () => now,
        requestIdGenerator: () => 'refresh-during-logout',
      );
      await repository.restore();
      final pending = Completer<AuthApiSession>();
      api.pendingRefresh = pending;
      final refresh = repository.accessToken(forceRefresh: true);
      final logout = repository.logout();

      pending.complete(_apiSession(now, access: 'cca_late.secret'));
      await refresh;
      await logout;

      expect(api.logoutCalls, 1);
      expect(store.value, isNull);
      await expectLater(
        repository.accessToken(),
        throwsA(isA<AuthException>()),
      );
    },
  );

  test(
    'failed secure deletion keeps the account signed in and logout retriable',
    () async {
      final store = _MemorySessionStore(_stored(now));
      final api = _FakeAuthApi(now);
      final repository = AuthRepository(
        api: api,
        store: store,
        installationIds: InstallationIdRepository(),
        now: () => now,
        requestIdGenerator: () => 'logout-storage-failure',
      );
      final controller = AuthSessionController(repository);
      addTearDown(controller.dispose);
      await controller.restore();
      store.failClear = true;

      await controller.logout();

      expect(controller.state, isA<AuthSignedIn>());
      expect(
        (controller.state as AuthSignedIn).failure?.kind,
        AuthFailureKind.storage,
      );
      expect(store.value, isNotNull);
      expect(api.logoutCalls, 0, reason: 'do not revoke before local deletion');

      final restart = AuthRepository(
        api: _FakeAuthApi(now),
        store: store,
        installationIds: InstallationIdRepository(),
        now: () => now,
        requestIdGenerator: () => 'restart-after-failed-logout',
      );
      expect((await restart.restore()).signedIn, isTrue);

      store.failClear = false;
      await controller.logout();
      expect(controller.state, isA<AuthSignedOut>());
      expect(store.value, isNull);
      expect(api.logoutCalls, 1);

      final finalRestart = AuthRepository(
        api: _FakeAuthApi(now),
        store: store,
        installationIds: InstallationIdRepository(),
        now: () => now,
      );
      expect((await finalRestart.restore()).signedIn, isFalse);
    },
  );

  test(
    'remote revoke failure does not block successful local logout',
    () async {
      final store = _MemorySessionStore(_stored(now));
      final api = _FakeAuthApi(now)..logoutError = StateError('offline');
      final repository = AuthRepository(
        api: api,
        store: store,
        installationIds: InstallationIdRepository(),
        now: () => now,
        requestIdGenerator: () => 'best-effort-revoke',
      );
      await repository.restore();

      await repository.logout();

      expect(store.value, isNull);
      expect(repository.account, isNull);
      expect(api.logoutCalls, 1);
    },
  );

  test('register and login enforce backend input byte boundaries', () async {
    final store = _MemorySessionStore(null);
    final api = _FakeAuthApi(now);
    final repository = AuthRepository(
      api: api,
      store: store,
      installationIds: InstallationIdRepository(),
      now: () => now,
    );
    final ascii = (int count) => List.filled(count, 'a').join();
    final emoji = (int count) => List.filled(count, '😀').join();

    for (final input in [
      (password: ascii(11), displayName: 'Collector'),
      (password: ascii(129), displayName: 'Collector'),
      (password: ascii(12), displayName: ascii(101)),
      (password: ascii(12), displayName: emoji(51)),
    ]) {
      await expectLater(
        repository.register(
          email: 'collector@example.test',
          password: input.password,
          displayName: input.displayName,
        ),
        throwsA(
          isA<AuthException>().having(
            (error) => error.kind,
            'kind',
            AuthFailureKind.credentials,
          ),
        ),
      );
    }
    expect(api.registerCalls, 0);

    await repository.register(
      email: 'collector@example.test',
      password: ascii(128),
      displayName: ascii(100),
    );
    expect(api.registerCalls, 1);

    await expectLater(
      repository.login(email: 'collector@example.test', password: emoji(257)),
      throwsA(
        isA<AuthException>().having(
          (error) => error.kind,
          'kind',
          AuthFailureKind.credentials,
        ),
      ),
    );
    expect(api.loginCalls, 0);

    await repository.login(
      email: 'collector@example.test',
      password: emoji(256),
    );
    expect(api.loginCalls, 1);

    await expectLater(
      repository.login(email: '${emoji(63)}@example.test', password: ascii(12)),
      throwsA(
        isA<AuthException>().having(
          (error) => error.kind,
          'kind',
          AuthFailureKind.credentials,
        ),
      ),
    );
    expect(api.loginCalls, 1);
  });

  test('temporary refresh failures preserve the durable account', () async {
    for (final kind in [
      AuthFailureKind.rateLimited,
      AuthFailureKind.invalidResponse,
      AuthFailureKind.storage,
    ]) {
      final store = _MemorySessionStore(_stored(now));
      final repository = AuthRepository(
        api: _FakeAuthApi(now)..refreshError = AuthException(kind: kind),
        store: store,
        installationIds: InstallationIdRepository(),
        now: () => now,
        requestIdGenerator: () => 'temporary-$kind',
      );

      final result = await repository.restore();

      expect(result.signedIn, isTrue, reason: '$kind');
      expect(result.offline, isTrue, reason: '$kind');
      expect(store.value, isNotNull, reason: '$kind');
    }
  });
}

const _account = Account(
  id: 'account-1',
  email: 'collector@example.test',
  displayName: 'Collector',
  emailVerified: true,
);

StoredAuthSession _stored(DateTime now) => StoredAuthSession(
  account: _account,
  refreshToken: 'ccr_old.secret',
  refreshExpiresAt: now.add(const Duration(days: 30)),
);

AuthApiSession _apiSession(DateTime now, {String access = 'cca_one.secret'}) =>
    AuthApiSession(
      account: _account,
      accessToken: access,
      accessExpiresAt: now.add(const Duration(minutes: 15)),
      refreshToken: 'ccr_rotated.secret',
      refreshExpiresAt: now.add(const Duration(days: 30)),
    );

class _MemorySessionStore implements AuthSessionStore {
  _MemorySessionStore(this.value);
  StoredAuthSession? value;
  bool failClear = false;

  @override
  Future<void> clear() async {
    if (failClear) throw StateError('secure deletion failed');
    value = null;
  }

  @override
  Future<StoredAuthSession?> read() async => value;

  @override
  Future<void> write(StoredAuthSession session) async => value = session;
}

class _FakeAuthApi implements AuthApi {
  _FakeAuthApi(this.now);
  final DateTime now;
  int refreshCalls = 0;
  int logoutCalls = 0;
  int loginCalls = 0;
  int registerCalls = 0;
  final requestIds = <String>[];
  Completer<AuthApiSession>? pendingRefresh;
  AuthException? refreshError;
  Object? logoutError;

  @override
  Future<AuthApiSession> refresh({
    required String refreshToken,
    required String installationId,
    required String requestId,
  }) async {
    refreshCalls++;
    requestIds.add(requestId);
    if (refreshError case final error?) throw error;
    if (pendingRefresh case final pending?) return pending.future;
    return _apiSession(now);
  }

  @override
  Future<void> logout({required String accessToken}) async {
    logoutCalls++;
    if (logoutError case final error?) throw error;
  }

  @override
  Future<AuthApiSession> login({
    required String email,
    required String password,
    required String installationId,
  }) async {
    loginCalls++;
    return _apiSession(now);
  }

  @override
  Future<AuthApiSession> register({
    required String email,
    required String password,
    required String displayName,
    required String installationId,
  }) async {
    registerCalls++;
    return _apiSession(now);
  }

  @override
  Future<Account> me({required String accessToken}) async => _account;
}
