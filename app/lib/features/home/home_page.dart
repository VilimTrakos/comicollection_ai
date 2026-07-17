import 'package:flutter/material.dart';

import '../../app_controller.dart';
import '../../models/comic.dart';
import '../../ui/app_theme.dart';
import '../../ui/common_widgets.dart';
import '../collection/upcoming_page.dart';
import '../comics/comic_detail.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key, required this.controller});
  final AppController controller;
  @override
  Widget build(BuildContext context) {
    final owned = controller.comics.where((c) => c.owned).toList();
    final unread = owned.where((c) => !c.read).toList();
    final value = owned.fold<double>(
      0,
      (sum, c) => sum + (c.estimatedValue ?? 0),
    );
    final editions = <String, List<Comic>>{};
    for (final comic in controller.comics) {
      editions
          .putIfAbsent('${comic.series} · ${comic.edition}', () => [])
          .add(comic);
    }
    final closest = editions.entries.toList()
      ..sort(
        (a, b) => (b.value.where((c) => c.owned).length / b.value.length)
            .compareTo(a.value.where((c) => c.owned).length / a.value.length),
      );
    return RefreshIndicator(
      onRefresh: () => controller.sync(force: true),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 100),
        children: [
          Text(
            '${owned.length} stripova · ${value.toStringAsFixed(2)} €',
            style: const TextStyle(color: tan),
          ),
          const SectionTitle('U NAJAVI'),
          GestureDetector(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => UpcomingPage(
                  controller: controller,
                  releaseWatchRepository: controller.releaseWatchRepository,
                ),
              ),
            ),
            child: SizedBox(
              height: 142,
              child: Row(
                children: const [
                  Expanded(
                    child: _ReleaseCard(
                      day: '28',
                      month: 'LIP',
                      title: 'DYLAN DOG #202',
                      seed: 1,
                    ),
                  ),
                  SizedBox(width: 10),
                  Expanded(
                    child: _ReleaseCard(
                      day: '05',
                      month: 'SRP',
                      title: 'EXTRA #167',
                      seed: 2,
                    ),
                  ),
                  SizedBox(width: 10),
                  Expanded(
                    child: _ReleaseCard(
                      day: '12',
                      month: 'SRP',
                      title: 'SPECIAL',
                      seed: 3,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SectionTitle('NASTAVI ČITATI'),
          if (unread.isEmpty)
            const EmptyCard(text: 'Sve pročitano — lijep osjećaj.')
          else
            ComicTile(comic: unread.first, controller: controller),
          const SectionTitle('NEDAVNO DODANO'),
          ...owned.reversed
              .take(4)
              .map((c) => ComicTile(comic: c, controller: controller)),
          if (owned.isEmpty)
            const EmptyCard(
              text:
                  'Otvori Poliču, odaberi Dylan Dog ediciju i označi brojeve koje imaš.',
            ),
          const SectionTitle('NAJBLIŽE KOMPLETIRANJU'),
          ...closest
              .take(2)
              .map(
                (entry) =>
                    EditionProgressRow(name: entry.key, comics: entry.value),
              ),
        ],
      ),
    );
  }
}

class _ReleaseCard extends StatelessWidget {
  const _ReleaseCard({
    required this.day,
    required this.month,
    required this.title,
    required this.seed,
  });
  final String day, month, title;
  final int seed;
  @override
  Widget build(BuildContext context) => Card(
    clipBehavior: Clip.antiAlias,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Stack(
            fit: StackFit.expand,
            children: [
              ComicCover(label: title.split(' ').first, seed: seed),
              Positioned(
                top: 6,
                left: 6,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xDD060808),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    children: [
                      Text(
                        day,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.primary,
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        month,
                        style: const TextStyle(color: tan, fontSize: 9),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(7),
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    ),
  );
}
