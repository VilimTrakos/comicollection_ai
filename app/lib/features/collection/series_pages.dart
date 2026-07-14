import 'package:flutter/material.dart';

import '../../app_controller.dart';
import '../../models/comic.dart';
import '../../ui/app_theme.dart';
import '../../ui/common_widgets.dart';
import '../comics/comic_detail.dart';

class SeriesPage extends StatelessWidget {
  const SeriesPage({super.key, required this.name, required this.controller});
  final String name;
  final AppController controller;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      final editions = <String, List<Comic>>{};
      for (final comic in controller.comics.where(
        (comic) => comic.series == name,
      )) {
        editions.putIfAbsent(comic.edition, () => []).add(comic);
      }
      return Scaffold(
        appBar: AppBar(
          centerTitle: true,
          title: Text(
            name.toUpperCase(),
            style: TextStyle(
              color: Theme.of(context).colorScheme.primary,
              fontSize: 28,
              fontWeight: FontWeight.w900,
              letterSpacing: 1,
            ),
          ),
        ),
        body: Stack(
          children: [
            const Positioned.fill(child: GrungeBackground()),
            ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 30),
              children: editions.entries.map((entry) {
                final issues = entry.value
                  ..sort((a, b) => a.number.compareTo(b.number));
                final owned = issues.where((c) => c.owned).length;
                final publisher = issues.first.publisher;
                final progress = issues.isEmpty ? 0.0 : owned / issues.length;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Card(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => EditionPage(
                            series: name,
                            edition: entry.key,
                            comics: issues,
                            controller: controller,
                          ),
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 58,
                              height: 78,
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: ComicCover(
                                  label: name,
                                  seed: entry.key.hashCode,
                                  assetPath: issues.first.coverAsset,
                                ),
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    publisher,
                                    style: const TextStyle(
                                      color: tan,
                                      fontSize: 12,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    entry.key.toUpperCase(),
                                    style: const TextStyle(
                                      fontSize: 19,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: .5,
                                    ),
                                  ),
                                  const SizedBox(height: 9),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: ClipRRect(
                                          borderRadius: BorderRadius.circular(
                                            99,
                                          ),
                                          child: LinearProgressIndicator(
                                            value: progress,
                                            minHeight: 6,
                                            backgroundColor: const Color(
                                              0xFF080909,
                                            ),
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.primary,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 9),
                                      Text(
                                        '$owned/${issues.length}',
                                        style: const TextStyle(
                                          color: tan,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            Icon(
                              Icons.play_arrow,
                              color: Theme.of(context).colorScheme.primary,
                              size: 18,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      );
    },
  );
}

class EditionPage extends StatefulWidget {
  const EditionPage({
    super.key,
    required this.series,
    required this.edition,
    required this.comics,
    required this.controller,
  });
  final String series, edition;
  final List<Comic> comics;
  final AppController controller;
  @override
  State<EditionPage> createState() => _EditionPageState();
}

class _EditionPageState extends State<EditionPage> {
  bool dense = true;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      final issues =
          widget.controller.comics
              .where(
                (c) => c.series == widget.series && c.edition == widget.edition,
              )
              .toList()
            ..sort((a, b) => a.number.compareTo(b.number));
      return Scaffold(
        appBar: AppBar(
          title: Text(
            '${widget.series.toUpperCase()} · ${widget.edition.toUpperCase()}',
            style: TextStyle(
              color: Theme.of(context).colorScheme.primary,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          actions: [
            IconButton(
              tooltip: dense ? 'Udoban prikaz' : 'Zbijeni prikaz',
              onPressed: () => setState(() => dense = !dense),
              icon: Icon(
                dense ? Icons.view_agenda_outlined : Icons.view_list_outlined,
              ),
            ),
          ],
        ),
        body: ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 30),
          itemCount: issues.length,
          separatorBuilder: (_, _) => const SizedBox(height: 7),
          itemBuilder: (context, i) {
            final comic = issues[i];
            if (!dense) {
              return ComicTile(comic: comic, controller: widget.controller);
            }
            return Material(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ComicDetail(
                      comic: comic,
                      controller: widget.controller,
                    ),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 36,
                        child: Text(
                          '#${comic.number}',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.primary,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          comic.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        tooltip: 'Pročitano',
                        onPressed: comic.owned
                            ? () => widget.controller.save(
                                comic.copyWith(read: !comic.read),
                              )
                            : null,
                        icon: Icon(
                          Icons.visibility_outlined,
                          size: 17,
                          color: comic.read
                              ? const Color(0xFF3EC63E)
                              : Theme.of(context).colorScheme.primary,
                        ),
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        tooltip: 'U kolekciji',
                        onPressed: () => widget.controller.save(
                          comic.copyWith(
                            owned: !comic.owned,
                            read: comic.owned ? false : comic.read,
                          ),
                        ),
                        icon: Icon(
                          comic.owned ? Icons.check : Icons.close,
                          size: 18,
                          color: comic.owned
                              ? const Color(0xFF3EC63E)
                              : Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      );
    },
  );
}
