import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../data/auth/auth_repository.dart';
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
  AuthSessionController(this.repository) {
    _subscription = repository.events.listen((event) {
      if (event == AuthRepositoryEvent.sessionExpired) {
        state = const AuthSignedOut(sessionExpired: true);
        notifyListeners();
      }
    });
  }

  final AuthRepository repository;
  late final StreamSubscription<AuthRepositoryEvent> _subscription;
  AuthState state = const AuthRestoring();
  bool _logoutInProgress = false;

  bool get busy =>
      state is AuthSubmitting || state is AuthRestoring || _logoutInProgress;

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
