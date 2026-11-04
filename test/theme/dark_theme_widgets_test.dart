import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:instant_messenger/app/theme/app_colors.dart';
import 'package:instant_messenger/app/theme/app_theme.dart';
import 'package:instant_messenger/features/messaging/domain/models/chat_message.dart';
import 'package:instant_messenger/features/messaging/presentation/providers/messaging_providers.dart';
import 'package:instant_messenger/features/messaging/presentation/widgets/chat_bubble.dart';
import 'package:instant_messenger/features/messaging/presentation/widgets/chat_delivery_row.dart';
import 'package:instant_messenger/features/messaging/presentation/widgets/chat_input.dart';
import 'package:instant_messenger/features/messaging/presentation/widgets/jump_to_latest_button.dart';
import 'package:instant_messenger/features/chats/presentation/widgets/delete_chats_dialog.dart';
import 'package:instant_messenger/features/messaging/presentation/controllers/chat_scroll_notifier.dart';

void main() {
  group('Dark Theme Widget Rendering Tests', () {
    testWidgets('ChatInput renders with dark input background and readable text in dark mode', (tester) async {
      const args = ChatControllerArgs(
        chatId: 'test-chat-1',
        currentUserId: 'user-a',
        otherUserId: 'user-b',
      );

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.light,
            darkTheme: AppTheme.dark,
            themeMode: ThemeMode.dark,
            home: const Scaffold(
              body: ChatInput(
                args: args,
                otherName: 'Alice',
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Find the input pill Container
      final containers = tester.widgetList<Container>(find.byType(Container));
      final pillContainer = containers.firstWhere(
        (c) {
          final dec = c.decoration;
          return dec is BoxDecoration &&
              dec.color == AppColors.darkInputBackground;
        },
      );
      expect(
        (pillContainer.decoration as BoxDecoration).color,
        equals(AppColors.darkInputBackground),
        reason: 'Input pill must use dark input background in dark mode',
      );

      // Verify TextField has dark text style and readable hint
      final textField = tester.widget<TextField>(find.byType(TextField));
      expect(textField.style?.color, equals(AppColors.darkTextPrimary));
      expect(
        textField.decoration?.hintStyle?.color,
        equals(AppColors.darkInputHint),
      );
    });

    testWidgets('ChatBubble sent & received render with theme extension colors in dark mode', (tester) async {
      final sentMsg = ChatMessage(
        id: 'msg-1',
        chatId: 'chat-1',
        senderId: 'user-a',
        text: 'Hello from sender',
        type: MessageType.text,
        sentAt: DateTime.utc(2026, 10, 28, 12, 0),
        deliveryState: DeliveryState.delivered,
      );

      final receivedMsg = ChatMessage(
        id: 'msg-2',
        chatId: 'chat-1',
        senderId: 'user-b',
        text: 'Hello from receiver',
        type: MessageType.text,
        sentAt: DateTime.utc(2026, 10, 28, 12, 1),
        deliveryState: DeliveryState.read,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          themeMode: ThemeMode.dark,
          home: Scaffold(
            body: Column(
              children: [
                ChatBubble(msg: sentMsg, isMe: true),
                ChatBubble(msg: receivedMsg, isMe: false),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Check sent bubble container color
      final containers = tester.widgetList<Container>(find.byType(Container));
      final sentContainer = containers.firstWhere(
        (c) {
          final dec = c.decoration;
          return dec is BoxDecoration && dec.color == AppColors.darkBubbleSent;
        },
      );
      expect(
        (sentContainer.decoration as BoxDecoration).color,
        equals(AppColors.darkBubbleSent),
      );

      // Check received bubble container color
      final receivedContainer = containers.firstWhere(
        (c) {
          final dec = c.decoration;
          return dec is BoxDecoration &&
              dec.color == AppColors.darkBubbleReceived;
        },
      );
      expect(
        (receivedContainer.decoration as BoxDecoration).color,
        equals(AppColors.darkBubbleReceived),
      );

      // Check text colors in both bubbles
      final sentText = tester.widget<Text>(find.text('Hello from sender'));
      expect(sentText.style?.color, equals(AppColors.darkTextPrimary));

      final receivedText = tester.widget<Text>(find.text('Hello from receiver'));
      expect(receivedText.style?.color, equals(AppColors.darkTextPrimary));
    });

    testWidgets('ChatDeliveryRow displays correct timestamp and tick colors in dark mode', (tester) async {
      final readMsg = ChatMessage(
        id: 'msg-read',
        chatId: 'chat-1',
        senderId: 'user-a',
        text: 'Seen message',
        type: MessageType.text,
        sentAt: DateTime.utc(2026, 10, 28, 14, 30),
        deliveryState: DeliveryState.read,
      );

      final deliveredMsg = ChatMessage(
        id: 'msg-delivered',
        chatId: 'chat-1',
        senderId: 'user-a',
        text: 'Delivered message',
        type: MessageType.text,
        sentAt: DateTime.utc(2026, 10, 28, 14, 31),
        deliveryState: DeliveryState.delivered,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          themeMode: ThemeMode.dark,
          home: Scaffold(
            body: Column(
              children: [
                ChatDeliveryRow(msg: readMsg),
                ChatDeliveryRow(msg: deliveredMsg),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Find timestamp texts
      final timestampTexts = tester.widgetList<Text>(find.byType(Text));
      for (final t in timestampTexts) {
        expect(t.style?.color, equals(AppColors.darkTimestampSent));
      }

      // Check read tick color
      final icons = tester.widgetList<Icon>(find.byType(Icon));
      final readIcon = icons.firstWhere((i) => i.color == AppColors.darkTickRead);
      expect(readIcon.color, equals(AppColors.darkTickRead));

      // Check delivered tick color
      final deliveredIcon = icons.firstWhere(
        (i) => i.color == AppColors.darkTickDelivered,
      );
      expect(deliveredIcon.color, equals(AppColors.darkTickDelivered));
    });

    testWidgets('JumpToLatestButton renders with dark surfaceContainerHigh in dark mode', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            chatScrollControllerProvider.overrideWith(
              () => _MockChatScrollNotifier(
                const ChatScrollState(showJumpButton: true, unreadCount: 3),
              ),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.light,
            darkTheme: AppTheme.dark,
            themeMode: ThemeMode.dark,
            home: const Scaffold(
              body: Stack(
                children: [
                  JumpToLatestButton(),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Find the circular button container
      final containers = tester.widgetList<Container>(find.byType(Container));
      final buttonContainer = containers.firstWhere(
        (c) {
          final dec = c.decoration;
          return dec is BoxDecoration &&
              dec.shape == BoxShape.circle &&
              dec.color == AppColors.darkSurfaceContainerHigh;
        },
      );
      expect(
        (buttonContainer.decoration as BoxDecoration).color,
        equals(AppColors.darkSurfaceContainerHigh),
      );

      // Icon should be dark onSurface
      final icon = tester.widget<Icon>(find.byIcon(Icons.keyboard_arrow_down));
      expect(icon.color, equals(AppColors.darkTextPrimary));
    });

    testWidgets('Delete chats dialog uses theme error color for destructive action', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          themeMode: ThemeMode.dark,
          home: Scaffold(
            body: Builder(
              builder: (ctx) => ElevatedButton(
                onPressed: () => showDeleteChatDialog(ctx, 1),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      final deleteText = tester.widget<Text>(find.text('Delete chat'));
      expect(deleteText.style?.color, equals(AppColors.errorDark));
    });
  });
}

class _MockChatScrollNotifier extends ChatScrollNotifier {
  final ChatScrollState _initial;
  _MockChatScrollNotifier(this._initial);

  @override
  ChatScrollState build() => _initial;
}
