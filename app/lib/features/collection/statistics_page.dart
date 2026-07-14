import 'package:flutter/material.dart';

import '../../app_controller.dart';
import '../../models/comic.dart';
import '../../ui/app_theme.dart';
import '../../ui/common_widgets.dart';

class StatisticsPage extends StatelessWidget {
  const StatisticsPage({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      final owned = controller.comics.where((comic) => comic.owned).toList();
      final read = owned.where((comic) => comic.read).length;
      final value = owned.fold<double>(
        0,
        (total, comic) => total + (comic.estimatedValue ?? 0),
      );
      final editions = <String, List<Comic>>{};
      for (final comic in controller.comics) {
        editions
            .putIfAbsent('${comic.series} · ${comic.edition}', () => [])
            .add(comic);
      }
      return Scaffold(
        appBar: AppBar(
          centerTitle: true,
          title: Text(
            'STATISTIKA',
            style: TextStyle(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 30),
          children: [
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              childAspectRatio: 1.65,
              children: [
                _StatCard(
                  label: 'U KOLEKCIJI',
                  value: '${owned.length}',
                  icon: Icons.menu_book_outlined,
                ),
                _StatCard(
                  label: 'PROČITANO',
                  value: '$read',
                  icon: Icons.visibility_outlined,
                ),
                _StatCard(
                  label: 'KOMPLETNOST',
                  value: controller.comics.isEmpty
                      ? '0%'
                      : '${(owned.length * 100 / controller.comics.length).round()}%',
                  icon: Icons.donut_large,
                ),
                _StatCard(
                  label: 'VRIJEDNOST',
                  value: '${value.toStringAsFixed(2)} €',
                  icon: Icons.euro,
                ),
              ],
            ),
            const SectionTitle('PO EDICIJAMA'),
            ...editions.entries.map(
              (entry) =>
                  EditionProgressRow(name: entry.key, comics: entry.value),
            ),
          ],
        ),
      );
    },
  );
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Card(
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    child: Padding(
      padding: const EdgeInsets.all(13),
      child: Row(
        children: [
          Icon(icon, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(label, style: const TextStyle(color: tan, fontSize: 10.5)),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
