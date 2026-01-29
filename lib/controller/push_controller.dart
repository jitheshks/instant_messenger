import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'package:instant_messenger/services/onesignal_service.dart';
import 'package:instant_messenger/services/permission_service.dart';
import 'package:instant_messenger/services/player_id_service.dart';

class PushController extends ChangeNotifier {
  final OneSignalService oneSignal;
  final String oneSignalAppId;

  /// Optional server-side sender callback (NOT used on Spark plan)
  final Future<void> Function({
    required String chatId,
    required String senderId,
    required String preview,
    required String type,
  })? serverSend;

  /// OneSignal REST API key (REQUIRED on Spark plan)
  final String? oneSignalRestApiKey;

  String? _playerId;
  bool _initialized = false;
  String? _currentUid;

  String? get playerId => _playerId;
  bool get initialized => _initialized;

  PushController({
    required this.oneSignal,
    required this.oneSignalAppId,
    this.serverSend,
    this.oneSignalRestApiKey,
  });

  // ------------------------------------------------------------
  // INIT (ONLY THIS – NO ROUTING, NO LISTENERS)
  // ------------------------------------------------------------
Future<void> init({
  required String uid,
  bool promptPermission = true,
}) async {
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
    await PermissionService.ensureNotifications();

    // 2️⃣ Initialize OneSignal (includes login(uid))
    _playerId = await oneSignal.initialize(
      appId: oneSignalAppId,
      uid: uid,
      promptPermission: promptPermission,
    );

    if (kDebugMode) {
      debugPrint(
        '[PushController] init done uid=$uid playerId=$_playerId',
      );
    }

    notifyListeners();
  } catch (e, st) {
    // 🔓 ROLLBACK if something failed
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

    _playerId = null;
    _initialized = false;
    _currentUid = null;
    notifyListeners();
  }

  /// Optional explicit remove (logout)
  Future<void> removePlayer({required String uid}) async {
    if (_playerId == null) return;

    await oneSignal.removePlayer(uid, _playerId!);

    if (kDebugMode) {
      debugPrint(
        '[PushController] removePlayer uid=$uid playerId=$_playerId',
      );
    }

    _playerId = null;
    _initialized = false;
    notifyListeners();
  }

  // ------------------------------------------------------------
  // SEND PUSH (AFTER FIRESTORE WRITE)
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
    // Server sender (not used on Spark)
    if (serverSend != null) {
      await serverSend!(
        chatId: chatId,
        senderId: senderId,
        preview: preview,
        type: type,
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
      recipientUserIds =
          recipientUserIds.where((id) => id != senderId).toList();
    }

    // Remove sender's own device playerId
    if (recipientPlayerIds != null && _playerId != null) {
      recipientPlayerIds =
          recipientPlayerIds.where((id) => id != _playerId).toList();
    }

    // ------------------------------------------------------------
    // Validate recipients + REST key
    // ------------------------------------------------------------
    if (oneSignalRestApiKey == null ||
        recipientPlayerIds == null ||
        recipientPlayerIds.isEmpty) {
      if (kDebugMode) {
        debugPrint('[PushController] Skip push (no recipients / no REST key)');
      }
      return;
    }

    // ------------------------------------------------------------
    // Send OneSignal push
    // ------------------------------------------------------------
    final resp = await _sendOneSignalDirect(
      includePlayerIds: recipientPlayerIds,
      chatId: chatId,
        messageId: messageId, 
      preview: preview,
      type: type,
      senderName: senderName,
      avatarUrl: avatarUrl,
    );

    if (kDebugMode) {
      debugPrint(
        '[PushController] OneSignal resp ${resp.statusCode}: ${resp.body}',
      );
    }
  } catch (e, st) {
    if (kDebugMode) {
      debugPrint('[PushController] onMessageSent error: $e');
      debugPrintStack(stackTrace: st);
    }
  }
}

  // ------------------------------------------------------------
  // RAW ONESIGNAL REST CALL
  // ------------------------------------------------------------
  Future<http.Response> _sendOneSignalDirect({
    required List<String> includePlayerIds,
    required String chatId,
      required String messageId, 
    required String preview,
    required String type,
    String? senderName,
    String? avatarUrl,
  }) {
    final endpoint =
        Uri.parse('https://onesignal.com/api/v1/notifications');

    final body = {
      'app_id': oneSignalAppId,
      'include_player_ids': includePlayerIds,
      'headings': {'en': senderName ?? 'New message'},
      'contents': {'en': preview},
      'data': {
        'chatId': chatId,
         'messageId': messageId,
        'type': type,
        if (senderName != null) 'senderName': senderName,
        if (avatarUrl != null) 'avatarUrl': avatarUrl,
      },
      'android_channel_id': 'chat_messages',
      'android_group': 'chat_$chatId',
      'priority': 10,
    };

    return http.post(
      endpoint,
      headers: {
        'Content-Type': 'application/json; charset=UTF-8',
        'Authorization': 'Basic $oneSignalRestApiKey',
      },
      body: jsonEncode(body),
    );
  }
}
