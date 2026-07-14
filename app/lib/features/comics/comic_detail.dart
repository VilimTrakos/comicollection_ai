import 'package:flutter/material.dart';

import '../../app_controller.dart';
import '../../models/comic.dart';
import '../../ui/app_theme.dart';
import '../../ui/common_widgets.dart';
import 'comic_form.dart';

class ComicTile extends StatelessWidget {
  const ComicTile({super.key, required this.comic, required this.controller});
  final Comic comic;
  final AppController controller;
  @override
  Widget build(BuildContext context) => Card(
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    child: InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ComicDetail(comic: comic, controller: controller),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          children: [
            SizedBox(
              width: 58,
              height: 78,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(9),
                child: ComicCover(
                  label: '#${comic.number}',
                  seed: comic.series.hashCode + comic.number,
                  assetPath: comic.coverAsset,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${comic.series} #${comic.number}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                  ),
                  Text(
                    comic.title.isEmpty ? comic.edition : comic.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: tan),
                  ),
                  const SizedBox(height: 7),
                  Wrap(
                    spacing: 6,
                    children: [
                      Tag(
                        comic.condition.isEmpty
                            ? 'bez stanja'
                            : comic.condition,
                      ),
                      if (comic.duplicate) const Tag('DUPLI'),
                      if (comic.loanedTo.isNotEmpty) const Tag('POSUĐENO'),
                    ],
                  ),
                ],
              ),
            ),
            Column(
              children: [
                IconButton(
                  tooltip: comic.owned
                      ? 'Imam — ukloni s police'
                      : 'Dodaj na moju policu',
                  onPressed: () => controller.save(
                    comic.copyWith(
                      owned: !comic.owned,
                      read: comic.owned ? false : comic.read,
                    ),
                  ),
                  icon: Icon(
                    comic.owned ? Icons.check_circle : Icons.add_circle_outline,
                    color: comic.owned ? const Color(0xFF3EC63E) : tan,
                  ),
                ),
                IconButton(
                  tooltip: comic.read
                      ? 'Označi nepročitano'
                      : 'Označi pročitano',
                  onPressed: comic.owned
                      ? () => controller.save(comic.copyWith(read: !comic.read))
                      : null,
                  icon: Icon(
                    comic.read ? Icons.visibility : Icons.visibility_off,
                    color: comic.read ? const Color(0xFF3EC63E) : Colors.grey,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

class ComicDetail extends StatelessWidget {
  const ComicDetail({super.key, required this.comic, required this.controller});
  final Comic comic;
  final AppController controller;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      final current =
          controller.comics.where((c) => c.id == comic.id).firstOrNull ?? comic;
      final edition =
          controller.comics
              .where(
                (c) =>
                    c.series == current.series && c.edition == current.edition,
              )
              .toList()
            ..sort((a, b) => a.number.compareTo(b.number));
      final at = edition.indexWhere((c) => c.id == current.id);
      final previous = at > 0 ? edition[at - 1] : null;
      final next = at >= 0 && at < edition.length - 1 ? edition[at + 1] : null;
      return Scaffold(
        appBar: AppBar(
          centerTitle: true,
          title: Text(
            current.series.toUpperCase(),
            style: TextStyle(
              color: Theme.of(context).colorScheme.primary,
              fontSize: 25,
              fontWeight: FontWeight.w900,
              letterSpacing: 1,
            ),
          ),
        ),
        body: Stack(
          children: [
            const Positioned.fill(child: GrungeBackground()),
            ListView(
              padding: const EdgeInsets.fromLTRB(24, 4, 24, 32),
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 150,
                      height: 200,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: ComicCover(
                          label: '${current.series}\n#${current.number}',
                          seed: current.series.hashCode + current.number,
                          assetPath: current.coverAsset,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${current.series} ${current.edition}',
                              style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '#${current.number} - ${current.title}',
                              style: const TextStyle(
                                fontSize: 15.5,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 9),
                            Text(
                              '${current.year ?? '—'} · ${current.publisher}',
                              style: const TextStyle(color: tan, fontSize: 13),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: List.generate(
                                5,
                                (index) => Icon(
                                  index < current.rating
                                      ? Icons.star
                                      : Icons.star_border,
                                  color: const Color(0xFFE8C547),
                                  size: 17,
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            if (current.owned)
                              Row(
                                children: [
                                  Container(
                                    width: 36,
                                    height: 36,
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF080909),
                                      borderRadius: BorderRadius.circular(9),
                                      border: Border.all(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.primary,
                                        width: 1.5,
                                      ),
                                    ),
                                    child: Text(
                                      current.condition.isEmpty
                                          ? '—'
                                          : current.condition,
                                      style: TextStyle(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.primary,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 9),
                                  Text(
                                    current.estimatedValue == null
                                        ? 'U kolekciji'
                                        : '~${current.estimatedValue!.toStringAsFixed(0)} €',
                                    style: const TextStyle(
                                      color: tan,
                                      fontSize: 12.5,
                                    ),
                                  ),
                                ],
                              )
                            else
                              Text(
                                'TRAŽIM',
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.primary,
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                if (current.loanedTo.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(top: 14),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Theme.of(
                        context,
                      ).colorScheme.primary.withValues(alpha: .14),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: Theme.of(
                          context,
                        ).colorScheme.primary.withValues(alpha: .45),
                      ),
                    ),
                    child: Text(
                      'Posuđeno: ${current.loanedTo}',
                      style: const TextStyle(fontSize: 12.5),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.only(top: 14),
                  child: Text(
                    current.notes.isEmpty ||
                            current.notes.startsWith('Početni katalog') ||
                            current.notes.startsWith('BSP katalog') ||
                            current.notes.startsWith('Dodano unosom raspona')
                        ? 'Kultni talijanski horror strip prati istražitelja noćnih mora Dylana Doga i njegove neobične slučajeve.'
                        : current.notes,
                    style: const TextStyle(
                      color: tan,
                      fontSize: 13.5,
                      height: 1.55,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _IssueStep(
                        label: 'Prethodni broj',
                        comic: previous,
                        controller: controller,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _IssueStep(
                        label: 'Sljedeći broj',
                        comic: next,
                        controller: controller,
                        right: true,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: _StatusAction(
                        active: current.read,
                        icon: Icons.visibility_outlined,
                        activeLabel: 'PROČITANO',
                        inactiveLabel: 'NIJE ČITANO',
                        onTap: current.owned
                            ? () => controller.save(
                                current.copyWith(read: !current.read),
                              )
                            : null,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _StatusAction(
                        active: current.owned,
                        icon: Icons.check,
                        activeLabel: 'U KOLEKCIJI',
                        inactiveLabel: '+ DODAJ',
                        onTap: () => controller.save(
                          current.copyWith(
                            owned: !current.owned,
                            read: current.owned ? false : current.read,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          ComicForm(controller: controller, comic: current),
                    ),
                  ),
                  icon: const Icon(Icons.edit_outlined, size: 17),
                  label: Text(
                    current.owned
                        ? 'UREDI PRIMJERAK — stanje, posudba, vrijednost'
                        : 'UREDI — bilješke i ciljna cijena',
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: tan,
                    side: BorderSide(color: tan.withValues(alpha: .2)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
                const SectionTitle('DETALJI IZDANJA'),
                Card(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    child: Column(
                      children: [
                        DetailRow('Izdavač', current.publisher),
                        DetailRow(
                          'Edicija',
                          '${current.edition} #${current.number}',
                        ),
                        DetailRow('Godina', current.year?.toString() ?? '—'),
                        if (current.pageCount != null)
                          DetailRow('Stranice', '${current.pageCount}'),
                        if (current.writer.isNotEmpty)
                          DetailRow('Scenarij', current.writer),
                        if (current.artist.isNotEmpty)
                          DetailRow('Crtež', current.artist),
                        DetailRow(
                          'Ocjena',
                          current.rating == 0 ? '—' : '${current.rating}/5',
                        ),
                        DetailRow(
                          'Stanje',
                          current.condition.isEmpty
                              ? 'Bez stanja'
                              : current.condition,
                        ),
                        DetailRow(
                          'Vrijednost',
                          current.estimatedValue == null
                              ? '—'
                              : '${current.estimatedValue!.toStringAsFixed(2)} €',
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextButton.icon(
                  onPressed: () => _delete(context, current),
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('UKLONI ZAPIS'),
                  style: TextButton.styleFrom(foregroundColor: Colors.grey),
                ),
              ],
            ),
          ],
        ),
      );
    },
  );
  Future<void> _delete(BuildContext context, Comic selected) async {
    final yes =
        await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Ukloniti strip?'),
            content: const Text('Brisanje će se sinkronizirati sa serverom.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('ODUSTANI'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('UKLONI'),
              ),
            ],
          ),
        ) ??
        false;
    if (yes) {
      await controller.remove(selected);
      if (context.mounted) Navigator.pop(context);
    }
  }
}

class _IssueStep extends StatelessWidget {
  const _IssueStep({
    required this.label,
    required this.comic,
    required this.controller,
    this.right = false,
  });
  final String label;
  final Comic? comic;
  final AppController controller;
  final bool right;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: right
        ? CrossAxisAlignment.end
        : CrossAxisAlignment.start,
    children: [
      Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
      const SizedBox(height: 6),
      SizedBox(
        width: double.infinity,
        child: OutlinedButton(
          onPressed: comic == null
              ? null
              : () => Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        ComicDetail(comic: comic!, controller: controller),
                  ),
                ),
          style: OutlinedButton.styleFrom(
            alignment: right ? Alignment.centerRight : Alignment.centerLeft,
            foregroundColor: Colors.white,
            side: BorderSide(color: tan.withValues(alpha: .16)),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          child: Text(
            comic == null ? '—' : '#${comic!.number} ${comic!.title}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12.5),
          ),
        ),
      ),
    ],
  );
}

class _StatusAction extends StatelessWidget {
  const _StatusAction({
    required this.active,
    required this.icon,
    required this.activeLabel,
    required this.inactiveLabel,
    required this.onTap,
  });
  final bool active;
  final IconData icon;
  final String activeLabel, inactiveLabel;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final color = active
        ? const Color(0xFF3EC63E)
        : Theme.of(context).colorScheme.primary;
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 16),
      label: Text(
        active ? activeLabel : inactiveLabel,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
      ),
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        backgroundColor: color.withValues(alpha: .13),
        side: BorderSide(color: color.withValues(alpha: .65)),
        padding: const EdgeInsets.symmetric(vertical: 13),
        shape: const StadiumBorder(),
      ),
    );
  }
}
