import 'package:flutter/material.dart';

import '../../app_controller.dart';
import '../../models/comic.dart';
import '../../ui/app_theme.dart';
import '../../ui/common_widgets.dart';
import 'collection_export.dart';
import 'collection_list_page.dart';
import 'series_pages.dart';
import 'statistics_page.dart';
import 'upcoming_page.dart';

class ShelfPage extends StatelessWidget {
  const ShelfPage({super.key, required this.controller});
  final AppController controller;
  @override
  Widget build(BuildContext context) {
    final groups = <String, List<Comic>>{};
    for (final c in controller.comics) {
      groups.putIfAbsent(c.series, () => []).add(c);
    }
    final names = groups.keys.toList()..sort();
    final unread = controller.comics
        .where((comic) => comic.owned && !comic.read)
        .length;
    final wanted = controller.comics.where((comic) => !comic.owned).length;
    final duplicates = controller.comics
        .where((comic) => comic.owned && comic.duplicate)
        .length;
    final loaned = controller.comics
        .where((comic) => comic.owned && comic.loanedTo.isNotEmpty)
        .length;
    final tiles = <Widget>[
      if (controller.showStatistics)
        _CollectionHubTile(
          icon: Icons.bar_chart_outlined,
          label: 'STATISTIKA',
          subtitle: 'kompletnost i vrijednost',
          onTap: () => _open(context, StatisticsPage(controller: controller)),
        ),
      _CollectionHubTile(
        icon: Icons.visibility_outlined,
        label: 'NIJE ČITANO',
        subtitle: '$unread čeka',
        count: unread,
        onTap: () => _open(
          context,
          CollectionListPage(
            controller: controller,
            type: CollectionListType.unread,
          ),
        ),
      ),
      _CollectionHubTile(
        icon: Icons.manage_search,
        label: 'TRAŽIM',
        subtitle: '$wanted nedostaje',
        count: wanted,
        highlighted: true,
        onTap: () => _open(
          context,
          CollectionListPage(
            controller: controller,
            type: CollectionListType.wanted,
          ),
        ),
      ),
      _CollectionHubTile(
        icon: Icons.copy_all_outlined,
        label: 'DUPLI',
        subtitle: '$duplicates za zamjenu',
        count: duplicates,
        onTap: () => _open(
          context,
          CollectionListPage(
            controller: controller,
            type: CollectionListType.duplicates,
          ),
        ),
      ),
      _CollectionHubTile(
        icon: Icons.campaign_outlined,
        label: 'POSUĐENO',
        subtitle: '$loaned vani',
        count: loaned,
        onTap: () => _open(
          context,
          CollectionListPage(
            controller: controller,
            type: CollectionListType.loaned,
          ),
        ),
      ),
      _CollectionHubTile(
        icon: Icons.calendar_month_outlined,
        label: 'U NAJAVI',
        subtitle: 'nadolazeći brojevi',
        onTap: () => _open(context, UpcomingPage(controller: controller)),
      ),
      _CollectionHubTile(
        icon: Icons.download_outlined,
        label: 'EXPORT CSV',
        subtitle: 'sigurnosna kopija',
        onTap: () => exportComicsCsv(context, controller.comics),
      ),
    ];
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 6, 18, 100),
      children: [
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          mainAxisSpacing: 11,
          crossAxisSpacing: 11,
          childAspectRatio: 1.38,
          children: tiles,
        ),
        const SectionTitle('SERIJALI'),
        if (names.isEmpty)
          const EmptyCard(text: 'Dodaj prvi strip na policu.')
        else
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              childAspectRatio: .82,
              crossAxisSpacing: 14,
              mainAxisSpacing: 14,
            ),
            itemCount: names.length,
            itemBuilder: (context, index) {
              final items = groups[names[index]]!;
              final owned = items.where((comic) => comic.owned).length;
              final read = items.where((comic) => comic.read).length;
              return InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: () => _open(
                  context,
                  SeriesPage(name: names[index], controller: controller),
                ),
                child: Card(
                  clipBehavior: Clip.antiAlias,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: ComicCover(
                          label: names[index],
                          seed: names[index].hashCode,
                          assetPath: items.first.coverAsset,
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              names[index].toUpperCase(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              '$owned imam · $read pročitano',
                              style: const TextStyle(color: tan, fontSize: 12),
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
      ],
    );
  }

  void _open(BuildContext context, Widget page) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => page));
}

class _CollectionHubTile extends StatelessWidget {
  const _CollectionHubTile({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.onTap,
    this.count,
    this.highlighted = false,
  });

  final IconData icon;
  final String label;
  final String subtitle;
  final int? count;
  final bool highlighted;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Material(
      color: highlighted ? accent : Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(13),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 37,
                    height: 37,
                    decoration: BoxDecoration(
                      color: highlighted
                          ? Colors.white.withValues(alpha: .18)
                          : Theme.of(context).scaffoldBackgroundColor,
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Icon(
                      icon,
                      color: highlighted ? Colors.white : accent,
                      size: 20,
                    ),
                  ),
                  const Spacer(),
                  if (count != null && count! > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: highlighted
                            ? Colors.white.withValues(alpha: .2)
                            : Theme.of(context).scaffoldBackgroundColor,
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: Text(
                        '$count',
                        style: TextStyle(
                          color: highlighted ? Colors.white : null,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                ],
              ),
              const Spacer(),
              Text(
                label,
                style: TextStyle(
                  color: highlighted ? Colors.white : null,
                  fontWeight: FontWeight.w900,
                  fontSize: 13.5,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: highlighted ? Colors.white70 : tan,
                  fontSize: 11.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
