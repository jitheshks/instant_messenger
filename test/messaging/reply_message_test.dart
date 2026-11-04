import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:instant_messenger/core/persistence/hive_init.dart';
import 'package:instant_messenger/core/persistence/stores/messages_store.dart';
import 'package:instant_messenger/features/messaging/domain/models/chat_message.dart';
import 'package:instant_messenger/features/messaging/presentation/providers/messaging_providers.dart';
import 'package:instant_messenger/app/theme/chat_theme_extension.dart';
import 'package:instant_messenger/features/messaging/presentation/widgets/chat_bubble.dart';
import 'package:instant_messenger/features/messaging/presentation/widgets/chat_input.dart';
import 'package:instant_messenger/features/messaging/data/messages_repository.dart';

class _FakeMessagesRepository extends MessagesRepository {
  final List<ChatMessage> sentMessages = [];
  bool shouldThrow = false;

  @override
  Future<String> sendMessage(
    String chatId,
    ChatMessage msg, {
    required String otherUserId,
    required String otherName,
    String? otherAvatar,
  }) async {
    if (shouldThrow) {
      throw Exception('Network simulated failure');
    }
    sentMessages.add(msg);
    return msg.id;
  }
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

  group('Reply Message Feature Verification', () {
    late Directory tempDir;
    late Box<ChatMessage> msgBox;
    late MessagesStore messagesStore;

    const senderUid = 'user-alice-123';
    const recipientUid = 'user-bob-456';
    const chatId = 'chat-reply-test-777';
    final chatArgs = ChatControllerArgs(
      chatId: chatId,
      currentUserId: senderUid,
      otherUserId: recipientUid,
    );

    setUp(() async {
      tempDir = Directory.systemTemp.createTempSync('reply_test_');
      Hive.init(tempDir.path);
      HiveInit.registerAdapters();
      msgBox = await Hive.openBox<ChatMessage>('messages_$senderUid');
      messagesStore = MessagesStore(msgBox);
    });

    tearDown(() async {
      await msgBox.close();
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('1. ChatSendNotifier manages replyTarget correctly and clears on send', () async {
      final fakeRepo = _FakeMessagesRepository();
      final container = ProviderContainer(
        overrides: [
          messagesRepositoryProvider.overrideWithValue(fakeRepo),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(chatSendNotifierProvider(chatArgs).notifier);
      expect(container.read(chatSendNotifierProvider(chatArgs)).hasReplyTarget, isFalse);

      final targetMsg = ChatMessage(
        id: 'target-001',
        chatId: chatId,
        senderId: recipientUid,
        text: 'What time is the meeting?',
        sentAt: DateTime.now().subtract(const Duration(minutes: 5)),
        deliveryState: DeliveryState.read,
        type: MessageType.text,
      );

      // Set reply target
      notifier.setReplyTarget(targetMsg, senderName: 'Bob');

      final stateWithReply = container.read(chatSendNotifierProvider(chatArgs));
      expect(stateWithReply.hasReplyTarget, isTrue);
      expect(stateWithReply.replyTarget?.id, equals('target-001'));
      expect(stateWithReply.replyTargetSenderName, equals('Bob'));

      // Send text message replying to target
      await notifier.sendText('Meeting is at 3 PM', otherName: 'Bob');

      expect(fakeRepo.sentMessages.length, equals(1));
      final sent = fakeRepo.sentMessages.first;
      expect(sent.text, equals('Meeting is at 3 PM'));
      expect(sent.replyToMessageId, equals('target-001'));
      expect(sent.replyText, equals('What time is the meeting?'));
      expect(sent.replySenderName, equals('Bob'));
      expect(sent.hasReply, isTrue);

      // Reply target should be cleared after successful send
      final finalState = container.read(chatSendNotifierProvider(chatArgs));
      expect(finalState.hasReplyTarget, isFalse);
      expect(finalState.replyTarget, isNull);
    });

    test('2. ChatSendNotifier preserves replyTarget when send fails', () async {
      final fakeRepo = _FakeMessagesRepository()..shouldThrow = true;
      final container = ProviderContainer(
        overrides: [
          messagesRepositoryProvider.overrideWithValue(fakeRepo),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(chatSendNotifierProvider(chatArgs).notifier);

      final targetMsg = ChatMessage(
        id: 'target-002',
        chatId: chatId,
        senderId: recipientUid,
        text: 'Important request',
        sentAt: DateTime.now(),
        deliveryState: DeliveryState.read,
        type: MessageType.text,
      );

      notifier.setReplyTarget(targetMsg, senderName: 'Bob');
      expect(container.read(chatSendNotifierProvider(chatArgs)).hasReplyTarget, isTrue);

      // Attempt send that throws
      await notifier.sendText('Attempted answer', otherName: 'Bob');

      final stateAfterFailure = container.read(chatSendNotifierProvider(chatArgs));
      expect(stateAfterFailure.error, isNotNull);
      // Reply target must be preserved on error so user does not lose reply context!
      expect(stateAfterFailure.hasReplyTarget, isTrue);
      expect(stateAfterFailure.replyTarget?.id, equals('target-002'));
    });

    test('3. ChatMessage Hive persistence and serialization preserves all reply fields', () async {
      final replyMsg = ChatMessage(
        id: 'msg-with-reply-003',
        chatId: chatId,
        senderId: senderUid,
        text: 'I agree with this',
        sentAt: DateTime.now(),
        deliveryState: DeliveryState.sent,
        type: MessageType.text,
        replyToMessageId: 'orig-reply-target-999',
        replyText: 'Should we launch today?',
        replySenderName: 'Bob',
        replyMediaKind: 'image',
      );

      // 1. Hive store roundtrip
      await messagesStore.saveMessage(replyMsg);
      final fromHive = messagesStore.getMessage(replyMsg.id);
      expect(fromHive, isNotNull);
      expect(fromHive!.hasReply, isTrue);
      expect(fromHive.replyToMessageId, equals('orig-reply-target-999'));
      expect(fromHive.replyText, equals('Should we launch today?'));
      expect(fromHive.replySenderName, equals('Bob'));
      expect(fromHive.replyMediaKind, equals('image'));

      // 2. Map serialization roundtrip
      final map = replyMsg.toMap();
      final fromMap = ChatMessage.fromMap(map);
      expect(fromMap.replyToMessageId, equals('orig-reply-target-999'));
      expect(fromMap.replyText, equals('Should we launch today?'));
      expect(fromMap.replySenderName, equals('Bob'));
      expect(fromMap.replyMediaKind, equals('image'));

      // 3. Supabase row with reply_snapshot
      final sbRow = {
        'id': 'sb-reply-004',
        'chat_id': chatId,
        'sender_id': recipientUid,
        'type': 'text',
        'text': 'Reply via Supabase',
        'sent_at': DateTime.now().toIso8601String(),
        'status': 2,
        'reply_to_message_id': 'orig-reply-target-999',
        'reply_snapshot': {
          'text': 'Snapshot original text',
          'sender_name': 'Alice',
          'media_kind': null,
        },
      };

      final fromSb = ChatMessage.fromSupabase(sbRow, senderUid);
      expect(fromSb.replyToMessageId, equals('orig-reply-target-999'));
      expect(fromSb.replyText, equals('Snapshot original text'));
      expect(fromSb.replySenderName, equals('Alice'));
      expect(fromSb.hasReply, isTrue);
    });

    testWidgets('4. ChatBubble renders quoted reply preview and responds to onTapQuote', (tester) async {
      String? tappedQuoteId;

      final messageWithReply = ChatMessage(
        id: 'bubble-reply-005',
        chatId: chatId,
        senderId: senderUid,
        text: 'Yes, absolutely!',
        sentAt: DateTime.now(),
        deliveryState: DeliveryState.sent,
        type: MessageType.text,
        replyToMessageId: 'quote-target-12345',
        replyText: 'Is the new release ready?',
        replySenderName: 'Bob',
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.light().copyWith(
            extensions: const [ChatThemeExtension.light],
          ),
          home: Scaffold(
            body: ChatBubble(
              msg: messageWithReply,
              isMe: true,
              onTapQuote: (msgId) {
                tappedQuoteId = msgId;
              },
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Quoted reply content
      expect(find.text('Bob'), findsOneWidget);
      expect(find.text('Is the new release ready?'), findsOneWidget);
      expect(find.text('Yes, absolutely!'), findsOneWidget);

      // Tap quote to verify callback
      await tester.tap(find.text('Is the new release ready?'));
      await tester.pumpAndSettle();

      expect(tappedQuoteId, equals('quote-target-12345'));
    });

    testWidgets('5. ChatInput renders composer reply preview and cancel button clears target', (tester) async {
      final fakeRepo = _FakeMessagesRepository();
      final container = ProviderContainer(
        overrides: [
          messagesRepositoryProvider.overrideWithValue(fakeRepo),
          chatTypingNotifierProvider(chatArgs).overrideWith(
            () => _FakeChatTypingNotifier(chatArgs),
          ),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(chatSendNotifierProvider(chatArgs).notifier);

      final quoteMsg = ChatMessage(
        id: 'quote-in-composer',
        chatId: chatId,
        senderId: recipientUid,
        text: 'Please review PR #42',
        sentAt: DateTime.now(),
        deliveryState: DeliveryState.read,
        type: MessageType.text,
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: ThemeData.light().copyWith(
              extensions: const [ChatThemeExtension.light],
            ),
            home: Scaffold(
              body: ChatInput(
                args: chatArgs,
                otherName: 'Bob',
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Initially no reply preview
      expect(find.text('Please review PR #42'), findsNothing);

      // Set reply target
      notifier.setReplyTarget(quoteMsg, senderName: 'Bob');
      await tester.pumpAndSettle();

      // Reply preview should now be visible
      expect(find.text('Bob'), findsOneWidget);
      expect(find.text('Please review PR #42'), findsOneWidget);
      expect(find.byTooltip('Cancel reply'), findsOneWidget);

      // Tap cancel button
      await tester.tap(find.byTooltip('Cancel reply'));
      await tester.pumpAndSettle();

      // Reply preview should be removed
      expect(find.text('Please review PR #42'), findsNothing);
      expect(container.read(chatSendNotifierProvider(chatArgs)).hasReplyTarget, isFalse);
    });
  });
}
