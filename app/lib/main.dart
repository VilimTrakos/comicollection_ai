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
    home: Shell(controller: controller),
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
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ComicForm(controller: widget.controller),
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
    final loaned = owned.where((c) => c.loanedTo.isNotEmpty).length;
    return RefreshIndicator(
      onRefresh: controller.sync,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 100),
        children: [
          Text(
            '${owned.length} stripova · ${value.toStringAsFixed(2)} €',
            style: const TextStyle(color: tan),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: MetricCard(
                  icon: Icons.auto_stories,
                  value: '${unread.length}',
                  label: 'NEPROČITANO',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: MetricCard(
                  icon: Icons.people_outline,
                  value: '$loaned',
                  label: 'POSUĐENO',
                ),
              ),
            ],
          ),
          const SectionTitle('NASTAVI ČITATI'),
          if (unread.isEmpty)
            const EmptyCard(text: 'Sve pročitano — lijep osjećaj.')
          else
            ComicTile(comic: unread.first, controller: controller),
          const SectionTitle('NEDAVNO DODANO'),
          ...controller.comics
              .toList()
              .reversed
              .take(4)
              .map((c) => ComicTile(comic: c, controller: controller)),
          if (controller.comics.isEmpty)
            const EmptyCard(
              text: 'Tvoja polica je prazna. Dodaj prvi strip tipkom +.',
            ),
        ],
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
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        name.toUpperCase(),
        style: const TextStyle(color: red, fontWeight: FontWeight.w900),
      ),
    ),
    body: ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 30),
      children: comics
          .map(
            (c) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: ComicTile(comic: c, controller: controller),
            ),
          )
          .toList(),
    ),
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
            IconButton(
              tooltip: comic.read ? 'Označi nepročitano' : 'Označi pročitano',
              onPressed: () =>
                  controller.save(comic.copyWith(read: !comic.read)),
              icon: Icon(
                comic.read ? Icons.visibility : Icons.visibility_off,
                color: comic.read ? const Color(0xFF3EC63E) : red,
              ),
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
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      actions: [
        IconButton(
          onPressed: () async {
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ComicForm(controller: controller, comic: comic),
              ),
            );
            if (context.mounted) Navigator.pop(context);
          },
          icon: const Icon(Icons.edit_outlined),
        ),
        IconButton(
          onPressed: () => _delete(context),
          icon: const Icon(Icons.delete_outline),
        ),
      ],
    ),
    body: ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      children: [
        Center(
          child: SizedBox(
            width: 190,
            height: 260,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: ComicCover(
                label: '${comic.series}\n#${comic.number}',
                seed: comic.series.hashCode + comic.number,
              ),
            ),
          ),
        ),
        const SizedBox(height: 24),
        Text(
          '${comic.series} #${comic.number}',
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w900,
            color: red,
          ),
        ),
        Text(
          comic.title,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 18, color: tan),
        ),
        const SizedBox(height: 20),
        DetailRow('Edicija', comic.edition),
        DetailRow('Izdavač', comic.publisher),
        DetailRow('Godina', comic.year?.toString() ?? '—'),
        DetailRow('Stanje', comic.condition),
        DetailRow('Imam', comic.owned ? 'Da' : 'Ne'),
        DetailRow('Pročitano', comic.read ? 'Da' : 'Ne'),
        DetailRow(
          'Vrijednost',
          comic.estimatedValue == null
              ? '—'
              : '${comic.estimatedValue!.toStringAsFixed(2)} €',
        ),
        if (comic.loanedTo.isNotEmpty) DetailRow('Posuđeno', comic.loanedTo),
        if (comic.notes.isNotEmpty) DetailRow('Bilješke', comic.notes),
      ],
    ),
  );
  Future<void> _delete(BuildContext context) async {
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
      await controller.remove(comic);
      if (context.mounted) Navigator.pop(context);
    }
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
