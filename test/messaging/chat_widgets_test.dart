import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:instant_messenger/features/messaging/domain/models/user_presence.dart';
import 'package:instant_messenger/features/messaging/presentation/widgets/chat_date_separator.dart';
import 'package:instant_messenger/features/messaging/presentation/widgets/chat_presence_subtitle.dart';
import 'package:instant_messenger/features/messaging/presentation/widgets/typing_dots.dart';

void main() {
  group('Chat Extracted Widgets Tests', () {
    testWidgets('ChatDateSeparator renders formatted date text', (
      tester,
    ) async {
      final now = DateTime(2026, 10, 27, 12, 0);
      final today = DateTime(2026, 10, 27, 9, 30);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChatDateSeparator(
              date: today,
              now: now,
            ),
          ),
        ),
      );

      expect(find.text('Today'), findsOneWidget);
    });

    testWidgets('ChatPresenceSubtitle shows TypingDots when typing', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ChatPresenceSubtitle(
              isTyping: true,
              presenceAsync: AsyncValue.data(
                UserPresence(online: true, lastSeen: null),
              ),
            ),
          ),
        ),
      );

      expect(find.byType(TypingDots), findsOneWidget);
    });

    testWidgets('ChatPresenceSubtitle shows online status when not typing', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ChatPresenceSubtitle(
              isTyping: false,
              presenceAsync: AsyncValue.data(
                UserPresence(online: true, lastSeen: null),
              ),
            ),
          ),
        ),
      );

      expect(find.text('online'), findsOneWidget);
    });
  });
}
