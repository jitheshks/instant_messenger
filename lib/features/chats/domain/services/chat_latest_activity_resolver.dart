// lib/features/chats/domain/services/chat_latest_activity_resolver.dart

import 'package:flutter/foundation.dart';
import 'package:instant_messenger/features/calls/domain/models/call_enums.dart';
import 'package:instant_messenger/features/calls/domain/models/call_record.dart';
import 'package:instant_messenger/features/messaging/domain/models/chat_message.dart';

/// Represents the resolved latest activity of a conversation for inbox preview display.
@immutable
class ChatActivitySummary {
  final String previewText;
  final DateTime timestamp;
  final String senderId;
  final int status; // 0-3
  final String? activityId;
  final bool isCallActivity;

  const ChatActivitySummary({
    required this.previewText,
    required this.timestamp,
    required this.senderId,
    required this.status,
    this.activityId,
    this.isCallActivity = false,
  });
}

/// Pure domain service responsible for determining and formatting the latest
/// conversation activity (messages vs audio/video call events) for chat list previews.
class ChatLatestActivityResolver {
  const ChatLatestActivityResolver._();

  /// Formats a call record into a standard WhatsApp-style chat list preview string.
  static String formatCallPreview(
    CallRecord call, {
    required String currentUserId,
  }) {
    final isVideo = call.callType == CallType.video;

    if (call.isMissed) {
      return isVideo ? 'Missed video call' : 'Missed voice call';
    }
    if (call.isCancelled) {
      return isVideo ? 'Cancelled video call' : 'Cancelled voice call';
    }
    if (call.isDeclined) {
      return isVideo ? 'Declined video call' : 'Declined voice call';
    }
    if (call.isOutgoing(currentUserId)) {
      return isVideo ? 'Outgoing video call' : 'Outgoing voice call';
    }
    return isVideo ? 'Incoming video call' : 'Incoming voice call';
  }

  /// Formats a chat message into a chat list preview string.
  static String formatMessagePreview(ChatMessage msg) {
    final trimmedText = msg.text.trim();

    if (msg.media != null) {
      switch (msg.media!.kind) {
        case MediaKind.image:
          return trimmedText.isNotEmpty ? trimmedText : '📷 Photo';
        case MediaKind.video:
          return trimmedText.isNotEmpty ? trimmedText : '🎥 Video';
        case MediaKind.audio:
          return trimmedText.isNotEmpty ? trimmedText : '🎵 Audio';
        case MediaKind.document:
          final fileName = msg.media!.fileName?.trim();
          if (fileName != null && fileName.isNotEmpty) return fileName;
          return trimmedText.isNotEmpty ? trimmedText : '📄 Document';
      }
    }

    if (trimmedText.isNotEmpty) {
      return trimmedText;
    }

    if (msg.type == MessageType.media) {
      return '📎 Attachment';
    }

    return trimmedText;
  }

  /// Evaluates the latest message and latest call record for a conversation,
  /// returning the strictly newer activity for chat list rendering.
  static ChatActivitySummary resolveLatestActivity({
    required DateTime messageTime,
    required String messagePreview,
    required String lastSenderId,
    required int lastMessageStatus,
    String? lastMessageId,
    CallRecord? latestCall,
    required String currentUserId,
  }) {
    if (latestCall == null) {
      return ChatActivitySummary(
        previewText: messagePreview,
        timestamp: messageTime,
        senderId: lastSenderId,
        status: lastMessageStatus,
        activityId: lastMessageId,
        isCallActivity: false,
      );
    }

    // Compare timestamps: if call strictly occurred after the latest message,
    // the call represents the conversation's latest activity.
    if (latestCall.startedAt.isAfter(messageTime)) {
      final callPreview = formatCallPreview(
        latestCall,
        currentUserId: currentUserId,
      );
      return ChatActivitySummary(
        previewText: callPreview,
        timestamp: latestCall.startedAt,
        senderId: latestCall.callerId,
        status: 1, // Sent/established status indicator
        activityId: 'call_${latestCall.id}',
        isCallActivity: true,
      );
    }

    // Message is newer or at the exact same moment: preserve message preview
    return ChatActivitySummary(
      previewText: messagePreview,
      timestamp: messageTime,
      senderId: lastSenderId,
      status: lastMessageStatus,
      activityId: lastMessageId,
      isCallActivity: false,
    );
  }
}
