import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:instant_messenger/shared/widgets/states/empty_state_view.dart';

void main() {
  group('EmptyStateView Tests', () {
    testWidgets('renders icon, title, optional message and triggers action button', (
      tester,
    ) async {
      var actionTriggered = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EmptyStateView(
              icon: Icons.chat_bubble_outline,
              title: 'No chats yet',
              message: 'Start a conversation with your contacts',
              actionLabel: 'Start a chat',
              onAction: () => actionTriggered = true,
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.chat_bubble_outline), findsOneWidget);
      expect(find.text('No chats yet'), findsOneWidget);
      expect(
        find.text('Start a conversation with your contacts'),
        findsOneWidget,
      );
      expect(find.text('Start a chat'), findsOneWidget);

      await tester.tap(find.text('Start a chat'));
      await tester.pump();

      expect(actionTriggered, isTrue);
    });
  });
}
