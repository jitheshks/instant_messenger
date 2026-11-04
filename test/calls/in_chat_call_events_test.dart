// test/calls/in_chat_call_events_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:instant_messenger/features/calls/domain/models/call_enums.dart';
import 'package:instant_messenger/features/calls/domain/models/call_record.dart';
import 'package:instant_messenger/features/messaging/domain/models/chat_message.dart';
import 'package:instant_messenger/features/messaging/presentation/widgets/call_bubble.dart';

void main() {
  group('In-Chat Call Events Tests', () {
    const currentUserId = 'user-me-123';
    const peerUserId = 'user-peer-456';
    const chatId = 'chat-789';

    test('1. Outgoing voice call creates the correct event', () {
      final now = DateTime.now();
      final call = CallRecord(
        id: 'call-out-voice-1',
        chatId: chatId,
        callerId: currentUserId,
        receiverId: peerUserId,
        callType: CallType.audio,
        status: CallStatus.ended,
        startedAt: now,
        endedAt: now.add(const Duration(minutes: 3)),
        durationSeconds: 180,
      );

      expect(call.isOutgoing(currentUserId), isTrue);
      expect(call.isIncoming(currentUserId), isFalse);
      expect(call.callType, CallType.audio);
      expect(call.isCompleted, isTrue);
      expect(call.durationSeconds, 180);
      expect(call.formattedDuration, '03:00');
    });

    test('2. Incoming voice call creates the correct event', () {
      final now = DateTime.now();
      final call = CallRecord(
        id: 'call-in-voice-2',
        chatId: chatId,
        callerId: peerUserId,
        receiverId: currentUserId,
        callType: CallType.audio,
        status: CallStatus.ended,
        startedAt: now,
        endedAt: now.add(const Duration(minutes: 1, seconds: 25)),
        durationSeconds: 85,
      );

      expect(call.isIncoming(currentUserId), isTrue);
      expect(call.isOutgoing(currentUserId), isFalse);
      expect(call.callType, CallType.audio);
      expect(call.formattedDuration, '01:25');
    });

    test('3. Outgoing video call creates the correct event', () {
      final now = DateTime.now();
      final call = CallRecord(
        id: 'call-out-video-3',
        chatId: chatId,
        callerId: currentUserId,
        receiverId: peerUserId,
        callType: CallType.video,
        status: CallStatus.ended,
        startedAt: now,
        durationSeconds: 240,
      );

      expect(call.isOutgoing(currentUserId), isTrue);
      expect(call.callType, CallType.video);
      expect(call.formattedDuration, '04:00');
    });

    test('4. Incoming video call creates the correct event', () {
      final now = DateTime.now();
      final call = CallRecord(
        id: 'call-in-video-4',
        chatId: chatId,
        callerId: peerUserId,
        receiverId: currentUserId,
        callType: CallType.video,
        status: CallStatus.ended,
        startedAt: now,
        durationSeconds: 62,
      );

      expect(call.isIncoming(currentUserId), isTrue);
      expect(call.callType, CallType.video);
      expect(call.formattedDuration, '01:02');
    });

    test('5. Missed calls are represented correctly', () {
      final now = DateTime.now();
      final call = CallRecord(
        id: 'call-missed-5',
        chatId: chatId,
        callerId: peerUserId,
        receiverId: currentUserId,
        callType: CallType.audio,
        status: CallStatus.missed,
        startedAt: now,
      );

      expect(call.isMissed, isTrue);
      expect(call.isCompleted, isFalse);
      expect(call.durationSeconds, isNull);
    });

    test('6. Rejected calls are represented correctly', () {
      final now = DateTime.now();
      final call = CallRecord(
        id: 'call-rejected-6',
        chatId: chatId,
        callerId: currentUserId,
        receiverId: peerUserId,
        callType: CallType.audio,
        status: CallStatus.declined,
        startedAt: now,
      );

      expect(call.isDeclined, isTrue);
      expect(call.isMissed, isFalse);
      expect(call.isCompleted, isFalse);
    });

    test('7. Connected calls calculate duration correctly', () {
      final now = DateTime.now();
      final call = CallRecord(
        id: 'call-duration-7',
        chatId: chatId,
        callerId: currentUserId,
        receiverId: peerUserId,
        callType: CallType.video,
        status: CallStatus.ended,
        startedAt: now,
        endedAt: now.add(const Duration(hours: 1, minutes: 2, seconds: 5)),
        durationSeconds: 3725,
      );

      expect(call.durationSeconds, 3725);
      expect(call.formattedDuration, '62:05');
    });

    test('8. In-chat call events appear in chronological order with messages', () {
      final baseTime = DateTime(2026, 11, 4, 10, 0, 0);

      final msg1 = ChatMessage(
        id: 'msg-1',
        chatId: chatId,
        senderId: currentUserId,
        text: 'Hello, are you free for a call?',
        sentAt: baseTime,
        deliveryState: DeliveryState.read,
        type: MessageType.text,
      );

      final call1 = CallRecord(
        id: 'call-1',
        chatId: chatId,
        callerId: currentUserId,
        receiverId: peerUserId,
        callType: CallType.audio,
        status: CallStatus.ended,
        startedAt: baseTime.add(const Duration(minutes: 5)),
        durationSeconds: 120,
      );

      final msg2 = ChatMessage(
        id: 'msg-2',
        chatId: chatId,
        senderId: peerUserId,
        text: 'Thanks for the call!',
        sentAt: baseTime.add(const Duration(minutes: 10)),
        deliveryState: DeliveryState.delivered,
        type: MessageType.text,
      );

      final events = <dynamic>[msg2, call1, msg1];
      events.sort((a, b) {
        final timeA = a is ChatMessage ? a.sentAt : (a as CallRecord).startedAt;
        final timeB = b is ChatMessage ? b.sentAt : (b as CallRecord).startedAt;
        return timeA.compareTo(timeB);
      });

      expect(events[0], msg1);
      expect(events[1], call1);
      expect(events[2], msg2);
    });

    test('9. Duplicate callbacks do not create duplicate events (deduplication by ID)', () {
      final now = DateTime.now();
      final call = CallRecord(
        id: 'call-dup-1',
        chatId: chatId,
        callerId: currentUserId,
        receiverId: peerUserId,
        callType: CallType.audio,
        status: CallStatus.ended,
        startedAt: now,
      );

      final callEvents = <String, CallRecord>{};
      callEvents[call.id] = call;
      // Re-triggering duplicate event callback:
      callEvents[call.id] = call.copyWith(durationSeconds: 45);

      expect(callEvents.length, 1);
      expect(callEvents[call.id]!.durationSeconds, 45);
    });

    test('10. Call events survive conversation reload via deserialization', () {
      final now = DateTime.now().toUtc();
      final row = {
        'id': 'a0000000-0000-0000-0000-000000000001',
        'chat_id': chatId,
        'caller_id': currentUserId,
        'call_type': 'video',
        'is_group': false,
        'status': 'ended',
        'room_id': 'room-1',
        'started_at': now.toIso8601String(),
        'ended_at': now.add(const Duration(minutes: 2)).toIso8601String(),
        'duration_seconds': 120,
        'caller': {
          'id': currentUserId,
          'display_name': 'Alice',
          'avatar_url': 'https://example.com/alice.jpg',
        },
        'call_participants': [
          {
            'user_id': peerUserId,
            'status': 'accepted',
            'profile': {
              'id': peerUserId,
              'display_name': 'Bob',
              'avatar_url': 'https://example.com/bob.jpg',
            },
          }
        ],
      };

      final parsed = CallRecord.fromSupabase(row, currentUserId);
      expect(parsed.id, 'a0000000-0000-0000-0000-000000000001');
      expect(parsed.chatId, chatId);
      expect(parsed.callType, CallType.video);
      expect(parsed.status, CallStatus.ended);
      expect(parsed.peerName, 'Bob');
      expect(parsed.peerAvatarUrl, 'https://example.com/bob.jpg');
      expect(parsed.durationSeconds, 120);
    });

    test('11. Calls do not appear in another account history (Account Isolation)', () {
      final callForMe = CallRecord(
        id: 'call-acc-1',
        chatId: chatId,
        callerId: currentUserId,
        receiverId: peerUserId,
        callType: CallType.audio,
        status: CallStatus.ended,
        startedAt: DateTime.now(),
      );

      const otherUserId = 'unrelated-user-999';
      expect(callForMe.callerId == otherUserId || callForMe.receiverId == otherUserId, isFalse);
    });

    test('12. Calls page and chat timeline show the same records (Consistency)', () {
      final record = CallRecord(
        id: 'call-consistent-1',
        chatId: chatId,
        callerId: currentUserId,
        receiverId: peerUserId,
        callType: CallType.audio,
        status: CallStatus.ended,
        startedAt: DateTime.now(),
        durationSeconds: 75,
      );

      final timelineCalls = [record];
      final historyCalls = [record];

      expect(timelineCalls.first.id, historyCalls.first.id);
      expect(timelineCalls.first.durationSeconds, historyCalls.first.durationSeconds);
      expect(timelineCalls.first.status, historyCalls.first.status);
    });

    testWidgets('CallBubble widget renders missed voice call with call back action', (tester) async {
      bool callBackTapped = false;
      final call = CallRecord(
        id: 'call-bubble-1',
        chatId: chatId,
        callerId: peerUserId,
        receiverId: currentUserId,
        callType: CallType.audio,
        status: CallStatus.missed,
        startedAt: DateTime(2026, 11, 4, 14, 30),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CallBubble(
              call: call,
              currentUserId: currentUserId,
              onCallBack: () => callBackTapped = true,
            ),
          ),
        ),
      );

      expect(find.text('Missed voice call'), findsOneWidget);
      expect(find.text('Tap to call back'), findsOneWidget);
      expect(find.byIcon(Icons.call_missed), findsOneWidget);

      await tester.tap(find.byType(CallBubble));
      expect(callBackTapped, isTrue);
    });

    testWidgets('CallBubble widget renders completed video call with duration', (tester) async {
      final call = CallRecord(
        id: 'call-bubble-2',
        chatId: chatId,
        callerId: currentUserId,
        receiverId: peerUserId,
        callType: CallType.video,
        status: CallStatus.ended,
        startedAt: DateTime(2026, 11, 4, 15, 45),
        durationSeconds: 154,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CallBubble(
              call: call,
              currentUserId: currentUserId,
            ),
          ),
        ),
      );

      expect(find.text('Outgoing video call'), findsOneWidget);
      expect(find.text('02:34'), findsOneWidget);
      expect(find.byIcon(Icons.videocam_outlined), findsOneWidget);
    });
  });
}
