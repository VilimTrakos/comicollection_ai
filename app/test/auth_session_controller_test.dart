import 'package:comicollect/data/auth/auth_api.dart';
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
}

class _MemoryStore implements AuthSessionStore {
  @override
  Future<void> clear() async {}
  @override
  Future<StoredAuthSession?> read() async => null;
  @override
  Future<void> write(StoredAuthSession session) async {}
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
