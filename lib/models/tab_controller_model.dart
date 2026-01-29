// lib/controller/tab_controller_model.dart
import 'package:flutter/material.dart';

class TabControllerModel extends ChangeNotifier {
  // Route paths in tab order; used to sync with go_router.
  static const tabs = <String>['/chats', '/updates', '/communities', '/calls'];

  final PageController pageController;
  int _index;

  TabControllerModel({int initialIndex = 0})
      : _index = initialIndex,
        pageController = PageController(initialPage: initialIndex); // PageView controller [web:657]

  int get index => _index;

  // Called on bottom bar tap or external route change; no animation for snappy parity.
  void jumpTo(int i) {
    if (i == _index) return;
    _index = i;
    pageController.jumpToPage(i); // instant switch [web:657]
    notifyListeners();            // updates the bar
  }

  // Called from PageView.onPageChanged on swipe; UI already moved, just update state.
  void onPageChanged(int i) {
    if (i == _index) return;
    _index = i;
    notifyListeners();            // updates the bar only
  }

  // Optional animated navigation; call instead of jumpTo if a slide is desired on taps.
  Future<void> animateTo(int i, {Duration duration = const Duration(milliseconds: 250), Curve curve = Curves.ease}) async {
    if (i == _index) return;
    _index = i;
    await pageController.animateToPage(i, duration: duration, curve: curve); // animated switch [web:657]
    notifyListeners();
  }

  @override
  void dispose() {
    pageController.dispose(); // prevent leaks [web:657]
    super.dispose();
  }
}
