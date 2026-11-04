import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:instant_messenger/features/notifications/data/notification_id_generator.dart';
import 'package:instant_messenger/features/notifications/domain/models/notification_payload.dart';

/// Local notification service used for:
/// - Showing foreground notifications when OneSignal triggers foreground handler
/// - Displaying WhatsApp-style grouped messages
/// - Handling tap → open correct chatId
class NotificationService {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  /// Notification tap handler callback
  static void Function(String chatId)? onTap;

  /// Unified payload notification tap handler callback
  static void Function(NotificationPayload payload)? onPayloadTap;

  /// Pending payload if notification tapped before coordinator is ready
  static NotificationPayload? pendingNotificationPayload;

  static NotificationPayload? consumePendingNotificationPayload() {
    final p = pendingNotificationPayload;
    pendingNotificationPayload = null;
    return p;
  }

  static const _channelId = 'chat_messages';
  static const _channelName = 'Chat messages';
  static const _channelDesc = 'Notifications for new chat messages';

  /// Generate a unique group key per chat thread
  static String _groupKeyFor(String chatId) => 'chat_$chatId';

  /// Initialize local notifications + create Android channel
  static Future<void> init() async {
    const android = AndroidInitializationSettings('@mipmap/launcher_icon');
    const ios = DarwinInitializationSettings();

    const settings = InitializationSettings(android: android, iOS: ios);

    await _plugin.initialize(
      settings: settings,
      onDidReceiveNotificationResponse: (resp) {
        final rawPayload = resp.payload;

        debugPrint(
          '[NotificationTap] NotificationService local notification tapped: payload=$rawPayload, actionId=${resp.actionId}',
        );

        if (rawPayload == null || rawPayload.isEmpty) {
          debugPrint('[NotificationTap] ⚠️ Local notification payload was empty');
          return;
        }

        final normalized = NotificationPayload.fromStringPayload(
          rawPayload,
          actionId: resp.actionId,
        );

        if (onPayloadTap != null) {
          debugPrint(
            '[NotificationTap] Local notification dispatching normalized payload: $normalized',
          );
          onPayloadTap!(normalized);
        } else {
          pendingNotificationPayload = normalized;
          if (normalized.chatId != null && normalized.chatId!.isNotEmpty) {
            onTap?.call(normalized.chatId!);
          }
        }
      },
    );

    // 🔹 Cold-start: Check if local notification launched the application from terminated state
    try {
      final launchDetails = await _plugin.getNotificationAppLaunchDetails();
      if (launchDetails?.didNotificationLaunchApp == true) {
        final rawPayload = launchDetails?.notificationResponse?.payload;
        debugPrint(
          '[NotificationTap] App cold-started by local notification: payload=$rawPayload',
        );
        if (rawPayload != null && rawPayload.isNotEmpty) {
          final normalized = NotificationPayload.fromStringPayload(
            rawPayload,
            actionId: launchDetails?.notificationResponse?.actionId,
          );
          if (onPayloadTap != null) {
            debugPrint(
              '[NotificationTap] Cold-start local notification dispatching normalized payload: $normalized',
            );
            onPayloadTap!(normalized);
          } else {
            pendingNotificationPayload = normalized;
            if (normalized.chatId != null && normalized.chatId!.isNotEmpty) {
              onTap?.call(normalized.chatId!);
            }
          }
        }
      }
    } catch (e) {
      debugPrint('[NotificationTap] Error checking notification launch details: $e');
    }

    // Create Android channel
    final androidPlugin = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();

    if (androidPlugin != null) {
      const channel = AndroidNotificationChannel(
        _channelId,
        _channelName,
        description: _channelDesc,
        importance: Importance.high,
        playSound: true,
      );

      await androidPlugin.createNotificationChannel(channel);

      const callsChannel = AndroidNotificationChannel(
        'calls',
        'Calls',
        description: 'Notifications for incoming voice and video calls',
        importance: Importance.max,
        playSound: true,
      );

      await androidPlugin.createNotificationChannel(callsChannel);

      if (kDebugMode) {
        debugPrint(
          '[NotificationService] Android channels created: $_channelId, calls',
        );
      }
    }
  }

  /// Show a local notification (foreground case)
  static Future<void> showLocalNotification({
    required String chatId,
    required String title,
    required String body,
    String? messageId,
  }) async {
    final cleanTitle = title.trim().isEmpty ? 'New message' : title.trim();
    final groupKey = _groupKeyFor(chatId);

    final androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDesc,
      importance: Importance.high,
      priority: Priority.high,
      category: AndroidNotificationCategory.message,
      groupKey: groupKey,
      styleInformation: BigTextStyleInformation(body),
    );

    final notifDetails = NotificationDetails(android: androidDetails);

    // Generate safe, deterministic 31-bit positive notification ID [0, 2147483647]
    final id = NotificationIdGenerator.generateMessageNotificationId(
      chatId: chatId,
      messageId: messageId,
    );
    NotificationIdGenerator.validateNotificationId(id);

    await _plugin.show(
      id: id,
      title: cleanTitle,
      body: body,
      notificationDetails: notifDetails,
      payload: jsonEncode({
        'chatId': chatId,
        if (messageId != null && messageId.isNotEmpty) 'messageId': messageId,
        'type': 'chat',
      }),
    );

    // Summary notification (required for grouping)
    final summaryAndroid = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDesc,
      setAsGroupSummary: true,
      groupKey: groupKey,
      importance: Importance.high,
      priority: Priority.high,
      styleInformation: const InboxStyleInformation(
        [],
        contentTitle: 'New messages',
        summaryText: 'You have new messages',
      ),
    );

    final summaryId =
        NotificationIdGenerator.generateGroupSummaryNotificationId(chatId);
    NotificationIdGenerator.validateNotificationId(summaryId);

    await _plugin.show(
      id: summaryId,
      title: 'New messages',
      body: '',
      notificationDetails: NotificationDetails(android: summaryAndroid),
      payload: jsonEncode({'chatId': chatId}),
    );
  }

  /// Cancels the group summary notification for a given chat thread.
  static Future<void> cancelChatGroupSummary(String chatId) async {
    final summaryId =
        NotificationIdGenerator.generateGroupSummaryNotificationId(chatId);
    await _plugin.cancel(id: summaryId);
  }

  /// Cancels a specific message notification.
  static Future<void> cancelMessageNotification({
    required String chatId,
    required String messageId,
  }) async {
    final id = NotificationIdGenerator.generateMessageNotificationId(
      chatId: chatId,
      messageId: messageId,
    );
    await _plugin.cancel(id: id);
  }
}


