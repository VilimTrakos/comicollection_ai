import 'dart:async';

import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../features/auth/login_gate.dart';
import '../features/shell/app_shell.dart';
import '../services/auth/auth_session_controller.dart';
import '../ui/app_theme.dart';
import 'app_runtime.dart';
import 'app_runtime_factory.dart';

class ComicollectApp extends StatefulWidget {
  const ComicollectApp({
    super.key,
    this.authController,
    this.runtimeFactory,
    this.controller,
  }) : assert(
         controller != null ||
             (authController != null && runtimeFactory != null),
       );

  /// Injected only by isolated widget previews and legacy tests.
  final AppController? controller;
  final AuthSessionController? authController;
  final AppRuntimeProvider? runtimeFactory;

  @override
  State<ComicollectApp> createState() => _ComicollectAppState();
}

class _ComicollectAppState extends State<ComicollectApp> {
  AppRuntime? _runtime;
  bool _guest = false;
  Object? _runtimeError;
  int _generation = 0;
  String? _openingAccountId;

  @override
  void initState() {
    super.initState();
    widget.authController?.addListener(_authChanged);
    if (widget.authController != null) _reconcileRuntime();
  }

  void _authChanged() {
    _reconcileRuntime();
    if (mounted) setState(() {});
  }

  Future<void> _reconcileRuntime() async {
    if (_guest || widget.runtimeFactory == null) return;
    final state = widget.authController?.state;
    if (state is AuthSignedIn) {
      if (_runtime?.account?.id == state.account.id ||
          _openingAccountId == state.account.id) {
        return;
      }
      final accountId = state.account.id;
      _openingAccountId = accountId;
      await _replaceRuntime(
        () => widget.runtimeFactory!.createAccount(state.account),
      );
      if (_openingAccountId == accountId) _openingAccountId = null;
      return;
    }
    if (_runtime?.account != null || _openingAccountId != null) {
      _openingAccountId = null;
      await _replaceRuntime(null);
    }
  }

  Future<void> _replaceRuntime(Future<AppRuntime> Function()? create) async {
    final generation = ++_generation;
    final previous = _runtime;
    _runtime = null;
    _runtimeError = null;
    if (mounted) setState(() {});
    try {
      await previous?.close();
    } on Object catch (error) {
      if (generation != _generation || !mounted || create == null) return;
      _runtimeError = error;
      setState(() {});
      return;
    }
    if (create == null || generation != _generation) return;
    try {
      final created = await create();
      if (generation != _generation || !mounted) {
        await created.close();
        return;
      }
      _runtime = created;
    } on Object catch (error) {
      if (generation != _generation || !mounted) return;
      _runtimeError = error;
    }
    if (generation == _generation && mounted) setState(() {});
  }

  void _continueAsGuest() {
    _guest = true;
    _openingAccountId = null;
    unawaited(_replaceRuntime(widget.runtimeFactory!.createGuest));
  }

  void _logout() {
    if (_guest) {
      _guest = false;
      unawaited(_replaceRuntime(null));
    } else {
      unawaited(widget.authController!.logout());
    }
  }

  void _retryRuntime() {
    final factory = widget.runtimeFactory!;
    if (_guest) {
      unawaited(_replaceRuntime(factory.createGuest));
      return;
    }
    unawaited(_reconcileRuntime());
  }

  @override
  void dispose() {
    widget.authController?.removeListener(_authChanged);
    _generation++;
    unawaited(_runtime?.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller ?? _runtime?.controller;
    if (controller == null) return _materialApp(null);
    return AnimatedBuilder(
      animation: controller.appearanceChanges,
      builder: (context, _) => _materialApp(controller),
    );
  }

  MaterialApp _materialApp(AppController? controller) {
    final accentName = controller?.accent ?? 'red';
    final darkMode = controller?.darkMode ?? true;
    final comicTitles = controller?.comicTitles ?? false;
    final accent = accentColor(accentName);
    final accentDeep = accentDeepColor(accentName);
    return MaterialApp(
      key: ValueKey<int>(_generation),
      debugShowCheckedModeBanner: false,
      title: 'Comicollect',
      themeMode: darkMode ? ThemeMode.dark : ThemeMode.light,
      theme: buildAppTheme(
        brightness: Brightness.light,
        accent: accent,
        accentDeep: accentDeep,
        comicTitles: comicTitles,
      ),
      darkTheme: buildAppTheme(
        brightness: Brightness.dark,
        accent: accent,
        accentDeep: accentDeep,
        comicTitles: comicTitles,
      ),
      home: _home(controller),
    );
  }

  Widget _home(AppController? controller) {
    if (widget.authController == null) {
      return LoginGate(controller: widget.controller);
    }
    final authState = widget.authController!.state;
    if (_runtimeError != null) {
      return _RuntimeError(
        retry: _retryRuntime,
        exit: _logout,
        exitLabel: _guest ? 'NATRAG' : 'ODJAVI SE',
      );
    }
    if (controller != null && _runtime != null) {
      final account = _runtime!.account;
      return Shell(
        controller: controller,
        accountEmail: account?.email ?? '',
        accountName: account?.displayName ?? 'Lokalni korisnik',
        emailVerified: account?.emailVerified ?? true,
        accountError: authState is AuthSignedIn && authState.failure != null
            ? 'Odjava nije dovršena. Podaci za prijavu nisu obrisani; '
                  'pokušajte ponovno.'
            : null,
        onLogout: _logout,
      );
    }
    if (authState is AuthRestoring || authState is AuthSignedIn || _guest) {
      return const _StartupSplash();
    }
    return LoginGate(
      authController: widget.authController,
      onGuest: _continueAsGuest,
    );
  }
}

class _StartupSplash extends StatelessWidget {
  const _StartupSplash();

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: CircularProgressIndicator()));
}

class _RuntimeError extends StatelessWidget {
  const _RuntimeError({
    required this.retry,
    required this.exit,
    required this.exitLabel,
  });

  final VoidCallback retry;
  final VoidCallback exit;
  final String exitLabel;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Lokalni podaci se ne mogu otvoriti.'),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: retry,
              child: const Text('POKUŠAJ PONOVNO'),
            ),
            const SizedBox(height: 8),
            TextButton(onPressed: exit, child: Text(exitLabel)),
          ],
        ),
      ),
    ),
  );
}
