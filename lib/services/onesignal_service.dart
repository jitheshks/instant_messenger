// lib/services/onesignal_service.dart
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';

import '../controller/notification_controller.dart';
import 'app_info_service.dart';

/// Mobile-only OneSignal service (v5+ namespaced API).
class OneSignalService {
  final FirebaseFirestore _db;
  final AppInfoService _appInfo;
  bool _wired = false;
  String? _currentUid;

  final Map<String, Timer> _persistTimers = {};
  final Map<String, DateTime> _lastPersistAt = {};

  OneSignalService(this._db, this._appInfo);

  /// Initialize OneSignal (v5 namespaced). Returns push subscription id (player id).
  Future<String?> initialize({
    required String appId,
    required String uid,
    bool promptPermission = true,
  }) async {
    _currentUid = uid;

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

} catch (e, st) {
  if (kDebugMode) {
    debugPrint('[OneSignalService] initialize/login error: $e');
    debugPrintStack(stackTrace: st);
  }
}



    // Prompt for permission via Notifications namespace (iOS / Android 13+)
    if (promptPermission) {
      try {
        await OneSignal.Notifications.requestPermission(true);
        if (kDebugMode) debugPrint('[OneSignalService] requested notification permission');
      } catch (e) {
        if (kDebugMode) debugPrint('[OneSignalService] requestPermission failed: $e');
      }
    }

    if (!_wired) {
      _wireListeners();
      _wired = true;
      if (kDebugMode) debugPrint('[OneSignalService] listeners wired (namespaced API)');
    }

    // Get push subscription id (player id)
    String? playerId;
    try {
      playerId = OneSignal.User.pushSubscription.id;
      if (kDebugMode) debugPrint('[OneSignalService] current playerId=$playerId');
    } catch (e) {
      if (kDebugMode) debugPrint('[OneSignalService] reading pushSubscription.id failed: $e');
      playerId = null;
    }

    if (playerId != null && uid.isNotEmpty) {
      await _schedulePersist(uid: uid, playerId: playerId);
    }

    return playerId;
  }

  void _wireListeners() {
    // Notification click / opened
    try {
  OneSignal.Notifications.addClickListener((event) async {
  try {
    final data = event.notification.additionalData;
    if (data == null) return;

    final chatId =
        data['chatId'] ?? data['chat_id'] ?? data['chat'];
    final messageId =
        data['messageId'] ?? data['message_id'];

    // 🔹 Mark delivered when notification is opened
    if (chatId != null && messageId != null) {
      await _db
          .collection('chats')
          .doc(chatId)
          .collection('messages')
          .doc(messageId)
          .update({'status': '2'});
    }

    // 🔹 Existing navigation logic
    if (chatId != null) {
      NotificationController.onNotificationTap(chatId);
    }
  } catch (e, st) {
    if (kDebugMode) {
      debugPrint('[OneSignalService] click listener error: $e');
      debugPrintStack(stackTrace: st);
    }
  }
});

    } catch (e) {
      if (kDebugMode) debugPrint('[OneSignalService] addClickListener failed: $e');
    }

// Foreground notification handling (WhatsApp-like)
try {
  OneSignal.Notifications.addForegroundWillDisplayListener((event) async {
    final notification = event.notification;
    final data = notification.additionalData;

    final incomingChatId =
        data?['chatId'] ?? data?['chat_id'] ?? data?['chat'];

    // 🔹 If user is inside SAME chat → suppress notification
    if (NotificationController.isChatOpen(incomingChatId)) {
      event.preventDefault();
      return;
    }

    // 🔹 Otherwise SHOW notification (foreground allowed)
    notification.display();

    // 🔹 Mark message as delivered (foreground case)
    final messageId = data?['messageId'] ?? data?['message_id'];
    if (incomingChatId != null && messageId != null) {
      await _db
          .collection('chats')
          .doc(incomingChatId)
          .collection('messages')
          .doc(messageId)
          .update({'status': '2'});
    }
  });
} catch (e, st) {
  if (kDebugMode) {
    debugPrint('[OneSignalService] foreground listener error: $e');
    debugPrintStack(stackTrace: st);
  }
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
        if (kDebugMode) debugPrint('[OneSignalService] pushSubscription changed: id=$playerId');
        if (uid != null && playerId != null) _schedulePersist(uid: uid, playerId: playerId);
      });
    } catch (e) {
      if (kDebugMode) debugPrint('[OneSignalService] pushSubscription.addObserver failed: $e');
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
        if (kDebugMode) debugPrint('[OneSignalService] permission changed');
        if (uid != null && playerId != null) _schedulePersist(uid: uid, playerId: playerId);
      });
    } catch (e) {
      if (kDebugMode) debugPrint('[OneSignalService] addPermissionObserver failed: $e');
    }
  }

  Future<void> _schedulePersist({
    required String uid,
    required String playerId,
    Duration debounce = const Duration(milliseconds: 800),
  }) async {
    _persistTimers[playerId]?.cancel();
    _persistTimers[playerId] = Timer(debounce, () async {
      final last = _lastPersistAt[playerId];
      if (last != null && DateTime.now().difference(last) < debounce) {
        if (kDebugMode) debugPrint('[OneSignalService] skip persist (recent) pid=$playerId');
        return;
      }
      await _persistPlayer(uid, playerId);
      _lastPersistAt[playerId] = DateTime.now();
    });
  }

Future<Map<String, dynamic>> _collectDeviceInfo() async {
  final versionPlusBuild = await _appInfo.versionPlusBuild();
  final dev = DeviceInfoPlugin();

  String platform = 'unknown';
  String model = 'unknown';
  String osVersion = 'unknown';
  String sdkVersion = 'unknown';

  if (kIsWeb) {
    platform = 'web';
    model = 'browser';
    osVersion = 'browser';
    sdkVersion = 'unknown';
  } else {
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        platform = 'android';
        try {
          final a = await dev.androidInfo;

          // manufacturer/model are non-nullable in current bindings
          model = '${a.manufacturer} ${a.model}'.trim();

          // version.release and sdkInt are non-nullable in current bindings
          // so use them directly (no ?? checks)
          final rel = a.version.release;
          final sdkInt = a.version.sdkInt;
          osVersion = 'Android $rel (SDK ${sdkInt.toString()})';
          sdkVersion = sdkInt.toString();
        } catch (_) {
          // In case of unexpected runtime issue, provide safe defaults
          model = 'android';
          osVersion = 'Android unknown';
          sdkVersion = 'unknown';
        }
        break;

      case TargetPlatform.iOS:
        platform = 'ios';
        try {
        final i = await dev.iosInfo;

          // Both are non-nullable in current plugin
          model = i.utsname.machine;
          osVersion = 'iOS ${i.systemVersion}';
          sdkVersion = i.systemVersion;
        } catch (_) {
          model = 'iphone';
          osVersion = 'iOS unknown';
          sdkVersion = 'unknown';
        }
        break;

      default:
        platform = defaultTargetPlatform.toString();
        model = 'device';
    }
  }

  return {
    'platform': platform,
    'model': model,
    'os_version': osVersion,
    'sdk_version': sdkVersion,
    'app_version': versionPlusBuild,
  };
}

 Future<void> _persistPlayer(String uid, String playerId) async {
  // ✅ HARD GUARD (MANDATORY)
  if (uid.isEmpty || playerId.isEmpty) {
    if (kDebugMode) {
      debugPrint(
        '[OneSignalService] skip persist (uid="$uid", playerId="$playerId")',
      );
    }
    return;
  }

  try {
    bool subscribed = false;
    try {
      final bool? maybeOptedIn = OneSignal.User.pushSubscription.optedIn;
      subscribed = maybeOptedIn ?? false;
    } catch (_) {
      subscribed = false;
    }

    bool? permission;
    try {
      permission = OneSignal.Notifications.permission;
    } catch (_) {
      permission = null;
    }

    final device = await _collectDeviceInfo();

    await _db.collection('users').doc(uid).set({
      'player_id': playerId,
      'player_ids': FieldValue.arrayUnion([playerId]),
      'push_provider': 'onesignal',
      'updated_at': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    await _db
        .collection('users')
        .doc(uid)
        .collection('players')
        .doc(playerId)
        .set({
      'player_id': playerId,
      'platform': device['platform'],
      'model': device['model'],
      'os_version': device['os_version'],
      'app_version': device['app_version'],
      'sdk_version': device['sdk_version'],
      'subscribed': subscribed,
      'permission': permission,
      'updated_at': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    if (kDebugMode) {
      debugPrint('[OneSignalService] persisted player=$playerId uid=$uid');
    }
  } catch (e, st) {
    if (kDebugMode) {
      debugPrint('[OneSignalService] persist error: $e');
      debugPrintStack(stackTrace: st);
    }
  }
}


  Future<void> removePlayer(String uid, String playerId) async {
    try {
      await _db.collection('users').doc(uid).collection('players').doc(playerId).delete();
      if (kDebugMode) debugPrint('[OneSignalService] removed playerId=$playerId for uid=$uid');
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('[OneSignalService] remove error: $e');
        debugPrintStack(stackTrace: st);
      }
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
