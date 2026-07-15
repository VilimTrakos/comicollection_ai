import 'package:flutter/material.dart';

import '../../app_controller.dart';
import '../../ui/app_theme.dart';
import '../collection/shelf_page.dart';
import '../comics/comic_form.dart';
import '../comics/range_entry_page.dart';
import '../home/home_page.dart';
import '../search/search_page.dart';
import '../scanner/smart_scanner_page.dart';
import '../settings/settings_page.dart';

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
  late Listenable _shellChanges;
  final labels = const ['POČETNA', 'MOJA KOLEKCIJA', 'TRAŽI', 'POSTAVKE'];

  @override
  void initState() {
    super.initState();
    _shellChanges = _createShellChanges();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didUpdateWidget(covariant Shell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      _shellChanges = _createShellChanges();
    }
  }

  Listenable _createShellChanges() => Listenable.merge([
    widget.controller.startupChanges,
    widget.controller.collectionChanges,
    widget.controller.preferenceChanges,
  ]);

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
    animation: _shellChanges,
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
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller.syncChanges,
    builder: (context, _) => _buildBadge(context),
  );

  Widget _buildBadge(BuildContext context) {
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
