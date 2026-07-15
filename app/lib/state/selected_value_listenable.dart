import 'package:flutter/foundation.dart';

/// Exposes one selected slice of a broader [Listenable].
///
/// The selector is evaluated whenever [source] changes, but listeners are only
/// notified when the selected value itself changes. Records make convenient
/// immutable slices for multiple related fields.
class SelectedValueListenable<T> extends ChangeNotifier
    implements ValueListenable<T> {
  SelectedValueListenable({required this.source, required T Function() select})
    : _select = select,
      _value = select() {
    source.addListener(_handleSourceChange);
  }

  final Listenable source;
  final T Function() _select;
  T _value;

  @override
  T get value => _value;

  void _handleSourceChange() {
    final next = _select();
    if (next == _value) return;
    _value = next;
    notifyListeners();
  }

  @override
  void dispose() {
    source.removeListener(_handleSourceChange);
    super.dispose();
  }
}
