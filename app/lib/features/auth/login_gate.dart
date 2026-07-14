import 'package:flutter/material.dart';

import '../../app_controller.dart';
import '../../ui/app_theme.dart';
import '../../ui/common_widgets.dart';
import '../shell/app_shell.dart';

class LoginGate extends StatefulWidget {
  const LoginGate({super.key, required this.controller});
  final AppController controller;
  @override
  State<LoginGate> createState() => _LoginGateState();
}

class _LoginGateState extends State<LoginGate> {
  final email = TextEditingController(text: 'demo@comicollect.local');
  final password = TextEditingController(text: 'demo');
  bool entered = false;
  int step = 0;

  @override
  void dispose() {
    email.dispose();
    password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (entered) {
      return Shell(
        controller: widget.controller,
        accountEmail: email.text.trim(),
        onLogout: () => setState(() {
          entered = false;
          step = 2;
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
                    'PRIJAVA',
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
                  TextField(
                    controller: email,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'E-mail',
                      prefixIcon: Icon(Icons.mail_outline),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: password,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Lozinka',
                      prefixIcon: Icon(Icons.lock_outline),
                    ),
                  ),
                  const SizedBox(height: 18),
                  FilledButton(
                    onPressed: () => setState(() => entered = true),
                    child: const Padding(
                      padding: EdgeInsets.all(15),
                      child: Text(
                        'PRIJAVI SE',
                        style: TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: () => setState(() => entered = true),
                    child: Padding(
                      padding: const EdgeInsets.all(13),
                      child: Text(
                        'NAPRAVI NOVI RAČUN',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Demo prijava je lokalna i prihvaća unesene podatke. Server nije potreban.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
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
                  onPressed: () => setState(() => entered = true),
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
