import 'package:flutter/foundation.dart';

/// Generic, allocation‑light selection state controller.
/// Use as a base for different entity types (threads, messages, etc.).
abstract class SelectionController<T> extends ChangeNotifier {
  final Set<T> _selected = <T>{};

  bool get active => _selected.isNotEmpty;
  int get count => _selected.length;

  /// Read‑only snapshot of selected items.
  Set<T> get selected => Set<T>.unmodifiable(_selected);

  @pragma('vm:prefer-inline')
  bool isSelected(T id) => _selected.contains(id);

  /// Toggle selection of a single id (single notify).
  @pragma('vm:prefer-inline')
  void toggle(T id) {
    if (!_selected.remove(id)) {
      _selected.add(id);
    }
    notifyListeners();
  }

  /// Select all candidates (single notify if anything changed).
  void selectAll(Iterable<T> ids) {
    var changed = false;
    for (final id in ids) {
      if (_selected.add(id)) changed = true;
    }
    if (changed) notifyListeners();
  }

  /// Clear selection (skips notify if already empty).
  void clear() {
    if (_selected.isEmpty) return;
    _selected.clear();
    notifyListeners();
  }

  /// Batch toggle (single notify).
  void toggleMany(Iterable<T> ids) {
    var changed = false;
    for (final id in ids) {
      if (!_selected.remove(id)) {
        _selected.add(id);
      }
      changed = true;
    }
    if (changed) notifyListeners();
  }
}
