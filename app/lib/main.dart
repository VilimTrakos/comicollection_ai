import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app_controller.dart';
import 'models/comic.dart';

const red = Color(0xFFC6291E);
const ink = Color(0xFF131412);
const surface = Color(0xFF1C1D1B);
const tan = Color(0xFFB7A88F);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final controller = AppController();
  await controller.init();
  runApp(ComicollectApp(controller: controller));
}

class ComicollectApp extends StatelessWidget {
  const ComicollectApp({super.key, required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'Comicollect',
    themeMode: ThemeMode.dark,
    darkTheme: ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: ink,
      colorScheme: ColorScheme.fromSeed(
        seedColor: red,
        brightness: Brightness.dark,
        surface: surface,
      ),
      useMaterial3: true,
      appBarTheme: const AppBarTheme(backgroundColor: ink, elevation: 0),
      cardTheme: const CardThemeData(
        color: surface,
        elevation: 4,
        margin: EdgeInsets.zero,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: red),
        ),
      ),
    ),
    home: LoginGate(controller: controller),
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
    if (entered) return Shell(controller: widget.controller);
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
                  const Text(
                    'PRIJAVA',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: red,
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
                    child: const Padding(
                      padding: EdgeInsets.all(13),
                      child: Text(
                        'NAPRAVI NOVI RAČUN',
                        style: TextStyle(
                          color: red,
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
                const Text(
                  'COMICS\nCOLLECTION',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: red,
                    fontSize: 42,
                    height: .96,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.5,
                    shadows: [Shadow(color: Color(0xAA8E1410), blurRadius: 18)],
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
            const Text(
              'TKO SI?',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: red,
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
    color: primary ? red : surface,
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
              child: Icon(icon, color: primary ? Colors.white : red),
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
                color: primary ? Colors.white : red,
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
  const Shell({super.key, required this.controller});
  final AppController controller;
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> with WidgetsBindingObserver {
  int index = 0;
  final labels = const ['Početna', 'Polica', 'Traži', 'Postavke'];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.controller.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) widget.controller.sync();
  }

  void addComic() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: surface,
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
                title: 'Skeniraj barkod',
                subtitle: 'Najbrži način — uperi u stražnju koricu',
                primary: true,
                onTap: () {
                  Navigator.pop(sheetContext);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const _ScannerPlaceholder(),
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
                      builder: (_) => ComicForm(controller: widget.controller),
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
        SettingsPage(controller: widget.controller),
      ];
      return Scaffold(
        appBar: AppBar(
          title: Text(
            index == 0 ? 'COMICOLLECT' : labels[index],
            style: const TextStyle(
              color: red,
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
              : IndexedStack(index: index, children: pages),
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: addComic,
          backgroundColor: red,
          foregroundColor: Colors.white,
          shape: const CircleBorder(),
          child: const Icon(Icons.add, size: 30),
        ),
        floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
        bottomNavigationBar: BottomAppBar(
          color: const Color(0xFF121211),
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
            Icon(icon, color: index == i ? red : Colors.grey),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                color: index == i ? red : Colors.grey,
              ),
            ),
          ],
        ),
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
      color: primary ? red : const Color(0xFF080909),
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
                child: Icon(icon, color: primary ? Colors.white : red),
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
                color: primary ? Colors.white : red,
                size: 17,
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _ScannerPlaceholder extends StatelessWidget {
  const _ScannerPlaceholder();
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    appBar: AppBar(
      backgroundColor: Colors.transparent,
      title: const Text(
        'BRZO SKENIRANJE',
        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
      ),
    ),
    body: Stack(
      children: [
        const Positioned.fill(child: ColoredBox(color: Color(0xFF080909))),
        Center(
          child: Container(
            width: 270,
            height: 180,
            decoration: BoxDecoration(
              border: Border.all(color: red, width: 3),
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Center(
              child: Icon(
                Icons.qr_code_scanner,
                size: 72,
                color: Colors.white54,
              ),
            ),
          ),
        ),
        const Positioned(
          left: 30,
          right: 30,
          bottom: 70,
          child: Text(
            'Uperi kameru u barkod. Demo način nema aktivnu kameru.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white70),
          ),
        ),
      ],
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
      onRefresh: controller.sync,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 100),
        children: [
          Text(
            '${owned.length} stripova · ${value.toStringAsFixed(2)} €',
            style: const TextStyle(color: tan),
          ),
          const SectionTitle('U NAJAVI'),
          SizedBox(
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
                        style: const TextStyle(
                          color: red,
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
                        color: red,
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
    if (names.isEmpty) {
      return const Center(
        child: Text(
          'Dodaj prvi strip na policu.',
          style: TextStyle(color: tan),
        ),
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 100),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: .78,
        crossAxisSpacing: 14,
        mainAxisSpacing: 14,
      ),
      itemCount: names.length,
      itemBuilder: (context, i) {
        final items = groups[names[i]]!;
        final owned = items.where((e) => e.owned).length;
        final read = items.where((e) => e.read).length;
        return InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => SeriesPage(
                name: names[i],
                comics: items,
                controller: controller,
              ),
            ),
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
                  child: ComicCover(label: names[i], seed: names[i].hashCode),
                ),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        names[i].toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w900),
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
    );
  }
}

class SeriesPage extends StatelessWidget {
  const SeriesPage({
    super.key,
    required this.name,
    required this.comics,
    required this.controller,
  });
  final String name;
  final List<Comic> comics;
  final AppController controller;
  @override
  Widget build(BuildContext context) {
    final editions = <String, List<Comic>>{};
    for (final comic in comics) {
      editions.putIfAbsent(comic.edition, () => []).add(comic);
    }
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: Text(
          name.toUpperCase(),
          style: const TextStyle(
            color: red,
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
                                        borderRadius: BorderRadius.circular(99),
                                        child: LinearProgressIndicator(
                                          value: progress,
                                          minHeight: 6,
                                          backgroundColor: const Color(
                                            0xFF080909,
                                          ),
                                          color: red,
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
                          const Icon(Icons.play_arrow, color: red, size: 18),
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
  }
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
            style: const TextStyle(
              color: red,
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
              color: surface,
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
                          style: const TextStyle(
                            color: red,
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
                          color: comic.read ? const Color(0xFF3EC63E) : red,
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
                          color: comic.owned ? const Color(0xFF3EC63E) : red,
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
  String query = '';
  @override
  Widget build(BuildContext context) {
    final q = query.toLowerCase();
    final results = widget.controller.comics
        .where(
          (c) =>
              '${c.series} ${c.edition} ${c.number} ${c.title} ${c.publisher}'
                  .toLowerCase()
                  .contains(q),
        )
        .toList();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            autofocus: false,
            onChanged: (v) => setState(() => query = v),
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Serijal, naslov, izdavač, broj…',
            ),
          ),
        ),
        Expanded(
          child: results.isEmpty
              ? const Center(
                  child: Text('Nema rezultata', style: TextStyle(color: tan)),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                  itemCount: results.length,
                  itemBuilder: (_, i) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: ComicTile(
                      comic: results[i],
                      controller: widget.controller,
                    ),
                  ),
                ),
        ),
      ],
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
                      Tag(comic.condition),
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
            style: const TextStyle(
              color: red,
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
                                        color: red,
                                        width: 1.5,
                                      ),
                                    ),
                                    child: Text(
                                      current.condition,
                                      style: const TextStyle(
                                        color: red,
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
                              const Text(
                                'TRAŽIM',
                                style: TextStyle(
                                  color: red,
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
                      color: red.withValues(alpha: .14),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: red.withValues(alpha: .45)),
                    ),
                    child: Text(
                      'Posuđeno: ${current.loanedTo}',
                      style: const TextStyle(fontSize: 12.5),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.only(top: 14),
                  child: Text(
                    current.notes.startsWith('Početni katalog')
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
                        DetailRow('Stanje', current.condition),
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
    final color = active ? const Color(0xFF3EC63E) : red;
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
  @override
  void initState() {
    super.initState();
    final c = widget.comic;
    owned = c?.owned ?? true;
    read = c?.read ?? false;
    duplicate = c?.duplicate ?? false;
    grade = c?.condition ?? 'F';
    f = {
      'series': TextEditingController(text: c?.series),
      'edition': TextEditingController(text: c?.edition),
      'number': TextEditingController(text: c?.number.toString()),
      'title': TextEditingController(text: c?.title),
      'publisher': TextEditingController(text: c?.publisher),
      'year': TextEditingController(text: c?.year?.toString()),
      'price': TextEditingController(text: c?.purchasePrice?.toString()),
      'value': TextEditingController(text: c?.estimatedValue?.toString()),
      'loan': TextEditingController(text: c?.loanedTo),
      'notes': TextEditingController(text: c?.notes),
    };
  }

  @override
  void dispose() {
    for (final c in f.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        widget.comic == null ? 'DODAJ STRIP' : 'UREDI STRIP',
        style: const TextStyle(color: red, fontWeight: FontWeight.w900),
      ),
    ),
    body: Form(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 40),
        children: [
          _field('series', 'Serijal *'),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _field('edition', 'Edicija')),
              const SizedBox(width: 10),
              SizedBox(
                width: 100,
                child: _field('number', 'Broj *', number: true),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _field('title', 'Naslov'),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _field('publisher', 'Izdavač')),
              const SizedBox(width: 10),
              SizedBox(
                width: 100,
                child: _field('year', 'Godina', number: true),
              ),
            ],
          ),
          const SectionTitle('STANJE PRIMJERKA'),
          Wrap(
            spacing: 8,
            children: ['M', 'VF', 'F', 'G', 'P']
                .map(
                  (g) => ChoiceChip(
                    label: Text(g),
                    selected: grade == g,
                    selectedColor: red,
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
          const SizedBox(height: 22),
          FilledButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.save_outlined),
            label: const Padding(
              padding: EdgeInsets.all(14),
              child: Text(
                'SPREMI',
                style: TextStyle(fontWeight: FontWeight.w800),
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
  Future<void> _save() async {
    final series = f['series']!.text.trim();
    final number = int.tryParse(f['number']!.text);
    if (series.isEmpty || number == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Serijal i broj su obavezni.')),
      );
      return;
    }
    final c = widget.comic;
    if (c == null) {
      await widget.controller.add(
        series: series,
        edition: f['edition']!.text,
        number: number,
        title: f['title']!.text,
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
      );
    } else {
      await widget.controller.save(
        c.copyWith(
          series: series,
          edition: f['edition']!.text,
          number: number,
          title: f['title']!.text,
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
        ),
      );
    }
    if (mounted) Navigator.pop(context);
  }
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.controller});
  final AppController controller;
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final server = TextEditingController();
  final token = TextEditingController();
  bool loaded = false;
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
    load();
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 100),
      children: [
        const Text(
          'LOKALNI SERVER',
          style: TextStyle(
            color: tan,
            fontWeight: FontWeight.bold,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: server,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(
            labelText: 'Adresa servera',
            helperText: 'Npr. http://192.168.1.50:8787',
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: token,
          obscureText: true,
          decoration: const InputDecoration(labelText: 'API token'),
        ),
        const SizedBox(height: 14),
        FilledButton.icon(
          onPressed: save,
          icon: const Icon(Icons.sync),
          label: const Text('SPREMI I SINKRONIZIRAJ'),
        ),
        const SizedBox(height: 28),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.storage_outlined, color: red),
          title: const Text('Lokalna SQLite baza'),
          subtitle: Text(
            '${widget.controller.comics.length} zapisa · radi bez interneta',
          ),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.cloud_outlined, color: red),
          title: Text(widget.controller.syncMessage),
          subtitle: const Text('Automatski pri pokretanju i svakih 5 minuta'),
        ),
        const Divider(),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.copy_all_outlined, color: red),
          title: const Text('Kopiraj CSV izvoz'),
          onTap: exportCsv,
        ),
        const AboutListTile(
          icon: Icon(Icons.info_outline, color: red),
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
    await widget.controller.sync();
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(widget.controller.syncMessage)));
    }
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
  const ComicCover({super.key, required this.label, required this.seed});
  final String label;
  final int seed;
  @override
  Widget build(BuildContext context) {
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
          Icon(icon, color: red, size: 30),
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
      color: red.withValues(alpha: .16),
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: red.withValues(alpha: .4)),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 9,
          color: red,
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
