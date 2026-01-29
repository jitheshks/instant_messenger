class NotificationController {
  // -----------------------------
  // Navigation callback (EXISTING)
  // -----------------------------
  static late void Function(String chatId) _onTap;

  /// Register tap callback (called once in main.dart)
  static void configure(void Function(String chatId) onTap) {
    _onTap = onTap;
  }

  /// Called when user taps a notification
  static void onNotificationTap(String chatId) {
    _onTap(chatId);
  }

  // -----------------------------
  // Foreground chat tracking (NEW)
  // -----------------------------
  static String? _openChatId;

  /// Call when a chat screen opens
  static void onChatOpen(String chatId) {
    _openChatId = chatId;
  }

  /// Call when leaving chat screen
  static void onChatClose(String chatId) {
    if (_openChatId == chatId) {
      _openChatId = null;
    }
  }

  /// Check if the given chat is currently open
  static bool isChatOpen(String? chatId) {
    if (chatId == null) return false;
    return _openChatId == chatId;
  }
}
