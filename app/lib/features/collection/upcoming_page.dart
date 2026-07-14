import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app_controller.dart';
import '../../models/comic.dart';
import '../../ui/app_theme.dart';
import '../../ui/common_widgets.dart';
import '../comics/comic_detail.dart';

class UpcomingPage extends StatefulWidget {
  const UpcomingPage({super.key, required this.controller});

  final AppController controller;

  @override
  State<UpcomingPage> createState() => _UpcomingPageState();
}

class _UpcomingPageState extends State<UpcomingPage> {
  Set<String> watched = {};

  @override
  void initState() {
    super.initState();
    _loadWatched();
  }

  Future<void> _loadWatched() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(
        () => watched = (prefs.getStringList('release_watch_ids') ?? const [])
            .toSet(),
      );
    }
  }

  List<Comic> _candidates() {
    final groups = <String, List<Comic>>{};
    for (final comic in widget.controller.comics) {
      groups
          .putIfAbsent('${comic.series}\u0000${comic.edition}', () => [])
          .add(comic);
    }
    final result = <Comic>[];
    for (final items in groups.values) {
      items.sort((a, b) => b.number.compareTo(a.number));
      final candidate = items.where((comic) => !comic.owned).firstOrNull;
      if (candidate != null) result.add(candidate);
    }
    result.sort((a, b) {
      final year = (b.year ?? 0).compareTo(a.year ?? 0);
      return year != 0 ? year : b.number.compareTo(a.number);
    });
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final candidates = _candidates();
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: Text(
          'U NAJAVI',
          style: TextStyle(
            color: Theme.of(context).colorScheme.primary,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 2, 16, 28),
        children: [
          const Text(
            'Najnoviji poznati brojevi iz lokalnog kataloga — uključi zvonce za praćenje',
            textAlign: TextAlign.center,
            style: TextStyle(color: tan, fontSize: 12.5),
          ),
          const SizedBox(height: 8),
          if (candidates.isEmpty)
            const EmptyCard(text: 'Nema novih kandidata za praćenje.')
          else
            ...candidates.map(
              (comic) => Padding(
                padding: const EdgeInsets.only(bottom: 9),
                child: Card(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    leading: SizedBox(
                      width: 46,
                      height: 62,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(7),
                        child: ComicCover(
                          label: comic.series,
                          seed: comic.number,
                          assetPath: comic.coverAsset,
                        ),
                      ),
                    ),
                    title: Text(
                      '${comic.series.toUpperCase()} #${comic.number}',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    subtitle: Text(
                      '${comic.edition} · ${comic.title}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: IconButton.filledTonal(
                      tooltip: watched.contains(comic.id)
                          ? 'Isključi praćenje'
                          : 'Prati ovaj broj',
                      onPressed: () => _toggle(comic.id),
                      icon: Icon(
                        watched.contains(comic.id)
                            ? Icons.notifications_active
                            : Icons.notifications_none,
                      ),
                    ),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ComicDetail(
                          comic: comic,
                          controller: widget.controller,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          const SizedBox(height: 6),
          const Text(
            'Napomena: BSP katalog nema datume budućih izlazaka. Praćenje se čuva lokalno; datumi se mogu dodati kada server dobije izvor najava.',
            style: TextStyle(color: tan, fontSize: 11.5, height: 1.4),
          ),
        ],
      ),
    );
  }

  Future<void> _toggle(String id) async {
    setState(() {
      if (!watched.add(id)) watched.remove(id);
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('release_watch_ids', watched.toList());
  }
}
