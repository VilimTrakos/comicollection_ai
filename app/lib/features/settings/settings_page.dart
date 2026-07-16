import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app_controller.dart';
import '../../data/sync_settings_repository.dart';
import '../../ui/app_theme.dart';
import '../../ui/common_widgets.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    required this.controller,
    required this.accountEmail,
    required this.onLogout,
    this.syncSettingsRepository = const SyncSettingsRepository(),
  });
  final AppController controller;
  final String accountEmail;
  final VoidCallback onLogout;
  final SyncSettingsRepository syncSettingsRepository;
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
    final settings = await widget.syncSettingsRepository.load();
    server.text = settings.serverUrl.isEmpty
        ? SyncSettingsRepository.suggestedServerUrl
        : settings.serverUrl;
    token.text = settings.apiToken;
    loaded = true;
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller.syncChanges,
    builder: (context, _) => _buildContent(context),
  );

  Widget _buildContent(BuildContext context) {
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
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: widget.controller.syncing
                      ? null
                      : _connectToNewServer,
                  icon: const Icon(Icons.swap_horiz),
                  label: const Text('POVEŽI DRUGI ILI NOVI SERVER'),
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
    await widget.syncSettingsRepository.saveConnection(
      serverUrl: server.text,
      apiToken: token.text,
    );
    await widget.controller.sync(force: true);
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(widget.controller.syncMessage)));
    }
  }

  Future<void> _connectToNewServer() async {
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Povezati novi server?'),
            content: const Text(
              'Lokalna kolekcija ostaje netaknuta. Prekida se veza sa '
              'starim serverom, a pri sljedećoj sinkronizaciji cijelo '
              'trenutačno stanje šalje se na upisani server. Ovo koristi '
              'samo kada je server zamijenjen ili ponovno instaliran.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('ODUSTANI'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('POVEŽI'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !mounted) return;

    await widget.syncSettingsRepository.saveConnection(
      serverUrl: server.text,
      apiToken: token.text,
    );
    await widget.controller.resetSyncServerBinding();
    await widget.controller.sync(force: true);
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(widget.controller.syncMessage)));
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
