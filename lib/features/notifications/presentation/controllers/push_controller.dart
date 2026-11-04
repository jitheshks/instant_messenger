import 'package:flutter/foundation.dart';

import 'package:instant_messenger/features/notifications/data/fcm_service.dart';
import 'package:instant_messenger/features/notifications/data/onesignal_service.dart';
import 'package:instant_messenger/core/utils/permission_service.dart';
import 'package:instant_messenger/features/notifications/data/player_id_service.dart';

class PushController extends ChangeNotifier {
  final OneSignalService oneSignal;
  final String oneSignalAppId;
  final FcmService? fcmService;

  /// Server-side push notification dispatcher (e.g. Supabase Edge Function).
  /// Client applications must NEVER embed master OneSignal REST API credentials.
  final Future<void> Function({
    required String chatId,
    required String senderId,
    required String preview,
    required String type,
    String? messageId,
    String? senderName,
  })?
  serverSend;

  String? _playerId;
  String? _fcmToken;
  bool _initialized = false;
  String? _currentUid;

  String? get playerId => _playerId;
  String? get fcmToken => _fcmToken;
  bool get initialized => _initialized;

  PushController({
    required this.oneSignal,
    required this.oneSignalAppId,
    this.fcmService,
    this.serverSend,
  });

  @visibleForTesting
  void setTestState({
    String? playerId,
    String? fcmToken,
    String? currentUid,
    bool initialized = true,
  }) {
    _playerId = playerId;
    _fcmToken = fcmToken;
    _currentUid = currentUid;
    _initialized = initialized;
  }

  // ------------------------------------------------------------
  // INIT (ONLY THIS – NO ROUTING, NO LISTENERS)
  // ------------------------------------------------------------
  Future<void> init({required String uid, bool promptPermission = true}) async {
    // 🔒 Check platform support first
    final isSupported =
        oneSignal.isPlatformSupported || FcmService.isSupportedPlatform();
    if (!isSupported) {
      if (kDebugMode) {
        debugPrint(
          '[PushController] Push initialization skipped: platform is unsupported.',
        );
      }
      return;
    }

    // 🔒 HARD GUARD — prevents duplicate init immediately
    if (_initialized && _currentUid == uid) {
      if (kDebugMode) {
        debugPrint('[PushController] init skipped (already initialized)');
      }
      return;
    }

    // 🔄 Switching user → cleanup
    if (_initialized && _currentUid != uid) {
      await _cleanupForUid();
    }

    // 🔒 MARK INITIALIZED *BEFORE* ASYNC WORK
    _initialized = true;
    _currentUid = uid;

    try {
      // 1️⃣ OS permission first (Android 13+/iOS)
      try {
        await PermissionService.ensureNotifications();
      } catch (e) {
        if (kDebugMode) {
          debugPrint('[PushController] ensureNotifications notice: $e');
        }
      }

      // 2️⃣ Initialize FCM transport (diagnostics only; does not write raw tokens to user_devices)
      if (fcmService != null) {
        try {
          _fcmToken = await fcmService!.init(
            uid: uid,
            promptPermission: promptPermission,
            persistToSupabase: false,
          );
          if (kDebugMode) {
            debugPrint('[PushController] FCM token initialized: $_fcmToken');
          }
        } catch (e) {
          if (kDebugMode) {
            debugPrint('[PushController] FCM init notice: $e');
          }
        }
      }

      // 3️⃣ Initialize OneSignal (sole notification delivery provider)
      if (oneSignalAppId.trim().isNotEmpty) {
        try {
          oneSignal.onSubscriptionChanged = (newPlayerId) {
            if (_playerId != newPlayerId) {
              _playerId = newPlayerId;
              notifyListeners();
            }
          };

          _playerId = await oneSignal.initialize(
            appId: oneSignalAppId,
            uid: uid,
            promptPermission: promptPermission,
          );
        } catch (e) {
          if (kDebugMode) {
            debugPrint('[PushController] OneSignal init notice: $e');
          }
        }
      }

      if (kDebugMode) {
        debugPrint(
          '[PushController] init done uid=$uid fcm=$_fcmToken playerId=$_playerId',
        );
      }

      notifyListeners();
    } catch (e, st) {
      // 🔓 ROLLBACK only if fatal uncaught exception occurred
      _initialized = false;
      _currentUid = null;

      if (kDebugMode) {
        debugPrint('[PushController] init error: $e');
        debugPrintStack(stackTrace: st);
      }
      rethrow;
    }
  }

  // ------------------------------------------------------------
  // CLEANUP (LOGOUT / ACCOUNT SWITCH)
  // ------------------------------------------------------------
  Future<void> _cleanupForUid() async {
    if (_currentUid != null && _playerId != null) {
      try {
        await oneSignal.removePlayer(_currentUid!, _playerId!);
        if (kDebugMode) {
          debugPrint(
            '[PushController] removed player=$_playerId uid=$_currentUid',
          );
        }
      } catch (e, st) {
        if (kDebugMode) {
          debugPrint('[PushController] cleanup error: $e');
          debugPrintStack(stackTrace: st);
        }
      }
    }

    if (fcmService != null && _currentUid != null) {
      try {
        await fcmService!.cleanupOnSignOut(_currentUid!);
      } catch (e, st) {
        if (kDebugMode) {
          debugPrint('[PushController] FCM cleanup error: $e');
          debugPrintStack(stackTrace: st);
        }
      }
    }

    try {
      await oneSignal.logout();
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('[PushController] account switch logout error: $e');
        debugPrintStack(stackTrace: st);
      }
    }

    _playerId = null;
    _fcmToken = null;
    _initialized = false;
    _currentUid = null;
    notifyListeners();
  }

  /// Performs complete push deregistration on user sign-out:
  /// 1. Removes device record from `user_devices` while the current user's session is still valid.
  /// 2. Invokes OneSignal.logout() to disassociate the user identity on OneSignal.
  /// 3. Resets internal controller state.
  Future<void> cleanupOnSignOut(String uid) async {
    final pid = _playerId;
    final trimmedUid = uid.trim();
    if (pid != null && pid.isNotEmpty && trimmedUid.isNotEmpty) {
      try {
        await oneSignal.removePlayer(trimmedUid, pid);
        if (kDebugMode) {
          debugPrint(
            '[PushController] Removed player=$pid for uid=$trimmedUid on signOut',
          );
        }
      } catch (e, st) {
        if (kDebugMode) {
          debugPrint(
            '[PushController] cleanupOnSignOut removePlayer error: $e',
          );
          debugPrintStack(stackTrace: st);
        }
      }
    }

    if (fcmService != null && trimmedUid.isNotEmpty) {
      try {
        await fcmService!.cleanupOnSignOut(trimmedUid);
        if (kDebugMode) {
          debugPrint('[PushController] Cleaned up FCM token on signOut');
        }
      } catch (e, st) {
        if (kDebugMode) {
          debugPrint('[PushController] cleanupOnSignOut FCM error: $e');
          debugPrintStack(stackTrace: st);
        }
      }
    }

    try {
      await oneSignal.logout();
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint(
          '[PushController] cleanupOnSignOut oneSignal.logout error: $e',
        );
        debugPrintStack(stackTrace: st);
      }
    } finally {
      _playerId = null;
      _fcmToken = null;
      _initialized = false;
      _currentUid = null;
      notifyListeners();
    }
  }

  /// Optional explicit remove (logout)
  Future<void> removePlayer({required String uid}) async {
    if (_playerId == null) return;

    await oneSignal.removePlayer(uid, _playerId!);

    if (kDebugMode) {
      debugPrint('[PushController] removePlayer uid=$uid playerId=$_playerId');
    }

    _playerId = null;
    _initialized = false;
    notifyListeners();
  }

  // ------------------------------------------------------------
  // SEND PUSH (SERVER-SIDE DISPATCH VIA SUPABASE EDGE FUNCTION)
  // ------------------------------------------------------------
  Future<void> onMessageSent({
    required String chatId,
    required String senderId,
    required String preview,
    required String messageId,
    String type = 'text',
    String? senderName,
    String? avatarUrl,
    List<String>? recipientPlayerIds,
    List<String>? recipientUserIds,
  }) async {
    try {
      // Server-side push dispatcher (Supabase send-push Edge Function)
      if (serverSend != null) {
        await serverSend!(
          chatId: chatId,
          senderId: senderId,
          preview: preview,
          type: type,
          messageId: messageId,
          senderName: senderName,
        );
        return;
      }

      // ------------------------------------------------------------
      // Resolve userIds → playerIds
      // ------------------------------------------------------------
      if ((recipientPlayerIds == null || recipientPlayerIds.isEmpty) &&
          recipientUserIds != null &&
          recipientUserIds.isNotEmpty) {
        final resolved = <String>{};
        for (final uid in recipientUserIds) {
          final ids = await PlayerIdService.fetchPlayerIdsForUid(uid);
          resolved.addAll(ids);
        }
        recipientPlayerIds = resolved.toList();
      }

      // ------------------------------------------------------------
      // 🔴 PREVENT SELF-NOTIFICATION (ADD HERE)
      // ------------------------------------------------------------

      // Remove sender userId (safety, if sender included by mistake)
      if (recipientUserIds != null) {
        recipientUserIds = recipientUserIds
            .where((id) => id != senderId)
            .toList();
      }

      // Remove sender's own device playerId
      if (recipientPlayerIds != null && _playerId != null) {
        recipientPlayerIds = recipientPlayerIds
            .where((id) => id != _playerId)
            .toList();
      }

      // ------------------------------------------------------------
      // Notification Dispatch: Server-Side Required
      // ------------------------------------------------------------
      if (kDebugMode) {
        debugPrint(
          '[PushController] Direct client-side push notification dispatch is disabled '
          'for security. Notifications are dispatched via server-side Edge Functions.',
        );
      }
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('[PushController] onMessageSent error: $e');
        debugPrintStack(stackTrace: st);
      }
    }
  }
}
