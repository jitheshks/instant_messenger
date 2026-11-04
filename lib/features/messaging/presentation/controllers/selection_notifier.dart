import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Modern Riverpod Notifier for generic selection state.
abstract mixin class BaseSelectionNotifier<T> {
  Set<T> get state;
  set state(Set<T> value);

  bool get active => state.isNotEmpty;
  int get count => state.length;
  Set<T> get selected => state;

  bool isSelected(T id) => state.contains(id);

  void toggle(T id) {
    if (state.contains(id)) {
      state = Set<T>.unmodifiable(state.where((item) => item != id));
    } else {
      state = Set<T>.unmodifiable({...state, id});
    }
  }

  void selectAll(Iterable<T> ids) {
    state = Set<T>.unmodifiable({...state, ...ids});
  }

  void clear() {
    if (state.isEmpty) return;
    state = Set<T>.unmodifiable(<T>{});
  }

  void toggleMany(Iterable<T> ids) {
    final next = Set<T>.from(state);
    for (final id in ids) {
      if (!next.remove(id)) {
        next.add(id);
      }
    }
    state = Set<T>.unmodifiable(next);
  }
}

class ChatsTabSelectionNotifier extends Notifier<Set<String>>
    with BaseSelectionNotifier<String> {
  @override
  Set<String> build() => const <String>{};
}

class ChatScreenSelectionNotifier extends Notifier<Set<String>>
    with BaseSelectionNotifier<String> {
  @override
  Set<String> build() => const <String>{};
}
