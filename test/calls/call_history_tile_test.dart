// test/calls/call_history_tile_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:instant_messenger/features/calls/domain/models/call_enums.dart';
import 'package:instant_messenger/features/calls/domain/models/call_record.dart';
import 'package:instant_messenger/features/calls/presentation/widgets/call_history_tile.dart';

void main() {
  group('CallHistoryTile Widget Tests', () {
    const currentUserId = 'user-me-123';

    testWidgets('1. Outgoing voice call renders correct title, green icon, and duration', (tester) async {
      final now = DateTime.now();
      final call = CallRecord(
        id: 'call-out-1',
        chatId: 'chat-1',
        callerId: currentUserId,
        receiverId: 'user-bob-456',
        callType: CallType.audio,
        status: CallStatus.ended,
        startedAt: now,
        durationSeconds: 154, // 02:34
        peerName: 'Bob Smith',
      );

      var callBackTriggered = false;
      var tileTapped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CallHistoryTile(
              call: call,
              currentUserId: currentUserId,
              onCallBack: () => callBackTriggered = true,
              onTap: () => tileTapped = true,
            ),
          ),
        ),
      );

      expect(find.text('Bob Smith'), findsOneWidget);
      expect(find.textContaining('Today'), findsOneWidget);
      expect(find.textContaining('02:34'), findsOneWidget);

      // Verify outgoing direction icon
      expect(find.byIcon(Icons.call_made), findsOneWidget);
      expect(find.byIcon(Icons.call), findsOneWidget); // Trailing action button

      // Test callbacks
      await tester.tap(find.byIcon(Icons.call));
      expect(callBackTriggered, isTrue);

      await tester.tap(find.text('Bob Smith'));
      expect(tileTapped, isTrue);
    });

    testWidgets('2. Missed video call displays red accent, videocam_off icon, and bold title', (tester) async {
      final now = DateTime.now();
      final call = CallRecord(
        id: 'call-missed-1',
        chatId: 'chat-2',
        callerId: 'user-alice-789',
        receiverId: currentUserId,
        callType: CallType.video,
        status: CallStatus.missed,
        startedAt: now,
        peerName: 'Alice Cooper',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CallHistoryTile(
              call: call,
              currentUserId: currentUserId,
            ),
          ),
        ),
      );

      expect(find.text('Alice Cooper'), findsOneWidget);
      expect(find.byIcon(Icons.videocam_off_outlined), findsOneWidget);
      expect(find.byIcon(Icons.videocam), findsOneWidget); // Trailing video call button

      final textWidget = tester.widget<Text>(find.text('Alice Cooper'));
      expect(textWidget.style?.fontWeight, FontWeight.bold);
      expect(textWidget.style?.color, Colors.red.shade400);
    });

    testWidgets('3. Incoming accepted call renders call_received icon', (tester) async {
      final now = DateTime.now();
      final call = CallRecord(
        id: 'call-inc-1',
        chatId: 'chat-3',
        callerId: 'user-carol-999',
        receiverId: currentUserId,
        callType: CallType.audio,
        status: CallStatus.ended,
        startedAt: now,
        durationSeconds: 45,
        peerName: 'Carol Danvers',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CallHistoryTile(
              call: call,
              currentUserId: currentUserId,
            ),
          ),
        ),
      );

      expect(find.text('Carol Danvers'), findsOneWidget);
      expect(find.byIcon(Icons.call_received), findsOneWidget);
      expect(find.textContaining('00:45'), findsOneWidget);
    });
  });
}
