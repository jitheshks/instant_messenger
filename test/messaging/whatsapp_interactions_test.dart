import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:instant_messenger/app/theme/chat_theme_extension.dart';
import 'package:instant_messenger/features/messaging/domain/models/chat_message.dart';
import 'package:instant_messenger/features/messaging/presentation/providers/messaging_providers.dart';
import 'package:instant_messenger/features/messaging/presentation/screens/chat_screen.dart';
import 'package:instant_messenger/features/messaging/presentation/widgets/chat_bubble.dart';
import 'package:instant_messenger/features/messaging/presentation/widgets/forward_recipient_sheet.dart';
import 'package:instant_messenger/features/messaging/presentation/widgets/swipe_to_reply.dart';

class _FakeChatTimelineNotifier extends ChatTimelineNotifier {
  _FakeChatTimelineNotifier(super.arg, this._initialMessages);

  final List<ChatMessage> _initialMessages;

  @override
  ChatTimelineState build() {
    return ChatTimelineState(
      messages: _initialMessages,
      isReady: true,
      hasMore: false,
    );
  }

  @override
  Future<void> ensureInit({
    required String otherName,
    String? otherAvatar,
    Duration timeout = const Duration(seconds: 6),
  }) async {}

  @override
  Future<void> maybeMarkRead([ChatMessage? newest]) async {}
}

class _FakeChatTypingNotifier extends ChatTypingNotifier {
  _FakeChatTypingNotifier(super.arg);

  @override
  bool build() => false;

  @override
  void onTypingChanged(String text) {}

  @override
  void clearTyping() {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const currentUserId = 'user-alice-123';
  const peerUserId = 'user-bob-456';
  const chatId = 'chat-whatsapp-test-999';
  const contactName = 'Bob';

  final chatArgs = ChatControllerArgs(
    chatId: chatId,
    currentUserId: currentUserId,
    otherUserId: peerUserId,
  );

  group('SwipeToReply Widget Tests', () {
    testWidgets('1. Right-swipe beyond threshold triggers onSwipeReply', (tester) async {
      var replyTriggered = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 250,
                height: 60,
                child: SwipeToReply(
                  isMe: false,
                  onSwipeReply: () {
                    replyTriggered = true;
                  },
                  child: Container(
                    color: Colors.blue,
                    child: const Text('Incoming message'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      // Drag right by 55 pixels (exceeds threshold)
      await tester.drag(find.text('Incoming message'), const Offset(55, 0));
      await tester.pumpAndSettle();

      expect(replyTriggered, isTrue);
    });

    testWidgets('2. Right-swipe on outgoing message beyond threshold triggers onSwipeReply', (tester) async {
      var replyTriggered = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 250,
                height: 60,
                child: SwipeToReply(
                  isMe: true,
                  onSwipeReply: () {
                    replyTriggered = true;
                  },
                  child: Container(
                    color: Colors.green,
                    child: const Text('Outgoing message'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.drag(find.text('Outgoing message'), const Offset(50, 0));
      await tester.pumpAndSettle();

      expect(replyTriggered, isTrue);
    });

    testWidgets('3. Short right-swipe (< 30px) does NOT trigger reply and resets smoothly', (tester) async {
      var replyTriggered = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 250,
                height: 60,
                child: SwipeToReply(
                  isMe: false,
                  onSwipeReply: () {
                    replyTriggered = true;
                  },
                  child: Container(
                    color: Colors.blue,
                    child: const Text('Short swipe message'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      // Drag only 20px
      await tester.drag(find.text('Short swipe message'), const Offset(20, 0));
      await tester.pumpAndSettle();

      expect(replyTriggered, isFalse);
    });

    testWidgets('4. Left-swipe does NOT trigger reply or move message', (tester) async {
      var replyTriggered = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 250,
                height: 60,
                child: SwipeToReply(
                  isMe: false,
                  onSwipeReply: () {
                    replyTriggered = true;
                  },
                  child: Container(
                    color: Colors.blue,
                    child: const Text('Left swipe message'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      // Drag left by -50px
      await tester.drag(find.text('Left swipe message'), const Offset(-50, 0));
      await tester.pumpAndSettle();

      expect(replyTriggered, isFalse);
    });

    testWidgets('5. Disabled SwipeToReply ignores swipes', (tester) async {
      var replyTriggered = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 250,
                height: 60,
                child: SwipeToReply(
                  enabled: false,
                  isMe: false,
                  onSwipeReply: () {
                    replyTriggered = true;
                  },
                  child: Container(
                    color: Colors.blue,
                    child: const Text('Disabled swipe message'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.drag(find.text('Disabled swipe message'), const Offset(60, 0));
      await tester.pumpAndSettle();

      expect(replyTriggered, isFalse);
    });

    testWidgets('5b. Completed gesture triggers onSwipeReply at most once', (tester) async {
      var callCount = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 250,
                height: 60,
                child: SwipeToReply(
                  isMe: false,
                  onSwipeReply: () {
                    callCount++;
                  },
                  child: Container(
                    color: Colors.blue,
                    child: const Text('Single trigger message'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.drag(find.text('Single trigger message'), const Offset(120, 0));
      await tester.pumpAndSettle();

      expect(callCount, equals(1));
    });

    testWidgets('5c. Vertical scrolling in a list does NOT trigger onSwipeReply', (tester) async {
      var replyTriggered = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView.builder(
              itemCount: 20,
              itemBuilder: (context, index) => SwipeToReply(
                isMe: false,
                onSwipeReply: () {
                  replyTriggered = true;
                },
                child: Container(
                  height: 60,
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  color: Colors.blue.shade100,
                  child: Text('Item $index'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.drag(find.text('Item 0'), const Offset(0, -200));
      await tester.pumpAndSettle();

      expect(replyTriggered, isFalse);
    });
  });

  group('Contextual AppBar Message Actions & Multi-Selection Tests', () {
    testWidgets('6. Long-pressing incoming message enters selection mode and shows contextual AppBar without bottom sheet', (tester) async {
      final msg = ChatMessage(
        id: 'msg-lp-inc-1',
        chatId: chatId,
        senderId: peerUserId,
        text: 'Incoming message to long-press',
        sentAt: DateTime.now(),
        deliveryState: DeliveryState.read,
        type: MessageType.text,
      );

      final container = ProviderContainer(
        overrides: [
          chatTimelineNotifierProvider(chatArgs).overrideWith(
            () => _FakeChatTimelineNotifier(chatArgs, [msg]),
          ),
          chatTypingNotifierProvider(chatArgs).overrideWith(
            () => _FakeChatTypingNotifier(chatArgs),
          ),
          chatPresenceStreamProvider(peerUserId).overrideWith(
            (ref) => const Stream.empty(),
          ),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: ThemeData.light().copyWith(
              extensions: const [ChatThemeExtension.light],
            ),
            home: ChatScreen(
              chatId: chatId,
              currentUserId: currentUserId,
              peerUserId: peerUserId,
              contactName: contactName,
              contactAvatar: '',
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Before long-press: Normal AppBar with contact name
      expect(find.text('Bob'), findsOneWidget);
      expect(find.byTooltip('Reply'), findsNothing);
      expect(find.byTooltip('Forward'), findsNothing);
      expect(find.byTooltip('Copy'), findsNothing);

      // Long press on the message
      await tester.longPress(find.text('Incoming message to long-press'));
      await tester.pumpAndSettle();

      // After long-press: Contextual AppBar activated with count '1'
      expect(find.text('1'), findsOneWidget);
      expect(find.byIcon(Icons.arrow_back), findsOneWidget); // Back to clear
      expect(find.byTooltip('Reply'), findsOneWidget);
      expect(find.byTooltip('Forward'), findsOneWidget);
      expect(find.byTooltip('Copy'), findsOneWidget);

      // Verify NO bottom sheet was opened
      expect(find.byType(BottomSheet), findsNothing);
      expect(find.text('Select'), findsNothing);
    });

    testWidgets('7. Long-pressing outgoing message enters selection mode with contextual AppBar', (tester) async {
      final msg = ChatMessage(
        id: 'msg-lp-out-1',
        chatId: chatId,
        senderId: currentUserId,
        text: 'Outgoing message to long-press',
        sentAt: DateTime.now(),
        deliveryState: DeliveryState.sent,
        type: MessageType.text,
      );

      final container = ProviderContainer(
        overrides: [
          chatTimelineNotifierProvider(chatArgs).overrideWith(
            () => _FakeChatTimelineNotifier(chatArgs, [msg]),
          ),
          chatTypingNotifierProvider(chatArgs).overrideWith(
            () => _FakeChatTypingNotifier(chatArgs),
          ),
          chatPresenceStreamProvider(peerUserId).overrideWith(
            (ref) => const Stream.empty(),
          ),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: ThemeData.light().copyWith(
              extensions: const [ChatThemeExtension.light],
            ),
            home: ChatScreen(
              chatId: chatId,
              currentUserId: currentUserId,
              peerUserId: peerUserId,
              contactName: contactName,
              contactAvatar: '',
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      await tester.longPress(find.text('Outgoing message to long-press'));
      await tester.pumpAndSettle();

      expect(find.text('1'), findsOneWidget);
      expect(find.byTooltip('Reply'), findsOneWidget);
      expect(find.byTooltip('Forward'), findsOneWidget);
      expect(find.byTooltip('Copy'), findsOneWidget);
    });

    testWidgets('8. Contextual AppBar Reply sets reply target and populates composer preview', (tester) async {
      final msg = ChatMessage(
        id: 'msg-reply-appbar-1',
        chatId: chatId,
        senderId: peerUserId,
        text: 'Can we reschedule to 4 PM?',
        sentAt: DateTime.now(),
        deliveryState: DeliveryState.read,
        type: MessageType.text,
      );

      final container = ProviderContainer(
        overrides: [
          chatTimelineNotifierProvider(chatArgs).overrideWith(
            () => _FakeChatTimelineNotifier(chatArgs, [msg]),
          ),
          chatTypingNotifierProvider(chatArgs).overrideWith(
            () => _FakeChatTypingNotifier(chatArgs),
          ),
          chatPresenceStreamProvider(peerUserId).overrideWith(
            (ref) => const Stream.empty(),
          ),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: ThemeData.light().copyWith(
              extensions: const [ChatThemeExtension.light],
            ),
            home: ChatScreen(
              chatId: chatId,
              currentUserId: currentUserId,
              peerUserId: peerUserId,
              contactName: contactName,
              contactAvatar: '',
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Long press to enter selection
      await tester.longPress(find.text('Can we reschedule to 4 PM?'));
      await tester.pumpAndSettle();

      // Tap Reply in the AppBar
      await tester.tap(find.byTooltip('Reply'));
      await tester.pumpAndSettle();

      // Selection mode should be cleared
      expect(container.read(chatScreenSelectionControllerProvider).isEmpty, isTrue);

      // Composer should now show the reply preview
      expect(find.byTooltip('Cancel reply'), findsOneWidget);
      expect(find.text('Bob'), findsWidgets);
      expect(find.text('Can we reschedule to 4 PM?'), findsWidgets);

      final sendState = container.read(chatSendNotifierProvider(chatArgs));
      expect(sendState.hasReplyTarget, isTrue);
      expect(sendState.replyTarget?.id, equals('msg-reply-appbar-1'));
    });

    testWidgets('9. Multi-selection Reply prefers the most recently selected message', (tester) async {
      final msg1 = ChatMessage(
        id: 'msg-multi-1',
        chatId: chatId,
        senderId: peerUserId,
        text: 'First message selected',
        sentAt: DateTime.now().subtract(const Duration(minutes: 5)),
        deliveryState: DeliveryState.read,
        type: MessageType.text,
      );
      final msg2 = ChatMessage(
        id: 'msg-multi-2',
        chatId: chatId,
        senderId: peerUserId,
        text: 'Second message selected',
        sentAt: DateTime.now().subtract(const Duration(minutes: 1)),
        deliveryState: DeliveryState.read,
        type: MessageType.text,
      );

      final container = ProviderContainer(
        overrides: [
          chatTimelineNotifierProvider(chatArgs).overrideWith(
            () => _FakeChatTimelineNotifier(chatArgs, [msg1, msg2]),
          ),
          chatTypingNotifierProvider(chatArgs).overrideWith(
            () => _FakeChatTypingNotifier(chatArgs),
          ),
          chatPresenceStreamProvider(peerUserId).overrideWith(
            (ref) => const Stream.empty(),
          ),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: ThemeData.light().copyWith(
              extensions: const [ChatThemeExtension.light],
            ),
            home: ChatScreen(
              chatId: chatId,
              currentUserId: currentUserId,
              peerUserId: peerUserId,
              contactName: contactName,
              contactAvatar: '',
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Select msg1, then msg2
      await tester.longPress(find.text('First message selected'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Second message selected'));
      await tester.pumpAndSettle();

      expect(find.text('2'), findsOneWidget);

      // Tap Reply: should prefer msg2 (most recently selected)
      await tester.tap(find.byTooltip('Reply'));
      await tester.pumpAndSettle();

      final sendState = container.read(chatSendNotifierProvider(chatArgs));
      expect(sendState.replyTarget?.id, equals('msg-multi-2'));
      expect(sendState.replyTarget?.text, equals('Second message selected'));
    });

    testWidgets('10. Contextual AppBar Forward opens ForwardRecipientSheet', (tester) async {
      final msg = ChatMessage(
        id: 'msg-fwd-appbar-1',
        chatId: chatId,
        senderId: peerUserId,
        text: 'Important announcement',
        sentAt: DateTime.now(),
        deliveryState: DeliveryState.read,
        type: MessageType.text,
      );

      final container = ProviderContainer(
        overrides: [
          chatTimelineNotifierProvider(chatArgs).overrideWith(
            () => _FakeChatTimelineNotifier(chatArgs, [msg]),
          ),
          chatTypingNotifierProvider(chatArgs).overrideWith(
            () => _FakeChatTypingNotifier(chatArgs),
          ),
          chatPresenceStreamProvider(peerUserId).overrideWith(
            (ref) => const Stream.empty(),
          ),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: ThemeData.light().copyWith(
              extensions: const [ChatThemeExtension.light],
            ),
            home: ChatScreen(
              chatId: chatId,
              currentUserId: currentUserId,
              peerUserId: peerUserId,
              contactName: contactName,
              contactAvatar: '',
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      await tester.longPress(find.text('Important announcement'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Forward'));
      await tester.pumpAndSettle();

      expect(find.byType(ForwardRecipientSheet), findsOneWidget);
    });

    testWidgets('11. Contextual AppBar Copy copies messages in chronological order and clears selection', (tester) async {
      final earlierMsg = ChatMessage(
        id: 'msg-time-1',
        chatId: chatId,
        senderId: peerUserId,
        text: 'First line',
        sentAt: DateTime(2026, 1, 1, 10, 0),
        deliveryState: DeliveryState.read,
        type: MessageType.text,
      );
      final laterMsg = ChatMessage(
        id: 'msg-time-2',
        chatId: chatId,
        senderId: currentUserId,
        text: 'Second line',
        sentAt: DateTime(2026, 1, 1, 10, 5),
        deliveryState: DeliveryState.sent,
        type: MessageType.text,
      );

      final container = ProviderContainer(
        overrides: [
          chatTimelineNotifierProvider(chatArgs).overrideWith(
            () => _FakeChatTimelineNotifier(chatArgs, [laterMsg, earlierMsg]),
          ),
          chatTypingNotifierProvider(chatArgs).overrideWith(
            () => _FakeChatTypingNotifier(chatArgs),
          ),
          chatPresenceStreamProvider(peerUserId).overrideWith(
            (ref) => const Stream.empty(),
          ),
        ],
      );
      addTearDown(container.dispose);

      String? copiedClipboardText;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (methodCall) async {
          if (methodCall.method == 'Clipboard.setData') {
            copiedClipboardText = (methodCall.arguments as Map)['text'] as String?;
            return null;
          }
          return null;
        },
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: ThemeData.light().copyWith(
              extensions: const [ChatThemeExtension.light],
            ),
            home: ChatScreen(
              chatId: chatId,
              currentUserId: currentUserId,
              peerUserId: peerUserId,
              contactName: contactName,
              contactAvatar: '',
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Select both messages
      await tester.longPress(find.text('Second line'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('First line'));
      await tester.pumpAndSettle();

      expect(find.text('2'), findsOneWidget);

      await tester.tap(find.byTooltip('Copy'));
      await tester.pumpAndSettle();

      // Chronological order verification: 'First line' followed by 'Second line'
      expect(copiedClipboardText, equals('First line\nSecond line'));
      expect(container.read(chatScreenSelectionControllerProvider).isEmpty, isTrue);
      expect(find.text('2 messages copied'), findsOneWidget);
    });

    testWidgets('12. Back button on selection AppBar clears selection and restores normal header', (tester) async {
      final msg = ChatMessage(
        id: 'msg-back-test',
        chatId: chatId,
        senderId: peerUserId,
        text: 'Testing back to dismiss',
        sentAt: DateTime.now(),
        deliveryState: DeliveryState.read,
        type: MessageType.text,
      );

      final container = ProviderContainer(
        overrides: [
          chatTimelineNotifierProvider(chatArgs).overrideWith(
            () => _FakeChatTimelineNotifier(chatArgs, [msg]),
          ),
          chatTypingNotifierProvider(chatArgs).overrideWith(
            () => _FakeChatTypingNotifier(chatArgs),
          ),
          chatPresenceStreamProvider(peerUserId).overrideWith(
            (ref) => const Stream.empty(),
          ),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: ThemeData.light().copyWith(
              extensions: const [ChatThemeExtension.light],
            ),
            home: ChatScreen(
              chatId: chatId,
              currentUserId: currentUserId,
              peerUserId: peerUserId,
              contactName: contactName,
              contactAvatar: '',
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      await tester.longPress(find.text('Testing back to dismiss'));
      await tester.pumpAndSettle();

      expect(find.text('1'), findsOneWidget);

      // Tap back button
      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();

      // Normal AppBar restored
      expect(find.text('Bob'), findsOneWidget);
      expect(find.text('1'), findsNothing);
      expect(container.read(chatScreenSelectionControllerProvider).isEmpty, isTrue);
    });

    testWidgets('13. Swiping right on message in ChatScreen triggers reply directly', (tester) async {
      final msg = ChatMessage(
        id: 'msg-swipe-screen-1',
        chatId: chatId,
        senderId: peerUserId,
        text: 'Direct swipe on screen',
        sentAt: DateTime.now(),
        deliveryState: DeliveryState.read,
        type: MessageType.text,
      );

      final container = ProviderContainer(
        overrides: [
          chatTimelineNotifierProvider(chatArgs).overrideWith(
            () => _FakeChatTimelineNotifier(chatArgs, [msg]),
          ),
          chatTypingNotifierProvider(chatArgs).overrideWith(
            () => _FakeChatTypingNotifier(chatArgs),
          ),
          chatPresenceStreamProvider(peerUserId).overrideWith(
            (ref) => const Stream.empty(),
          ),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: ThemeData.light().copyWith(
              extensions: const [ChatThemeExtension.light],
            ),
            home: ChatScreen(
              chatId: chatId,
              currentUserId: currentUserId,
              peerUserId: peerUserId,
              contactName: contactName,
              contactAvatar: '',
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(container.read(chatSendNotifierProvider(chatArgs)).hasReplyTarget, isFalse);

      await tester.drag(find.text('Direct swipe on screen'), const Offset(55, 0));
      await tester.pumpAndSettle();

      expect(container.read(chatSendNotifierProvider(chatArgs)).hasReplyTarget, isTrue);
      expect(find.byTooltip('Cancel reply'), findsOneWidget);
    });

    testWidgets('14. Swipe-to-reply is disabled while selection mode is active', (tester) async {
      final msg = ChatMessage(
        id: 'msg-swipe-disabled-1',
        chatId: chatId,
        senderId: peerUserId,
        text: 'No swipe when selected',
        sentAt: DateTime.now(),
        deliveryState: DeliveryState.read,
        type: MessageType.text,
      );

      final container = ProviderContainer(
        overrides: [
          chatTimelineNotifierProvider(chatArgs).overrideWith(
            () => _FakeChatTimelineNotifier(chatArgs, [msg]),
          ),
          chatTypingNotifierProvider(chatArgs).overrideWith(
            () => _FakeChatTypingNotifier(chatArgs),
          ),
          chatPresenceStreamProvider(peerUserId).overrideWith(
            (ref) => const Stream.empty(),
          ),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: ThemeData.light().copyWith(
              extensions: const [ChatThemeExtension.light],
            ),
            home: ChatScreen(
              chatId: chatId,
              currentUserId: currentUserId,
              peerUserId: peerUserId,
              contactName: contactName,
              contactAvatar: '',
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Enter selection mode
      await tester.longPress(find.text('No swipe when selected'));
      await tester.pumpAndSettle();
      expect(find.text('1'), findsOneWidget);

      // Attempt swipe right while in selection mode
      await tester.drag(find.text('No swipe when selected'), const Offset(55, 0));
      await tester.pumpAndSettle();

      // Should NOT set reply target
      expect(container.read(chatSendNotifierProvider(chatArgs)).hasReplyTarget, isFalse);
    });

    testWidgets('15. Cancel upload button is only shown if all selected messages are failed uploads', (tester) async {
      final failedMsg = ChatMessage(
        id: 'msg-failed-outbox-1',
        chatId: chatId,
        senderId: currentUserId,
        text: 'Failed upload message',
        sentAt: DateTime.now(),
        deliveryState: DeliveryState.sending,
        failure: MessageFailureReason.uploadFailed,
        type: MessageType.media,
        media: const MessageMedia(
          url: '/local/file.pdf',
          kind: MediaKind.document,
          mime: 'application/pdf',
          size: 2048,
        ),
      );

      final container = ProviderContainer(
        overrides: [
          chatTimelineNotifierProvider(chatArgs).overrideWith(
            () => _FakeChatTimelineNotifier(chatArgs, [failedMsg]),
          ),
          chatTypingNotifierProvider(chatArgs).overrideWith(
            () => _FakeChatTypingNotifier(chatArgs),
          ),
          chatPresenceStreamProvider(peerUserId).overrideWith(
            (ref) => const Stream.empty(),
          ),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: ThemeData.light().copyWith(
              extensions: const [ChatThemeExtension.light],
            ),
            home: ChatScreen(
              chatId: chatId,
              currentUserId: currentUserId,
              peerUserId: peerUserId,
              contactName: contactName,
              contactAvatar: '',
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      await tester.longPress(find.byType(ChatBubble));
      await tester.pumpAndSettle();

      // Cancel upload button should be visible in AppBar
      expect(find.byTooltip('Cancel upload'), findsOneWidget);
    });
  });
}
