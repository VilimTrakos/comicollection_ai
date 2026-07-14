import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app_controller.dart';
import 'models/comic.dart';
import 'screens/smart_scanner_page.dart';

const red = Color(0xFFC6291E);
const ink = Color(0xFF131412);
const surface = Color(0xFF1C1D1B);
const tan = Color(0xFFB7A88F);

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
  };
  PlatformDispatcher.instance.onError = (error, stackTrace) {
    debugPrint('Comicollect neobrađena startup greška: $error');
    debugPrintStack(stackTrace: stackTrace);
    return false;
  };
  debugPrint('Comicollect startup: main() je pokrenut');
  final controller = AppController();
  runApp(ComicollectApp(controller: controller));
  WidgetsBinding.instance.addPostFrameCallback((_) {
    debugPrint('Comicollect startup: prvi Flutter frame je prikazan');
    unawaited(controller.init());
  });
}

class ComicollectApp extends StatelessWidget {
  const ComicollectApp({super.key, required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      final accent = accentColor(controller.accent);
      final accentDeep = accentDeepColor(controller.accent);
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Comicollect',
        themeMode: controller.darkMode ? ThemeMode.dark : ThemeMode.light,
        theme: _appTheme(
          brightness: Brightness.light,
          accent: accent,
          accentDeep: accentDeep,
          comicTitles: controller.comicTitles,
        ),
        darkTheme: _appTheme(
          brightness: Brightness.dark,
          accent: accent,
          accentDeep: accentDeep,
          comicTitles: controller.comicTitles,
        ),
        home: LoginGate(controller: controller),
      );
    },
  );
}

Color accentColor(String key) => switch (key) {
  'yellow' => const Color(0xFFB7892E),
  'blue' => const Color(0xFF2A5FA8),
  _ => red,
};

Color accentDeepColor(String key) => switch (key) {
  'yellow' => const Color(0xFF7C5A18),
  'blue' => const Color(0xFF173E74),
  _ => const Color(0xFF8E1410),
};

ThemeData _appTheme({
  required Brightness brightness,
  required Color accent,
  required Color accentDeep,
  required bool comicTitles,
}) {
  final dark = brightness == Brightness.dark;
  final background = dark ? ink : const Color(0xFFF5F2ED);
  final card = dark ? surface : Colors.white;
  final base = ThemeData(brightness: brightness, useMaterial3: true);
  final generated = ColorScheme.fromSeed(
    seedColor: accent,
    brightness: brightness,
    surface: card,
  );
  final colorScheme = generated.copyWith(
    primary: accent,
    onPrimary: Colors.white,
    primaryContainer: accentDeep,
    onPrimaryContainer: Colors.white,
    secondary: accent,
    onSecondary: Colors.white,
    secondaryContainer: accent,
    onSecondaryContainer: Colors.white,
    inversePrimary: accent,
  );
  return base.copyWith(
    scaffoldBackgroundColor: background,
    colorScheme: colorScheme,
    textTheme: base.textTheme.apply(fontFamily: comicTitles ? 'serif' : null),
    appBarTheme: AppBarTheme(backgroundColor: background, elevation: 0),
    cardTheme: CardThemeData(
      color: card,
      elevation: 4,
      margin: EdgeInsets.zero,
    ),
    chipTheme: base.chipTheme.copyWith(
      selectedColor: accent,
      checkmarkColor: Colors.white,
      side: BorderSide(color: dark ? const Color(0xFF3A3936) : Colors.black26),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) return Colors.grey;
        return states.contains(WidgetState.selected)
            ? Colors.white
            : (dark ? const Color(0xFFB8B3AD) : Colors.white);
      }),
      trackColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) {
          return Colors.grey.withValues(alpha: .25);
        }
        return states.contains(WidgetState.selected)
            ? accent
            : (dark ? const Color(0xFF3B3937) : const Color(0xFFBDB8B2));
      }),
      trackOutlineColor: WidgetStateProperty.resolveWith((states) {
        return states.contains(WidgetState.selected)
            ? accentDeep
            : (dark ? const Color(0xFF67615C) : const Color(0xFF8C8782));
      }),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: accent,
        foregroundColor: Colors.white,
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: accent,
      foregroundColor: Colors.white,
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: accent),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: accent,
      selectionHandleColor: accent,
      selectionColor: accent.withValues(alpha: .28),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: card,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: accent),
      ),
    ),
  );
}

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
        const Positioned.fill(child: _GrungeBackground()),
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

class Shell extends StatefulWidget {
  const Shell({
    super.key,
    required this.controller,
    required this.accountEmail,
    required this.onLogout,
  });
  final AppController controller;
  final String accountEmail;
  final VoidCallback onLogout;
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> with WidgetsBindingObserver {
  int index = 0;
  final labels = const ['POČETNA', 'MOJA KOLEKCIJA', 'TRAŽI', 'POSTAVKE'];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) widget.controller.sync();
  }

  void addComic() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: tan.withValues(alpha: .25),
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              const Text(
                'DODAJ STRIP',
                style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1),
              ),
              const SizedBox(height: 12),
              _AddOption(
                icon: Icons.qr_code_scanner,
                title: 'Pametno skeniranje',
                subtitle: 'Automatski prepoznaje barkod ili naslovnicu',
                primary: true,
                onTap: () {
                  Navigator.pop(sheetContext);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          SmartScannerPage(controller: widget.controller),
                    ),
                  );
                },
              ),
              _AddOption(
                icon: Icons.search,
                title: 'Traži po nazivu',
                subtitle: 'Pretraži bazu serijala i brojeva',
                onTap: () {
                  Navigator.pop(sheetContext);
                  setState(() => index = 2);
                },
              ),
              _AddOption(
                icon: Icons.edit_outlined,
                title: 'Ručni unos',
                subtitle: 'Upiši serijal, broj i stanje sam',
                onTap: () {
                  Navigator.pop(sheetContext);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ComicForm(controller: widget.controller),
                    ),
                  );
                },
              ),
              _AddOption(
                icon: Icons.dynamic_feed_outlined,
                title: 'Unos raspona',
                subtitle: 'Cijela kolekcija odjednom — npr. 1–50',
                onTap: () {
                  Navigator.pop(sheetContext);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          RangeEntryPage(controller: widget.controller),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      final pages = [
        HomePage(controller: widget.controller),
        ShelfPage(controller: widget.controller),
        SearchPage(controller: widget.controller),
        SettingsPage(
          controller: widget.controller,
          accountEmail: widget.accountEmail,
          onLogout: widget.onLogout,
        ),
      ];
      return Scaffold(
        appBar: AppBar(
          title: Text(
            index == 0 ? 'COMICOLLECT' : labels[index],
            style: TextStyle(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.2,
            ),
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: SyncBadge(controller: widget.controller),
            ),
          ],
        ),
        body: SafeArea(
          child: widget.controller.loading
              ? const Center(child: CircularProgressIndicator())
              : widget.controller.startupError != null
              ? _StartupError(controller: widget.controller)
              : IndexedStack(index: index, children: pages),
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: addComic,
          backgroundColor: Theme.of(context).colorScheme.primary,
          foregroundColor: Colors.white,
          shape: const CircleBorder(),
          child: const Icon(Icons.add, size: 30),
        ),
        floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
        bottomNavigationBar: BottomAppBar(
          color: Theme.of(context).colorScheme.surface,
          shape: const CircularNotchedRectangle(),
          notchMargin: 8,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _nav(0, Icons.home_outlined, 'Home'),
              _nav(1, Icons.menu_book_outlined, 'Polica'),
              const SizedBox(width: 48),
              _nav(2, Icons.search, 'Traži'),
              _nav(3, Icons.settings_outlined, 'Postavke'),
            ],
          ),
        ),
      );
    },
  );

  Widget _nav(int i, IconData icon, String label) => Expanded(
    child: InkWell(
      onTap: () => setState(() => index = i),
      child: SizedBox(
        height: 62,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              color: index == i
                  ? Theme.of(context).colorScheme.primary
                  : Colors.grey,
            ),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                color: index == i
                    ? Theme.of(context).colorScheme.primary
                    : Colors.grey,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _StartupError extends StatelessWidget {
  const _StartupError({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.storage_outlined,
            color: Theme.of(context).colorScheme.primary,
            size: 54,
          ),
          const SizedBox(height: 14),
          const Text(
            'LOKALNI PODACI SE NE MOGU OTVORITI',
            textAlign: TextAlign.center,
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          Text(
            controller.startupError!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: tan, fontSize: 12),
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: controller.init,
            icon: const Icon(Icons.refresh),
            label: const Text('POKUŠAJ PONOVNO'),
          ),
        ],
      ),
    ),
  );
}

class _AddOption extends StatelessWidget {
  const _AddOption({
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
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Material(
      color: primary
          ? Theme.of(context).colorScheme.primary
          : Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: primary ? .18 : .06),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  icon,
                  color: primary
                      ? Colors.white
                      : Theme.of(context).colorScheme.primary,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: primary ? Colors.white70 : tan,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.play_arrow,
                color: primary
                    ? Colors.white
                    : Theme.of(context).colorScheme.primary,
                size: 17,
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class SyncBadge extends StatelessWidget {
  const SyncBadge({super.key, required this.controller});
  final AppController controller;
  @override
  Widget build(BuildContext context) {
    final color = controller.online
        ? const Color(0xFF3EC63E)
        : const Color(0xFFE8C547);
    return Tooltip(
      message: controller.syncMessage,
      child: Chip(
        avatar: controller.syncing
            ? SizedBox.square(
                dimension: 13,
                child: CircularProgressIndicator(strokeWidth: 2, color: color),
              )
            : Icon(
                controller.online
                    ? Icons.cloud_done_outlined
                    : Icons.cloud_off_outlined,
                size: 16,
                color: color,
              ),
        label: Text(
          controller.online ? 'Sync' : 'Offline',
          style: TextStyle(
            color: color,
            fontSize: 11,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: color.withValues(alpha: .12),
        side: BorderSide(color: color.withValues(alpha: .45)),
      ),
    );
  }
}

class HomePage extends StatelessWidget {
  const HomePage({super.key, required this.controller});
  final AppController controller;
  @override
  Widget build(BuildContext context) {
    final owned = controller.comics.where((c) => c.owned).toList();
    final unread = owned.where((c) => !c.read).toList();
    final value = owned.fold<double>(
      0,
      (sum, c) => sum + (c.estimatedValue ?? 0),
    );
    final editions = <String, List<Comic>>{};
    for (final comic in controller.comics) {
      editions
          .putIfAbsent('${comic.series} · ${comic.edition}', () => [])
          .add(comic);
    }
    final closest = editions.entries.toList()
      ..sort(
        (a, b) => (b.value.where((c) => c.owned).length / b.value.length)
            .compareTo(a.value.where((c) => c.owned).length / a.value.length),
      );
    return RefreshIndicator(
      onRefresh: () => controller.sync(force: true),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 100),
        children: [
          Text(
            '${owned.length} stripova · ${value.toStringAsFixed(2)} €',
            style: const TextStyle(color: tan),
          ),
          const SectionTitle('U NAJAVI'),
          GestureDetector(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => UpcomingPage(controller: controller),
              ),
            ),
            child: SizedBox(
              height: 142,
              child: Row(
                children: const [
                  Expanded(
                    child: _ReleaseCard(
                      day: '28',
                      month: 'LIP',
                      title: 'DYLAN DOG #202',
                      seed: 1,
                    ),
                  ),
                  SizedBox(width: 10),
                  Expanded(
                    child: _ReleaseCard(
                      day: '05',
                      month: 'SRP',
                      title: 'EXTRA #167',
                      seed: 2,
                    ),
                  ),
                  SizedBox(width: 10),
                  Expanded(
                    child: _ReleaseCard(
                      day: '12',
                      month: 'SRP',
                      title: 'SPECIAL',
                      seed: 3,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SectionTitle('NASTAVI ČITATI'),
          if (unread.isEmpty)
            const EmptyCard(text: 'Sve pročitano — lijep osjećaj.')
          else
            ComicTile(comic: unread.first, controller: controller),
          const SectionTitle('NEDAVNO DODANO'),
          ...owned.reversed
              .take(4)
              .map((c) => ComicTile(comic: c, controller: controller)),
          if (owned.isEmpty)
            const EmptyCard(
              text:
                  'Otvori Poliču, odaberi Dylan Dog ediciju i označi brojeve koje imaš.',
            ),
          const SectionTitle('NAJBLIŽE KOMPLETIRANJU'),
          ...closest
              .take(2)
              .map(
                (entry) => _ProgressRow(name: entry.key, comics: entry.value),
              ),
        ],
      ),
    );
  }
}

class _ReleaseCard extends StatelessWidget {
  const _ReleaseCard({
    required this.day,
    required this.month,
    required this.title,
    required this.seed,
  });
  final String day, month, title;
  final int seed;
  @override
  Widget build(BuildContext context) => Card(
    clipBehavior: Clip.antiAlias,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Stack(
            fit: StackFit.expand,
            children: [
              ComicCover(label: title.split(' ').first, seed: seed),
              Positioned(
                top: 6,
                left: 6,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xDD060808),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    children: [
                      Text(
                        day,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.primary,
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        month,
                        style: const TextStyle(color: tan, fontSize: 9),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(7),
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    ),
  );
}

class _ProgressRow extends StatelessWidget {
  const _ProgressRow({required this.name, required this.comics});
  final String name;
  final List<Comic> comics;
  @override
  Widget build(BuildContext context) {
    final owned = comics.where((c) => c.owned).length;
    final progress = comics.isEmpty ? 0.0 : owned / comics.length;
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(11),
          child: Row(
            children: [
              SizedBox(
                width: 46,
                height: 62,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(7),
                  child: ComicCover(
                    label: name.split(' · ').first,
                    seed: name.hashCode,
                    assetPath: comics.first.coverAsset,
                  ),
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                        Text(
                          '$owned/${comics.length}',
                          style: const TextStyle(color: tan, fontSize: 12),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(99),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 7,
                        backgroundColor: const Color(0xFF080909),
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      'još ${comics.length - owned} do kompleta',
                      style: const TextStyle(
                        color: Colors.grey,
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ShelfPage extends StatelessWidget {
  const ShelfPage({super.key, required this.controller});
  final AppController controller;
  @override
  Widget build(BuildContext context) {
    final groups = <String, List<Comic>>{};
    for (final c in controller.comics) {
      groups.putIfAbsent(c.series, () => []).add(c);
    }
    final names = groups.keys.toList()..sort();
    final unread = controller.comics
        .where((comic) => comic.owned && !comic.read)
        .length;
    final wanted = controller.comics.where((comic) => !comic.owned).length;
    final duplicates = controller.comics
        .where((comic) => comic.owned && comic.duplicate)
        .length;
    final loaned = controller.comics
        .where((comic) => comic.owned && comic.loanedTo.isNotEmpty)
        .length;
    final tiles = <Widget>[
      if (controller.showStatistics)
        _CollectionHubTile(
          icon: Icons.bar_chart_outlined,
          label: 'STATISTIKA',
          subtitle: 'kompletnost i vrijednost',
          onTap: () => _open(context, StatisticsPage(controller: controller)),
        ),
      _CollectionHubTile(
        icon: Icons.visibility_outlined,
        label: 'NIJE ČITANO',
        subtitle: '$unread čeka',
        count: unread,
        onTap: () => _open(
          context,
          CollectionListPage(
            controller: controller,
            type: CollectionListType.unread,
          ),
        ),
      ),
      _CollectionHubTile(
        icon: Icons.manage_search,
        label: 'TRAŽIM',
        subtitle: '$wanted nedostaje',
        count: wanted,
        highlighted: true,
        onTap: () => _open(
          context,
          CollectionListPage(
            controller: controller,
            type: CollectionListType.wanted,
          ),
        ),
      ),
      _CollectionHubTile(
        icon: Icons.copy_all_outlined,
        label: 'DUPLI',
        subtitle: '$duplicates za zamjenu',
        count: duplicates,
        onTap: () => _open(
          context,
          CollectionListPage(
            controller: controller,
            type: CollectionListType.duplicates,
          ),
        ),
      ),
      _CollectionHubTile(
        icon: Icons.campaign_outlined,
        label: 'POSUĐENO',
        subtitle: '$loaned vani',
        count: loaned,
        onTap: () => _open(
          context,
          CollectionListPage(
            controller: controller,
            type: CollectionListType.loaned,
          ),
        ),
      ),
      _CollectionHubTile(
        icon: Icons.calendar_month_outlined,
        label: 'U NAJAVI',
        subtitle: 'nadolazeći brojevi',
        onTap: () => _open(context, UpcomingPage(controller: controller)),
      ),
      _CollectionHubTile(
        icon: Icons.download_outlined,
        label: 'EXPORT CSV',
        subtitle: 'sigurnosna kopija',
        onTap: () => exportComicsCsv(context, controller.comics),
      ),
    ];
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 6, 18, 100),
      children: [
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          mainAxisSpacing: 11,
          crossAxisSpacing: 11,
          childAspectRatio: 1.38,
          children: tiles,
        ),
        const SectionTitle('SERIJALI'),
        if (names.isEmpty)
          const EmptyCard(text: 'Dodaj prvi strip na policu.')
        else
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              childAspectRatio: .82,
              crossAxisSpacing: 14,
              mainAxisSpacing: 14,
            ),
            itemCount: names.length,
            itemBuilder: (context, index) {
              final items = groups[names[index]]!;
              final owned = items.where((comic) => comic.owned).length;
              final read = items.where((comic) => comic.read).length;
              return InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: () => _open(
                  context,
                  SeriesPage(name: names[index], controller: controller),
                ),
                child: Card(
                  clipBehavior: Clip.antiAlias,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: ComicCover(
                          label: names[index],
                          seed: names[index].hashCode,
                          assetPath: items.first.coverAsset,
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              names[index].toUpperCase(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              '$owned imam · $read pročitano',
                              style: const TextStyle(color: tan, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
      ],
    );
  }

  void _open(BuildContext context, Widget page) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => page));
}

class _CollectionHubTile extends StatelessWidget {
  const _CollectionHubTile({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.onTap,
    this.count,
    this.highlighted = false,
  });

  final IconData icon;
  final String label;
  final String subtitle;
  final int? count;
  final bool highlighted;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Material(
      color: highlighted ? accent : Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(13),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 37,
                    height: 37,
                    decoration: BoxDecoration(
                      color: highlighted
                          ? Colors.white.withValues(alpha: .18)
                          : Theme.of(context).scaffoldBackgroundColor,
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Icon(
                      icon,
                      color: highlighted ? Colors.white : accent,
                      size: 20,
                    ),
                  ),
                  const Spacer(),
                  if (count != null && count! > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: highlighted
                            ? Colors.white.withValues(alpha: .2)
                            : Theme.of(context).scaffoldBackgroundColor,
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: Text(
                        '$count',
                        style: TextStyle(
                          color: highlighted ? Colors.white : null,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                ],
              ),
              const Spacer(),
              Text(
                label,
                style: TextStyle(
                  color: highlighted ? Colors.white : null,
                  fontWeight: FontWeight.w900,
                  fontSize: 13.5,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: highlighted ? Colors.white70 : tan,
                  fontSize: 11.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum CollectionListType { unread, wanted, duplicates, loaned }

class CollectionListPage extends StatelessWidget {
  const CollectionListPage({
    super.key,
    required this.controller,
    required this.type,
  });

  final AppController controller;
  final CollectionListType type;

  String get title => switch (type) {
    CollectionListType.unread => 'NIJE ČITANO',
    CollectionListType.wanted => 'TRAŽIM',
    CollectionListType.duplicates => 'DUPLI',
    CollectionListType.loaned => 'POSUĐENO',
  };

  String get subtitle => switch (type) {
    CollectionListType.unread => 'Brojevi koji čekaju čitanje',
    CollectionListType.wanted => 'Brojevi koji nedostaju u kolekciji',
    CollectionListType.duplicates => 'Primjerci za zamjenu ili prodaju',
    CollectionListType.loaned => 'Stripovi koji su trenutačno kod nekoga',
  };

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      final items = _items();
      return Scaffold(
        appBar: AppBar(
          centerTitle: true,
          title: Text(
            title,
            style: TextStyle(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w900,
            ),
          ),
          actions: [
            if (type == CollectionListType.wanted && items.isNotEmpty)
              IconButton(
                tooltip: 'Kopiraj popis',
                onPressed: () => _copyWanted(context, items),
                icon: const Icon(Icons.copy_outlined),
              ),
          ],
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 2, 18, 10),
              child: Text(
                '$subtitle · ${items.length}',
                textAlign: TextAlign.center,
                style: const TextStyle(color: tan, fontSize: 12.5),
              ),
            ),
            Expanded(
              child: items.isEmpty
                  ? Center(child: EmptyCard(text: _emptyLabel()))
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                      itemCount: items.length,
                      itemBuilder: (context, index) {
                        final comic = items[index];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              ComicTile(comic: comic, controller: controller),
                              Align(
                                alignment: Alignment.centerRight,
                                child: TextButton.icon(
                                  onPressed: () => _complete(comic),
                                  icon: Icon(_actionIcon(), size: 16),
                                  label: Text(_actionLabel()),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      );
    },
  );

  List<Comic> _items() {
    final items = controller.comics.where((comic) {
      return switch (type) {
        CollectionListType.unread => comic.owned && !comic.read,
        CollectionListType.wanted => !comic.owned,
        CollectionListType.duplicates => comic.owned && comic.duplicate,
        CollectionListType.loaned => comic.owned && comic.loanedTo.isNotEmpty,
      };
    }).toList();
    items.sort((a, b) {
      final series = a.series.compareTo(b.series);
      if (series != 0) return series;
      final edition = a.edition.compareTo(b.edition);
      return edition != 0 ? edition : a.number.compareTo(b.number);
    });
    return items;
  }

  String _actionLabel() => switch (type) {
    CollectionListType.unread => 'OZNAČI PROČITANO',
    CollectionListType.wanted => '+ NABAVLJEN',
    CollectionListType.duplicates => 'VIŠE NIJE DUPLI',
    CollectionListType.loaned => 'VRAĆENO',
  };

  IconData _actionIcon() => switch (type) {
    CollectionListType.unread => Icons.visibility_outlined,
    CollectionListType.wanted => Icons.add_circle_outline,
    CollectionListType.duplicates => Icons.done_all,
    CollectionListType.loaned => Icons.assignment_return_outlined,
  };

  String _emptyLabel() => switch (type) {
    CollectionListType.unread => 'Sve što imaš je pročitano.',
    CollectionListType.wanted => 'Kolekcija je kompletna!',
    CollectionListType.duplicates => 'Nema duplih primjeraka.',
    CollectionListType.loaned => 'Sve je vraćeno.',
  };

  Future<void> _complete(Comic comic) => switch (type) {
    CollectionListType.unread => controller.save(comic.copyWith(read: true)),
    CollectionListType.wanted => controller.save(comic.copyWith(owned: true)),
    CollectionListType.duplicates => controller.save(
      comic.copyWith(duplicate: false),
    ),
    CollectionListType.loaned => controller.save(comic.copyWith(loanedTo: '')),
  };

  void _copyWanted(BuildContext context, List<Comic> items) {
    final text = items
        .map(
          (comic) =>
              '${comic.series} · ${comic.edition} #${comic.number} — ${comic.title}',
        )
        .join('\n');
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Popis Tražim je kopiran.')));
  }
}

class StatisticsPage extends StatelessWidget {
  const StatisticsPage({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      final owned = controller.comics.where((comic) => comic.owned).toList();
      final read = owned.where((comic) => comic.read).length;
      final value = owned.fold<double>(
        0,
        (total, comic) => total + (comic.estimatedValue ?? 0),
      );
      final editions = <String, List<Comic>>{};
      for (final comic in controller.comics) {
        editions
            .putIfAbsent('${comic.series} · ${comic.edition}', () => [])
            .add(comic);
      }
      return Scaffold(
        appBar: AppBar(
          centerTitle: true,
          title: Text(
            'STATISTIKA',
            style: TextStyle(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 30),
          children: [
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              childAspectRatio: 1.65,
              children: [
                _StatCard(
                  label: 'U KOLEKCIJI',
                  value: '${owned.length}',
                  icon: Icons.menu_book_outlined,
                ),
                _StatCard(
                  label: 'PROČITANO',
                  value: '$read',
                  icon: Icons.visibility_outlined,
                ),
                _StatCard(
                  label: 'KOMPLETNOST',
                  value: controller.comics.isEmpty
                      ? '0%'
                      : '${(owned.length * 100 / controller.comics.length).round()}%',
                  icon: Icons.donut_large,
                ),
                _StatCard(
                  label: 'VRIJEDNOST',
                  value: '${value.toStringAsFixed(2)} €',
                  icon: Icons.euro,
                ),
              ],
            ),
            const SectionTitle('PO EDICIJAMA'),
            ...editions.entries.map(
              (entry) => _ProgressRow(name: entry.key, comics: entry.value),
            ),
          ],
        ),
      );
    },
  );
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Card(
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    child: Padding(
      padding: const EdgeInsets.all(13),
      child: Row(
        children: [
          Icon(icon, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(label, style: const TextStyle(color: tan, fontSize: 10.5)),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class UpcomingPage extends StatefulWidget {
  const UpcomingPage({super.key, required this.controller});

  final AppController controller;

  @override
  State<UpcomingPage> createState() => _UpcomingPageState();
}

class _UpcomingPageState extends State<UpcomingPage> {
  Set<String> watched = {};

  @override
  void initState() {
    super.initState();
    _loadWatched();
  }

  Future<void> _loadWatched() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(
        () => watched = (prefs.getStringList('release_watch_ids') ?? const [])
            .toSet(),
      );
    }
  }

  List<Comic> _candidates() {
    final groups = <String, List<Comic>>{};
    for (final comic in widget.controller.comics) {
      groups
          .putIfAbsent('${comic.series}\u0000${comic.edition}', () => [])
          .add(comic);
    }
    final result = <Comic>[];
    for (final items in groups.values) {
      items.sort((a, b) => b.number.compareTo(a.number));
      final candidate = items.where((comic) => !comic.owned).firstOrNull;
      if (candidate != null) result.add(candidate);
    }
    result.sort((a, b) {
      final year = (b.year ?? 0).compareTo(a.year ?? 0);
      return year != 0 ? year : b.number.compareTo(a.number);
    });
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final candidates = _candidates();
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: Text(
          'U NAJAVI',
          style: TextStyle(
            color: Theme.of(context).colorScheme.primary,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 2, 16, 28),
        children: [
          const Text(
            'Najnoviji poznati brojevi iz lokalnog kataloga — uključi zvonce za praćenje',
            textAlign: TextAlign.center,
            style: TextStyle(color: tan, fontSize: 12.5),
          ),
          const SizedBox(height: 8),
          if (candidates.isEmpty)
            const EmptyCard(text: 'Nema novih kandidata za praćenje.')
          else
            ...candidates.map(
              (comic) => Padding(
                padding: const EdgeInsets.only(bottom: 9),
                child: Card(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    leading: SizedBox(
                      width: 46,
                      height: 62,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(7),
                        child: ComicCover(
                          label: comic.series,
                          seed: comic.number,
                          assetPath: comic.coverAsset,
                        ),
                      ),
                    ),
                    title: Text(
                      '${comic.series.toUpperCase()} #${comic.number}',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    subtitle: Text(
                      '${comic.edition} · ${comic.title}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: IconButton.filledTonal(
                      tooltip: watched.contains(comic.id)
                          ? 'Isključi praćenje'
                          : 'Prati ovaj broj',
                      onPressed: () => _toggle(comic.id),
                      icon: Icon(
                        watched.contains(comic.id)
                            ? Icons.notifications_active
                            : Icons.notifications_none,
                      ),
                    ),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ComicDetail(
                          comic: comic,
                          controller: widget.controller,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          const SizedBox(height: 6),
          const Text(
            'Napomena: BSP katalog nema datume budućih izlazaka. Praćenje se čuva lokalno; datumi se mogu dodati kada server dobije izvor najava.',
            style: TextStyle(color: tan, fontSize: 11.5, height: 1.4),
          ),
        ],
      ),
    );
  }

  Future<void> _toggle(String id) async {
    setState(() {
      if (!watched.add(id)) watched.remove(id);
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('release_watch_ids', watched.toList());
  }
}

void exportComicsCsv(BuildContext context, Iterable<Comic> comics) {
  String esc(Object? value) =>
      '"${(value ?? '').toString().replaceAll('"', '""')}"';
  final rows = <String>[
    'Serijal,Edicija,Broj,Naslov,Izdavač,Godina,Imam,Pročitano,Stanje,Vrijednost,Dupli,Posuđeno',
  ];
  for (final comic in comics) {
    rows.add(
      [
        comic.series,
        comic.edition,
        comic.number,
        comic.title,
        comic.publisher,
        comic.year ?? '',
        comic.owned ? 'DA' : 'NE',
        comic.read ? 'DA' : 'NE',
        comic.condition,
        comic.estimatedValue ?? '',
        comic.duplicate ? 'DA' : 'NE',
        comic.loanedTo,
      ].map(esc).join(','),
    );
  }
  Clipboard.setData(ClipboardData(text: rows.join('\n')));
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text('CSV je kopiran u međuspremnik.')),
  );
}

class SeriesPage extends StatelessWidget {
  const SeriesPage({super.key, required this.name, required this.controller});
  final String name;
  final AppController controller;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      final editions = <String, List<Comic>>{};
      for (final comic in controller.comics.where(
        (comic) => comic.series == name,
      )) {
        editions.putIfAbsent(comic.edition, () => []).add(comic);
      }
      return Scaffold(
        appBar: AppBar(
          centerTitle: true,
          title: Text(
            name.toUpperCase(),
            style: TextStyle(
              color: Theme.of(context).colorScheme.primary,
              fontSize: 28,
              fontWeight: FontWeight.w900,
              letterSpacing: 1,
            ),
          ),
        ),
        body: Stack(
          children: [
            const Positioned.fill(child: _GrungeBackground()),
            ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 30),
              children: editions.entries.map((entry) {
                final issues = entry.value
                  ..sort((a, b) => a.number.compareTo(b.number));
                final owned = issues.where((c) => c.owned).length;
                final publisher = issues.first.publisher;
                final progress = issues.isEmpty ? 0.0 : owned / issues.length;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Card(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => EditionPage(
                            series: name,
                            edition: entry.key,
                            comics: issues,
                            controller: controller,
                          ),
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 58,
                              height: 78,
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: ComicCover(
                                  label: name,
                                  seed: entry.key.hashCode,
                                  assetPath: issues.first.coverAsset,
                                ),
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    publisher,
                                    style: const TextStyle(
                                      color: tan,
                                      fontSize: 12,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    entry.key.toUpperCase(),
                                    style: const TextStyle(
                                      fontSize: 19,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: .5,
                                    ),
                                  ),
                                  const SizedBox(height: 9),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: ClipRRect(
                                          borderRadius: BorderRadius.circular(
                                            99,
                                          ),
                                          child: LinearProgressIndicator(
                                            value: progress,
                                            minHeight: 6,
                                            backgroundColor: const Color(
                                              0xFF080909,
                                            ),
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.primary,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 9),
                                      Text(
                                        '$owned/${issues.length}',
                                        style: const TextStyle(
                                          color: tan,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            Icon(
                              Icons.play_arrow,
                              color: Theme.of(context).colorScheme.primary,
                              size: 18,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      );
    },
  );
}

class EditionPage extends StatefulWidget {
  const EditionPage({
    super.key,
    required this.series,
    required this.edition,
    required this.comics,
    required this.controller,
  });
  final String series, edition;
  final List<Comic> comics;
  final AppController controller;
  @override
  State<EditionPage> createState() => _EditionPageState();
}

class _EditionPageState extends State<EditionPage> {
  bool dense = true;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      final issues =
          widget.controller.comics
              .where(
                (c) => c.series == widget.series && c.edition == widget.edition,
              )
              .toList()
            ..sort((a, b) => a.number.compareTo(b.number));
      return Scaffold(
        appBar: AppBar(
          title: Text(
            '${widget.series.toUpperCase()} · ${widget.edition.toUpperCase()}',
            style: TextStyle(
              color: Theme.of(context).colorScheme.primary,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          actions: [
            IconButton(
              tooltip: dense ? 'Udoban prikaz' : 'Zbijeni prikaz',
              onPressed: () => setState(() => dense = !dense),
              icon: Icon(
                dense ? Icons.view_agenda_outlined : Icons.view_list_outlined,
              ),
            ),
          ],
        ),
        body: ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 30),
          itemCount: issues.length,
          separatorBuilder: (_, _) => const SizedBox(height: 7),
          itemBuilder: (context, i) {
            final comic = issues[i];
            if (!dense) {
              return ComicTile(comic: comic, controller: widget.controller);
            }
            return Material(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ComicDetail(
                      comic: comic,
                      controller: widget.controller,
                    ),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 36,
                        child: Text(
                          '#${comic.number}',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.primary,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          comic.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        tooltip: 'Pročitano',
                        onPressed: comic.owned
                            ? () => widget.controller.save(
                                comic.copyWith(read: !comic.read),
                              )
                            : null,
                        icon: Icon(
                          Icons.visibility_outlined,
                          size: 17,
                          color: comic.read
                              ? const Color(0xFF3EC63E)
                              : Theme.of(context).colorScheme.primary,
                        ),
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        tooltip: 'U kolekciji',
                        onPressed: () => widget.controller.save(
                          comic.copyWith(
                            owned: !comic.owned,
                            read: comic.owned ? false : comic.read,
                          ),
                        ),
                        icon: Icon(
                          comic.owned ? Icons.check : Icons.close,
                          size: 18,
                          color: comic.owned
                              ? const Color(0xFF3EC63E)
                              : Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      );
    },
  );
}

class SearchPage extends StatefulWidget {
  const SearchPage({super.key, required this.controller});
  final AppController controller;
  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final search = TextEditingController();
  String query = '';
  String scope = 'all';
  List<String> recent = const [];

  @override
  void initState() {
    super.initState();
    _loadRecent();
  }

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  Future<void> _loadRecent() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() => recent = prefs.getStringList('recent_searches') ?? const []);
  }

  Future<void> _remember([String? value]) async {
    final normalized = (value ?? query).trim();
    if (normalized.isEmpty) return;
    final next = [
      normalized,
      ...recent.where((item) => item.toLowerCase() != normalized.toLowerCase()),
    ].take(6).toList(growable: false);
    if (mounted) setState(() => recent = next);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('recent_searches', next);
  }

  void _setQuery(String value) {
    search.text = value;
    search.selection = TextSelection.collapsed(offset: value.length);
    setState(() => query = value);
  }

  @override
  Widget build(BuildContext context) {
    final q = query.trim().toLowerCase();
    final issueResults = q.isEmpty
        ? <Comic>[]
        : widget.controller.comics
              .where(
                (comic) =>
                    '${comic.series} ${comic.edition} ${comic.number} ${comic.title} ${comic.publisher}'
                        .toLowerCase()
                        .contains(q),
              )
              .toList();
    final seriesGroups = <String, List<Comic>>{};
    if (q.isNotEmpty) {
      for (final comic in widget.controller.comics) {
        if ('${comic.series} ${comic.publisher}'.toLowerCase().contains(q)) {
          seriesGroups.putIfAbsent(comic.series, () => []).add(comic);
        }
      }
    }
    final showSeries = scope != 'issues';
    final showIssues = scope != 'series';
    final empty =
        q.isNotEmpty &&
        (!showSeries || seriesGroups.isEmpty) &&
        (!showIssues || issueResults.isEmpty);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
      children: [
        TextField(
          controller: search,
          textInputAction: TextInputAction.search,
          onChanged: (value) => setState(() => query = value),
          onSubmitted: _remember,
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search),
            hintText: 'Serijal, broj ili naslov…',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(999),
              borderSide: BorderSide(color: Theme.of(context).dividerColor),
            ),
            suffixIcon: q.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Očisti',
                    onPressed: () => _setQuery(''),
                    icon: const Icon(Icons.close, size: 18),
                  ),
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 7,
          children: [
            _scopeChip('all', 'Sve'),
            _scopeChip('series', 'Serijali'),
            _scopeChip('issues', 'Brojevi'),
          ],
        ),
        if (q.isEmpty) ...[
          const SectionTitle('NEDAVNO TRAŽENO'),
          if (recent.isEmpty)
            const EmptyCard(text: 'Ovdje će se pojaviti tvoje zadnje pretrage.')
          else
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: recent
                  .map(
                    (item) => ActionChip(
                      avatar: const Icon(Icons.history, size: 15),
                      label: Text(item),
                      onPressed: () => _setQuery(item),
                    ),
                  )
                  .toList(),
            ),
        ],
        if (showSeries && seriesGroups.isNotEmpty) ...[
          const SectionTitle('SERIJALI'),
          ...seriesGroups.entries.map(
            (entry) => Padding(
              padding: const EdgeInsets.only(bottom: 9),
              child: _SeriesSearchResult(
                name: entry.key,
                comics: entry.value,
                controller: widget.controller,
                onOpen: _remember,
              ),
            ),
          ),
        ],
        if (showIssues && issueResults.isNotEmpty) ...[
          const SectionTitle('BROJEVI'),
          ...issueResults
              .take(60)
              .map(
                (comic) => Padding(
                  padding: const EdgeInsets.only(bottom: 9),
                  child: GestureDetector(
                    onTapDown: (_) => _remember(),
                    child: ComicTile(
                      comic: comic,
                      controller: widget.controller,
                    ),
                  ),
                ),
              ),
        ],
        if (empty)
          Padding(
            padding: const EdgeInsets.only(top: 40),
            child: Text(
              'Nema rezultata za „${query.trim()}”',
              textAlign: TextAlign.center,
              style: const TextStyle(color: tan),
            ),
          ),
      ],
    );
  }

  Widget _scopeChip(String value, String label) => ChoiceChip(
    label: Text(label),
    selected: scope == value,
    showCheckmark: false,
    onSelected: (_) => setState(() => scope = value),
  );
}

class _SeriesSearchResult extends StatelessWidget {
  const _SeriesSearchResult({
    required this.name,
    required this.comics,
    required this.controller,
    required this.onOpen,
  });

  final String name;
  final List<Comic> comics;
  final AppController controller;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final owned = comics.where((comic) => comic.owned).length;
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        leading: SizedBox(
          width: 42,
          height: 56,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(7),
            child: ComicCover(
              label: name,
              seed: name.hashCode,
              assetPath: comics.first.coverAsset,
            ),
          ),
        ),
        title: Text(
          name.toUpperCase(),
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        subtitle: Text(
          '$owned imam · ${comics.length} brojeva',
          style: const TextStyle(color: tan, fontSize: 12),
        ),
        trailing: Icon(
          Icons.play_arrow,
          color: Theme.of(context).colorScheme.primary,
        ),
        onTap: () {
          onOpen();
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => SeriesPage(name: name, controller: controller),
            ),
          );
        },
      ),
    );
  }
}

class ComicTile extends StatelessWidget {
  const ComicTile({super.key, required this.comic, required this.controller});
  final Comic comic;
  final AppController controller;
  @override
  Widget build(BuildContext context) => Card(
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    child: InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ComicDetail(comic: comic, controller: controller),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          children: [
            SizedBox(
              width: 58,
              height: 78,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(9),
                child: ComicCover(
                  label: '#${comic.number}',
                  seed: comic.series.hashCode + comic.number,
                  assetPath: comic.coverAsset,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${comic.series} #${comic.number}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                  ),
                  Text(
                    comic.title.isEmpty ? comic.edition : comic.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: tan),
                  ),
                  const SizedBox(height: 7),
                  Wrap(
                    spacing: 6,
                    children: [
                      Tag(
                        comic.condition.isEmpty
                            ? 'bez stanja'
                            : comic.condition,
                      ),
                      if (comic.duplicate) const Tag('DUPLI'),
                      if (comic.loanedTo.isNotEmpty) const Tag('POSUĐENO'),
                    ],
                  ),
                ],
              ),
            ),
            Column(
              children: [
                IconButton(
                  tooltip: comic.owned
                      ? 'Imam — ukloni s police'
                      : 'Dodaj na moju policu',
                  onPressed: () => controller.save(
                    comic.copyWith(
                      owned: !comic.owned,
                      read: comic.owned ? false : comic.read,
                    ),
                  ),
                  icon: Icon(
                    comic.owned ? Icons.check_circle : Icons.add_circle_outline,
                    color: comic.owned ? const Color(0xFF3EC63E) : tan,
                  ),
                ),
                IconButton(
                  tooltip: comic.read
                      ? 'Označi nepročitano'
                      : 'Označi pročitano',
                  onPressed: comic.owned
                      ? () => controller.save(comic.copyWith(read: !comic.read))
                      : null,
                  icon: Icon(
                    comic.read ? Icons.visibility : Icons.visibility_off,
                    color: comic.read ? const Color(0xFF3EC63E) : Colors.grey,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

class ComicDetail extends StatelessWidget {
  const ComicDetail({super.key, required this.comic, required this.controller});
  final Comic comic;
  final AppController controller;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      final current =
          controller.comics.where((c) => c.id == comic.id).firstOrNull ?? comic;
      final edition =
          controller.comics
              .where(
                (c) =>
                    c.series == current.series && c.edition == current.edition,
              )
              .toList()
            ..sort((a, b) => a.number.compareTo(b.number));
      final at = edition.indexWhere((c) => c.id == current.id);
      final previous = at > 0 ? edition[at - 1] : null;
      final next = at >= 0 && at < edition.length - 1 ? edition[at + 1] : null;
      return Scaffold(
        appBar: AppBar(
          centerTitle: true,
          title: Text(
            current.series.toUpperCase(),
            style: TextStyle(
              color: Theme.of(context).colorScheme.primary,
              fontSize: 25,
              fontWeight: FontWeight.w900,
              letterSpacing: 1,
            ),
          ),
        ),
        body: Stack(
          children: [
            const Positioned.fill(child: _GrungeBackground()),
            ListView(
              padding: const EdgeInsets.fromLTRB(24, 4, 24, 32),
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 150,
                      height: 200,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: ComicCover(
                          label: '${current.series}\n#${current.number}',
                          seed: current.series.hashCode + current.number,
                          assetPath: current.coverAsset,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${current.series} ${current.edition}',
                              style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '#${current.number} - ${current.title}',
                              style: const TextStyle(
                                fontSize: 15.5,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 9),
                            Text(
                              '${current.year ?? '—'} · ${current.publisher}',
                              style: const TextStyle(color: tan, fontSize: 13),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: List.generate(
                                5,
                                (index) => Icon(
                                  index < current.rating
                                      ? Icons.star
                                      : Icons.star_border,
                                  color: const Color(0xFFE8C547),
                                  size: 17,
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            if (current.owned)
                              Row(
                                children: [
                                  Container(
                                    width: 36,
                                    height: 36,
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF080909),
                                      borderRadius: BorderRadius.circular(9),
                                      border: Border.all(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.primary,
                                        width: 1.5,
                                      ),
                                    ),
                                    child: Text(
                                      current.condition.isEmpty
                                          ? '—'
                                          : current.condition,
                                      style: TextStyle(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.primary,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 9),
                                  Text(
                                    current.estimatedValue == null
                                        ? 'U kolekciji'
                                        : '~${current.estimatedValue!.toStringAsFixed(0)} €',
                                    style: const TextStyle(
                                      color: tan,
                                      fontSize: 12.5,
                                    ),
                                  ),
                                ],
                              )
                            else
                              Text(
                                'TRAŽIM',
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.primary,
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                if (current.loanedTo.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(top: 14),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Theme.of(
                        context,
                      ).colorScheme.primary.withValues(alpha: .14),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: Theme.of(
                          context,
                        ).colorScheme.primary.withValues(alpha: .45),
                      ),
                    ),
                    child: Text(
                      'Posuđeno: ${current.loanedTo}',
                      style: const TextStyle(fontSize: 12.5),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.only(top: 14),
                  child: Text(
                    current.notes.isEmpty ||
                            current.notes.startsWith('Početni katalog') ||
                            current.notes.startsWith('BSP katalog') ||
                            current.notes.startsWith('Dodano unosom raspona')
                        ? 'Kultni talijanski horror strip prati istražitelja noćnih mora Dylana Doga i njegove neobične slučajeve.'
                        : current.notes,
                    style: const TextStyle(
                      color: tan,
                      fontSize: 13.5,
                      height: 1.55,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _IssueStep(
                        label: 'Prethodni broj',
                        comic: previous,
                        controller: controller,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _IssueStep(
                        label: 'Sljedeći broj',
                        comic: next,
                        controller: controller,
                        right: true,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: _StatusAction(
                        active: current.read,
                        icon: Icons.visibility_outlined,
                        activeLabel: 'PROČITANO',
                        inactiveLabel: 'NIJE ČITANO',
                        onTap: current.owned
                            ? () => controller.save(
                                current.copyWith(read: !current.read),
                              )
                            : null,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _StatusAction(
                        active: current.owned,
                        icon: Icons.check,
                        activeLabel: 'U KOLEKCIJI',
                        inactiveLabel: '+ DODAJ',
                        onTap: () => controller.save(
                          current.copyWith(
                            owned: !current.owned,
                            read: current.owned ? false : current.read,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          ComicForm(controller: controller, comic: current),
                    ),
                  ),
                  icon: const Icon(Icons.edit_outlined, size: 17),
                  label: Text(
                    current.owned
                        ? 'UREDI PRIMJERAK — stanje, posudba, vrijednost'
                        : 'UREDI — bilješke i ciljna cijena',
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: tan,
                    side: BorderSide(color: tan.withValues(alpha: .2)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
                const SectionTitle('DETALJI IZDANJA'),
                Card(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    child: Column(
                      children: [
                        DetailRow('Izdavač', current.publisher),
                        DetailRow(
                          'Edicija',
                          '${current.edition} #${current.number}',
                        ),
                        DetailRow('Godina', current.year?.toString() ?? '—'),
                        if (current.pageCount != null)
                          DetailRow('Stranice', '${current.pageCount}'),
                        if (current.writer.isNotEmpty)
                          DetailRow('Scenarij', current.writer),
                        if (current.artist.isNotEmpty)
                          DetailRow('Crtež', current.artist),
                        DetailRow(
                          'Ocjena',
                          current.rating == 0 ? '—' : '${current.rating}/5',
                        ),
                        DetailRow(
                          'Stanje',
                          current.condition.isEmpty
                              ? 'Bez stanja'
                              : current.condition,
                        ),
                        DetailRow(
                          'Vrijednost',
                          current.estimatedValue == null
                              ? '—'
                              : '${current.estimatedValue!.toStringAsFixed(2)} €',
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextButton.icon(
                  onPressed: () => _delete(context, current),
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('UKLONI ZAPIS'),
                  style: TextButton.styleFrom(foregroundColor: Colors.grey),
                ),
              ],
            ),
          ],
        ),
      );
    },
  );
  Future<void> _delete(BuildContext context, Comic selected) async {
    final yes =
        await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Ukloniti strip?'),
            content: const Text('Brisanje će se sinkronizirati sa serverom.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('ODUSTANI'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('UKLONI'),
              ),
            ],
          ),
        ) ??
        false;
    if (yes) {
      await controller.remove(selected);
      if (context.mounted) Navigator.pop(context);
    }
  }
}

class _GrungeBackground extends StatelessWidget {
  const _GrungeBackground();
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(
      gradient: RadialGradient(
        center: Alignment(-.8, -.9),
        radius: 1.2,
        colors: [Color(0x332D0B08), Colors.transparent],
      ),
    ),
  );
}

class _IssueStep extends StatelessWidget {
  const _IssueStep({
    required this.label,
    required this.comic,
    required this.controller,
    this.right = false,
  });
  final String label;
  final Comic? comic;
  final AppController controller;
  final bool right;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: right
        ? CrossAxisAlignment.end
        : CrossAxisAlignment.start,
    children: [
      Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
      const SizedBox(height: 6),
      SizedBox(
        width: double.infinity,
        child: OutlinedButton(
          onPressed: comic == null
              ? null
              : () => Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        ComicDetail(comic: comic!, controller: controller),
                  ),
                ),
          style: OutlinedButton.styleFrom(
            alignment: right ? Alignment.centerRight : Alignment.centerLeft,
            foregroundColor: Colors.white,
            side: BorderSide(color: tan.withValues(alpha: .16)),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          child: Text(
            comic == null ? '—' : '#${comic!.number} ${comic!.title}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12.5),
          ),
        ),
      ),
    ],
  );
}

class _StatusAction extends StatelessWidget {
  const _StatusAction({
    required this.active,
    required this.icon,
    required this.activeLabel,
    required this.inactiveLabel,
    required this.onTap,
  });
  final bool active;
  final IconData icon;
  final String activeLabel, inactiveLabel;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final color = active
        ? const Color(0xFF3EC63E)
        : Theme.of(context).colorScheme.primary;
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 16),
      label: Text(
        active ? activeLabel : inactiveLabel,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
      ),
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        backgroundColor: color.withValues(alpha: .13),
        side: BorderSide(color: color.withValues(alpha: .65)),
        padding: const EdgeInsets.symmetric(vertical: 13),
        shape: const StadiumBorder(),
      ),
    );
  }
}

class ComicForm extends StatefulWidget {
  const ComicForm({super.key, required this.controller, this.comic});
  final AppController controller;
  final Comic? comic;
  @override
  State<ComicForm> createState() => _ComicFormState();
}

class _ComicFormState extends State<ComicForm> {
  late final Map<String, TextEditingController> f;
  bool owned = true, read = false, duplicate = false;
  String grade = 'F';
  int rating = 0;
  Comic? matchedIssue;
  @override
  void initState() {
    super.initState();
    final c = widget.comic;
    final initial = widget.controller.comics.firstOrNull;
    owned = c?.owned ?? true;
    read = c?.read ?? false;
    duplicate = c?.duplicate ?? false;
    grade = c?.condition ?? 'F';
    rating = c?.rating ?? 0;
    f = {
      'series': TextEditingController(text: c?.series ?? initial?.series ?? ''),
      'edition': TextEditingController(
        text: c?.edition ?? initial?.edition ?? '',
      ),
      'number': TextEditingController(text: c?.number.toString()),
      'title': TextEditingController(text: c?.title),
      'publisher': TextEditingController(text: c?.publisher),
      'year': TextEditingController(text: c?.year?.toString()),
      'price': TextEditingController(text: c?.purchasePrice?.toString()),
      'value': TextEditingController(text: c?.estimatedValue?.toString()),
      'loan': TextEditingController(text: c?.loanedTo),
      'notes': TextEditingController(text: c?.notes),
      'pages': TextEditingController(text: c?.pageCount?.toString()),
      'writer': TextEditingController(text: c?.writer),
      'artist': TextEditingController(text: c?.artist),
    };
    matchedIssue = _findMatchingIssue();
    f['number']!.addListener(_matchIssue);
  }

  @override
  void dispose() {
    f['number']!.removeListener(_matchIssue);
    for (final c in f.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        widget.comic == null ? 'RUČNI UNOS' : 'UREDI STRIP',
        style: TextStyle(
          color: Theme.of(context).colorScheme.primary,
          fontWeight: FontWeight.w900,
        ),
      ),
    ),
    body: Form(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 40),
        children: [
          if (matchedIssue != null) ...[
            _matchedCard(matchedIssue!),
            const SizedBox(height: 14),
          ],
          _dropdown(
            keyName: 'series',
            label: 'Serijal *',
            values: _seriesOptions(),
            onChanged: _selectSeries,
          ),
          const SizedBox(height: 10),
          _dropdown(
            keyName: 'edition',
            label: 'Edicija',
            values: _editionOptions(),
            onChanged: (value) {
              f['edition']!.text = value;
              _matchIssue();
            },
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _field('number', 'Broj *', number: true)),
              const SizedBox(width: 10),
              Expanded(child: _field('year', 'Godina', number: true)),
            ],
          ),
          if (_nextMissing() case final next?) ...[
            const SizedBox(height: 7),
            TextButton.icon(
              onPressed: () {
                f['number']!.text = next.number.toString();
                _matchIssue();
              },
              icon: const Icon(Icons.auto_awesome, size: 16),
              label: Text(
                'Sljedeći broj koji nemaš: #${next.number} · ${next.edition}',
              ),
              style: TextButton.styleFrom(
                alignment: Alignment.centerLeft,
                foregroundColor: const Color(0xFF3EC63E),
              ),
            ),
          ],
          const SizedBox(height: 10),
          _field('title', 'Naslov'),
          const SizedBox(height: 10),
          Row(children: [Expanded(child: _field('publisher', 'Izdavač'))]),
          const SectionTitle('STANJE PRIMJERKA'),
          Wrap(
            spacing: 8,
            children: ['M', 'VF', 'F', 'G', 'P', '']
                .map(
                  (g) => ChoiceChip(
                    label: Text(g.isEmpty ? 'Bez stanja' : g),
                    selected: grade == g,
                    selectedColor: Theme.of(context).colorScheme.primary,
                    onSelected: (_) => setState(() => grade = g),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: _field('price', 'Plaćeno €', decimal: true)),
              const SizedBox(width: 10),
              Expanded(child: _field('value', 'Vrijednost €', decimal: true)),
            ],
          ),
          SwitchListTile(
            value: owned,
            onChanged: (v) => setState(() => owned = v),
            title: const Text('Imam u kolekciji'),
            contentPadding: EdgeInsets.zero,
          ),
          SwitchListTile(
            value: read,
            onChanged: (v) => setState(() => read = v),
            title: const Text('Pročitano'),
            contentPadding: EdgeInsets.zero,
          ),
          SwitchListTile(
            value: duplicate,
            onChanged: (v) => setState(() => duplicate = v),
            title: const Text('Dupli primjerak'),
            contentPadding: EdgeInsets.zero,
          ),
          _field('loan', 'Posuđeno kome'),
          const SizedBox(height: 10),
          _field('notes', 'Bilješke', lines: 3),
          const SectionTitle('DODATNI PODACI IZDANJA'),
          Row(
            children: [
              Expanded(child: _field('writer', 'Scenarij')),
              const SizedBox(width: 10),
              Expanded(child: _field('artist', 'Crtež')),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: 150,
            child: _field('pages', 'Broj stranica', number: true),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Text(
                'Ocjena',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(width: 12),
              ...List.generate(
                5,
                (index) => IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: '${index + 1}/5',
                  onPressed: () => setState(
                    () => rating = rating == index + 1 ? 0 : index + 1,
                  ),
                  icon: Icon(
                    index < rating ? Icons.star : Icons.star_border,
                    color: const Color(0xFFE8C547),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          FilledButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.save_outlined),
            label: Padding(
              padding: const EdgeInsets.all(14),
              child: Text(
                widget.comic == null ? 'SPREMI U KOLEKCIJU' : 'SPREMI PROMJENE',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ],
      ),
    ),
  );
  Widget _field(
    String key,
    String label, {
    bool number = false,
    bool decimal = false,
    int lines = 1,
  }) => TextField(
    controller: f[key],
    maxLines: lines,
    keyboardType: number || decimal
        ? TextInputType.numberWithOptions(decimal: decimal)
        : TextInputType.text,
    inputFormatters: number ? [FilteringTextInputFormatter.digitsOnly] : null,
    decoration: InputDecoration(labelText: label),
  );

  List<String> _seriesOptions() {
    final values = widget.controller.comics
        .map((comic) => comic.series)
        .toSet();
    if (f['series']!.text.trim().isNotEmpty) {
      values.add(f['series']!.text.trim());
    }
    return values.toList()..sort((a, b) => a.compareTo(b));
  }

  List<String> _editionOptions() {
    final series = f['series']!.text.trim().toLowerCase();
    final values = widget.controller.comics
        .where((comic) => comic.series.toLowerCase() == series)
        .map((comic) => comic.edition)
        .toSet();
    if (f['edition']!.text.trim().isNotEmpty) {
      values.add(f['edition']!.text.trim());
    }
    return values.toList()..sort((a, b) => a.compareTo(b));
  }

  Widget _dropdown({
    required String keyName,
    required String label,
    required List<String> values,
    required ValueChanged<String> onChanged,
  }) {
    final current = f[keyName]!.text.trim();
    if (values.isEmpty) return _field(keyName, label);
    final selected = values.contains(current) ? current : values.first;
    return DropdownButtonFormField<String>(
      key: ValueKey('$keyName-$selected-${values.length}'),
      initialValue: selected,
      isExpanded: true,
      decoration: InputDecoration(labelText: label),
      items: values
          .map(
            (value) => DropdownMenuItem<String>(
              value: value,
              child: Text(value, overflow: TextOverflow.ellipsis),
            ),
          )
          .toList(),
      onChanged: (value) {
        if (value != null) onChanged(value);
      },
    );
  }

  void _selectSeries(String value) {
    f['series']!.text = value;
    final editions =
        widget.controller.comics
            .where((comic) => comic.series == value)
            .map((comic) => comic.edition)
            .toSet()
            .toList()
          ..sort();
    if (editions.isNotEmpty && !editions.contains(f['edition']!.text)) {
      f['edition']!.text = editions.first;
    }
    _matchIssue();
  }

  Comic? _findMatchingIssue() {
    final number = int.tryParse(f['number']?.text ?? '');
    if (number == null) return null;
    final series = f['series']?.text.trim().toLowerCase();
    final edition = f['edition']?.text.trim().toLowerCase();
    return widget.controller.comics
        .where(
          (comic) =>
              comic.number == number &&
              comic.series.toLowerCase() == series &&
              comic.edition.toLowerCase() == edition,
        )
        .firstOrNull;
  }

  void _matchIssue() {
    final match = _findMatchingIssue();
    if (match != null && widget.comic == null) {
      f['title']!.text = match.title;
      f['publisher']!.text = match.publisher;
      f['year']!.text = match.year?.toString() ?? '';
    }
    if (mounted) setState(() => matchedIssue = match);
  }

  Comic? _nextMissing() {
    final series = f['series']!.text.trim().toLowerCase();
    final edition = f['edition']!.text.trim().toLowerCase();
    final candidates =
        widget.controller.comics
            .where(
              (comic) =>
                  !comic.owned &&
                  comic.series.toLowerCase() == series &&
                  comic.edition.toLowerCase() == edition,
            )
            .toList()
          ..sort((a, b) => a.number.compareTo(b.number));
    return candidates.firstOrNull;
  }

  Widget _matchedCard(Comic issue) => Card(
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    child: Padding(
      padding: const EdgeInsets.all(10),
      child: Row(
        children: [
          SizedBox(
            width: 48,
            height: 64,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(7),
              child: ComicCover(
                label: issue.series,
                seed: issue.number,
                assetPath: issue.coverAsset,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${issue.series.toUpperCase()} · ${issue.edition.toUpperCase()} #${issue.number}',
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 3),
                Text(
                  issue.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: tan, fontSize: 12),
                ),
                const SizedBox(height: 3),
                const Text(
                  'Podaci su automatski popunjeni iz lokalnog kataloga.',
                  style: TextStyle(color: Color(0xFF3EC63E), fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
  Future<void> _save() async {
    final series = f['series']!.text.trim();
    final number = int.tryParse(f['number']!.text);
    if (series.isEmpty || number == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Serijal i broj su obavezni.')),
      );
      return;
    }
    final c = widget.comic ?? _findMatchingIssue();
    if (c == null) {
      await widget.controller.add(
        series: series,
        edition: f['edition']!.text,
        number: number,
        title: f['title']!.text.trim().isEmpty
            ? '$series #$number'
            : f['title']!.text,
        publisher: f['publisher']!.text,
        year: int.tryParse(f['year']!.text),
        owned: owned,
        read: read,
        condition: grade,
        purchasePrice: double.tryParse(f['price']!.text.replaceAll(',', '.')),
        estimatedValue: double.tryParse(f['value']!.text.replaceAll(',', '.')),
        duplicate: duplicate,
        loanedTo: f['loan']!.text,
        notes: f['notes']!.text,
        rating: rating,
        pageCount: int.tryParse(f['pages']!.text),
        writer: f['writer']!.text,
        artist: f['artist']!.text,
      );
    } else {
      await widget.controller.save(
        c.copyWith(
          series: series,
          edition: f['edition']!.text,
          number: number,
          title: f['title']!.text.trim().isEmpty
              ? '$series #$number'
              : f['title']!.text,
          publisher: f['publisher']!.text,
          year: int.tryParse(f['year']!.text),
          owned: owned,
          read: read,
          condition: grade,
          purchasePrice: double.tryParse(f['price']!.text.replaceAll(',', '.')),
          estimatedValue: double.tryParse(
            f['value']!.text.replaceAll(',', '.'),
          ),
          duplicate: duplicate,
          loanedTo: f['loan']!.text,
          notes: f['notes']!.text,
          rating: rating,
          pageCount: int.tryParse(f['pages']!.text),
          writer: f['writer']!.text,
          artist: f['artist']!.text,
        ),
      );
    }
    if (mounted) Navigator.pop(context);
  }
}

class BatchConditionResult {
  const BatchConditionResult(this.conditions);

  final Map<String, String> conditions;
}

class BatchConditionPage extends StatefulWidget {
  const BatchConditionPage({super.key, required this.comics});

  final List<Comic> comics;

  @override
  State<BatchConditionPage> createState() => _BatchConditionPageState();
}

class _BatchConditionPageState extends State<BatchConditionPage> {
  late final List<String?> selections;
  int index = 0;

  static const grades = ['M', 'VF', 'F', 'G', 'P'];

  @override
  void initState() {
    super.initState();
    selections = widget.comics
        .map<String?>((comic) {
          if (!comic.owned || comic.condition.isEmpty) return null;
          return grades.contains(comic.condition) ? comic.condition : null;
        })
        .toList(growable: false);
  }

  bool get done => index >= widget.comics.length;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      centerTitle: true,
      title: Text(
        'STANJE PRIMJERAKA',
        style: TextStyle(
          color: Theme.of(context).colorScheme.primary,
          fontWeight: FontWeight.w900,
          fontSize: 18,
        ),
      ),
      actions: [
        IconButton(
          key: const ValueKey('condition-all-without'),
          tooltip: 'Dodaj sve bez stanja',
          onPressed: _confirmAllWithoutCondition,
          icon: const Icon(Icons.fast_forward_outlined),
        ),
      ],
    ),
    body: widget.comics.isEmpty
        ? const Center(child: Text('Nema odabranih stripova.'))
        : done
        ? _summary(context)
        : _review(context),
  );

  Widget _review(BuildContext context) {
    final comic = widget.comics[index];
    final selected = selections[index];
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 14),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(99),
                    child: LinearProgressIndicator(
                      value: index / widget.comics.length,
                      minHeight: 7,
                      backgroundColor: Theme.of(context).colorScheme.surface,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  '${index + 1}/${widget.comics.length}',
                  style: const TextStyle(color: tan, fontSize: 12),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: 260,
                    maxHeight: 350,
                  ),
                  child: AspectRatio(
                    aspectRatio: 3 / 4,
                    child: ClipRRect(
                      key: const ValueKey('condition-cover'),
                      borderRadius: BorderRadius.circular(14),
                      child: ComicCover(
                        label: '${comic.series}\n#${comic.number}',
                        seed: comic.number + comic.edition.hashCode,
                        assetPath: comic.coverAsset,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              '${comic.series.toUpperCase()} · ${comic.edition.toUpperCase()} #${comic.number}',
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 3),
            Text(
              comic.title,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: tan, fontSize: 12.5),
            ),
            const SizedBox(height: 12),
            Row(
              children: grades
                  .map(
                    (grade) => Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        child: _ConditionChoice(
                          key: ValueKey('condition-$grade'),
                          grade: grade,
                          selected: selected == grade,
                          onTap: () => _select(grade),
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                key: const ValueKey('condition-none'),
                onPressed: () => _select(''),
                icon: const Icon(Icons.remove_circle_outline, size: 17),
                label: const Text('BEZ STANJA — PRESKOČI I NASTAVI'),
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: TextButton.icon(
                    key: const ValueKey('condition-previous'),
                    onPressed: index == 0 ? null : _previous,
                    icon: const Icon(Icons.arrow_back),
                    label: const Text('PRETHODNI'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextButton.icon(
                    key: const ValueKey('condition-next'),
                    onPressed: _next,
                    icon: const Icon(Icons.arrow_forward),
                    label: const Text('DALJE'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _summary(BuildContext context) {
    final described = selections
        .where((value) => value?.isNotEmpty ?? false)
        .length;
    final unspecified = selections.length - described;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Icon(
              Icons.task_alt,
              size: 74,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 18),
            const Text(
              'SVE JE PREGLEDANO',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 23, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            Text(
              '$described sa stanjem · $unspecified bez stanja',
              textAlign: TextAlign.center,
              style: const TextStyle(color: tan),
            ),
            const SizedBox(height: 28),
            OutlinedButton.icon(
              key: const ValueKey('condition-summary-previous'),
              onPressed: _previous,
              icon: const Icon(Icons.arrow_back),
              label: const Text('VRATI SE NA PRETHODNI'),
            ),
            const SizedBox(height: 10),
            FilledButton.icon(
              key: const ValueKey('condition-finish'),
              onPressed: _finish,
              icon: const Icon(Icons.library_add_outlined),
              label: Padding(
                padding: const EdgeInsets.all(14),
                child: Text(
                  'DODAJ ${_hrIssueCount(widget.comics.length)}',
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _select(String grade) {
    setState(() {
      selections[index] = grade;
      index++;
    });
  }

  void _next() {
    setState(() {
      selections[index] ??= '';
      index++;
    });
  }

  void _previous() {
    setState(() {
      index = (index - 1).clamp(0, widget.comics.length - 1);
    });
  }

  Future<void> _confirmAllWithoutCondition() async {
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Dodati sve bez stanja?'),
            content: const Text(
              'Svi odabrani stripovi spremit će se bez M/VF/F/G/P oznake.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('ODUSTANI'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('BEZ STANJA'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !mounted) return;
    for (var i = 0; i < selections.length; i++) {
      selections[i] = '';
    }
    _finish();
  }

  void _finish() {
    Navigator.pop(
      context,
      BatchConditionResult({
        for (var i = 0; i < widget.comics.length; i++)
          widget.comics[i].id: selections[i] ?? '',
      }),
    );
  }
}

class _ConditionChoice extends StatelessWidget {
  const _ConditionChoice({
    super.key,
    required this.grade,
    required this.selected,
    required this.onTap,
  });

  final String grade;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final description = switch (grade) {
      'M' => 'Novo',
      'VF' => 'Vrlo dobro',
      'F' => 'Dobro',
      'G' => 'Solidno',
      _ => 'Loše',
    };
    return Material(
      color: selected ? accent : Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(11),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(11),
        child: Container(
          height: 58,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(11),
            border: Border.all(
              color: selected ? accent : Theme.of(context).dividerColor,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                grade,
                style: TextStyle(
                  color: selected ? Colors.white : null,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(
                description,
                textAlign: TextAlign.center,
                maxLines: 1,
                style: TextStyle(
                  color: selected ? Colors.white70 : tan,
                  fontSize: 8,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _hrIssueCount(int count) {
  final lastTwo = count % 100;
  final last = count % 10;
  if (last == 1 && lastTwo != 11) return '$count STRIP';
  if (last >= 2 && last <= 4 && (lastTwo < 12 || lastTwo > 14)) {
    return '$count STRIPA';
  }
  return '$count STRIPOVA';
}

class RangeEntryPage extends StatefulWidget {
  const RangeEntryPage({super.key, required this.controller});

  final AppController controller;

  @override
  State<RangeEntryPage> createState() => _RangeEntryPageState();
}

class _RangeEntryPageState extends State<RangeEntryPage> {
  final from = TextEditingController();
  final to = TextEditingController();
  final excluded = <int>{};
  String series = '';
  String edition = '';
  bool saving = false;
  bool updatingBounds = false;

  @override
  void initState() {
    super.initState();
    final seriesValues = _seriesValues();
    if (seriesValues.isNotEmpty) {
      series = seriesValues.first;
      final editionValues = _editionValues();
      if (editionValues.isNotEmpty) edition = editionValues.first;
    }
    _resetBounds();
    from.addListener(_rangeChanged);
    to.addListener(_rangeChanged);
  }

  @override
  void dispose() {
    from.removeListener(_rangeChanged);
    to.removeListener(_rangeChanged);
    from.dispose();
    to.dispose();
    super.dispose();
  }

  void _rangeChanged() {
    if (!updatingBounds && mounted) setState(() {});
  }

  List<String> _seriesValues() =>
      (widget.controller.comics.map((comic) => comic.series).toSet().toList()
        ..sort());

  List<String> _editionValues() =>
      (widget.controller.comics
          .where((comic) => comic.series == series)
          .map((comic) => comic.edition)
          .toSet()
          .toList()
        ..sort());

  List<Comic> _editionIssues() =>
      widget.controller.comics
          .where((comic) => comic.series == series && comic.edition == edition)
          .toList()
        ..sort((a, b) => a.number.compareTo(b.number));

  void _resetBounds() {
    final issues = _editionIssues();
    final first = issues.isEmpty ? 1 : issues.first.number;
    final last = issues.isEmpty ? 50 : issues.last.number;
    updatingBounds = true;
    try {
      from.text = first.toString();
      to.text = (first + 49).clamp(first, last).toString();
      excluded.clear();
    } finally {
      updatingBounds = false;
    }
  }

  int? get _first => int.tryParse(from.text);
  int? get _last => int.tryParse(to.text);
  bool get _validRange =>
      _first != null &&
      _last != null &&
      _first! > 0 &&
      _last! >= _first! &&
      _last! - _first! < 500;

  List<int> get _numbers {
    if (!_validRange) return const [];
    return List<int>.generate(_last! - _first! + 1, (index) => _first! + index);
  }

  int get _selectedCount =>
      _numbers.where((number) => !excluded.contains(number)).length;

  @override
  Widget build(BuildContext context) {
    final seriesValues = _seriesValues();
    final editionValues = _editionValues();
    final numbers = _numbers.take(150).toList(growable: false);
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: Text(
          'UNOS RASPONA',
          style: TextStyle(
            color: Theme.of(context).colorScheme.primary,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 4, 18, 30),
        children: [
          const Text(
            'Za prvi unos postojeće kolekcije — cijeli raspon odjednom',
            textAlign: TextAlign.center,
            style: TextStyle(color: tan, fontSize: 12.5),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            key: ValueKey('range-series-$series'),
            initialValue: seriesValues.contains(series) ? series : null,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Serijal'),
            items: seriesValues
                .map(
                  (value) => DropdownMenuItem(value: value, child: Text(value)),
                )
                .toList(),
            onChanged: (value) {
              if (value == null) return;
              setState(() {
                series = value;
                final editions = _editionValues();
                edition = editions.firstOrNull ?? '';
                _resetBounds();
              });
            },
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            key: ValueKey('range-edition-$series-$edition'),
            initialValue: editionValues.contains(edition) ? edition : null,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Edicija'),
            items: editionValues
                .map(
                  (value) => DropdownMenuItem(value: value, child: Text(value)),
                )
                .toList(),
            onChanged: (value) {
              if (value == null) return;
              setState(() {
                edition = value;
                _resetBounds();
              });
            },
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _numberField(from, 'Od broja')),
              const SizedBox(width: 10),
              Expanded(child: _numberField(to, 'Do broja')),
            ],
          ),
          const SectionTitle('OSIM BROJEVA (NEMAM IH) — TAPNI BROJ'),
          if (!_validRange)
            const EmptyCard(
              text: 'Upiši ispravan raspon do najviše 500 brojeva.',
            )
          else ...[
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7,
                mainAxisSpacing: 6,
                crossAxisSpacing: 6,
              ),
              itemCount: numbers.length,
              itemBuilder: (context, index) {
                final number = numbers[index];
                final off = excluded.contains(number);
                return InkWell(
                  key: ValueKey('range-number-$number'),
                  onTap: () => setState(() {
                    if (!excluded.add(number)) excluded.remove(number);
                  }),
                  borderRadius: BorderRadius.circular(9),
                  child: Container(
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: off
                          ? Theme.of(
                              context,
                            ).colorScheme.primary.withValues(alpha: .14)
                          : Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(9),
                      border: Border.all(
                        color: off
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).dividerColor,
                      ),
                    ),
                    child: Text(
                      '$number',
                      style: TextStyle(
                        color: off
                            ? Theme.of(context).colorScheme.primary
                            : null,
                        fontWeight: FontWeight.w700,
                        decoration: off ? TextDecoration.lineThrough : null,
                      ),
                    ),
                  ),
                );
              },
            ),
            if (_numbers.length > 150)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'Prikazano je prvih 150 brojeva — suzi raspon za označavanje ostalih.',
                  style: TextStyle(color: tan, fontSize: 11.5),
                ),
              ),
          ],
          const SectionTitle('STANJE PRIMJERAKA'),
          Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            child: Padding(
              padding: const EdgeInsets.all(13),
              child: Row(
                children: [
                  Icon(
                    Icons.photo_library_outlined,
                    color: Theme.of(context).colorScheme.primary,
                    size: 28,
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Prikaži naslovnicu svakog stripa i brzo odaberi M, VF, F, G ili P. Nakon odabira odmah se otvara sljedeći.',
                      style: TextStyle(fontSize: 12.5, height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              color: const Color(0xFF3EC63E).withValues(alpha: .1),
              borderRadius: BorderRadius.circular(13),
              border: Border.all(
                color: const Color(0xFF3EC63E).withValues(alpha: .4),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.library_add, color: Color(0xFF3EC63E)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _validRange
                        ? 'Dodat će se $_selectedCount brojeva (${from.text}–${to.text}). '
                              '${excluded.isEmpty ? '' : 'Preskočeni brojevi ostat će u Tražim.'}'
                        : 'Raspon još nije ispravan.',
                    style: const TextStyle(fontSize: 13, height: 1.4),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            key: const ValueKey('range-review-conditions'),
            onPressed: !_validRange || _selectedCount == 0 || saving
                ? null
                : _reviewConditions,
            icon: saving
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.photo_library_outlined),
            label: Padding(
              padding: const EdgeInsets.all(14),
              child: Text(
                saving
                    ? 'SPREMAM…'
                    : 'ODABERI STANJE ZA ${_issueCount(_selectedCount)}',
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ),
          const SizedBox(height: 9),
          OutlinedButton.icon(
            key: const ValueKey('range-save-without-condition'),
            onPressed: !_validRange || _selectedCount == 0 || saving
                ? null
                : _saveWithoutCondition,
            icon: const Icon(Icons.fast_forward_outlined),
            label: Padding(
              padding: const EdgeInsets.all(13),
              child: Text(
                'DODAJ ${_issueCount(_selectedCount)} BEZ STANJA',
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _numberField(TextEditingController controller, String label) =>
      TextField(
        controller: controller,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: InputDecoration(labelText: label),
      );

  List<Comic> _drafts() {
    final existing = {
      for (final comic in _editionIssues()) comic.number: comic,
    };
    final template = existing.values.firstOrNull;
    final now = DateTime.now().millisecondsSinceEpoch;
    return _numbers
        .map((number) {
          return existing[number] ??
              Comic(
                id: 'range-${_slug(series)}-${_slug(edition)}-$number',
                series: series,
                edition: edition,
                number: number,
                title: '$series #$number',
                publisher: template?.publisher ?? '',
                owned: false,
                read: false,
                condition: '',
                notes: 'Dodano unosom raspona',
                updatedAt: now,
              );
        })
        .toList(growable: false);
  }

  Future<void> _reviewConditions() async {
    final drafts = _drafts()
        .where((comic) => !excluded.contains(comic.number))
        .toList(growable: false);
    final result = await Navigator.push<BatchConditionResult>(
      context,
      MaterialPageRoute(builder: (_) => BatchConditionPage(comics: drafts)),
    );
    if (result == null || !mounted) return;
    await _save(conditions: result.conditions);
  }

  Future<void> _saveWithoutCondition() => _save(withoutCondition: true);

  Future<void> _save({
    Map<String, String> conditions = const {},
    bool withoutCondition = false,
  }) async {
    setState(() => saving = true);
    final changes = <Comic>[];
    for (final base in _drafts()) {
      final owned = !excluded.contains(base.number);
      changes.add(
        base.copyWith(
          owned: owned,
          read: owned ? base.read : false,
          condition: owned
              ? (withoutCondition ? '' : conditions[base.id] ?? '')
              : base.condition,
        ),
      );
    }
    try {
      await widget.controller.saveAll(changes);
      if (mounted) Navigator.pop(context, _selectedCount);
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  String _slug(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-|-$'), '');

  String _issueCount(int count) {
    final lastTwo = count % 100;
    final last = count % 10;
    if (last == 1 && lastTwo != 11) return '$count BROJ';
    if (last >= 2 && last <= 4 && (lastTwo < 12 || lastTwo > 14)) {
      return '$count BROJA';
    }
    return '$count BROJEVA';
  }
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    required this.controller,
    required this.accountEmail,
    required this.onLogout,
  });
  final AppController controller;
  final String accountEmail;
  final VoidCallback onLogout;
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final server = TextEditingController();
  final token = TextEditingController();
  bool loaded = false;

  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    server.dispose();
    token.dispose();
    super.dispose();
  }

  Future<void> load() async {
    if (loaded) return;
    final p = await SharedPreferences.getInstance();
    server.text = p.getString('server_url') ?? 'http://192.168.1.50:8787';
    token.text = p.getString('api_token') ?? '';
    loaded = true;
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 100),
      children: [
        const SectionTitle('IZGLED'),
        _settingRow(
          'Tema',
          _segment<bool>(
            value: widget.controller.darkMode,
            options: const [(true, 'Tamna'), (false, 'Svijetla')],
            onChanged: (value) =>
                widget.controller.updatePreferences(darkMode: value),
          ),
        ),
        const SizedBox(height: 9),
        _settingRow(
          'Boja',
          Row(
            mainAxisSize: MainAxisSize.min,
            children: ['red', 'yellow', 'blue']
                .map(
                  (name) => Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Semantics(
                      button: true,
                      selected: widget.controller.accent == name,
                      label: switch (name) {
                        'yellow' => 'Žuta boja',
                        'blue' => 'Plava boja',
                        _ => 'Crvena boja',
                      },
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: () =>
                            widget.controller.updatePreferences(accent: name),
                        child: Container(
                          width: 31,
                          height: 31,
                          decoration: BoxDecoration(
                            color: accentColor(name),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: widget.controller.accent == name
                                  ? Theme.of(context).colorScheme.onSurface
                                  : Colors.transparent,
                              width: 2,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
        ),
        const SizedBox(height: 9),
        _settingRow(
          'Naslovi',
          _segment<bool>(
            value: widget.controller.comicTitles,
            options: const [(false, 'Roboto'), (true, 'Comic')],
            onChanged: (value) =>
                widget.controller.updatePreferences(comicTitles: value),
          ),
        ),
        const SizedBox(height: 9),
        _settingRow(
          'Statistika',
          _segment<bool>(
            value: widget.controller.showStatistics,
            options: const [(true, 'Da'), (false, 'Ne')],
            onChanged: (value) =>
                widget.controller.updatePreferences(showStatistics: value),
          ),
        ),
        const SectionTitle('SINKRONIZACIJA'),
        Card(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            children: [
              SwitchListTile(
                value: widget.controller.autoSync,
                onChanged: (value) =>
                    widget.controller.updatePreferences(autoSync: value),
                title: const Text(
                  'Automatska sinkronizacija',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: const Text(
                  'Promjene se spremaju lokalno i šalju na server',
                  style: TextStyle(fontSize: 12),
                ),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 9,
                ),
                child: Row(
                  children: [
                    Icon(
                      widget.controller.online
                          ? Icons.cloud_done_outlined
                          : Icons.cloud_off_outlined,
                      color: widget.controller.online
                          ? const Color(0xFF3EC63E)
                          : const Color(0xFFE8C547),
                      size: 17,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _lastSyncLabel(),
                        style: const TextStyle(color: tan, fontSize: 12),
                      ),
                    ),
                    TextButton(
                      onPressed: widget.controller.syncing ? null : _syncNow,
                      child: Text(
                        widget.controller.syncing
                            ? 'Sinkroniziram…'
                            : 'Sinkroniziraj sad',
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 9),
        Card(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          child: SwitchListTile(
            value: widget.controller.newIssueNotifications,
            onChanged: (value) => widget.controller.updatePreferences(
              newIssueNotifications: value,
            ),
            title: const Text(
              'Obavijesti o novim brojevima',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ),
        const SectionTitle('RAČUN'),
        Card(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: Theme.of(context).colorScheme.surface,
              foregroundColor: accent,
              child: const Text(
                'K',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
            title: const Text(
              'Kolekcionar',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: Text(
              widget.accountEmail.isEmpty
                  ? 'lokalni korisnik'
                  : widget.accountEmail,
            ),
            trailing: TextButton.icon(
              onPressed: _logout,
              icon: const Icon(Icons.logout, size: 17),
              label: const Text('Odjava'),
              style: TextButton.styleFrom(foregroundColor: tan),
            ),
          ),
        ),
        const SectionTitle('PODACI I SERVER'),
        Card(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          child: ExpansionTile(
            leading: Icon(Icons.lan_outlined, color: accent),
            title: const Text('Lokalni sync server'),
            subtitle: Text(widget.controller.syncMessage),
            childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
            children: [
              TextField(
                controller: server,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(
                  labelText: 'Adresa servera',
                  helperText: 'Npr. http://192.168.1.50:8787',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: token,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'API token'),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: save,
                  icon: const Icon(Icons.save_outlined),
                  label: const Text('SPREMI I SINKRONIZIRAJ'),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 9),
        Card(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            children: [
              ListTile(
                leading: Icon(Icons.storage_outlined, color: accent),
                title: const Text('Lokalna SQLite baza'),
                subtitle: Text(
                  '${widget.controller.comics.length} zapisa · radi bez interneta',
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: Icon(Icons.copy_all_outlined, color: accent),
                title: const Text('Kopiraj CSV izvoz'),
                subtitle: const Text('Sigurnosna kopija za Excel ili Sheets'),
                onTap: exportCsv,
              ),
            ],
          ),
        ),
        AboutListTile(
          icon: Icon(
            Icons.info_outline,
            color: Theme.of(context).colorScheme.primary,
          ),
          applicationName: 'Comicollect',
          applicationVersion: '1.0.0',
          applicationLegalese: 'Privatna kolekcija stripova',
        ),
      ],
    );
  }

  Future<void> save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString('server_url', server.text.trim());
    await p.setString('api_token', token.text.trim());
    await widget.controller.sync(force: true);
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(widget.controller.syncMessage)));
    }
  }

  Widget _settingRow(String label, Widget control) => Card(
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          control,
        ],
      ),
    ),
  );

  Widget _segment<T>({
    required T value,
    required List<(T, String)> options,
    required ValueChanged<T> onChanged,
  }) => Wrap(
    spacing: 5,
    children: options.map((option) {
      final selected = value == option.$1;
      return ChoiceChip(
        label: Text(
          option.$2,
          style: TextStyle(color: selected ? Colors.white : null),
        ),
        selected: selected,
        selectedColor: Theme.of(context).colorScheme.primary,
        showCheckmark: false,
        onSelected: (_) => onChanged(option.$1),
      );
    }).toList(),
  );

  String _lastSyncLabel() {
    final at = widget.controller.lastSyncAt;
    if (at == null) return widget.controller.syncMessage;
    final now = DateTime.now();
    final day =
        at.year == now.year && at.month == now.month && at.day == now.day
        ? 'danas'
        : '${at.day}.${at.month}.${at.year}.';
    final minute = at.minute.toString().padLeft(2, '0');
    return 'Zadnja sinkronizacija: $day ${at.hour}:$minute';
  }

  Future<void> _syncNow() async {
    await widget.controller.sync(force: true);
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(widget.controller.syncMessage)));
  }

  Future<void> _logout() async {
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Odjaviti se?'),
            content: const Text(
              'Lokalna kolekcija ostaje spremljena na ovom uređaju.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('ODUSTANI'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('ODJAVA'),
              ),
            ],
          ),
        ) ??
        false;
    if (confirmed) widget.onLogout();
  }

  void exportCsv() {
    String esc(Object? v) => '"${(v ?? '').toString().replaceAll('"', '""')}"';
    final rows = <String>[
      'Serijal,Edicija,Broj,Naslov,Izdavač,Godina,Imam,Pročitano,Stanje,Vrijednost,Dupli,Posuđeno',
    ];
    for (final c in widget.controller.comics) {
      rows.add(
        [
          c.series,
          c.edition,
          c.number,
          c.title,
          c.publisher,
          c.year ?? '',
          c.owned ? 'DA' : 'NE',
          c.read ? 'DA' : 'NE',
          c.condition,
          c.estimatedValue ?? '',
          c.duplicate ? 'DA' : 'NE',
          c.loanedTo,
        ].map(esc).join(','),
      );
    }
    Clipboard.setData(ClipboardData(text: rows.join('\n')));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('CSV je kopiran u međuspremnik.')),
    );
  }
}

class ComicCover extends StatelessWidget {
  const ComicCover({
    super.key,
    required this.label,
    required this.seed,
    this.assetPath = '',
  });
  final String label;
  final int seed;
  final String assetPath;
  @override
  Widget build(BuildContext context) {
    if (assetPath.isNotEmpty) {
      return Image.asset(
        assetPath,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.medium,
        errorBuilder: (_, _, _) => _placeholder(),
      );
    }
    return _placeholder();
  }

  Widget _placeholder() {
    const colors = [
      Color(0xFFB5281E),
      Color(0xFF1F5FA8),
      Color(0xFFE0C530),
      Color(0xFF1E4A42),
      Color(0xFF5A2A6E),
      Color(0xFF3A2C20),
    ];
    final color = colors[seed.abs() % colors.length];
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            color.withValues(alpha: .95),
            Color.lerp(color, Colors.black, .55)!,
          ],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          CustomPaint(painter: DotPainter()),
          Center(
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Text(
                label.toUpperCase(),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 22,
                  height: 1,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFFF2D02B),
                  shadows: [
                    Shadow(
                      color: Colors.black,
                      offset: Offset(2, 2),
                      blurRadius: 1,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class DotPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = Colors.black.withValues(alpha: .16);
    for (double y = 4; y < size.height; y += 8) {
      for (double x = 4; x < size.width; x += 8) {
        canvas.drawCircle(Offset(x, y), 1.2, p);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class MetricCard extends StatelessWidget {
  const MetricCard({
    super.key,
    required this.icon,
    required this.value,
    required this.label,
  });
  final IconData icon;
  final String value, label;
  @override
  Widget build(BuildContext context) => Card(
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Icon(icon, color: Theme.of(context).colorScheme.primary, size: 30),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 10,
                  color: tan,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 24, bottom: 10),
    child: Text(
      text,
      style: const TextStyle(
        color: tan,
        fontSize: 12,
        fontWeight: FontWeight.bold,
        letterSpacing: 1.2,
      ),
    ),
  );
}

class EmptyCard extends StatelessWidget {
  const EmptyCard({super.key, required this.text});
  final String text;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(22),
      child: Text(text, style: const TextStyle(color: tan)),
    ),
  );
}

class Tag extends StatelessWidget {
  const Tag(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.primary.withValues(alpha: .16),
      borderRadius: BorderRadius.circular(6),
      border: Border.all(
        color: Theme.of(context).colorScheme.primary.withValues(alpha: .4),
      ),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 9,
          color: Theme.of(context).colorScheme.primary,
          fontWeight: FontWeight.bold,
        ),
      ),
    ),
  );
}

class DetailRow extends StatelessWidget {
  const DetailRow(this.label, this.value, {super.key});
  final String label, value;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 9),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 110,
          child: Text(label, style: const TextStyle(color: tan)),
        ),
        Expanded(
          child: Text(
            value.isEmpty ? '—' : value,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    ),
  );
}
