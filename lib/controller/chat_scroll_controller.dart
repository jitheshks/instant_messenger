import 'package:flutter/material.dart';

/// ChatScrollController
/// ------------------------------------------------------------
/// Responsibilities:
/// - Own ScrollController for chat ListView
/// - Detect when user scrolls away from bottom
/// - Show / hide "jump to latest" button
/// - Track unread count while user is away
///
/// DOES NOT:
/// - Know Firestore
/// - Know Hive
/// - Know message types
/// - Modify messages
class ChatScrollController extends ChangeNotifier {
  /// ListView controller (reverse: true)
  final ScrollController scrollController = ScrollController();

  /// Whether the floating jump button should be visible
  bool _showJumpButton = false;
  bool get showJumpButton => _showJumpButton;

  /// Unread messages count while user is away from bottom
  int _unreadCount = 0;
  int get unreadCount => _unreadCount;

  bool _attached = false;

  /// Distance from bottom (pixels) before we consider user "away"
  static const double _awayThreshold = 120;

  // ------------------------------------------------------------
  // ATTACH / DISPOSE
  // ------------------------------------------------------------

  void attach() {
    if (_attached) return;
    _attached = true;

    scrollController.addListener(_onScroll);
  }

  void disposeController() {
    scrollController.removeListener(_onScroll);
    scrollController.dispose();
  }

  // ------------------------------------------------------------
  // SCROLL LOGIC
  // ------------------------------------------------------------

  void _onScroll() {
    if (!scrollController.hasClients) return;

    // ListView(reverse: true)
    final offset = scrollController.position.pixels;

    final isAwayFromBottom = offset > _awayThreshold;

    if (isAwayFromBottom != _showJumpButton) {
      _showJumpButton = isAwayFromBottom;

      // Reset unread when user comes back
      if (!isAwayFromBottom) {
        _unreadCount = 0;
      }

      notifyListeners();
    }
  }

  // ------------------------------------------------------------
  // MESSAGE EVENTS (CALLED BY ChatScreenController)
  // ------------------------------------------------------------

  /// Call this when NEW messages arrive
  /// Only increments unread if user is away from bottom
  void onNewMessages(int count) {
    if (!_showJumpButton || count <= 0) return;

    _unreadCount += count;
    notifyListeners();
  }

  /// Jump user to the latest message
  void jumpToLatest() {
    if (!scrollController.hasClients) return;

    scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );

    _unreadCount = 0;
    _showJumpButton = false;
    notifyListeners();
  }
}
