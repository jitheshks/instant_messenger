import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:instant_messenger/controller/notification_controller.dart';


/// Local notification service used for:
/// - Showing foreground notifications when OneSignal triggers foreground handler
/// - Displaying WhatsApp-style grouped messages
/// - Handling tap → open correct chatId
class NotificationService {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static const _channelId = 'chat_messages';
  static const _channelName = 'Chat messages';
  static const _channelDesc = 'Notifications for new chat messages';

  /// Generate a unique group key per chat thread
  static String _groupKeyFor(String chatId) => 'chat_$chatId';

  /// Initialize local notifications + create Android channel
  static Future<void> init() async {
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings();

    const settings = InitializationSettings(android: android, iOS: ios);

    await _plugin.initialize(
      settings,
      onDidReceiveNotificationResponse: (resp) {
        final payload = resp.payload;

        if (kDebugMode) {
          debugPrint('[NotificationService] Notification tapped payload=$payload');
        }

        if (payload == null || payload.isEmpty) return;

        // Extract chatId (payload may be plain or JSON)
        String? chatId;
        try {
          final map = jsonDecode(payload);
          if (map is Map<String, dynamic>) {
            chatId = map['chatId'] as String?;
          }
        } catch (_) {
          chatId = payload;
        }

        if (chatId != null) {
          NotificationController.onNotificationTap(chatId);
        }
      },
    );

    // Create Android channel
    final androidPlugin = _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();

    if (androidPlugin != null) {
      const channel = AndroidNotificationChannel(
        _channelId,
        _channelName,
        description: _channelDesc,
        importance: Importance.high,
        playSound: true,
      );

      await androidPlugin.createNotificationChannel(channel);

      if (kDebugMode) {
        debugPrint('[NotificationService] Android channel created: $_channelId');
      }
    }
  }

  /// Show a local notification (foreground case)
  static Future<void> showLocalNotification({
    required String chatId,
    required String title,
    required String body,
  }) async {
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

    // Each notification ID must be unique
    final id = chatId.hashCode ^ DateTime.now().microsecondsSinceEpoch;

    await _plugin.show(
      id,
      title,
      body,
      notifDetails,
      payload: jsonEncode({'chatId': chatId}),
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

    await _plugin.show(
      groupKey.hashCode,
      'New messages',
      '',
      NotificationDetails(android: summaryAndroid),
      payload: jsonEncode({'chatId': chatId}),
    );
  }
}
