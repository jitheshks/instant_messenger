import 'package:flutter/foundation.dart';
import 'package:instant_messenger/features/notifications/data/fcm_service.dart';
import 'package:instant_messenger/features/notifications/data/notification_service.dart';
import 'package:instant_messenger/features/notifications/data/onesignal_service.dart';
import 'package:instant_messenger/features/notifications/domain/models/notification_payload.dart';
import 'package:instant_messenger/features/notifications/presentation/controllers/notification_navigation_coordinator.dart';

class NotificationController {
  // -----------------------------
  // Navigation callback (EXISTING)
  // -----------------------------
  static void Function(String chatId)? _onTap;
  static String? _pendingChatId;
  static DateTime? _lastTapHandledAt;
  static String? _lastTapHandledChatId;

  static void Function(NotificationPayload payload)? _onPayloadTap;
  static NotificationPayload? _pendingPayload;

  static String? get pendingChatId => _pendingChatId;
  static NotificationPayload? get pendingPayload => _pendingPayload;

  /// Configures the unified NotificationNavigationCoordinator as the single destination
  /// for all notification interactions across FCM, OneSignal, and Local Notifications.
  static void configureCoordinator(
    NotificationNavigationCoordinator coordinator,
  ) {
    debugPrint(
      '[NotificationTap] NotificationController.configureCoordinator called',
    );
    _onPayloadTap = (payload) => coordinator.handleNotificationPayload(payload);

    NotificationService.onPayloadTap = onPayloadReceived;
    OneSignalService.onPayloadTap = onPayloadReceived;
    FcmService.onPayloadTap = onPayloadReceived;

    OneSignalService.isChatOpenDelegate = isChatOpen;
    FcmService.isChatOpenDelegate = isChatOpen;

    // Drain pending payloads from individual services if cold-started
    final osPayload = OneSignalService.consumePendingNotificationPayload();
    final fcmPayload = FcmService.consumePendingNotificationPayload();
    final localPayload =
        NotificationService.consumePendingNotificationPayload();
    final pendingOneSignalChatId =
        OneSignalService.consumePendingNotificationChatId();
    final pendingOneSignalCall =
        OneSignalService.consumePendingCallAction();

    final candidates = [
      osPayload,
      fcmPayload,
      localPayload,
      _pendingPayload,
      if (pendingOneSignalChatId != null &&
          pendingOneSignalChatId.trim().isNotEmpty)
        NotificationPayload(
          type: NotificationType.chat,
          chatId: pendingOneSignalChatId.trim(),
        ),
      if (pendingOneSignalCall != null)
        NotificationPayload(
          type: NotificationType.call,
          callId: pendingOneSignalCall.callId,
          callerId: pendingOneSignalCall.callerId,
          callerName: pendingOneSignalCall.callerName,
          callType: pendingOneSignalCall.callType,
          callActionIntent: pendingOneSignalCall.isAccepted
              ? CallActionIntent.accept
              : CallActionIntent.openIncomingUi,
        ),
    ];

    final toDrain = candidates.firstWhere(
      (p) => p != null && p.type != NotificationType.unknown,
      orElse: () => null,
    );

    if (toDrain != null) {
      debugPrint(
        '[NotificationTap] Draining pending payload from services: $toDrain',
      );
      _pendingPayload = null;
      coordinator.handleNotificationPayload(toDrain);
    }
  }

  /// Receiver for unified notification payload from any underlying provider.
  static void onPayloadReceived(NotificationPayload payload) {
    debugPrint(
      '[NotificationTap] NotificationController.onPayloadReceived: $payload',
    );
    final tap = _onPayloadTap;
    if (tap != null) {
      tap(payload);
    } else {
      _pendingPayload = payload;
      if (payload.chatId != null && payload.chatId!.isNotEmpty) {
        onNotificationTap(payload.chatId!);
      }
    }
  }

  /// Register tap callback (called once in main.dart / app.dart)
  static void configure(
    void Function(String chatId) onTap, {
    void Function(CallNotificationAction action)? onCallAction,
    Future<void> Function(String callId)? onCallDecline,
  }) {
    debugPrint('[NotificationTap] NotificationController.configure called');
    _onTap = onTap;
    NotificationService.onTap = onNotificationTap;
    OneSignalService.onTap = onNotificationTap;
    OneSignalService.onCallAction = onCallAction;
    OneSignalService.onCallDecline = onCallDecline;
    OneSignalService.isChatOpenDelegate = isChatOpen;
    FcmService.onTap = onNotificationTap;
    FcmService.isChatOpenDelegate = isChatOpen;

    // Drain pending call action from OneSignal if cold-started by call notification
    final pendingCall = OneSignalService.consumePendingCallAction();
    if (pendingCall != null) {
      debugPrint(
        '[CallNotification] Draining pending call: ${pendingCall.callId} from NotificationController.configure',
      );
      onCallAction?.call(pendingCall);
    }

    // Drain pending chat ID from OneSignal or early tap
    final pendingOneSignal =
        OneSignalService.consumePendingNotificationChatId();
    final toDrain = pendingOneSignal ?? _pendingChatId;
    if (toDrain != null && toDrain.trim().isNotEmpty) {
      final clean = toDrain.trim();
      debugPrint(
        '[NotificationTap] Draining pending chatId: $clean from NotificationController.configure',
      );
      _pendingChatId = null;
      onNotificationTap(clean);
    }
  }

  /// Called when user taps a notification
  static void onNotificationTap(String chatId) {
    final cleanId = chatId.trim();
    if (cleanId.isEmpty) {
      debugPrint(
        '[NotificationTap] ⚠️ NotificationController.onNotificationTap called with empty chatId',
      );
      return;
    }

    final tap = _onTap;
    if (tap != null) {
      // Debounce rapid duplicate taps (within 1000ms) for the same chat
      final now = DateTime.now();
      if (_lastTapHandledChatId == cleanId &&
          _lastTapHandledAt != null &&
          now.difference(_lastTapHandledAt!).inMilliseconds < 1000) {
        debugPrint(
          '[NotificationTap] ⚠️ Debounced rapid duplicate tap for chatId: $cleanId',
        );
        return;
      }
      _lastTapHandledChatId = cleanId;
      _lastTapHandledAt = now;

      debugPrint(
        '[NotificationTap] NotificationController invoking _onTap callback for chatId: $cleanId',
      );
      tap(cleanId);
    } else {
      debugPrint(
        '[NotificationTap] NotificationController _onTap is null; buffering in _pendingChatId: $cleanId',
      );
      _pendingChatId = cleanId;
    }
  }

  // -----------------------------
  // Foreground chat tracking (NEW)
  // -----------------------------
  static String? _openChatId;

  /// Call when a chat screen opens
  static void onChatOpen(String chatId) {
    final clean = chatId.trim();
    debugPrint('[NotificationTap] NotificationController.onChatOpen: $clean');
    _openChatId = clean;
  }

  /// Call when leaving chat screen
  static void onChatClose(String chatId) {
    final clean = chatId.trim();
    debugPrint('[NotificationTap] NotificationController.onChatClose: $clean');
    if (_openChatId == clean) {
      _openChatId = null;
    }
  }

  /// Check if the given chat is currently open
  static bool isChatOpen(String? chatId) {
    if (chatId == null || chatId.trim().isEmpty) return false;
    final isOpen = _openChatId == chatId.trim();
    return isOpen;
  }

  /// Reset state for test isolation
  static void resetForTesting() {
    _onTap = null;
    _pendingChatId = null;
    _openChatId = null;
    _lastTapHandledAt = null;
    _lastTapHandledChatId = null;
  }
}
