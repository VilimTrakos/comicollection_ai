import 'package:comicollect/models/collection_entry.dart';
import 'package:comicollect/models/comic_copy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CollectionEntry', () {
    test('round-trips every persisted field', () {
      const entry = CollectionEntry(
        issueId: 'issue-1',
        owned: true,
        wanted: true,
        read: true,
        duplicate: true,
        rating: 4,
        notes: 'Bilješka',
        deleted: true,
        updatedAt: 123,
      );

      expect(CollectionEntry.fromMap(entry.toMap()).toMap(), entry.toMap());
    });

    test('provides safe defaults and copyWith preserves other state', () {
      const entry = CollectionEntry(issueId: 'issue-1', updatedAt: 1);

      final changed = entry.copyWith(owned: true, notes: 'Novo', updatedAt: 2);

      expect(changed.issueId, 'issue-1');
      expect(changed.owned, isTrue);
      expect(changed.wanted, isFalse);
      expect(changed.read, isFalse);
      expect(changed.duplicate, isFalse);
      expect(changed.rating, 0);
      expect(changed.notes, 'Novo');
      expect(changed.deleted, isFalse);
      expect(changed.updatedAt, 2);
    });
  });

  group('ComicCopy', () {
    test('round-trips every persisted field and numeric values', () {
      const copy = ComicCopy(
        id: 'copy-1',
        issueId: 'issue-1',
        ordinal: 2,
        active: false,
        condition: 'VF',
        purchasePrice: 3.5,
        estimatedValue: 9,
        loanedTo: 'Ana',
        deleted: true,
        updatedAt: 456,
      );

      final map = copy.toMap()
        ..['purchase_price'] = 3
        ..['estimated_value'] = 9;
      final restored = ComicCopy.fromMap(map);

      expect(restored.purchasePrice, 3.0);
      expect(restored.estimatedValue, 9.0);
      expect(restored.toMap(), {...copy.toMap(), 'purchase_price': 3.0});
    });

    test(
      'copyWith preserves, replaces and explicitly clears nullable prices',
      () {
        const copy = ComicCopy(
          id: 'copy-1',
          issueId: 'issue-1',
          ordinal: 0,
          purchasePrice: 2.5,
          estimatedValue: 7,
          updatedAt: 1,
        );

        final preserved = copy.copyWith(active: false);
        final replaced = copy.copyWith(purchasePrice: 4, estimatedValue: 10.5);
        final cleared = copy.copyWith(
          purchasePrice: null,
          estimatedValue: null,
        );

        expect(preserved.purchasePrice, 2.5);
        expect(preserved.estimatedValue, 7);
        expect(replaced.purchasePrice, 4.0);
        expect(replaced.estimatedValue, 10.5);
        expect(cleared.purchasePrice, isNull);
        expect(cleared.estimatedValue, isNull);
      },
    );
  });
}
