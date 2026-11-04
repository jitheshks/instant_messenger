import 'dart:async';
import 'dart:ui';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:instant_messenger/core/utils/app_info_service.dart';
import 'package:instant_messenger/features/notifications/data/background_delivery_ack_service.dart';
import 'package:instant_messenger/features/notifications/data/notification_service.dart';
import 'package:instant_messenger/features/notifications/data/onesignal_service.dart';
import 'package:instant_messenger/features/notifications/domain/models/notification_payload.dart';
import 'package:instant_messenger/firebase_options.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Top-level background message handler required by FirebaseMessaging.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    WidgetsFlutterBinding.ensureInitialized();
    try {
      DartPluginRegistrant.ensureInitialized();
    } catch (_) {}
  } catch (_) {}

  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    }
  } catch (e) {
    debugPrint('[FcmService] Background handler Firebase init notice: $e');
  }

  if (kDebugMode) {
    debugPrint(
      '[FcmService] Handling background message id=${message.messageId} data=${message.data}',
    );
  }

  // Acknowledge delivery to Supabase so sender gets double tick
  try {
    await BackgroundDeliveryAckService.acknowledgeFromRemoteMessage(message);
  } catch (e) {
    debugPrint('[FcmService] Background delivery acknowledgement notice: $e');
  }
}

typedef NotificationDisplayDelegate = Future<void> Function({
  required String chatId,
  required String title,
  required String body,
});

/// Firebase Cloud Messaging (FCM) client service.
///
/// Handles:
/// - Firebase Core initialization across supported platforms
/// - FCM permission requests
/// - Token acquisition, refresh, and storage in Supabase `user_devices`
/// - Sign-out token deregistration and account isolation
/// - Foreground notification suppression when targeted chat is currently open
/// - Warm and cold-start notification tap navigation via [NotificationService.onTap]
class FcmService {
  /// Callback invoked when a notification is tapped to navigate to the chat.
  static void Function(String chatId)? onTap;

  /// Callback for unified notification payload click navigation
  static void Function(NotificationPayload payload)? onPayloadTap;

  /// Holds a pending normalized notification payload if clicked before coordinator is ready
  static NotificationPayload? pendingNotificationPayload;

  /// Consumes and clears any pending normalized notification payload
  static NotificationPayload? consumePendingNotificationPayload() {
    final p = pendingNotificationPayload;
    if (p != null) {
      debugPrint(
        '[NotificationTap] FcmService.consumePendingNotificationPayload consumed: $p',
      );
    }
    pendingNotificationPayload = null;
    return p;
  }

  /// Delegate invoked to check whether a specific chat screen is open in the foreground.
  static bool Function(String? chatId)? isChatOpenDelegate;

  /// UUID validation pattern for message IDs
  static final RegExp uuidRegex = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
    caseSensitive: false,
  );
  static RegExp get _uuidRegex => uuidRegex;

  final FirebaseMessaging? _messagingClient;
  final SupabaseClient? _supabaseClient;
  final AppInfoService _appInfo;
  final bool Function()? _platformChecker;
  final NotificationDisplayDelegate _notificationDisplay;

  String? _currentToken;
  String? _currentUid;
  bool _initialized = false;
  StreamSubscription<RemoteMessage>? _foregroundSubscription;
  StreamSubscription<RemoteMessage>? _messageOpenedSubscription;
  StreamSubscription<String>? _tokenRefreshSubscription;

  FcmService({
    FirebaseMessaging? messaging,
    SupabaseClient? supabaseClient,
    AppInfoService? appInfo,
    bool Function()? platformChecker,
    NotificationDisplayDelegate? notificationDisplayDelegate,
  })  : _messagingClient = messaging,
        _supabaseClient = supabaseClient,
        _appInfo = appInfo ?? AppInfoService(),
        _platformChecker = platformChecker,
        _notificationDisplay =
            notificationDisplayDelegate ?? NotificationService.showLocalNotification;

  FirebaseMessaging get _messaging =>
      _messagingClient ?? FirebaseMessaging.instance;

  SupabaseClient get _supabase =>
      _supabaseClient ?? Supabase.instance.client;

  String? get currentToken => _currentToken;
  bool get isInitialized => _initialized;

  /// Normalizes platform string to standard lowercase names ('android', 'ios', 'web').
  /// Returns null for unsupported platforms.
  static String? normalizePlatform(String? platform) {
    if (platform == null) return null;
    final clean = platform.trim().toLowerCase();
    if (clean.contains('android')) return 'android';
    if (clean.contains('ios')) return 'ios';
    if (clean == 'web') return 'web';
    return null;
  }

  /// Whether the platform supports FCM notifications.
  static bool isSupportedPlatform({
    TargetPlatform? targetPlatform,
    bool isWeb = false,
  }) {
    if (isWeb) return true;
    final tp = targetPlatform ?? defaultTargetPlatform;
    return tp == TargetPlatform.android || tp == TargetPlatform.iOS;
  }

  /// Builds a validated device registration payload matching `user_devices` schema.
  static Map<String, dynamic> buildDevicePayload({
    required String uid,
    required String token,
    required String platform,
    String? appVersion,
    bool subscribed = true,
    DateTime? timestamp,
  }) {
    final normalized = normalizePlatform(platform);
    if (normalized == null) {
      throw ArgumentError(
        'Platform "$platform" is unsupported for FCM. Must be android, ios, or web.',
      );
    }
    final now = (timestamp ?? DateTime.now()).toUtc();
    return {
      'user_id': uid,
      'player_id': token,
      'platform': normalized,
      if (appVersion != null && appVersion.trim().isNotEmpty)
        'app_version': appVersion.trim(),
      'subscribed': subscribed,
      'last_seen': now.toIso8601String(),
    };
  }

  /// Persists device payload to Supabase `user_devices`.
  Future<bool> persistDeviceRecord(Map<String, dynamic> payload) async {
    try {
      await _supabase.from('user_devices').upsert(
            payload,
            onConflict: 'player_id',
          );
      return true;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[FcmService] Persist FCM token error: $e');
      }
      return false;
    }
  }

  /// Whether FCM push notifications are supported on the current platform.
  bool get isPlatformSupported {
    if (_platformChecker != null) return _platformChecker();
    return isSupportedPlatform(isWeb: kIsWeb);
  }

  /// Initializes Firebase Core if not already initialized.
  ///
  /// Safe to call multiple times; returns silently if already initialized or
  /// if running on an unsupported platform.
  static Future<bool> initializeFirebase() async {
    try {
      if (Firebase.apps.isNotEmpty) {
        return true;
      }

      if (kIsWeb) {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
        return true;
      }

      if (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS) {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
        return true;
      }

      if (kDebugMode) {
        debugPrint(
          '[FcmService] Firebase init skipped: unsupported platform ($defaultTargetPlatform).',
        );
      }
      return false;
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('[FcmService] Firebase.initializeApp notice: $e');
        debugPrintStack(stackTrace: st);
      }
      return false;
    }
  }

  /// Initializes Firebase Core and registers the top-level background handler.
  ///
  /// Safe to call during app bootstrap.
  static Future<void> registerBackgroundHandler() async {
    try {
      final initialized = await initializeFirebase();
      if (initialized) {
        FirebaseMessaging.onBackgroundMessage(
          firebaseMessagingBackgroundHandler,
        );
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[FcmService] registerBackgroundHandler notice: $e');
      }
    }
  }

  /// Inspects whether the app was cold-started from an FCM notification tap.
  /// Safe to call early during app bootstrap in main().
  static Future<void> checkColdStartTap() async {
    if (!isSupportedPlatform()) return;
    try {
      final initialized = await initializeFirebase();
      if (!initialized) return;

      final initialMessage =
          await FirebaseMessaging.instance.getInitialMessage();
      if (initialMessage != null) {
        if (kDebugMode) {
          debugPrint(
            '[FcmService] Cold-start message detected early: id=${initialMessage.messageId}',
          );
        }
        final data = initialMessage.data;
        final normalizedPayload = NotificationPayload.fromMap(data);
        if (onPayloadTap != null) {
          onPayloadTap!(normalizedPayload);
        } else {
          pendingNotificationPayload = normalizedPayload;
          if (normalizedPayload.chatId != null &&
              normalizedPayload.chatId!.isNotEmpty) {
            onTap?.call(normalizedPayload.chatId!);
          }
        }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[FcmService] checkColdStartTap notice: $e');
      }
    }
  }

  /// Initializes FCM client, requests permissions, registers device token,
  /// and attaches foreground/tap notification listeners.
  Future<String?> init({
    required String uid,
    bool promptPermission = true,
    bool persistToSupabase = true,
  }) async {
    _currentUid = uid;

    if (!isPlatformSupported) {
      if (kDebugMode) {
        debugPrint(
          '[FcmService] FCM initialization skipped: platform is unsupported ($defaultTargetPlatform).',
        );
      }
      return null;
    }

    try {
      await initializeFirebase();

      if (promptPermission) {
        final settings = await _messaging.requestPermission(
          alert: true,
          badge: true,
          sound: true,
          provisional: false,
        );

        if (kDebugMode) {
          debugPrint(
            '[FcmService] Notification authorization status: ${settings.authorizationStatus}',
          );
        }
      }

      // Configure foreground presentation options for iOS
      await _messaging.setForegroundNotificationPresentationOptions(
        alert: false, // Handled manually via NotificationService
        badge: true,
        sound: true,
      );

      // Acquire initial FCM token
      try {
        _currentToken = await _messaging.getToken();
        if (kDebugMode) {
          debugPrint('[FcmService] FCM registration token acquired: $_currentToken');
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint('[FcmService] getToken error: $e');
        }
      }

      // Persist token to Supabase user_devices only when requested
      if (persistToSupabase && _currentToken != null && _currentToken!.isNotEmpty) {
        await _persistToken(uid, _currentToken!);
      }

      // Wire listeners
      _wireListeners(uid, persistToSupabase: persistToSupabase);

      // Check cold-start notification launch
      await _checkInitialMessage();

      _initialized = true;
      return _currentToken;
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('[FcmService] init error: $e');
        debugPrintStack(stackTrace: st);
      }
      return null;
    }
  }

  void _wireListeners(String uid, {bool persistToSupabase = true}) {
    // 1. Token refresh listener
    _tokenRefreshSubscription?.cancel();
    _tokenRefreshSubscription = _messaging.onTokenRefresh.listen((newToken) async {
      if (kDebugMode) {
        debugPrint('[FcmService] FCM token refreshed: $newToken');
      }
      _currentToken = newToken;
      if (persistToSupabase && _currentUid != null && _currentUid!.isNotEmpty) {
        await _persistToken(_currentUid!, newToken);
      }
    });

    // 2. Foreground message listener
    _foregroundSubscription?.cancel();
    _foregroundSubscription = FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
      await _handleForegroundMessage(message);
    });

    // 3. Warm-start notification tap listener (app was in background)
    _messageOpenedSubscription?.cancel();
    _messageOpenedSubscription = FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      _handleNotificationTap(message);
    });
  }

  /// Inspects whether the app was cold-started from an FCM notification tap.
  Future<void> _checkInitialMessage() async {
    try {
      final initialMessage = await _messaging.getInitialMessage();
      if (initialMessage != null) {
        if (kDebugMode) {
          debugPrint(
            '[FcmService] Cold-start message detected: id=${initialMessage.messageId}',
          );
        }
        _handleNotificationTap(initialMessage);
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[FcmService] getInitialMessage error: $e');
      }
    }
  }

  /// Handles incoming foreground messages.
  /// Suppresses display if user is actively in the targeted chat.
  Future<void> _handleForegroundMessage(RemoteMessage message) async {
    final data = message.data;
    final chatId = data['chatId'] ?? data['chat_id'];
    final messageId = data['messageId'] ?? data['message_id'];

    if (kDebugMode) {
      debugPrint('[FcmService] Foreground message received: chatId=$chatId msgId=$messageId');
    }

    // Mark delivered in Supabase
    if (messageId != null && _uuidRegex.hasMatch(messageId.trim())) {
      final receiptToken =
          (data['receiptToken'] ?? data['receipt_token'])?.toString().trim();
      if (receiptToken != null && receiptToken.isNotEmpty) {
        try {
          await _supabase.rpc(
            'acknowledge_delivery_token',
            params: {
              'p_message_id': messageId.trim(),
              'p_receipt_token': receiptToken,
            },
          );
        } catch (_) {}
      } else {
        try {
          await _supabase.rpc(
            'promote_message_status',
            params: {
              'p_message_ids': [messageId.trim()],
              'p_new_status': 2,
            },
          );
        } catch (_) {}
      }
    }

    // Suppress notification if user is inside the same conversation
    if (chatId != null && (isChatOpenDelegate?.call(chatId) ?? false)) {
      if (kDebugMode) {
        debugPrint('[FcmService] Chat $chatId is currently open; suppressing local alert.');
      }
      return;
    }

    // Otherwise show local heads-up notification
    final rawPhone = (data['senderPhone'] ?? data['sender_phone'])?.toString().trim();
    final cleanPhone = (rawPhone != null && rawPhone.isNotEmpty) ? rawPhone : null;
    final title = cleanPhone != null
        ? ((OneSignalService.resolveContactDelegate?.call(cleanPhone)) ?? cleanPhone)
        : (data['senderName'] ?? data['sender_name'] ?? message.notification?.title ?? 'New message');
    final body = message.notification?.body ?? data['preview'] ?? 'You received a message';
    if (chatId != null && chatId.isNotEmpty) {
      if (identical(_notificationDisplay, NotificationService.showLocalNotification)) {
        final cleanMsgId = messageId?.toString().trim();
        await NotificationService.showLocalNotification(
          chatId: chatId,
          title: title,
          body: body,
          messageId: cleanMsgId,
        );
      } else {
        await _notificationDisplay(
          chatId: chatId,
          title: title,
          body: body,
        );
      }
    }
  }

  /// Handles user tapping an FCM notification.
  void _handleNotificationTap(RemoteMessage message) {
    final data = message.data;
    final normalizedPayload = NotificationPayload.fromMap(data);

    if (kDebugMode) {
      debugPrint('[FcmService] Notification tapped: $normalizedPayload');
    }

    final messageId = normalizedPayload.messageId;
    // Mark delivered when opened
    if (messageId != null && _uuidRegex.hasMatch(messageId.trim())) {
      final receiptToken =
          (data['receiptToken'] ?? data['receipt_token'])?.toString().trim();
      if (receiptToken != null && receiptToken.isNotEmpty) {
        try {
          _supabase.rpc(
            'acknowledge_delivery_token',
            params: {
              'p_message_id': messageId.trim(),
              'p_receipt_token': receiptToken,
            },
          ).catchError((_) {});
        } catch (_) {}
      } else {
        try {
          _supabase.rpc(
            'promote_message_status',
            params: {
              'p_message_ids': [messageId.trim()],
              'p_new_status': 2,
            },
          ).catchError((_) {});
        } catch (_) {}
      }
    }

    if (onPayloadTap != null) {
      onPayloadTap!(normalizedPayload);
    } else {
      pendingNotificationPayload = normalizedPayload;
      if (normalizedPayload.chatId != null && normalizedPayload.chatId!.isNotEmpty) {
        onTap?.call(normalizedPayload.chatId!);
      }
    }
  }

  /// Persists the FCM token to Supabase `user_devices`.
  Future<bool> _persistToken(String uid, String token) async {
    if (uid.isEmpty || token.isEmpty) return false;

    try {
      final appVersion = await _appInfo.versionPlusBuild();
      final platform = defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android';

      final payload = buildDevicePayload(
        uid: uid,
        token: token,
        platform: platform,
        appVersion: appVersion,
        subscribed: true,
      );

      final success = await persistDeviceRecord(payload);
      if (success && kDebugMode) {
        debugPrint('[FcmService] Persisted FCM token to Supabase user_devices for uid=$uid');
      }
      return success;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[FcmService] Persist FCM token error: $e');
      }
      return false;
    }
  }

  /// Cleans up FCM token upon user sign-out or account switch.
  Future<void> cleanupOnSignOut(String uid) async {
    var token = _currentToken;
    final cleanUid = uid.trim();

    // Fallback: if token is not cached in memory, try retrieving before deregistration
    if ((token == null || token.isEmpty) && isPlatformSupported) {
      try {
        token = await _messaging.getToken();
      } catch (_) {}
    }

    if (token != null && token.isNotEmpty && cleanUid.isNotEmpty) {
      try {
        await _supabase
            .from('user_devices')
            .delete()
            .match({'user_id': cleanUid, 'player_id': token});

        if (kDebugMode) {
          debugPrint('[FcmService] Removed FCM token from user_devices for uid=$cleanUid');
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint('[FcmService] cleanupOnSignOut error: $e');
        }
      }
    }

    try {
      await _messaging.deleteToken();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[FcmService] deleteToken notice: $e');
      }
    }

    _foregroundSubscription?.cancel();
    _messageOpenedSubscription?.cancel();
    _tokenRefreshSubscription?.cancel();

    _currentToken = null;
    _currentUid = null;
    _initialized = false;
  }

  @visibleForTesting
  Future<void> handleForegroundMessageForTesting(RemoteMessage message) =>
      _handleForegroundMessage(message);

  @visibleForTesting
  void handleNotificationTapForTesting(RemoteMessage message) =>
      _handleNotificationTap(message);

  @visibleForTesting
  void setCurrentTokenForTesting(String? token) => _currentToken = token;

  @visibleForTesting
  void setCurrentUidForTesting(String? uid) => _currentUid = uid;
}
