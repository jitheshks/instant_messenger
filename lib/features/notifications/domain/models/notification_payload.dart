// lib/features/notifications/domain/models/notification_payload.dart

import 'dart:convert';
import 'package:flutter/foundation.dart';

/// Normalized notification type classification.
enum NotificationType {
  chat,
  call,
  callCancelled,
  unknown,
}

/// Action intent when interacting with a call notification.
enum CallActionIntent {
  /// User tapped the notification banner/body; opens Incoming Call UI with Accept/Decline buttons.
  openIncomingUi,

  /// User clicked the explicit native 'Accept' action button on the notification banner.
  accept,

  /// User clicked the explicit native 'Decline' or 'Reject' action button on the notification banner.
  decline,
}

/// Normalized, transport-agnostic notification contract.
///
/// Harmonizes payload differences across OneSignal, Firebase Cloud Messaging (FCM),
/// and Flutter Local Notifications in foreground, background, and cold-start (terminated) states.
@immutable
class NotificationPayload {
  final NotificationType type;
  final String? chatId;
  final String? messageId;
  final String? callId;
  final String? callerId;
  final String? callerName;
  final String? callType; // 'audio' or 'video'
  final String? senderPhone;
  final CallActionIntent callActionIntent;
  final Map<String, dynamic> rawData;

  const NotificationPayload({
    required this.type,
    this.chatId,
    this.messageId,
    this.callId,
    this.callerId,
    this.callerName,
    this.callType,
    this.senderPhone,
    this.callActionIntent = CallActionIntent.openIncomingUi,
    this.rawData = const {},
  });

  bool get isCall => type == NotificationType.call;
  bool get isChat => type == NotificationType.chat;
  bool get isCallCancelled => type == NotificationType.callCancelled;

  /// Creates a normalized [NotificationPayload] from an arbitrary map,
  /// supporting camelCase, snake_case, stringified JSON, and nested payload variants.
  static NotificationPayload fromMap(
    Map<dynamic, dynamic>? data, {
    String? actionId,
  }) {
    if (data == null || data.isEmpty) {
      return const NotificationPayload(type: NotificationType.unknown);
    }

    // Convert keys to string for reliable querying
    final map = <String, dynamic>{};
    for (final entry in data.entries) {
      map[entry.key.toString()] = entry.value;
    }

    // Unpack nested 'data' or 'custom' maps/strings common across vendors (OneSignal/FCM)
    if (map['data'] is String) {
      try {
        final inner = jsonDecode(map['data'] as String);
        if (inner is Map) {
          for (final entry in inner.entries) {
            map.putIfAbsent(entry.key.toString(), () => entry.value);
          }
        }
      } catch (_) {}
    } else if (map['data'] is Map) {
      for (final entry in (map['data'] as Map).entries) {
        map.putIfAbsent(entry.key.toString(), () => entry.value);
      }
    }

    if (map['custom'] is String) {
      try {
        final inner = jsonDecode(map['custom'] as String);
        if (inner is Map) {
          if (inner['a'] is Map) {
            for (final entry in (inner['a'] as Map).entries) {
              map.putIfAbsent(entry.key.toString(), () => entry.value);
            }
          }
          for (final entry in inner.entries) {
            map.putIfAbsent(entry.key.toString(), () => entry.value);
          }
        }
      } catch (_) {}
    } else if (map['custom'] is Map) {
      final inner = map['custom'] as Map;
      if (inner['a'] is Map) {
        for (final entry in (inner['a'] as Map).entries) {
          map.putIfAbsent(entry.key.toString(), () => entry.value);
        }
      }
      for (final entry in inner.entries) {
        map.putIfAbsent(entry.key.toString(), () => entry.value);
      }
    }

    // Resolve chat_id / chatId / chat
    final rawChatId = map['chatId'] ?? map['chat_id'] ?? map['chat'];
    final chatId = _cleanString(rawChatId);

    // Resolve message_id / messageId
    final rawMessageId = map['messageId'] ?? map['message_id'];
    final messageId = _cleanString(rawMessageId);

    // Resolve call_id / callId
    final rawCallId = map['callId'] ?? map['call_id'];
    final callId = _cleanString(rawCallId);

    // Resolve caller_id / callerId / senderId / sender_id
    final rawCallerId = map['callerId'] ??
        map['caller_id'] ??
        map['senderId'] ??
        map['sender_id'];
    final callerId = _cleanString(rawCallerId);

    // Resolve caller_name / callerName / senderName / sender_name
    final rawCallerName = map['callerName'] ??
        map['caller_name'] ??
        map['senderName'] ??
        map['sender_name'];
    final callerName = _cleanString(rawCallerName);

    // Resolve call_type / callType
    final rawCallType = map['callType'] ?? map['call_type'];
    final cleanCallType = _cleanString(rawCallType)?.toLowerCase();
    final callType = (cleanCallType == 'video') ? 'video' : 'audio';

    // Resolve sender_phone / senderPhone
    final rawPhone = map['senderPhone'] ?? map['sender_phone'];
    final senderPhone = _cleanString(rawPhone);

    // Parse notification action intent
    final cleanActionId = actionId?.trim().toLowerCase();
    final CallActionIntent callActionIntent;
    if (cleanActionId == 'accept') {
      callActionIntent = CallActionIntent.accept;
    } else if (cleanActionId == 'decline' || cleanActionId == 'reject') {
      callActionIntent = CallActionIntent.decline;
    } else {
      callActionIntent = CallActionIntent.openIncomingUi;
    }

    // Determine type
    final rawType = _cleanString(map['type'])?.toLowerCase();
    final NotificationType type;

    if (rawType == 'call_cancelled') {
      type = NotificationType.callCancelled;
    } else if (rawType == 'call' ||
        rawType == 'call_invitation' ||
        (callId != null && callId.isNotEmpty)) {
      type = NotificationType.call;
    } else if (chatId != null && chatId.isNotEmpty) {
      type = NotificationType.chat;
    } else {
      type = NotificationType.unknown;
    }

    return NotificationPayload(
      type: type,
      chatId: chatId,
      messageId: messageId,
      callId: callId,
      callerId: callerId,
      callerName: callerName,
      callType: callType,
      senderPhone: senderPhone,
      callActionIntent: callActionIntent,
      rawData: map,
    );
  }

  /// Parses a notification string payload, which may be raw JSON or a simple chat ID.
  static NotificationPayload fromStringPayload(
    String? rawPayload, {
    String? actionId,
  }) {
    if (rawPayload == null || rawPayload.trim().isEmpty) {
      return const NotificationPayload(type: NotificationType.unknown);
    }

    final trimmed = rawPayload.trim();
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is Map<dynamic, dynamic>) {
        return fromMap(decoded, actionId: actionId);
      }
    } catch (_) {
      // If not JSON, treat raw string as a direct chatId
    }

    return NotificationPayload(
      type: NotificationType.chat,
      chatId: trimmed,
      callActionIntent: CallActionIntent.openIncomingUi,
      rawData: {'chatId': trimmed},
    );
  }

  static String? _cleanString(dynamic val) {
    if (val == null) return null;
    final str = val.toString().trim();
    return str.isEmpty ? null : str;
  }

  @override
  String toString() =>
      'NotificationPayload(type: $type, chatId: $chatId, messageId: $messageId, '
      'callId: $callId, callerName: $callerName, callType: $callType, '
      'actionIntent: $callActionIntent)';
}
