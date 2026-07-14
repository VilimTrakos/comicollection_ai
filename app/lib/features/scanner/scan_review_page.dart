import 'package:flutter/material.dart';

import '../../app_controller.dart';
import '../../models/catalog_issue.dart';
import '../../ui/app_theme.dart';

class ScanReviewPage extends StatefulWidget {
  const ScanReviewPage({
    super.key,
    required this.controller,
    required this.issues,
  });

  final AppController controller;
  final List<CatalogIssue> issues;

  @override
  State<ScanReviewPage> createState() => _ScanReviewPageState();
}

class _ScanReviewPageState extends State<ScanReviewPage> {
  late final Map<String, bool> _included = {
    for (final issue in widget.issues) issue.id: true,
  };
  late final Map<String, bool> _owned = {
    for (final issue in widget.issues) issue.id: true,
  };
  bool _saving = false;

  Future<void> _save() async {
    final results = <CatalogIssue, bool>{};
    for (final issue in widget.issues) {
      if (_included[issue.id] ?? false) {
        results[issue] = _owned[issue.id] ?? true;
      }
    }
    if (results.isEmpty) return;
    setState(() => _saving = true);
    await widget.controller.saveScanResults(results);
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text('PRONAĐENO ${widget.issues.length}'),
      actions: [
        TextButton(
          onPressed: () => setState(() {
            for (final issue in widget.issues) {
              _owned[issue.id] = true;
              _included[issue.id] = true;
            }
          }),
          child: const Text('SVE IMAM'),
        ),
      ],
    ),
    body: ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 100),
      itemCount: widget.issues.length,
      itemBuilder: (context, index) {
        final issue = widget.issues[index];
        final included = _included[issue.id] ?? true;
        final owned = _owned[issue.id] ?? true;
        return Card(
          margin: const EdgeInsets.only(bottom: 9),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              children: [
                Checkbox(
                  value: included,
                  onChanged: (value) => setState(() {
                    _included[issue.id] = value ?? false;
                  }),
                ),
                ClipRRect(
                  borderRadius: BorderRadius.circular(7),
                  child: issue.coverAsset == null
                      ? const SizedBox(
                          width: 48,
                          height: 64,
                          child: ColoredBox(color: Color(0xFF292A28)),
                        )
                      : Image.asset(
                          issue.coverAsset!,
                          width: 48,
                          height: 64,
                          fit: BoxFit.cover,
                        ),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${issue.series} #${issue.number}',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      Text(
                        issue.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: tan, fontSize: 12),
                      ),
                      const SizedBox(height: 5),
                      SegmentedButton<bool>(
                        segments: const [
                          ButtonSegment(value: true, label: Text('IMAM')),
                          ButtonSegment(value: false, label: Text('NEMAM')),
                        ],
                        selected: {owned},
                        onSelectionChanged: included
                            ? (selection) => setState(() {
                                _owned[issue.id] = selection.first;
                              })
                            : null,
                        showSelectedIcon: false,
                        style: const ButtonStyle(
                          visualDensity: VisualDensity.compact,
                        ),
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
    floatingActionButton: FloatingActionButton.extended(
      onPressed: _saving ? null : _save,
      backgroundColor: red,
      foregroundColor: Colors.white,
      icon: _saving
          ? const SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.check),
      label: const Text('SPREMI ODABRANO'),
    ),
  );
}
