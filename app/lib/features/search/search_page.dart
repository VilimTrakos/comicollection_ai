import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app_controller.dart';
import '../../models/comic.dart';
import '../../ui/app_theme.dart';
import '../../ui/common_widgets.dart';
import '../collection/series_pages.dart';
import '../comics/comic_detail.dart';

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
