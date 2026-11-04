// lib/services/onesignal_service.dart
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:instant_messenger/core/utils/app_info_service.dart';
import 'package:instant_messenger/features/notifications/data/notification_service.dart';
import 'package:instant_messenger/features/notifications/data/onesignal_device_helper.dart';
import 'package:instant_messenger/features/notifications/domain/models/notification_payload.dart';

/// Represents an incoming or active call notification payload with user intent.
class CallNotificationAction {
  final String callId;
  final String callerId;
  final String callerName;
  final String callType;
  final bool isAccepted;

  const CallNotificationAction({
    required this.callId,
    required this.callerId,
    required this.callerName,
    required this.callType,
    this.isAccepted = false,
  });
}

/// Mobile-only OneSignal service (v5+ namespaced API).
class OneSignalService {
  /// Callback for unified notification payload click navigation
  static void Function(NotificationPayload payload)? onPayloadTap;

  /// Holds a pending normalized notification payload if clicked before coordinator is ready
  static NotificationPayload? pendingNotificationPayload;

  /// Consumes and clears any pending normalized notification payload
  static NotificationPayload? consumePendingNotificationPayload() {
    final p = pendingNotificationPayload;
    if (p != null) {
      debugPrint(
        '[NotificationTap] OneSignalService.consumePendingNotificationPayload consumed: $p',
      );
    }
    pendingNotificationPayload = null;
    return p;
  }

  /// Callback for notification click navigation
  static void Function(String chatId)? onTap;

  /// Callback for incoming call notification interaction (tap or accept action)
  static void Function(CallNotificationAction action)? onCallAction;

  /// Callback for declining a call via notification action button
  static Future<void> Function(String callId)? onCallDecline;

  /// Holds a pending call notification action if a tap arrives before listener is registered
  static CallNotificationAction? pendingCallAction;

  /// Consumes and clears any pending call notification action
  static CallNotificationAction? consumePendingCallAction() {
    final action = pendingCallAction;
    if (action != null) {
      debugPrint(
        '[NotificationTap] OneSignalService.consumePendingCallAction consumed: ${action.callId}',
      );
    }
    pendingCallAction = null;
    return action;
  }

  /// Delegate to check if chat is currently open
  static bool Function(String? chatId)? isChatOpenDelegate;

  /// Callback to resolve contact name for a given phone number
  static String Function(String? phoneE164)? resolveContactDelegate;

  /// Holds a pending notification chat ID if a tap arrives before onTap is registered
  static String? pendingNotificationChatId;

  /// Consumes and clears any pending notification chat ID
  static String? consumePendingNotificationChatId() {
    final id = pendingNotificationChatId;
    if (id != null) {
      debugPrint(
        '[NotificationTap] OneSignalService.consumePendingNotificationChatId consumed: $id',
      );
    }
    pendingNotificationChatId = null;
    return id;
  }

  /// Safely extracts and trims a chat identifier from a notification payload.
  /// Supports 'chatId', 'chat_id', and legacy 'chat' keys.
  static String? extractChatIdFromPayload(Map<dynamic, dynamic>? data) {
    if (data == null) return null;
    final rawChatId = data['chatId'] ?? data['chat_id'] ?? data['chat'];
    if (rawChatId == null) return null;
    final clean = rawChatId.toString().trim();
    return clean.isEmpty ? null : clean;
  }

  static bool _earlyInitialized = false;
  static bool _clickListenerWired = false;

  /// Internal unified handler for notification click events.
  static Future<void> _handleNotificationClick(
    OSNotificationClickEvent event,
  ) async {
    debugPrint(
      '[NotificationTap] OneSignal.Notifications.addClickListener received event',
    );
    try {
      final data = event.notification.additionalData;
      debugPrint(
        '[NotificationTap] Notification payload parsed: rawData=$data',
      );

      // Dispatch unified payload via NotificationNavigationCoordinator
      final normalizedPayload = NotificationPayload.fromMap(
        data,
        actionId: event.result.actionId,
      );

      if (onPayloadTap != null) {
        debugPrint(
          '[NotificationTap] OneSignalService dispatching normalized payload: $normalizedPayload',
        );
        onPayloadTap!(normalizedPayload);
      } else {
        debugPrint(
          '[NotificationTap] OneSignalService onPayloadTap is null; buffering in pendingNotificationPayload: $normalizedPayload',
        );
        pendingNotificationPayload = normalizedPayload;
      }

      final isCall = (data?['type'] == 'call') ||
          (data?['callId'] != null) ||
          (data?['call_id'] != null);

      if (isCall) {
        final callId =
            (data?['callId'] ?? data?['call_id'])?.toString().trim();
        final callerId =
            (data?['callerId'] ?? data?['caller_id'])?.toString().trim() ?? '';
        final callerName =
            (data?['callerName'] ?? data?['caller_name'])?.toString().trim() ??
                'Caller';
        final callType =
            (data?['callType'] ?? data?['call_type'])?.toString().trim() ??
                'audio';
        final actionId = event.result.actionId?.trim().toLowerCase();

        debugPrint(
          '[NotificationTap] Call notification clicked: callId=$callId, actionId=$actionId, callType=$callType',
        );

        if (actionId == 'decline' || actionId == 'reject') {
          if (callId != null && callId.isNotEmpty) {
            if (onCallDecline != null) {
              await onCallDecline!(callId);
            } else {
              try {
                await Supabase.instance.client.rpc(
                  'reject_call',
                  params: {'p_call_id': callId},
                );
              } catch (e) {
                debugPrint(
                  '[NotificationTap] Error rejecting call on notification action: $e',
                );
              }
            }
          }
          return;
        }

        final isAccepted = actionId == 'accept';
        if (callId != null && callId.isNotEmpty) {
          final action = CallNotificationAction(
            callId: callId,
            callerId: callerId,
            callerName: callerName,
            callType: callType,
            isAccepted: isAccepted,
          );

          if (onCallAction != null) {
            debugPrint(
              '[NotificationTap] OneSignalService invoking onCallAction callback for callId: $callId',
            );
            onCallAction!(action);
          } else {
            debugPrint(
              '[NotificationTap] OneSignalService onCallAction is null; buffering in pendingCallAction: $callId',
            );
            pendingCallAction = action;
          }
        }
        return;
      }

      final chatId = extractChatIdFromPayload(data);
      debugPrint('[NotificationTap] chatId extracted: "$chatId"');

      final rawMessageId =
          data != null ? (data['messageId'] ?? data['message_id']) : null;
      final messageId = rawMessageId?.toString().trim();
      final receiptToken =
          data != null ? (data['receiptToken'] ?? data['receipt_token'])?.toString().trim() : null;

      // 🔹 Mark delivered when notification is opened
      if (chatId != null && messageId != null && messageId.isNotEmpty) {
        if (receiptToken != null && receiptToken.isNotEmpty) {
          try {
            await Supabase.instance.client.rpc(
              'acknowledge_delivery_token',
              params: {
                'p_message_id': messageId,
                'p_receipt_token': receiptToken,
              },
            );
          } catch (_) {}
        } else {
          try {
            await Supabase.instance.client.rpc(
              'promote_message_status',
              params: {
                'p_message_ids': [messageId],
                'p_new_status': 2,
              },
            );
          } catch (_) {}
        }
      }

      // 🔹 Navigation logic (support pending cold-start clicks)
      if (chatId != null) {
        if (onTap != null) {
          debugPrint(
            '[NotificationTap] OneSignalService invoking onTap callback with chatId: $chatId',
          );
          onTap!(chatId);
        } else {
          debugPrint(
            '[NotificationTap] OneSignalService onTap is null; buffering in pendingNotificationChatId: $chatId',
          );
          pendingNotificationChatId = chatId;
        }
      } else {
        debugPrint(
          '[NotificationTap] ⚠️ No valid chatId found in notification data; skipping navigation',
        );
      }
    } catch (e, st) {
      debugPrint('[NotificationTap] Error in click listener: $e\n$st');
    }
  }

  /// Early SDK initialization and click-listener wiring during app boot in main().
  /// Does not require user authentication.
  static void initializeEarly(String appId) {
    if (!isSupportedPlatform()) return;
    final cleanAppId = appId.trim();
    if (cleanAppId.isEmpty) return;
    if (_earlyInitialized) return;
    _earlyInitialized = true;

    try {
      OneSignal.Debug.setLogLevel(OSLogLevel.verbose);
      OneSignal.Debug.setAlertLevel(OSLogLevel.none);
      OneSignal.initialize(cleanAppId);
      debugPrint(
        '[NotificationTap] OneSignalService.initializeEarly completed with appId: $cleanAppId',
      );

      // Wire native click listener immediately on cold start (once)
      if (!_clickListenerWired) {
        OneSignal.Notifications.addClickListener(_handleNotificationClick);
        _clickListenerWired = true;
        debugPrint('[NotificationTap] Early click listener wired successfully');
      }
    } catch (e) {
      debugPrint('[NotificationTap] OneSignalService.initializeEarly notice: $e');
    }
  }

  /// Callback invoked when a new push subscription ID is assigned or updated.
  void Function(String playerId)? onSubscriptionChanged;

  final AppInfoService _appInfo;
  final SupabaseClient? _supabaseClient;
  final bool Function()? _platformChecker;
  final Future<void> Function()? _oneSignalLogout;
  bool _wired = false;
  String? _currentUid;

  final Map<String, Timer> _persistTimers = {};
  final Map<String, DateTime> _lastPersistAt = {};

  OneSignalService([
    @Deprecated('Firestore is obsolete and unused.') Object? legacyDb,
    AppInfoService? appInfo,
    SupabaseClient? client,
    bool Function()? platformChecker,
    Future<void> Function()? oneSignalLogout,
  ]) : _appInfo = appInfo ?? AppInfoService(),
       _supabaseClient = client,
       _platformChecker = platformChecker,
       _oneSignalLogout = oneSignalLogout;

  SupabaseClient get _supabase => _supabaseClient ?? Supabase.instance.client;

  bool get isPlatformSupported =>
      _platformChecker?.call() ?? isSupportedPlatform();

  /// Initialize OneSignal (v5 namespaced). Returns push subscription id (player id).
  Future<String?> initialize({
    required String appId,
    required String uid,
    bool promptPermission = true,
  }) async {
    _currentUid = uid;

    if (!isPlatformSupported) {
      if (kDebugMode) {
        debugPrint(
          '[OneSignalService] Push notification initialization skipped on unsupported platform ($defaultTargetPlatform).',
        );
      }
      return null;
    }

    if (appId.trim().isEmpty) {
      if (kDebugMode) {
        debugPrint(
          '[OneSignalService] ⚠️ ONESIGNAL_APP_ID is not configured in environment. Push initialization skipped.',
        );
      }
      return null;
    }

    // Debug logging
    OneSignal.Debug.setLogLevel(OSLogLevel.verbose);
    OneSignal.Debug.setAlertLevel(OSLogLevel.none);

    // v5 initialization (namespaced)
    try {
      // 1️⃣ Initialize OneSignal SDK (REQUIRED)
      OneSignal.initialize(appId);
      if (kDebugMode) {
        debugPrint('[OneSignalService] initialize appId=$appId uid=$uid');
      }

      // Wire listeners early so push subscription changes during login are captured
      if (!_wired) {
        _wireListeners();
        _wired = true;
        if (kDebugMode) {
          debugPrint('[OneSignalService] listeners wired (namespaced API)');
        }
      }

      // 2️⃣ Bind OneSignal user to your app user (CRITICAL for chat apps)
      await OneSignal.login(uid);
      if (kDebugMode) {
        debugPrint('[OneSignalService] logged in uid=$uid');
      }

      // 3️⃣ Ensure push subscription is enabled (Android 13+ safe)
      try {
        await OneSignal.User.pushSubscription.optIn();
        if (kDebugMode) {
          debugPrint('[OneSignalService] pushSubscription optIn()');
        }
      } catch (_) {
        // Safe to ignore — optIn may fail on older SDKs / devices
      }

      // 4️⃣ Ensure notifications are enabled on the device (Android 13+ runtime permissions)
      if (promptPermission) {
        try {
          await OneSignal.Notifications.requestPermission(true);
          if (kDebugMode) {
            debugPrint('[OneSignalService] requested notification permission');
          }
        } catch (e) {
          if (kDebugMode) {
            debugPrint('[OneSignalService] requestPermission failed: $e');
          }
        }
      }
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('[OneSignalService] initialize/login error: $e');
        debugPrintStack(stackTrace: st);
      }
    }

    // Get push subscription id (player id)
    String? playerId;
    try {
      playerId = OneSignal.User.pushSubscription.id;
      if (kDebugMode) {
        debugPrint('[OneSignalService] current playerId=$playerId');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[OneSignalService] reading pushSubscription.id failed: $e');
      }
      playerId = null;
    }

    if (playerId != null && uid.isNotEmpty && isValidSubscriptionId(playerId)) {
      onSubscriptionChanged?.call(playerId);
      await _schedulePersist(uid: uid, playerId: playerId);
    }

    return playerId;
  }

  void _wireListeners() {
    // Notification click / opened (wire once)
    try {
      if (!_clickListenerWired) {
        OneSignal.Notifications.addClickListener(_handleNotificationClick);
        _clickListenerWired = true;
        debugPrint(
          '[NotificationTap] Registered OneSignal native click listener',
        );
      } else {
        debugPrint(
          '[NotificationTap] OneSignal native click listener already wired; skipping duplicate registration',
        );
      }
    } catch (e) {
      debugPrint('[NotificationTap] OneSignal addClickListener failed: $e');
    }

    // Foreground notification handling (WhatsApp-like)
    try {
      OneSignal.Notifications.addForegroundWillDisplayListener((event) async {
        debugPrint(
          '[NotificationTap] OneSignal.Notifications.addForegroundWillDisplayListener received event',
        );
        final notification = event.notification;
        final data = notification.additionalData;

        final isCall = (data?['type'] == 'call') ||
            (data?['callId'] != null) ||
            (data?['call_id'] != null);

        if (isCall) {
          debugPrint(
            '[NotificationTap] Foreground call push notification received; presenting call interface',
          );
          event.preventDefault();

          final callId =
              (data?['callId'] ?? data?['call_id'])?.toString().trim();
          final callerId =
              (data?['callerId'] ?? data?['caller_id'])?.toString().trim() ?? '';
          final callerName =
              (data?['callerName'] ?? data?['caller_name'])?.toString().trim() ??
                  'Caller';
          final callType =
              (data?['callType'] ?? data?['call_type'])?.toString().trim() ??
                  'audio';

          if (callId != null && callId.isNotEmpty) {
            final action = CallNotificationAction(
              callId: callId,
              callerId: callerId,
              callerName: callerName,
              callType: callType,
              isAccepted: false,
            );

            if (onCallAction != null) {
              onCallAction!(action);
            } else {
              pendingCallAction = action;
            }
          }
          return;
        }

        final rawChatId =
            data?['chatId'] ?? data?['chat_id'] ?? data?['chat'];
        final incomingChatId = rawChatId?.toString().trim();
        final senderPhone =
            (data?['senderPhone'] ?? data?['sender_phone'])?.toString().trim();
        final rawMsgId = data?['messageId'] ?? data?['message_id'];
        final messageId = rawMsgId?.toString().trim();
        final receiptToken =
            (data?['receiptToken'] ?? data?['receipt_token'])?.toString().trim();

        // 🔹 Mark message as delivered immediately upon receiving notification
        if (incomingChatId != null && messageId != null && messageId.isNotEmpty) {
          if (receiptToken != null && receiptToken.isNotEmpty) {
            try {
              await _supabase.rpc(
                'acknowledge_delivery_token',
                params: {
                  'p_message_id': messageId,
                  'p_receipt_token': receiptToken,
                },
              );
            } catch (e) {
              debugPrint('[OneSignalService] acknowledge_delivery_token notice: $e');
            }
          } else {
            try {
              await _supabase.rpc(
                'promote_message_status',
                params: {
                  'p_message_ids': [messageId],
                  'p_new_status': 2,
                },
              );
            } catch (e) {
              debugPrint('[OneSignalService] promote_message_status notice: $e');
            }
          }
        }

        // 🔹 If user is inside SAME chat → suppress notification
        if (isChatOpenDelegate?.call(incomingChatId) ?? false) {
          debugPrint(
            '[NotificationTap] User is inside same chat ($incomingChatId); suppressing foreground alert',
          );
          event.preventDefault();
          return;
        }

        // 🔹 Otherwise SHOW notification with resolved contact name
        event.preventDefault();

        if (incomingChatId != null && incomingChatId.isNotEmpty) {
          final cleanPhone = (senderPhone != null && senderPhone.isNotEmpty)
              ? senderPhone
              : null;
          final resolvedTitle = resolveContactDelegate?.call(cleanPhone) ??
              cleanPhone ??
              'New message';
          final body = notification.body ?? '';

          debugPrint(
            '[NotificationTap] Showing local notification for chatId: $incomingChatId, messageId: $messageId, title: "$resolvedTitle"',
          );
          await NotificationService.showLocalNotification(
            chatId: incomingChatId,
            title: resolvedTitle,
            body: body,
            messageId: messageId,
          );
        }
      });
      debugPrint(
        '[NotificationTap] Registered OneSignal foreground will-display listener',
      );
    } catch (e, st) {
      debugPrint('[NotificationTap] OneSignal foreground listener error: $e');
      debugPrintStack(stackTrace: st);
    }

    // Push subscription observer
    try {
      OneSignal.User.pushSubscription.addObserver((dynamic state) {
        final uid = _currentUid;
        String? playerId;
        try {
          playerId = OneSignal.User.pushSubscription.id;
        } catch (_) {
          playerId = null;
        }
        if (kDebugMode) {
          debugPrint(
            '[OneSignalService] pushSubscription changed: id=$playerId',
          );
        }
        if (uid != null &&
            playerId != null &&
            isValidSubscriptionId(playerId)) {
          onSubscriptionChanged?.call(playerId);
          _schedulePersist(uid: uid, playerId: playerId);
        }
      });
    } catch (e) {
      if (kDebugMode) {
        debugPrint(
          '[OneSignalService] pushSubscription.addObserver failed: $e',
        );
      }
    }

    // Permission observer
    try {
      OneSignal.Notifications.addPermissionObserver((dynamic state) {
        final uid = _currentUid;
        String? playerId;
        try {
          playerId = OneSignal.User.pushSubscription.id;
        } catch (_) {
          playerId = null;
        }
        if (kDebugMode) {
          debugPrint('[OneSignalService] permission changed');
        }
        if (uid != null &&
            playerId != null &&
            isValidSubscriptionId(playerId)) {
          onSubscriptionChanged?.call(playerId);
          _schedulePersist(uid: uid, playerId: playerId);
        }
      });
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[OneSignalService] addPermissionObserver failed: $e');
      }
    }
  }

  Future<void> _schedulePersist({
    required String uid,
    required String playerId,
    Duration debounce = const Duration(milliseconds: 800),
  }) async {
    if (!isValidSubscriptionId(playerId)) return;
    _persistTimers[playerId]?.cancel();
    _persistTimers[playerId] = Timer(debounce, () async {
      final last = _lastPersistAt[playerId];
      if (last != null && DateTime.now().difference(last) < debounce) {
        if (kDebugMode) {
          debugPrint('[OneSignalService] skip persist (recent) pid=$playerId');
        }
        return;
      }
      await _persistPlayer(uid, playerId);
      _lastPersistAt[playerId] = DateTime.now();
    });
  }

  /// Checks whether an identifier is a valid OneSignal push subscription ID.
  static bool isValidSubscriptionId(String? id) =>
      OneSignalDeviceHelper.isValidSubscriptionId(id);

  /// Checks whether push notifications are supported on the target platform.
  static bool isSupportedPlatform({
    TargetPlatform? targetPlatform,
    bool isWeb = kIsWeb,
  }) => OneSignalDeviceHelper.isSupportedPlatform(
    targetPlatform: targetPlatform,
    isWeb: isWeb,
  );

  /// Normalizes a platform string to match the PostgreSQL constraint.
  static String? normalizePlatform(String? rawPlatform) =>
      OneSignalDeviceHelper.normalizePlatform(rawPlatform);

  /// Computes the subscription state from OneSignal SDK properties.
  static bool computeSubscribed({
    required bool? optedIn,
    required bool? permission,
  }) => OneSignalDeviceHelper.computeSubscribed(
    optedIn: optedIn,
    permission: permission,
  );

  /// Builds the canonical registration payload for `user_devices`.
  static Map<String, dynamic> buildDevicePayload({
    required String uid,
    required String playerId,
    required String platform,
    required String? appVersion,
    required bool subscribed,
    DateTime? timestamp,
  }) => OneSignalDeviceHelper.buildDevicePayload(
    uid: uid,
    playerId: playerId,
    platform: platform,
    appVersion: appVersion,
    subscribed: subscribed,
    timestamp: timestamp,
  );

  /// Registers the device push token using the authorized `register_device` RPC.
  Future<bool> registerDevice({
    required String playerId,
    required String platform,
    String? appVersion,
    bool subscribed = true,
  }) async {
    final cleanPid = playerId.trim();
    if (!isValidSubscriptionId(cleanPid)) {
      if (kDebugMode) {
        debugPrint(
          '[OneSignalService] skip registerDevice: invalid OneSignal subscription ID "$playerId"',
        );
      }
      return false;
    }

    final normalized = normalizePlatform(platform);
    if (normalized == null) {
      if (kDebugMode) {
        debugPrint(
          '[OneSignalService] skip registerDevice: unsupported platform "$platform"',
        );
      }
      return false;
    }

    try {
      await _supabase.rpc(
        'register_device',
        params: {
          'p_player_id': cleanPid,
          'p_platform': normalized,
          if (appVersion != null && appVersion.trim().isNotEmpty)
            'p_app_version': appVersion.trim()
          else
            'p_app_version': null,
          'p_subscribed': subscribed,
        },
      );
      if (kDebugMode) {
        debugPrint(
          '[OneSignalService] Successfully registered device via RPC: $cleanPid (platform: $normalized)',
        );
      }
      return true;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[OneSignalService] register_device RPC error: $e');
      }
      return false;
    }
  }

  /// Persists device registration via the authorized `register_device` RPC.
  Future<bool> persistDeviceRecord(
    Map<String, dynamic> payload, {
    String onConflict = 'player_id',
  }) async {
    final playerId = (payload['player_id'] as String?)?.trim() ?? '';
    final platform = (payload['platform'] as String?)?.trim() ?? 'android';
    final appVersion = (payload['app_version'] as String?)?.trim();
    final subscribed = payload['subscribed'] == true;

    return registerDevice(
      playerId: playerId,
      platform: platform,
      appVersion: appVersion,
      subscribed: subscribed,
    );
  }

  Future<void> _persistPlayer(String uid, String playerId) async {
    if (uid.isEmpty || !isValidSubscriptionId(playerId)) {
      if (kDebugMode) {
        debugPrint(
          '[OneSignalService] skip persist (uid="$uid", playerId="$playerId")',
        );
      }
      return;
    }

    if (!isPlatformSupported) {
      if (kDebugMode) {
        debugPrint(
          '[OneSignalService] skip persist on unsupported platform ($defaultTargetPlatform)',
        );
      }
      return;
    }

    try {
      bool? maybeOptedIn;
      try {
        maybeOptedIn = OneSignal.User.pushSubscription.optedIn;
      } catch (_) {
        maybeOptedIn = null;
      }

      bool? permission;
      try {
        permission = OneSignal.Notifications.permission;
      } catch (_) {
        permission = null;
      }

      final subscribed = computeSubscribed(
        optedIn: maybeOptedIn,
        permission: permission,
      );

      final device = await OneSignalDeviceHelper.collectDeviceInfo(_appInfo);
      final rawPlatform = device['platform'] as String?;
      final normalizedPlatform = normalizePlatform(rawPlatform);
      if (normalizedPlatform == null) {
        if (kDebugMode) {
          debugPrint(
            '[OneSignalService] skip persist: raw platform "$rawPlatform" is not supported.',
          );
        }
        return;
      }

      final payload = buildDevicePayload(
        uid: uid,
        playerId: playerId,
        platform: normalizedPlatform,
        appVersion: device['app_version'] as String?,
        subscribed: subscribed,
      );

      final registered = await persistDeviceRecord(payload);
      if (registered) {
        try {
          final rows = await _supabase
              .from('user_devices')
              .select('player_id')
              .eq('user_id', uid);
          for (final row in rows) {
            final pid = (row['player_id'] as String?)?.trim() ?? '';
            if (pid.isNotEmpty && !isValidSubscriptionId(pid)) {
              await _supabase
                  .from('user_devices')
                  .delete()
                  .eq('user_id', uid)
                  .eq('player_id', pid);
              if (kDebugMode) {
                debugPrint(
                  '[OneSignalService] Purged legacy non-UUID token from user_devices: $pid',
                );
              }
            }
          }
        } catch (e) {
          if (kDebugMode) {
            debugPrint('[OneSignalService] Legacy token cleanup notice: $e');
          }
        }
      }
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('[OneSignalService] persist error: $e');
        debugPrintStack(stackTrace: st);
      }
    }
  }

  Future<void> removePlayer(String uid, String playerId) async {
    final cleanUid = uid.trim();
    final cleanPid = playerId.trim();
    if (cleanUid.isEmpty || cleanPid.isEmpty) {
      if (kDebugMode) {
        debugPrint(
          '[OneSignalService] skip removePlayer: empty uid or playerId',
        );
      }
      return;
    }

    try {
      await _supabase
          .from('user_devices')
          .delete()
          .eq('user_id', cleanUid)
          .eq('player_id', cleanPid);
      if (kDebugMode) {
        debugPrint(
          '[OneSignalService] Removed player from Supabase user_devices: $cleanPid',
        );
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[OneSignalService] Supabase user_devices remove error: $e');
      }
    }
  }

  /// Logs out of OneSignal (v5 namespaced SDK).
  Future<void> logout() async {
    try {
      final customLogout = _oneSignalLogout;
      if (customLogout != null) {
        await customLogout();
      } else if (isPlatformSupported) {
        await OneSignal.logout();
      }
      if (kDebugMode) {
        debugPrint('[OneSignalService] OneSignal.logout() succeeded.');
      }
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('[OneSignalService] OneSignal.logout() error: $e');
        debugPrintStack(stackTrace: st);
      }
    } finally {
      dispose();
    }
  }

  void dispose() {
    for (final t in _persistTimers.values) {
      t.cancel();
    }
    _persistTimers.clear();
    _lastPersistAt.clear();
    _currentUid = null;
  }
}
