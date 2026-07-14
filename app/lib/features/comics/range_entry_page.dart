import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app_controller.dart';
import '../../models/comic.dart';
import '../../ui/app_theme.dart';
import '../../ui/common_widgets.dart';
import 'batch_condition_page.dart';

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
