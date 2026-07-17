import 'dart:async';

import 'package:comicollect/app/app_runtime.dart';
import 'package:comicollect/app/app_runtime_factory.dart';
import 'package:comicollect/app/comicollect_app.dart';
import 'package:comicollect/data/auth/auth_api.dart';
import 'package:comicollect/data/auth/auth_repository.dart';
import 'package:comicollect/data/auth/auth_session_store.dart';
import 'package:comicollect/data/local_database.dart';
import 'package:comicollect/features/auth/login_gate.dart';
import 'package:comicollect/features/shell/app_shell.dart';
import 'package:comicollect/models/account.dart';
import 'package:comicollect/models/auth_failure.dart';
import 'package:comicollect/models/auth_session.dart';
import 'package:comicollect/services/auth/auth_session_controller.dart';
import 'package:comicollect/services/auth/installation_id_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({
      'installation_id_v1': 'installation-1',
    });
  });

  testWidgets('LoginGate performs real login and shows sanitized errors', (
    tester,
  ) async {
    final api = _UiAuthApi();
    final auth = _controller(api);
    addTearDown(auth.dispose);
    await auth.restore();
    await tester.pumpWidget(MaterialApp(home: LoginGate(authController: auth)));
    await _openLogin(tester);
    await tester.enterText(
      find.byKey(const ValueKey('auth-email')),
      ' Collector@Example.Test ',
    );
    await tester.enterText(
      find.byKey(const ValueKey('auth-password')),
      'exact password',
    );
    await tester.tap(find.text('PRIJAVI SE'));
    await tester.pump();

    expect(auth.state, isA<AuthSignedIn>());
    expect(api.loginEmail, 'collector@example.test');
    expect(api.loginPassword, 'exact password');

    await auth.logout();
    api.loginError = const AuthException(kind: AuthFailureKind.credentials);
    await tester.enterText(
      find.byKey(const ValueKey('auth-email')),
      'collector@example.test',
    );
    await tester.enterText(
      find.byKey(const ValueKey('auth-password')),
      'wrong password',
    );
    await tester.tap(find.text('PRIJAVI SE'));
    await tester.pump();
    expect(find.text('E-mail ili lozinka nisu ispravni.'), findsOneWidget);
  });

  testWidgets('register uses its own fields and confirmation', (tester) async {
    final api = _UiAuthApi();
    final auth = _controller(api);
    addTearDown(auth.dispose);
    await auth.restore();
    await tester.pumpWidget(MaterialApp(home: LoginGate(authController: auth)));
    await _openLogin(tester);
    await tester.tap(find.text('NAPRAVI NOVI RAČUN'));
    await tester.pump();
    await tester.enterText(
      find.byKey(const ValueKey('auth-display-name')),
      'Collector',
    );
    await tester.enterText(
      find.byKey(const ValueKey('auth-email')),
      'new@example.test',
    );
    await tester.enterText(
      find.byKey(const ValueKey('auth-password')),
      'twelve-chars!',
    );
    await tester.enterText(
      find.byKey(const ValueKey('auth-password-confirmation')),
      'twelve-chars!',
    );
    await tester.tap(find.text('NAPRAVI NOVI RAČUN'));
    await tester.pump();

    expect(auth.state, isA<AuthSignedIn>());
    expect(api.registerName, 'Collector');
  });

  testWidgets('logout cancels a pending account runtime creation', (
    tester,
  ) async {
    final api = _UiAuthApi();
    final auth = _controller(api);
    addTearDown(auth.dispose);
    await auth.restore();
    final runtimes = _DelayedRuntimeProvider();
    await tester.pumpWidget(
      ComicollectApp(authController: auth, runtimeFactory: runtimes),
    );

    await auth.login('collector@example.test', 'exact password');
    await tester.pump();
    expect(runtimes.accountCreates, 1);
    await auth.logout();
    await tester.pump();

    final runtime = AppRuntime(
      controller: RecordingController(),
      database: LocalDatabase(pathOverride: '/tmp/auth-race-unused.db'),
      account: _account,
    );
    runtimes.pending.complete(runtime);
    await tester.pumpAndSettle();

    expect(find.text('UĐI U KOLEKCIJU'), findsOneWidget);
    expect(find.text('COMICOLLECT'), findsNothing);
  });

  testWidgets('delayed account runtime failure is ignored after logout', (
    tester,
  ) async {
    final api = _UiAuthApi();
    final auth = _controller(api);
    addTearDown(auth.dispose);
    await auth.restore();
    final runtimes = _DelayedRuntimeProvider();
    await tester.pumpWidget(
      ComicollectApp(authController: auth, runtimeFactory: runtimes),
    );

    await auth.login('collector@example.test', 'exact password');
    await tester.pump();
    await auth.logout();
    await tester.pump();
    runtimes.pending.completeError(StateError('stale account failure'));
    await tester.pumpAndSettle();

    expect(find.text('UĐI U KOLEKCIJU'), findsOneWidget);
    expect(find.text('Lokalni podaci se ne mogu otvoriti.'), findsNothing);
  });

  testWidgets('guest runtime error retries guest creation', (tester) async {
    final api = _UiAuthApi();
    final auth = _controller(api);
    addTearDown(auth.dispose);
    await auth.restore();
    final runtimes = _RetryGuestRuntimeProvider();
    await tester.pumpWidget(
      ComicollectApp(authController: auth, runtimeFactory: runtimes),
    );

    await tester.tap(find.text('Nastavi kao gost'));
    await _pumpUntil(tester, find.text('Lokalni podaci se ne mogu otvoriti.'));

    expect(runtimes.guestCreates, 1);
    expect(find.text('Lokalni podaci se ne mogu otvoriti.'), findsOneWidget);
    expect(find.text('NATRAG'), findsOneWidget);

    await tester.tap(find.text('POKUŠAJ PONOVNO'));
    await _pumpUntil(tester, find.byType(Shell));

    expect(runtimes.guestCreates, 2);
    expect(find.byType(Shell), findsOneWidget);
    expect(find.text('Lokalni podaci se ne mogu otvoriti.'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await runtimes.runtime.close();
  });

  testWidgets('logout resets pushed routes before closing account runtime', (
    tester,
  ) async {
    final api = _UiAuthApi();
    final auth = _controller(api);
    addTearDown(auth.dispose);
    await auth.restore();
    final runtimes = _ImmediateAccountRuntimeProvider();
    await tester.pumpWidget(
      ComicollectApp(authController: auth, runtimeFactory: runtimes),
    );

    await auth.login('collector@example.test', 'exact password');
    await _pumpUntil(tester, find.byType(Shell));
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('STARI EKRAN RAČUNA')),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('STARI EKRAN RAČUNA'), findsOneWidget);

    await auth.logout();
    await _pumpUntil(tester, find.text('UĐI U KOLEKCIJU'));

    expect(find.text('STARI EKRAN RAČUNA'), findsNothing);
    expect(find.text('UĐI U KOLEKCIJU'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await runtimes.runtime.close();
  });

  testWidgets('failed credential cleanup remains visible and signed in', (
    tester,
  ) async {
    final api = _UiAuthApi();
    final store = _MemoryStore();
    final auth = _controller(api, store: store);
    addTearDown(auth.dispose);
    await auth.restore();
    final runtimes = _ImmediateAccountRuntimeProvider();
    await tester.pumpWidget(
      ComicollectApp(authController: auth, runtimeFactory: runtimes),
    );

    await auth.login('collector@example.test', 'exact password');
    await _pumpUntil(tester, find.byType(Shell));
    store.clearError = StateError('secure storage locked');
    await auth.logout();
    await tester.pump();
    await tester.tap(find.text('Postavke'));
    await tester.pump();
    await tester.scrollUntilVisible(
      find.text('Odjava nije uspjela'),
      250,
      scrollable: find.byType(Scrollable).first,
    );

    expect(auth.state, isA<AuthSignedIn>());
    expect(find.text('Odjava nije uspjela'), findsOneWidget);
    expect(
      find.textContaining('Podaci za prijavu nisu obrisani'),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await runtimes.runtime.close();
  });
}

Future<void> _openLogin(WidgetTester tester) async {
  await tester.tap(find.text('UĐI U KOLEKCIJU'));
  await tester.pump();
  await tester.tap(find.text('Osobna kolekcija'));
  await tester.pump();
}

Future<void> _pumpUntil(WidgetTester tester, Finder finder) async {
  for (var attempt = 0; attempt < 20; attempt++) {
    await tester.pump(const Duration(milliseconds: 10));
    if (finder.evaluate().isNotEmpty) return;
  }
  throw TestFailure('Expected widget did not appear: $finder');
}

AuthSessionController _controller(_UiAuthApi api, {_MemoryStore? store}) =>
    AuthSessionController(
      AuthRepository(
        api: api,
        store: store ?? _MemoryStore(),
        installationIds: InstallationIdRepository(),
        now: () => DateTime.utc(2030),
        requestIdGenerator: () => 'refresh-request-1',
      ),
    );

const _account = Account(
  id: 'account-1',
  email: 'collector@example.test',
  displayName: 'Collector',
  emailVerified: true,
);

class _UiAuthApi implements AuthApi {
  String? loginEmail;
  String? loginPassword;
  String? registerName;
  AuthException? loginError;

  AuthApiSession get session => AuthApiSession(
    account: _account,
    accessToken: 'cca_access.secret',
    accessExpiresAt: DateTime.utc(2030).add(const Duration(minutes: 15)),
    refreshToken: 'ccr_refresh.secret',
    refreshExpiresAt: DateTime.utc(2030).add(const Duration(days: 30)),
  );

  @override
  Future<AuthApiSession> login({
    required String email,
    required String password,
    required String installationId,
  }) async {
    loginEmail = email;
    loginPassword = password;
    if (loginError case final error?) throw error;
    return session;
  }

  @override
  Future<AuthApiSession> register({
    required String email,
    required String password,
    required String displayName,
    required String installationId,
  }) async {
    registerName = displayName;
    return session;
  }

  @override
  Future<AuthApiSession> refresh({
    required String refreshToken,
    required String installationId,
    required String requestId,
  }) async => session;

  @override
  Future<void> logout({required String accessToken}) async {}

  @override
  Future<Account> me({required String accessToken}) async => _account;
}

class _MemoryStore implements AuthSessionStore {
  StoredAuthSession? value;
  Object? clearError;
  @override
  Future<void> clear() async {
    final error = clearError;
    if (error != null) throw error;
    value = null;
  }

  @override
  Future<StoredAuthSession?> read() async => value;
  @override
  Future<void> write(StoredAuthSession session) async => value = session;
}

class _DelayedRuntimeProvider implements AppRuntimeProvider {
  final pending = Completer<AppRuntime>();
  int accountCreates = 0;

  @override
  Future<AppRuntime> createAccount(Account account) {
    accountCreates++;
    return pending.future;
  }

  @override
  Future<AppRuntime> createGuest() => throw UnimplementedError();
}

class _RetryGuestRuntimeProvider implements AppRuntimeProvider {
  final runtime = AppRuntime(
    controller: RecordingController(),
    database: LocalDatabase(pathOverride: '/tmp/guest-retry-unused.db'),
  );
  int guestCreates = 0;

  @override
  Future<AppRuntime> createAccount(Account account) =>
      throw UnimplementedError();

  @override
  Future<AppRuntime> createGuest() async {
    guestCreates++;
    if (guestCreates == 1) throw StateError('temporary guest failure');
    return runtime;
  }
}

class _ImmediateAccountRuntimeProvider implements AppRuntimeProvider {
  final runtime = AppRuntime(
    controller: RecordingController(),
    database: LocalDatabase(pathOverride: '/tmp/account-ui-unused.db'),
    account: _account,
  );

  @override
  Future<AppRuntime> createAccount(Account account) async => runtime;

  @override
  Future<AppRuntime> createGuest() => throw UnimplementedError();
}
