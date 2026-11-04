import 'package:flutter/widgets.dart';
import 'package:instant_messenger/core/config/supabase_config.dart';
import 'package:instant_messenger/features/notifications/domain/models/notification_payload.dart';
import 'package:instant_messenger/features/notifications/presentation/controllers/push_controller.dart';

class RouterNotifier extends ChangeNotifier {
  bool _isAuthed = false;
  bool _requiresName = false;
  bool _bootstrapped = false;

  bool _pushInitDone = false;
  PushController? _pushController;

  String? _pendingNotificationChatId;
  NotificationPayload? _pendingNotification;

  // ───────────────── GETTERS ─────────────────

  bool get isAuthed => _isAuthed;
  bool get requiresName => _requiresName;
  bool get bootstrapped => _bootstrapped;
  String? get pendingNotificationChatId =>
      _pendingNotification?.chatId ?? _pendingNotificationChatId;
  NotificationPayload? get pendingNotification => _pendingNotification;

  // ───────────────── PENDING NOTIFICATION NAVIGATION ─────────────────

  void setPendingNotification(NotificationPayload? payload) {
    if (payload == null) return;
    _pendingNotification = payload;
    if (payload.chatId != null && payload.chatId!.isNotEmpty) {
      _pendingNotificationChatId = payload.chatId;
    }
    debugPrint(
      '[NotificationTap] RouterNotifier.setPendingNotification: $payload',
    );
    notifyListeners();
  }

  void clearPendingNotification() {
    _pendingNotification = null;
    _pendingNotificationChatId = null;
  }

  NotificationPayload? consumePendingNotification() {
    final payload = _pendingNotification;
    if (payload != null) {
      debugPrint(
        '[NotificationTap] RouterNotifier.consumePendingNotification consumed: $payload',
      );
    }
    _pendingNotification = null;
    _pendingNotificationChatId = null;
    return payload;
  }

  void setPendingNotificationChatId(String? chatId) {
    final clean = chatId?.trim();
    if (clean == null || clean.isEmpty) return;
    _pendingNotificationChatId = clean;
    _pendingNotification = NotificationPayload(
      type: NotificationType.chat,
      chatId: clean,
    );
    debugPrint(
      '[NotificationTap] RouterNotifier.setPendingNotificationChatId: $clean (previous: $_pendingNotificationChatId)',
    );
    notifyListeners();
  }

  String? consumePendingNotificationChatId() {
    final id = _pendingNotificationChatId;
    if (id != null) {
      debugPrint(
        '[NotificationTap] RouterNotifier.consumePendingNotificationChatId consumed: $id',
      );
    }
    _pendingNotificationChatId = null;
    _pendingNotification = null;
    return id;
  }

  // ───────────────── AUTH STATE ─────────────────

  void setAuthed(bool value) {
    if (_isAuthed == value) return;
    debugPrint(
      '[NotificationTap] RouterNotifier.setAuthed: $value (pendingNotification: $_pendingNotificationChatId)',
    );
    _isAuthed = value;
    if (value) {
      attachPushInit();
    }
    notifyListeners();
  }

  // ───────────────── NAME STATE ─────────────────

  void setRequiresName(bool value) {
    if (_requiresName == value) return;
    debugPrint(
      '[NotificationTap] RouterNotifier.setRequiresName: $value',
    );
    _requiresName = value;
    notifyListeners();
  }

  // ───────────────── BOOTSTRAP STATE ─────────────────

  void setBootstrapped(bool value) {
    if (_bootstrapped == value) return;
    debugPrint(
      '[NotificationTap] RouterNotifier.setBootstrapped: $value (pendingNotification: $_pendingNotificationChatId, isAuthed: $_isAuthed)',
    );
    _bootstrapped = value;
    notifyListeners();
  }

  // ───────────────── PUSH INIT (SAFE, ONE-TIME) ─────────────────

  /// Call from GoRouter builder / redirect AFTER auth
  void attachPushInit([PushController? pushController]) {
    if (pushController != null) {
      _pushController = pushController;
    }
    if (_pushInitDone) return;

    final controller = _pushController;
    if (controller == null) return;

    final uid = SupabaseConfig.currentUserId;
    if (uid == null || uid.isEmpty) return;

    debugPrint('[NotificationTap] RouterNotifier invoking PushController.init for uid: $uid');
    controller.init(uid: uid);
    _pushInitDone = true;
  }

  // ───────────────── RESET (ON LOGOUT / TOKEN LOSS) ─────────────────

  void reset({bool clearPendingNotification = false}) {
    debugPrint(
      '[NotificationTap] RouterNotifier.reset (clearPendingNotification=$clearPendingNotification)',
    );
    _isAuthed = false;
    _requiresName = false;
    _bootstrapped = false;
    _pushInitDone = false;
    if (clearPendingNotification) {
      _pendingNotificationChatId = null;
      _pendingNotification = null;
    }
    notifyListeners();
  }
}
