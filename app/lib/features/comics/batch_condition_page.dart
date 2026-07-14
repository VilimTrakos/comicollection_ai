import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/comic.dart';
import '../../ui/app_theme.dart';
import '../../ui/common_widgets.dart';

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
  bool advancing = false;
  Timer? advanceTimer;

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

  @override
  void dispose() {
    advanceTimer?.cancel();
    super.dispose();
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
          onPressed: advancing ? null : _confirmAllWithoutCondition,
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
                          onTap: advancing ? null : () => _selectGrade(grade),
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
                onPressed: advancing ? null : _skipWithoutCondition,
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
                    onPressed: index == 0 || advancing ? null : _previous,
                    icon: const Icon(Icons.arrow_back),
                    label: const Text('PRETHODNI'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextButton.icon(
                    key: const ValueKey('condition-next'),
                    onPressed: advancing ? null : _next,
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

  void _selectGrade(String grade) {
    if (advancing) return;
    HapticFeedback.selectionClick();
    setState(() {
      selections[index] = grade;
      advancing = true;
    });
    advanceTimer?.cancel();
    advanceTimer = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      setState(() {
        index++;
        advancing = false;
      });
    });
  }

  void _skipWithoutCondition() {
    setState(() {
      selections[index] = '';
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
  final VoidCallback? onTap;

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
