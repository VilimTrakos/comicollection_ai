import 'package:comicollect/data/auth/auth_api.dart';
import 'package:comicollect/data/auth/account_lifecycle_api.dart';
import 'package:comicollect/data/auth/account_lifecycle_repository.dart';
import 'package:comicollect/data/auth/auth_repository.dart';
import 'package:comicollect/data/auth/auth_session_store.dart';
import 'package:comicollect/models/account.dart';
import 'package:comicollect/models/auth_session.dart';
import 'package:comicollect/services/auth/auth_session_controller.dart';
import 'package:comicollect/services/auth/installation_id_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(
    () => SharedPreferences.setMockInitialValues({
      'installation_id_v1': 'installation-1',
    }),
  );

  test(
    'unexpected restore failure always leaves the restoring state',
    () async {
      final controller = AuthSessionController(
        AuthRepository(
          api: _ThrowingApi(),
          store: _ThrowingStore(),
          installationIds: InstallationIdRepository(),
        ),
      );
      addTearDown(controller.dispose);

      await controller.restore();

      expect(controller.state, isA<AuthSignedOut>());
      expect(controller.busy, isFalse);
    },
  );

  test('unexpected login failure always leaves the submitting state', () async {
    final controller = AuthSessionController(
      AuthRepository(
        api: _ThrowingApi(),
        store: _MemoryStore(),
        installationIds: InstallationIdRepository(),
      ),
    );
    addTearDown(controller.dispose);
    await controller.restore();

    await controller.login('valid@example.test', 'password');

    expect(controller.state, isA<AuthSignedOut>());
    expect(controller.busy, isFalse);
  });

  test(
    'confirmed verification updates controller and durable session',
    () async {
      final store = _MemoryStore();
      final repository = AuthRepository(
        api: _SessionApi(),
        store: store,
        installationIds: InstallationIdRepository(),
      );
      final lifecycleApi = _ControllerLifecycleApi();
      final controller = AuthSessionController(
        repository,
        accountLifecycle: AccountLifecycleRepository(
          api: lifecycleApi,
          accessTokens: repository,
          requestIdGenerator: () => 'verification-request',
        ),
      );
      addTearDown(controller.dispose);
      await controller.restore();
      await controller.login('collector@example.test', 'login-password');

      final confirmed = await controller.confirmEmailVerification(
        'verification-token',
      );

      expect(confirmed, isTrue);
      expect(controller.busy, isFalse);
      expect((controller.state as AuthSignedIn).account.emailVerified, isTrue);
      expect(repository.account?.emailVerified, isTrue);
      expect(store.value?.account.emailVerified, isTrue);
      expect(store.value?.refreshToken, 'refresh-token');
      expect(lifecycleApi.verificationRequestIds, ['verification-request']);
    },
  );

  test('password reset is callable only while signed out', () async {
    final repository = AuthRepository(
      api: _SessionApi(),
      store: _MemoryStore(),
      installationIds: InstallationIdRepository(),
    );
    final lifecycleApi = _ControllerLifecycleApi();
    final controller = AuthSessionController(
      repository,
      accountLifecycle: AccountLifecycleRepository(
        api: lifecycleApi,
        accessTokens: repository,
        requestIdGenerator: () => 'reset-request',
      ),
    );
    addTearDown(controller.dispose);
    await controller.restore();

    expect(
      await controller.requestPasswordReset('collector@example.test'),
      isTrue,
    );
    expect(
      await controller.confirmPasswordReset(
        token: 'reset-token',
        newPassword: 'new-password-value',
      ),
      isTrue,
    );
    expect(controller.state, isA<AuthSignedOut>());
    expect(lifecycleApi.resetEmails, ['collector@example.test']);
    expect(lifecycleApi.resetRequestIds, ['reset-request']);

    await controller.login('collector@example.test', 'login-password');
    expect(
      await controller.requestPasswordReset('collector@example.test'),
      isFalse,
    );
    expect(lifecycleApi.resetEmails, hasLength(1));
  });
}

class _MemoryStore implements AuthSessionStore {
  StoredAuthSession? value;

  @override
  Future<void> clear() async => value = null;
  @override
  Future<StoredAuthSession?> read() async => value;
  @override
  Future<void> write(StoredAuthSession session) async => value = session;
}

class _ThrowingStore extends _MemoryStore {
  @override
  Future<StoredAuthSession?> read() => throw StateError('storage failed');
}

class _ThrowingApi implements AuthApi {
  Never _fail() => throw StateError('unexpected API failure');

  @override
  Future<AuthApiSession> login({
    required String email,
    required String password,
    required String installationId,
  }) async => _fail();
  @override
  Future<void> logout({required String accessToken}) async => _fail();
  @override
  Future<Account> me({required String accessToken}) async => _fail();
  @override
  Future<AuthApiSession> refresh({
    required String refreshToken,
    required String installationId,
    required String requestId,
  }) async => _fail();
  @override
  Future<AuthApiSession> register({
    required String email,
    required String password,
    required String displayName,
    required String installationId,
  }) async => _fail();
}

class _SessionApi implements AuthApi {
  @override
  Future<AuthApiSession> login({
    required String email,
    required String password,
    required String installationId,
  }) async => _session;

  @override
  Future<void> logout({required String accessToken}) async {}

  @override
  Future<Account> me({required String accessToken}) async => _account;

  @override
  Future<AuthApiSession> refresh({
    required String refreshToken,
    required String installationId,
    required String requestId,
  }) async => _session;

  @override
  Future<AuthApiSession> register({
    required String email,
    required String password,
    required String displayName,
    required String installationId,
  }) async => _session;
}

class _ControllerLifecycleApi implements AccountLifecycleApi {
  final verificationRequestIds = <String>[];
  final resetEmails = <String>[];
  final resetRequestIds = <String>[];

  @override
  Future<Account> confirmEmailVerification({
    required String accessToken,
    required String token,
    required String requestId,
  }) async {
    verificationRequestIds.add(requestId);
    return _verifiedAccount;
  }

  @override
  Future<void> confirmPasswordReset({
    required String token,
    required String newPassword,
    required String requestId,
  }) async {
    resetRequestIds.add(requestId);
  }

  @override
  Future<void> requestEmailVerification({required String accessToken}) async {}

  @override
  Future<void> requestPasswordReset({required String email}) async {
    resetEmails.add(email);
  }
}

final _now = DateTime.now().toUtc();

final _session = AuthApiSession(
  account: _account,
  accessToken: 'access-token',
  accessExpiresAt: _now.add(const Duration(hours: 1)),
  refreshToken: 'refresh-token',
  refreshExpiresAt: _now.add(const Duration(days: 30)),
);

const _account = Account(
  id: 'account-1',
  email: 'collector@example.test',
  displayName: 'Collector',
  emailVerified: false,
);

const _verifiedAccount = Account(
  id: 'account-1',
  email: 'collector@example.test',
  displayName: 'Collector',
  emailVerified: true,
);
