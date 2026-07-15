import 'package:comicollect/state/selected_value_listenable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('notifies only when the selected slice changes', () {
    final source = _Source();
    final selected = SelectedValueListenable(
      source: source,
      select: () => (enabled: source.enabled, label: source.label),
    );
    addTearDown(source.dispose);
    addTearDown(selected.dispose);
    var notifications = 0;
    selected.addListener(() => notifications++);

    source.changeUnrelated();
    expect(notifications, 0);

    source.setEnabled(true);
    expect(notifications, 1);
    expect(selected.value, (enabled: true, label: 'initial'));

    source.setLabel('updated');
    expect(notifications, 2);
    expect(selected.value, (enabled: true, label: 'updated'));
  });

  test('dispose detaches from the broad source', () {
    final source = _Source();
    final selected = SelectedValueListenable(
      source: source,
      select: () => source.enabled,
    );
    var notifications = 0;
    selected.addListener(() => notifications++);

    selected.dispose();
    source.setEnabled(true);

    expect(notifications, 0);
    source.dispose();
  });
}

class _Source extends ChangeNotifier {
  bool enabled = false;
  String label = 'initial';
  int unrelated = 0;

  void setEnabled(bool value) {
    enabled = value;
    notifyListeners();
  }

  void setLabel(String value) {
    label = value;
    notifyListeners();
  }

  void changeUnrelated() {
    unrelated++;
    notifyListeners();
  }
}
