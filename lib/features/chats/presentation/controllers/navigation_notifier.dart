import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class NavigationNotifier extends Notifier<int> {
  final PageController pageController = PageController();

  @override
  int build() {
    ref.onDispose(pageController.dispose);
    return 0;
  }

  int get index => state;

  void jumpTo(int i) {
    if (state == i) return;
    state = i;
    if (pageController.hasClients) {
      pageController.jumpToPage(i);
    }
  }

  void onPageChanged(int i) {
    if (state == i) return;
    state = i;
  }
}
