import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../data/auth/auth_repository.dart';
import '../../data/auth/account_lifecycle_repository.dart';
import '../../models/account.dart';
import '../../models/auth_failure.dart';

sealed class AuthState {
  const AuthState();
}

final class AuthRestoring extends AuthState {
  const AuthRestoring();
}

final class AuthSignedOut extends AuthState {
  const AuthSignedOut({this.failure, this.sessionExpired = false});
  final AuthException? failure;
  final bool sessionExpired;
}

enum AuthOperation { login, register, logout }

final class AuthSubmitting extends AuthState {
  const AuthSubmitting(this.operation);
  final AuthOperation operation;
}

final class AuthSignedIn extends AuthState {
  const AuthSignedIn(this.account, {required this.offline, this.failure});
  final Account account;
  final bool offline;
  final AuthException? failure;
}

final class AuthSessionController extends ChangeNotifier {
  AuthSessionController(this.repository, {this.accountLifecycle}) {
    _subscription = repository.events.listen((event) {
      if (event == AuthRepositoryEvent.sessionExpired) {
        state = const AuthSignedOut(sessionExpired: true);
        notifyListeners();
      }
    });
  }

  final AuthRepository repository;
  final AccountLifecycleRepository? accountLifecycle;
  late final StreamSubscription<AuthRepositoryEvent> _subscription;
  AuthState state = const AuthRestoring();
  bool _logoutInProgress = false;
  bool _lifecycleInProgress = false;

  bool get busy =>
      state is AuthSubmitting ||
      state is AuthRestoring ||
      _logoutInProgress ||
      _lifecycleInProgress;

  Future<void> restore() async {
    state = const AuthRestoring();
    notifyListeners();
    try {
      final result = await repository.restore();
      state = result.account == null
          ? const AuthSignedOut()
          : AuthSignedIn(result.account!, offline: result.offline);
    } on Object {
      state = const AuthSignedOut(
        failure: AuthException(kind: AuthFailureKind.server),
      );
    }
    notifyListeners();
  }

  Future<void> login(String email, String password) => _submit(
    AuthOperation.login,
    () => repository.login(email: email, password: password),
  );

  Future<void> register(String email, String password, String displayName) =>
      _submit(
        AuthOperation.register,
        () => repository.register(
          email: email,
          password: password,
          displayName: displayName,
        ),
      );

  Future<bool> requestEmailVerification() => _runSignedInLifecycle(
    (lifecycle, _) => lifecycle.requestEmailVerification(),
  );

  Future<bool> confirmEmailVerification(String token) =>
      _runSignedInLifecycle((lifecycle, _) async {
        final account = await lifecycle.confirmEmailVerification(token);
        await repository.updateAccount(account);
        state = AuthSignedIn(account, offline: false);
      });

  Future<bool> requestPasswordReset(String email) => _runSignedOutLifecycle(
    (lifecycle) => lifecycle.requestPasswordReset(email),
  );

  Future<bool> confirmPasswordReset({
    required String token,
    required String newPassword,
  }) => _runSignedOutLifecycle(
    (lifecycle) =>
        lifecycle.confirmPasswordReset(token: token, newPassword: newPassword),
  );

  Future<void> _submit(
    AuthOperation operation,
    Future<Account> Function() action,
  ) async {
    if (busy) return;
    state = AuthSubmitting(operation);
    notifyListeners();
    try {
      state = AuthSignedIn(await action(), offline: false);
    } on AuthException catch (error) {
      state = AuthSignedOut(failure: error);
    } on Object {
      state = const AuthSignedOut(
        failure: AuthException(kind: AuthFailureKind.server),
      );
    }
    notifyListeners();
  }

  Future<bool> _runSignedInLifecycle(
    Future<void> Function(
      AccountLifecycleRepository lifecycle,
      AuthSignedIn current,
    )
    action,
  ) async {
    final current = state;
    final lifecycle = accountLifecycle;
    if (busy || current is! AuthSignedIn || lifecycle == null) return false;
    _lifecycleInProgress = true;
    notifyListeners();
    try {
      await action(lifecycle, current);
      if (identical(state, current)) {
        state = AuthSignedIn(current.account, offline: current.offline);
      }
      return true;
    } on AuthException catch (error) {
      if (state is AuthSignedIn) {
        state = AuthSignedIn(
          current.account,
          offline: current.offline,
          failure: error,
        );
      }
      return false;
    } on Object {
      if (state is AuthSignedIn) {
        state = AuthSignedIn(
          current.account,
          offline: current.offline,
          failure: const AuthException(kind: AuthFailureKind.server),
        );
      }
      return false;
    } finally {
      _lifecycleInProgress = false;
      notifyListeners();
    }
  }

  Future<bool> _runSignedOutLifecycle(
    Future<void> Function(AccountLifecycleRepository lifecycle) action,
  ) async {
    final lifecycle = accountLifecycle;
    if (busy || state is! AuthSignedOut || lifecycle == null) return false;
    _lifecycleInProgress = true;
    notifyListeners();
    try {
      await action(lifecycle);
      state = const AuthSignedOut();
      return true;
    } on AuthException catch (error) {
      state = AuthSignedOut(failure: error);
      return false;
    } on Object {
      state = const AuthSignedOut(
        failure: AuthException(kind: AuthFailureKind.server),
      );
      return false;
    } finally {
      _lifecycleInProgress = false;
      notifyListeners();
    }
  }

  Future<void> logout() async {
    if (busy) return;
    final previous = state;
    _logoutInProgress = true;
    notifyListeners();
    try {
      await repository.logout();
      state = const AuthSignedOut();
    } on AuthException catch (error) {
      state = _logoutFailure(previous, error);
    } on Object {
      state = _logoutFailure(
        previous,
        const AuthException(kind: AuthFailureKind.server),
      );
    } finally {
      _logoutInProgress = false;
      notifyListeners();
    }
  }

  AuthState _logoutFailure(AuthState previous, AuthException error) {
    final account = repository.account;
    if (previous case final AuthSignedIn signedIn when account != null) {
      return AuthSignedIn(account, offline: signedIn.offline, failure: error);
    }
    return AuthSignedOut(failure: error);
  }

  @override
  void dispose() {
    unawaited(_subscription.cancel());
    super.dispose();
  }
}
