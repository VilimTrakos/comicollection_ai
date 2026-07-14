import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app_controller.dart';
import '../../models/comic.dart';
import '../../ui/app_theme.dart';
import '../../ui/common_widgets.dart';

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
