// test/messaging/chat_latest_activity_resolver_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:instant_messenger/features/calls/domain/models/call_enums.dart';
import 'package:instant_messenger/features/calls/domain/models/call_record.dart';
import 'package:instant_messenger/features/chats/domain/services/chat_latest_activity_resolver.dart';
import 'package:instant_messenger/features/messaging/domain/models/chat_message.dart';

void main() {
  group('ChatLatestActivityResolver Unit Tests', () {
    const currentUserId = 'user_me';
    const peerUserId = 'user_peer';
    final baseTime = DateTime(2026, 11, 4, 12, 0, 0);

    test('1. Formats text message preview correctly', () {
      final msg = ChatMessage(
        id: 'msg-1',
        chatId: 'chat-1',
        senderId: peerUserId,
        text: 'Hello there!',
        sentAt: baseTime,
        deliveryState: DeliveryState.sent,
        type: MessageType.text,
      );

      final preview = ChatLatestActivityResolver.formatMessagePreview(msg);
      expect(preview, equals('Hello there!'));
    });

    test('2. Formats media message indicators with and without captions', () {
      final imgNoCaption = ChatMessage(
        id: 'msg-2',
        chatId: 'chat-1',
        senderId: peerUserId,
        text: '',
        sentAt: baseTime,
        deliveryState: DeliveryState.sent,
        type: MessageType.media,
        media: const MessageMedia(
          url: 'https://example.com/img.jpg',
          kind: MediaKind.image,
          mime: 'image/jpeg',
          size: 1024,
        ),
      );
      expect(ChatLatestActivityResolver.formatMessagePreview(imgNoCaption), equals('📷 Photo'));

      final imgWithCaption = ChatMessage(
        id: 'msg-3',
        chatId: 'chat-1',
        senderId: peerUserId,
        text: 'Sunset view',
        sentAt: baseTime,
        deliveryState: DeliveryState.sent,
        type: MessageType.media,
        media: const MessageMedia(
          url: 'https://example.com/img.jpg',
          kind: MediaKind.image,
          mime: 'image/jpeg',
          size: 1024,
        ),
      );
      expect(ChatLatestActivityResolver.formatMessagePreview(imgWithCaption), equals('Sunset view'));

      final videoMsg = ChatMessage(
        id: 'msg-4',
        chatId: 'chat-1',
        senderId: peerUserId,
        text: '',
        sentAt: baseTime,
        deliveryState: DeliveryState.sent,
        type: MessageType.media,
        media: const MessageMedia(
          url: 'https://example.com/vid.mp4',
          kind: MediaKind.video,
          mime: 'video/mp4',
          size: 2048,
        ),
      );
      expect(ChatLatestActivityResolver.formatMessagePreview(videoMsg), equals('🎥 Video'));

      final voiceMsg = ChatMessage(
        id: 'msg-5',
        chatId: 'chat-1',
        senderId: peerUserId,
        text: '',
        sentAt: baseTime,
        deliveryState: DeliveryState.sent,
        type: MessageType.media,
        media: const MessageMedia(
          url: 'https://example.com/audio.m4a',
          kind: MediaKind.audio,
          mime: 'audio/mp4',
          size: 512,
        ),
      );
      expect(ChatLatestActivityResolver.formatMessagePreview(voiceMsg), equals('🎵 Audio'));
    });

    test('3. Formats all call event modalities and directions accurately', () {
      // Missed voice call
      final missedVoice = CallRecord(
        id: 'c-1',
        chatId: 'chat-1',
        callerId: peerUserId,
        receiverId: currentUserId,
        callType: CallType.audio,
        status: CallStatus.missed,
        startedAt: baseTime,
      );
      expect(
        ChatLatestActivityResolver.formatCallPreview(missedVoice, currentUserId: currentUserId),
        equals('Missed voice call'),
      );

      // Missed video call
      final missedVideo = CallRecord(
        id: 'c-2',
        chatId: 'chat-1',
        callerId: peerUserId,
        receiverId: currentUserId,
        callType: CallType.video,
        status: CallStatus.missed,
        startedAt: baseTime,
      );
      expect(
        ChatLatestActivityResolver.formatCallPreview(missedVideo, currentUserId: currentUserId),
        equals('Missed video call'),
      );

      // Cancelled voice call
      final cancelledVoice = CallRecord(
        id: 'c-3',
        chatId: 'chat-1',
        callerId: currentUserId,
        receiverId: peerUserId,
        callType: CallType.audio,
        status: CallStatus.cancelled,
        startedAt: baseTime,
      );
      expect(
        ChatLatestActivityResolver.formatCallPreview(cancelledVoice, currentUserId: currentUserId),
        equals('Cancelled voice call'),
      );

      // Cancelled video call
      final cancelledVideo = CallRecord(
        id: 'c-4',
        chatId: 'chat-1',
        callerId: currentUserId,
        receiverId: peerUserId,
        callType: CallType.video,
        status: CallStatus.cancelled,
        startedAt: baseTime,
      );
      expect(
        ChatLatestActivityResolver.formatCallPreview(cancelledVideo, currentUserId: currentUserId),
        equals('Cancelled video call'),
      );

      // Outgoing completed call
      final outgoingVoice = CallRecord(
        id: 'c-5',
        chatId: 'chat-1',
        callerId: currentUserId,
        receiverId: peerUserId,
        callType: CallType.audio,
        status: CallStatus.ended,
        startedAt: baseTime,
        durationSeconds: 120,
      );
      expect(
        ChatLatestActivityResolver.formatCallPreview(outgoingVoice, currentUserId: currentUserId),
        equals('Outgoing voice call'),
      );

      // Incoming completed call
      final incomingVoice = CallRecord(
        id: 'c-6',
        chatId: 'chat-1',
        callerId: peerUserId,
        receiverId: currentUserId,
        callType: CallType.audio,
        status: CallStatus.ended,
        startedAt: baseTime,
        durationSeconds: 95,
      );
      expect(
        ChatLatestActivityResolver.formatCallPreview(incomingVoice, currentUserId: currentUserId),
        equals('Incoming voice call'),
      );
    });

    test('4. Newer call replaces older text message preview and timestamp', () {
      final msgTime = baseTime;
      final callTime = baseTime.add(const Duration(minutes: 15));

      final latestCall = CallRecord(
        id: 'call-newer',
        chatId: 'chat-1',
        callerId: peerUserId,
        receiverId: currentUserId,
        callType: CallType.audio,
        status: CallStatus.missed,
        startedAt: callTime,
      );

      final activity = ChatLatestActivityResolver.resolveLatestActivity(
        messageTime: msgTime,
        messagePreview: 'hii',
        lastSenderId: currentUserId,
        lastMessageStatus: 1,
        lastMessageId: 'msg-old',
        latestCall: latestCall,
        currentUserId: currentUserId,
      );

      expect(activity.isCallActivity, isTrue);
      expect(activity.previewText, equals('Missed voice call'));
      expect(activity.timestamp, equals(callTime));
      expect(activity.senderId, equals(peerUserId));
      expect(activity.activityId, equals('call_call-newer'));
    });

    test('5. Older call does NOT override newer message preview', () {
      final callTime = baseTime;
      final msgTime = baseTime.add(const Duration(minutes: 20));

      final olderCall = CallRecord(
        id: 'call-older',
        chatId: 'chat-1',
        callerId: peerUserId,
        receiverId: currentUserId,
        callType: CallType.video,
        status: CallStatus.missed,
        startedAt: callTime,
      );

      final activity = ChatLatestActivityResolver.resolveLatestActivity(
        messageTime: msgTime,
        messagePreview: 'Let me call you later',
        lastSenderId: peerUserId,
        lastMessageStatus: 2,
        lastMessageId: 'msg-new',
        latestCall: olderCall,
        currentUserId: currentUserId,
      );

      expect(activity.isCallActivity, isFalse);
      expect(activity.previewText, equals('Let me call you later'));
      expect(activity.timestamp, equals(msgTime));
      expect(activity.senderId, equals(peerUserId));
      expect(activity.activityId, equals('msg-new'));
    });

    test('6. Null latest call preserves message activity unchanged', () {
      final activity = ChatLatestActivityResolver.resolveLatestActivity(
        messageTime: baseTime,
        messagePreview: 'Regular message',
        lastSenderId: peerUserId,
        lastMessageStatus: 1,
        lastMessageId: 'msg-regular',
        latestCall: null,
        currentUserId: currentUserId,
      );

      expect(activity.isCallActivity, isFalse);
      expect(activity.previewText, equals('Regular message'));
      expect(activity.timestamp, equals(baseTime));
      expect(activity.senderId, equals(peerUserId));
    });
  });
}
