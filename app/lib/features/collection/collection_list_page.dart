import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app_controller.dart';
import '../../models/comic.dart';
import '../../ui/app_theme.dart';
import '../../ui/common_widgets.dart';
import '../comics/comic_detail.dart';

enum CollectionListType { unread, wanted, duplicates, loaned }

class CollectionListPage extends StatelessWidget {
  const CollectionListPage({
    super.key,
    required this.controller,
    required this.type,
  });

  final AppController controller;
  final CollectionListType type;

  String get title => switch (type) {
    CollectionListType.unread => 'NIJE ČITANO',
    CollectionListType.wanted => 'TRAŽIM',
    CollectionListType.duplicates => 'DUPLI',
    CollectionListType.loaned => 'POSUĐENO',
  };

  String get subtitle => switch (type) {
    CollectionListType.unread => 'Brojevi koji čekaju čitanje',
    CollectionListType.wanted => 'Brojevi koji nedostaju u kolekciji',
    CollectionListType.duplicates => 'Primjerci za zamjenu ili prodaju',
    CollectionListType.loaned => 'Stripovi koji su trenutačno kod nekoga',
  };

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      final items = _items();
      return Scaffold(
        appBar: AppBar(
          centerTitle: true,
          title: Text(
            title,
            style: TextStyle(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w900,
            ),
          ),
          actions: [
            if (type == CollectionListType.wanted && items.isNotEmpty)
              IconButton(
                tooltip: 'Kopiraj popis',
                onPressed: () => _copyWanted(context, items),
                icon: const Icon(Icons.copy_outlined),
              ),
          ],
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 2, 18, 10),
              child: Text(
                '$subtitle · ${items.length}',
                textAlign: TextAlign.center,
                style: const TextStyle(color: tan, fontSize: 12.5),
              ),
            ),
            Expanded(
              child: items.isEmpty
                  ? Center(child: EmptyCard(text: _emptyLabel()))
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                      itemCount: items.length,
                      itemBuilder: (context, index) {
                        final comic = items[index];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              ComicTile(comic: comic, controller: controller),
                              Align(
                                alignment: Alignment.centerRight,
                                child: TextButton.icon(
                                  onPressed: () => _complete(comic),
                                  icon: Icon(_actionIcon(), size: 16),
                                  label: Text(_actionLabel()),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      );
    },
  );

  List<Comic> _items() {
    final items = controller.comics.where((comic) {
      return switch (type) {
        CollectionListType.unread => comic.owned && !comic.read,
        CollectionListType.wanted => !comic.owned,
        CollectionListType.duplicates => comic.owned && comic.duplicate,
        CollectionListType.loaned => comic.owned && comic.loanedTo.isNotEmpty,
      };
    }).toList();
    items.sort((a, b) {
      final series = a.series.compareTo(b.series);
      if (series != 0) return series;
      final edition = a.edition.compareTo(b.edition);
      return edition != 0 ? edition : a.number.compareTo(b.number);
    });
    return items;
  }

  String _actionLabel() => switch (type) {
    CollectionListType.unread => 'OZNAČI PROČITANO',
    CollectionListType.wanted => '+ NABAVLJEN',
    CollectionListType.duplicates => 'VIŠE NIJE DUPLI',
    CollectionListType.loaned => 'VRAĆENO',
  };

  IconData _actionIcon() => switch (type) {
    CollectionListType.unread => Icons.visibility_outlined,
    CollectionListType.wanted => Icons.add_circle_outline,
    CollectionListType.duplicates => Icons.done_all,
    CollectionListType.loaned => Icons.assignment_return_outlined,
  };

  String _emptyLabel() => switch (type) {
    CollectionListType.unread => 'Sve što imaš je pročitano.',
    CollectionListType.wanted => 'Kolekcija je kompletna!',
    CollectionListType.duplicates => 'Nema duplih primjeraka.',
    CollectionListType.loaned => 'Sve je vraćeno.',
  };

  Future<void> _complete(Comic comic) => switch (type) {
    CollectionListType.unread => controller.save(comic.copyWith(read: true)),
    CollectionListType.wanted => controller.save(comic.copyWith(owned: true)),
    CollectionListType.duplicates => controller.save(
      comic.copyWith(duplicate: false),
    ),
    CollectionListType.loaned => controller.save(comic.copyWith(loanedTo: '')),
  };

  void _copyWanted(BuildContext context, List<Comic> items) {
    final text = items
        .map(
          (comic) =>
              '${comic.series} · ${comic.edition} #${comic.number} — ${comic.title}',
        )
        .join('\n');
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Popis Tražim je kopiran.')));
  }
}
