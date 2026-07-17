import 'package:flutter/material.dart';

import '../../app_controller.dart';
import '../../data/sync_settings_repository.dart';

/// Self-hosted compatibility UI for guest/local collections only.
/// Authenticated accounts always use the production endpoint and secure session.
class LegacySyncSettingsPanel extends StatefulWidget {
  const LegacySyncSettingsPanel({
    super.key,
    required this.controller,
    this.repository = const SyncSettingsRepository(),
  });

  final AppController controller;
  final SyncSettingsRepository repository;

  @override
  State<LegacySyncSettingsPanel> createState() =>
      _LegacySyncSettingsPanelState();
}

class _LegacySyncSettingsPanelState extends State<LegacySyncSettingsPanel> {
  final server = TextEditingController();
  final token = TextEditingController();
  bool _loading = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final settings = await widget.repository.load();
      if (!mounted) return;
      server.text = settings.serverUrl.isEmpty
          ? SyncSettingsRepository.suggestedServerUrl
          : settings.serverUrl;
      token.text = settings.apiToken;
    } on Object {
      if (!mounted) return;
      _error = 'Postavke sinkronizacije trenutačno nisu dostupne.';
    } finally {
      if (mounted) {
        _loading = false;
        setState(() {});
      }
    }
  }

  @override
  void dispose() {
    server.dispose();
    token.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Card(
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    child: ExpansionTile(
      leading: Icon(
        Icons.lan_outlined,
        color: Theme.of(context).colorScheme.primary,
      ),
      title: const Text('Lokalni sync server'),
      subtitle: Text(widget.controller.syncMessage),
      childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
      children: [
        if (_loading) const LinearProgressIndicator(),
        if (_error case final error?) ...[
          Text(
            error,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
          const SizedBox(height: 8),
        ],
        TextField(
          controller: server,
          enabled: !_busy,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(
            labelText: 'Adresa servera',
            helperText: 'Tržišna verzija zahtijeva HTTPS.',
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: token,
          enabled: !_busy,
          obscureText: true,
          enableSuggestions: false,
          autocorrect: false,
          decoration: const InputDecoration(labelText: 'API token'),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _loading || _busy ? null : _save,
            icon: const Icon(Icons.save_outlined),
            label: Text(_busy ? 'PRIČEKAJTE…' : 'SPREMI I SINKRONIZIRAJ'),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _loading || _busy || widget.controller.syncing
                ? null
                : _rebind,
            icon: const Icon(Icons.swap_horiz),
            label: const Text('POVEŽI DRUGI ILI NOVI SERVER'),
          ),
        ),
      ],
    ),
  );

  Future<void> _save() => _run(() async {
    await widget.repository.saveConnection(
      serverUrl: server.text,
      apiToken: token.text,
    );
    await widget.controller.sync(force: true);
  });

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      _showResult();
    } on Object {
      if (!mounted) return;
      setState(() {
        _error = 'Postavke nije moguće spremiti. Pokušajte ponovno.';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Postavke nije moguće spremiti. Pokušajte ponovno.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _rebind() async {
    if (_busy) return;
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Povezati novi server?'),
            content: const Text(
              'Lokalna kolekcija ostaje netaknuta. Sljedeća '
              'sinkronizacija povezat će je s upisanim serverom.',
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
    await _run(() async {
      await widget.repository.saveConnection(
        serverUrl: server.text,
        apiToken: token.text,
      );
      await widget.controller.resetSyncServerBinding();
      await widget.controller.sync(force: true);
    });
  }

  void _showResult() {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(widget.controller.syncMessage)));
  }
}
