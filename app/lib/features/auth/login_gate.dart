import 'package:flutter/material.dart';

import '../../app_controller.dart';
import '../../models/auth_failure.dart';
import '../../services/auth/auth_session_controller.dart';
import '../../ui/app_theme.dart';
import '../../ui/common_widgets.dart';
import '../shell/app_shell.dart';

class LoginGate extends StatefulWidget {
  const LoginGate({
    super.key,
    this.authController,
    this.onGuest,
    this.controller,
  });
  final AuthSessionController? authController;
  final VoidCallback? onGuest;
  final AppController? controller;
  @override
  State<LoginGate> createState() => _LoginGateState();
}

class _LoginGateState extends State<LoginGate> {
  final email = TextEditingController();
  final password = TextEditingController();
  final displayName = TextEditingController();
  final confirmation = TextEditingController();
  bool previewGuest = false;
  bool registering = false;
  int step = 0;

  @override
  void initState() {
    super.initState();
    widget.authController?.addListener(_authChanged);
  }

  void _authChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    email.dispose();
    password.dispose();
    displayName.dispose();
    confirmation.dispose();
    widget.authController?.removeListener(_authChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (previewGuest && widget.controller != null) {
      return Shell(
        controller: widget.controller!,
        accountEmail: '',
        onLogout: () => setState(() {
          previewGuest = false;
          step = 0;
        }),
      );
    }
    if (step == 0) return _welcome();
    if (step == 1) return _mode();
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    registering ? 'NOVI RAČUN' : 'PRIJAVA',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.w900,
                      fontSize: 30,
                      letterSpacing: 2,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Račun čuva kolekciju na serveru — telefon, tablet i web uvijek isto.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: tan),
                  ),
                  const SizedBox(height: 38),
                  if (registering) ...[
                    TextField(
                      key: const ValueKey('auth-display-name'),
                      controller: displayName,
                      textInputAction: TextInputAction.next,
                      autofillHints: const [AutofillHints.name],
                      decoration: const InputDecoration(
                        labelText: 'Ime',
                        prefixIcon: Icon(Icons.person_outline),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  TextField(
                    key: const ValueKey('auth-email'),
                    controller: email,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    autofillHints: const [AutofillHints.email],
                    decoration: const InputDecoration(
                      labelText: 'E-mail',
                      prefixIcon: Icon(Icons.mail_outline),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    key: const ValueKey('auth-password'),
                    controller: password,
                    obscureText: true,
                    enableSuggestions: false,
                    autocorrect: false,
                    textInputAction: registering
                        ? TextInputAction.next
                        : TextInputAction.done,
                    autofillHints: [
                      registering
                          ? AutofillHints.newPassword
                          : AutofillHints.password,
                    ],
                    onSubmitted: registering ? null : (_) => _submit(),
                    decoration: const InputDecoration(
                      labelText: 'Lozinka',
                      prefixIcon: Icon(Icons.lock_outline),
                    ),
                  ),
                  if (registering) ...[
                    const SizedBox(height: 12),
                    TextField(
                      key: const ValueKey('auth-password-confirmation'),
                      controller: confirmation,
                      obscureText: true,
                      enableSuggestions: false,
                      autocorrect: false,
                      textInputAction: TextInputAction.done,
                      autofillHints: const [AutofillHints.newPassword],
                      onSubmitted: (_) => _submit(),
                      decoration: const InputDecoration(
                        labelText: 'Ponovi lozinku',
                        prefixIcon: Icon(Icons.lock_outline),
                      ),
                    ),
                  ],
                  if (_errorMessage case final message?) ...[
                    const SizedBox(height: 12),
                    Text(
                      message,
                      key: const ValueKey('auth-error'),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                  const SizedBox(height: 18),
                  FilledButton(
                    onPressed: _busy ? null : _submit,
                    child: Padding(
                      padding: const EdgeInsets.all(15),
                      child: Text(
                        _busy
                            ? 'PRIČEKAJTE…'
                            : registering
                            ? 'NAPRAVI NOVI RAČUN'
                            : 'PRIJAVI SE',
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: _busy
                        ? null
                        : () => setState(() => registering = !registering),
                    child: Padding(
                      padding: const EdgeInsets.all(13),
                      child: Text(
                        registering ? 'VEĆ IMAM RAČUN' : 'NAPRAVI NOVI RAČUN',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  bool get _busy => widget.authController?.busy ?? false;

  String? get _errorMessage {
    final state = widget.authController?.state;
    if (state is! AuthSignedOut) return null;
    if (state.sessionExpired) return 'Sesija je istekla. Prijavite se ponovno.';
    final failure = state.failure;
    if (failure == null) return null;
    return switch (failure.kind) {
      AuthFailureKind.credentials =>
        registering
            ? 'Provjerite podatke. Lozinka mora imati najmanje 12 znakova.'
            : 'E-mail ili lozinka nisu ispravni.',
      AuthFailureKind.emailInUse => 'Račun s ovim e-mailom već postoji.',
      AuthFailureKind.passwordPolicy =>
        'Lozinka ne zadovoljava sigurnosne zahtjeve.',
      AuthFailureKind.registrationDisabled =>
        'Otvaranje novih računa trenutačno nije dostupno.',
      AuthFailureKind.rateLimited =>
        'Previše pokušaja. Pričekajte pa pokušajte ponovno.',
      AuthFailureKind.network => 'Nema mrežne veze. Pokušajte ponovno.',
      _ => 'Prijava trenutačno nije dostupna. Pokušajte ponovno.',
    };
  }

  Future<void> _submit() async {
    final auth = widget.authController;
    if (auth == null) return;
    if (registering) {
      if (password.text != confirmation.text) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Lozinke se ne podudaraju.')),
        );
        return;
      }
      await auth.register(email.text, password.text, displayName.text);
    } else {
      await auth.login(email.text, password.text);
    }
  }

  void _continueAsGuest() {
    if (widget.onGuest case final callback?) {
      callback();
    } else if (widget.controller != null) {
      setState(() => previewGuest = true);
    }
  }

  Widget _welcome() => Scaffold(
    body: Stack(
      fit: StackFit.expand,
      children: [
        ComicCover(label: 'COMICS COLLECTION', seed: 17),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.transparent, Color(0x99131412), ink],
              stops: [0, .48, .72],
            ),
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(32, 20, 32, 46),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(
                  'COMICS\nCOLLECTION',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                    fontSize: 42,
                    height: .96,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.5,
                    shadows: const [
                      Shadow(color: Color(0xAA8E1410), blurRadius: 18),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Tvoja kolekcija — uvijek uz tebe.\nRadi i bez interneta, sinkronizira se sama.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: tan, fontSize: 15, height: 1.55),
                ),
                const SizedBox(height: 26),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => setState(() => step = 1),
                    child: const Padding(
                      padding: EdgeInsets.all(14),
                      child: Text(
                        'UĐI U KOLEKCIJU',
                        style: TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                TextButton(
                  onPressed: _continueAsGuest,
                  child: const Text(
                    'Nastavi kao gost',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
                const SizedBox(height: 10),
                const Chip(
                  avatar: Icon(
                    Icons.cloud_done_outlined,
                    color: Color(0xFF3EC63E),
                    size: 16,
                  ),
                  label: Text(
                    'Lokalno spremanje',
                    style: TextStyle(color: Color(0xFF3EC63E), fontSize: 11),
                  ),
                  backgroundColor: Color(0x223EC63E),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );

  Widget _mode() => Scaffold(
    appBar: AppBar(
      leading: IconButton(
        onPressed: () => setState(() => step = 0),
        icon: const Icon(Icons.arrow_back_ios_new),
      ),
    ),
    body: Stack(
      children: [
        const Positioned.fill(child: GrungeBackground()),
        ListView(
          padding: const EdgeInsets.fromLTRB(28, 20, 28, 30),
          children: [
            Text(
              'TKO SI?',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
                fontSize: 34,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Odaberi način rada — možeš ga promijeniti odjavom.',
              textAlign: TextAlign.center,
              style: TextStyle(color: tan, height: 1.5),
            ),
            const SizedBox(height: 24),
            _ModeCard(
              primary: true,
              icon: Icons.favorite_border,
              title: 'Osobna kolekcija',
              subtitle:
                  'Tvoja polica — skeniranje, čitanje, tražim, zamjene i sinkronizacija na svim uređajima.',
              onTap: () => setState(() => step = 2),
            ),
            const SizedBox(height: 12),
            _ModeCard(
              icon: Icons.business_center_outlined,
              title: 'Enterprise — poslovnica',
              subtitle:
                  'Za knjižnice i strip dućane. Aktivacija preko ugovora, inventar i posudbe članova.',
              onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Enterprise način nije dio osobne demo verzije.',
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

class _ModeCard extends StatelessWidget {
  const _ModeCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.primary = false,
  });
  final IconData icon;
  final String title, subtitle;
  final VoidCallback onTap;
  final bool primary;
  @override
  Widget build(BuildContext context) => Material(
    color: primary
        ? Theme.of(context).colorScheme.primary
        : Theme.of(context).colorScheme.surface,
    borderRadius: BorderRadius.circular(18),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: primary ? .18 : .05),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                icon,
                color: primary
                    ? Colors.white
                    : Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              title,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: TextStyle(
                color: primary ? Colors.white70 : tan,
                fontSize: 12.5,
                height: 1.55,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'NASTAVI  ▶',
              style: TextStyle(
                color: primary
                    ? Colors.white
                    : Theme.of(context).colorScheme.primary,
                fontSize: 12.5,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
