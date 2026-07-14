import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/comic.dart';

void exportComicsCsv(BuildContext context, Iterable<Comic> comics) {
  String esc(Object? value) =>
      '"${(value ?? '').toString().replaceAll('"', '""')}"';
  final rows = <String>[
    'Serijal,Edicija,Broj,Naslov,Izdavač,Godina,Imam,Pročitano,Stanje,Vrijednost,Dupli,Posuđeno',
  ];
  for (final comic in comics) {
    rows.add(
      [
        comic.series,
        comic.edition,
        comic.number,
        comic.title,
        comic.publisher,
        comic.year ?? '',
        comic.owned ? 'DA' : 'NE',
        comic.read ? 'DA' : 'NE',
        comic.condition,
        comic.estimatedValue ?? '',
        comic.duplicate ? 'DA' : 'NE',
        comic.loanedTo,
      ].map(esc).join(','),
    );
  }
  Clipboard.setData(ClipboardData(text: rows.join('\n')));
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text('CSV je kopiran u međuspremnik.')),
  );
}
