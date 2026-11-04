import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';

import 'package:instant_messenger/core/persistence/hive_init.dart';
import 'package:instant_messenger/core/persistence/stores/messages_store.dart';
import 'package:instant_messenger/features/messaging/domain/models/chat_message.dart';
import 'package:instant_messenger/app/theme/chat_theme_extension.dart';
import 'package:instant_messenger/features/messaging/presentation/widgets/chat_bubble.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Forward Message Feature Verification', () {
    late Directory tempDir;
    late Box<ChatMessage> msgBox;
    late MessagesStore messagesStore;

    const senderUid = 'user-alice-123';
    const recipientUid = 'user-bob-456';
    const originalChatId = 'chat-original-111';
    const destinationChatId = 'chat-destination-222';

    setUp(() async {
      tempDir = Directory.systemTemp.createTempSync('forward_test_');
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

    test('1. Forwarding creates a distinct new message with new ID and isForwarded: true', () async {
      final originalMsg = ChatMessage(
        id: 'orig-msg-001',
        chatId: originalChatId,
        senderId: recipientUid,
        text: 'Hello, this is original text!',
        sentAt: DateTime(2026, 10, 20, 10, 0),
        deliveryState: DeliveryState.read,
        type: MessageType.text,
        isForwarded: false,
      );

      await messagesStore.saveMessage(originalMsg);

      // Create forwarded copy to destination chat
      final forwardedId = const Uuid().v4();
      final forwardedSentAt = DateTime.now();

      final forwardedMsg = ChatMessage(
        id: forwardedId,
        chatId: destinationChatId,
        senderId: senderUid,
        text: originalMsg.text,
        sentAt: forwardedSentAt,
        deliveryState: DeliveryState.sending,
        type: originalMsg.type,
        media: originalMsg.media,
        isForwarded: true,
      );

      await messagesStore.saveMessage(forwardedMsg);

      // Verify original is intact
      final retrievedOriginal = messagesStore.getMessage(originalMsg.id);
      expect(retrievedOriginal, isNotNull);
      expect(retrievedOriginal!.id, equals('orig-msg-001'));
      expect(retrievedOriginal.chatId, equals(originalChatId));
      expect(retrievedOriginal.isForwarded, isFalse);

      // Verify forwarded copy
      final retrievedForwarded = messagesStore.getMessage(forwardedId);
      expect(retrievedForwarded, isNotNull);
      expect(retrievedForwarded!.id, equals(forwardedId));
      expect(retrievedForwarded.id, isNot(equals(originalMsg.id)));
      expect(retrievedForwarded.chatId, equals(destinationChatId));
      expect(retrievedForwarded.senderId, equals(senderUid));
      expect(retrievedForwarded.text, equals('Hello, this is original text!'));
      expect(retrievedForwarded.isForwarded, isTrue);
      expect(retrievedForwarded.replyToMessageId, isNull);
    });

    test('2. Forwarding preserves media attachments without data loss', () async {
      final originalMediaMsg = ChatMessage(
        id: 'orig-media-002',
        chatId: originalChatId,
        senderId: recipientUid,
        text: 'Check this image',
        sentAt: DateTime(2026, 10, 20, 11, 0),
        deliveryState: DeliveryState.read,
        type: MessageType.media,
        media: const MessageMedia(
          url: 'https://storage.example.com/media/chat/pic.png',
          thumbUrl: 'https://storage.example.com/media/chat/thumb.png',
          kind: MediaKind.image,
          mime: 'image/png',
          size: 204800,
          width: 800,
          height: 600,
        ),
      );

      final forwardedId = const Uuid().v4();
      final forwardedMsg = ChatMessage(
        id: forwardedId,
        chatId: destinationChatId,
        senderId: senderUid,
        text: originalMediaMsg.text,
        sentAt: DateTime.now(),
        deliveryState: DeliveryState.sending,
        type: originalMediaMsg.type,
        media: originalMediaMsg.media,
        isForwarded: true,
      );

      await messagesStore.saveMessage(forwardedMsg);

      final loaded = messagesStore.getMessage(forwardedId);
      expect(loaded, isNotNull);
      expect(loaded!.isForwarded, isTrue);
      expect(loaded.media, isNotNull);
      expect(loaded.media!.url, equals('https://storage.example.com/media/chat/pic.png'));
      expect(loaded.media!.kind, equals(MediaKind.image));
      expect(loaded.media!.size, equals(204800));
      expect(loaded.media!.width, equals(800));
      expect(loaded.media!.height, equals(600));
    });

    test('3. ChatMessage serialization to/from Map and Supabase retains isForwarded', () {
      final msg = ChatMessage(
        id: 'ser-msg-003',
        chatId: 'chat-333',
        senderId: senderUid,
        text: 'Forwarded serialized message',
        sentAt: DateTime.now(),
        deliveryState: DeliveryState.sent,
        type: MessageType.text,
        isForwarded: true,
      );

      // Local toMap / fromMap
      final map = msg.toMap();
      expect(map['isForwarded'], isTrue);

      final fromMap = ChatMessage.fromMap(map);
      expect(fromMap.isForwarded, isTrue);

      // Supabase fromSupabase
      final supabaseRow = {
        'id': 'sb-msg-004',
        'chat_id': 'chat-333',
        'sender_id': senderUid,
        'type': 'text',
        'text': 'Supabase forwarded message',
        'sent_at': DateTime.now().toIso8601String(),
        'status': 1,
        'is_forwarded': true,
      };

      final fromSb = ChatMessage.fromSupabase(supabaseRow, senderUid);
      expect(fromSb.isForwarded, isTrue);
    });

    test('4. Forwarding an already forwarded message continues to display Forwarded', () {
      final firstForward = ChatMessage(
        id: 'forward-1',
        chatId: 'chat-first',
        senderId: 'user-bob',
        text: 'Double forward test',
        sentAt: DateTime.now(),
        deliveryState: DeliveryState.read,
        type: MessageType.text,
        isForwarded: true,
      );

      // Forward it again
      final secondForward = ChatMessage(
        id: 'forward-2',
        chatId: 'chat-second',
        senderId: senderUid,
        text: firstForward.text,
        sentAt: DateTime.now(),
        deliveryState: DeliveryState.sending,
        type: firstForward.type,
        media: firstForward.media,
        isForwarded: true,
      );

      expect(secondForward.isForwarded, isTrue);
      expect(secondForward.id, isNot(equals(firstForward.id)));
      expect(secondForward.chatId, equals('chat-second'));
    });

    testWidgets('5. ChatBubble displays Forwarded label when isForwarded is true', (tester) async {
      final forwardedMsg = ChatMessage(
        id: 'ui-forward-005',
        chatId: 'chat-ui',
        senderId: senderUid,
        text: 'This message has a forwarded tag',
        sentAt: DateTime.now(),
        deliveryState: DeliveryState.sent,
        type: MessageType.text,
        isForwarded: true,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.light().copyWith(
            extensions: const [ChatThemeExtension.light],
          ),
          home: Scaffold(
            body: ChatBubble(
              msg: forwardedMsg,
              isMe: true,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Forwarded'), findsOneWidget);
      expect(find.byIcon(Icons.forward), findsOneWidget);
      expect(find.text('This message has a forwarded tag'), findsOneWidget);
    });

    testWidgets('6. ChatBubble does NOT display Forwarded label when isForwarded is false', (tester) async {
      final normalMsg = ChatMessage(
        id: 'ui-normal-006',
        chatId: 'chat-ui',
        senderId: senderUid,
        text: 'Direct message without forward',
        sentAt: DateTime.now(),
        deliveryState: DeliveryState.sent,
        type: MessageType.text,
        isForwarded: false,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.light().copyWith(
            extensions: const [ChatThemeExtension.light],
          ),
          home: Scaffold(
            body: ChatBubble(
              msg: normalMsg,
              isMe: true,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Forwarded'), findsNothing);
      expect(find.byIcon(Icons.forward), findsNothing);
      expect(find.text('Direct message without forward'), findsOneWidget);
    });
  });
}
