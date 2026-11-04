import 'package:flutter_test/flutter_test.dart';
import 'package:instant_messenger/features/messaging/domain/models/chat_message.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Server-side validation simulator mirroring public.attach_message_media RPC
class AttachMediaSimulator {
  final Map<String, Map<String, dynamic>> messages;
  final Set<String> chatMemberships; // format: "$chatId:$userId"

  AttachMediaSimulator({required this.messages, required this.chatMemberships});

  Map<String, dynamic> attachMedia({
    required String? callerId,
    required String chatId,
    required String messageId,
    required dynamic rawMediaPayload,
  }) {
    if (callerId == null || callerId.isEmpty) {
      throw const PostgrestException(
        message: 'Unauthorized: authentication required',
        code: '42501',
      );
    }

    if (!chatMemberships.contains('$chatId:$callerId')) {
      throw const PostgrestException(
        message: 'Forbidden: caller is not a member of this chat',
        code: '42501',
      );
    }

    final msg = messages[messageId];
    if (msg == null || msg['chat_id'] != chatId) {
      throw const PostgrestException(
        message: 'Message not found in specified chat',
        code: 'P0002',
      );
    }

    if (msg['sender_id'] != callerId) {
      throw const PostgrestException(
        message: 'Forbidden: only the message sender can attach media',
        code: '42501',
      );
    }

    if (msg['type'] != 'media') {
      throw const PostgrestException(
        message:
            'Invalid message type: media cannot be attached to non-media messages',
        code: '22023',
      );
    }

    final int status = msg['status'] as int? ?? 1;
    if (status > 2) {
      throw const PostgrestException(
        message: 'Cannot attach media to an already read message',
        code: '22023',
      );
    }

    if (rawMediaPayload is! Map) {
      throw const PostgrestException(
        message: 'Invalid media payload: JSON object expected',
        code: '22023',
      );
    }

    final url = rawMediaPayload['url'] as String?;
    if (url == null || url.trim().isEmpty) {
      throw const PostgrestException(
        message: 'Invalid media payload: url is required',
        code: '22023',
      );
    }

    final expectedPrefix = '$chatId/$messageId';
    if (!url.startsWith(expectedPrefix)) {
      throw PostgrestException(
        message:
            'Invalid media path: attachment object path must begin with $chatId/$messageId',
        code: '22023',
      );
    }

    // Build strictly sanitized media metadata object (stripping unexpected fields)
    final sanitized = <String, dynamic>{
      'url': url,
      'mime': rawMediaPayload['mime'] ?? 'application/octet-stream',
      'size': rawMediaPayload['size'] is int ? rawMediaPayload['size'] : 0,
      'kind': rawMediaPayload['kind'] ?? 'file',
    };

    if (rawMediaPayload.containsKey('fileName')) {
      sanitized['fileName'] = rawMediaPayload['fileName'];
    }

    msg['media'] = sanitized;
    msg['updated_at'] = DateTime.now().toUtc().toIso8601String();

    return sanitized;
  }
}

/// Server-side validation simulator mirroring public.promote_message_status RPC
class PromoteStatusSimulator {
  final Map<String, Map<String, dynamic>> messages;
  final Set<String> chatMemberships;

  PromoteStatusSimulator({
    required this.messages,
    required this.chatMemberships,
  });

  int promoteStatus({
    required String? callerId,
    required List<String> messageIds,
    required int newStatus,
  }) {
    if (callerId == null || callerId.isEmpty) {
      throw const PostgrestException(
        message: 'Unauthorized: authentication required',
        code: '42501',
      );
    }

    if (newStatus != 2 && newStatus != 3) {
      throw const PostgrestException(
        message:
            'Invalid status: target status must be 2 (delivered) or 3 (read)',
        code: '22023',
      );
    }

    int updatedCount = 0;
    for (final id in messageIds) {
      final msg = messages[id];
      if (msg == null) continue;

      final chatId = msg['chat_id'] as String;
      if (!chatMemberships.contains('$chatId:$callerId')) {
        continue;
      }

      // Reject self-promotion: sender cannot mark their own messages delivered/read
      if (msg['sender_id'] == callerId) {
        continue;
      }

      final int currentStatus = msg['status'] as int? ?? 1;
      // Monotonic progression: only strictly forward transitions allowed
      if (currentStatus < newStatus) {
        msg['status'] = newStatus;
        msg['updated_at'] = DateTime.now().toUtc().toIso8601String();
        updatedCount++;
      }
    }

    return updatedCount;
  }
}

/// Simulator for Realtime private channel topic authorization (realtime.messages)
class RealtimeTopicAuthorizer {
  final Set<String> chatMemberships;
  static final RegExp uuidRegex = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
    caseSensitive: false,
  );

  RealtimeTopicAuthorizer({required this.chatMemberships});

  String? safeUuid(String input) {
    if (uuidRegex.hasMatch(input)) {
      return input.toLowerCase();
    }
    return null; // Mirrors public.safe_uuid returning NULL on invalid string
  }

  bool authorizeBroadcast({
    required String? callerId,
    required String topic,
    required String extension,
  }) {
    if (callerId == null || callerId.isEmpty) return false;
    if (extension != 'broadcast') return false;

    if (!topic.startsWith('chat_typing:')) return false;

    final parts = topic.split(':');
    if (parts.length < 2) return false;

    final chatId = safeUuid(parts[1]);
    if (chatId == null) return false;

    return chatMemberships.contains('$chatId:$callerId');
  }
}

/// Simulator for Outbox SQLSTATE 23505 Idempotency Logic
class OutboxIdempotencyResolver {
  final Map<String, Map<String, dynamic>> serverMessages;

  OutboxIdempotencyResolver({required this.serverMessages});

  DeliveryState resolveConflict({
    required ChatMessage msg,
    required PostgrestException exception,
  }) {
    if (exception.code == '23505') {
      final existing = serverMessages[msg.id];
      if (existing != null &&
          existing['sender_id'] == msg.senderId &&
          existing['chat_id'] == msg.chatId) {
        return DeliveryState.sent; // Successfully resolved duplicate insert
      }
    }
    return DeliveryState.sending; // Unresolved / failed
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final chatId = '4580f488-ea9e-4b77-a89c-d0c3eb1a9d18';
  final messageId = '7b140df0-141a-4d2a-8c67-6ce2b0277f24';
  final senderId = 'c9ccc86c-cd42-40bb-8678-d9a30964ce30';
  final recipientId = 'e2b3c4d5-6789-4012-8345-6789abcdef01';
  final malloryId = '99999999-9999-9999-9999-999999999999';

  group('attach_message_media RPC Security & Validation Tests', () {
    late Map<String, Map<String, dynamic>> messages;
    late AttachMediaSimulator simulator;

    setUp(() {
      messages = {
        messageId: {
          'id': messageId,
          'chat_id': chatId,
          'sender_id': senderId,
          'type': 'media',
          'status': 1,
          'media': null,
        },
      };

      simulator = AttachMediaSimulator(
        messages: messages,
        chatMemberships: {'$chatId:$senderId', '$chatId:$recipientId'},
      );
    });

    test('Rejects unauthenticated caller', () {
      expect(
        () => simulator.attachMedia(
          callerId: null,
          chatId: chatId,
          messageId: messageId,
          rawMediaPayload: {'url': '$chatId/${messageId}_file.png'},
        ),
        throwsA(
          isA<PostgrestException>().having((e) => e.code, 'code', '42501'),
        ),
      );
    });

    test('Rejects non-chat member', () {
      expect(
        () => simulator.attachMedia(
          callerId: malloryId,
          chatId: chatId,
          messageId: messageId,
          rawMediaPayload: {'url': '$chatId/${messageId}_file.png'},
        ),
        throwsA(
          isA<PostgrestException>().having((e) => e.code, 'code', '42501'),
        ),
      );
    });

    test('Rejects caller who is not the message sender', () {
      expect(
        () => simulator.attachMedia(
          callerId: recipientId,
          chatId: chatId,
          messageId: messageId,
          rawMediaPayload: {'url': '$chatId/${messageId}_file.png'},
        ),
        throwsA(
          isA<PostgrestException>().having(
            (e) => e.message,
            'message',
            contains('only the message sender'),
          ),
        ),
      );
    });

    test('Rejects attachment to non-media message (e.g. text)', () {
      messages[messageId]!['type'] = 'text';

      expect(
        () => simulator.attachMedia(
          callerId: senderId,
          chatId: chatId,
          messageId: messageId,
          rawMediaPayload: {'url': '$chatId/${messageId}_file.png'},
        ),
        throwsA(
          isA<PostgrestException>().having((e) => e.code, 'code', '22023'),
        ),
      );
    });

    test('Rejects attachment to already read message', () {
      messages[messageId]!['status'] = 3;

      expect(
        () => simulator.attachMedia(
          callerId: senderId,
          chatId: chatId,
          messageId: messageId,
          rawMediaPayload: {'url': '$chatId/${messageId}_file.png'},
        ),
        throwsA(
          isA<PostgrestException>().having((e) => e.code, 'code', '22023'),
        ),
      );
    });

    test(
      'Rejects forged / mismatched storage path targeting different chat',
      () {
        final foreignChatId = '11111111-2222-3333-4444-555555555555';
        expect(
          () => simulator.attachMedia(
            callerId: senderId,
            chatId: chatId,
            messageId: messageId,
            rawMediaPayload: {'url': '$foreignChatId/${messageId}_file.png'},
          ),
          throwsA(
            isA<PostgrestException>().having(
              (e) => e.message,
              'message',
              contains('attachment object path must begin with'),
            ),
          ),
        );
      },
    );

    test(
      'Rejects forged / mismatched storage path targeting different message',
      () {
        final foreignMessageId = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';
        expect(
          () => simulator.attachMedia(
            callerId: senderId,
            chatId: chatId,
            messageId: messageId,
            rawMediaPayload: {'url': '$chatId/${foreignMessageId}_file.png'},
          ),
          throwsA(
            isA<PostgrestException>().having(
              (e) => e.message,
              'message',
              contains('attachment object path must begin with'),
            ),
          ),
        );
      },
    );

    test('Sanitizes payload and accepts valid canonical path', () {
      final validPayload = {
        'url': '$chatId/${messageId}_photo.jpg',
        'mime': 'image/jpeg',
        'size': 102400,
        'kind': 'image',
        'fileName': 'photo.jpg',
        'forged_admin_field': true,
      };

      final sanitized = simulator.attachMedia(
        callerId: senderId,
        chatId: chatId,
        messageId: messageId,
        rawMediaPayload: validPayload,
      );

      expect(sanitized['url'], equals('$chatId/${messageId}_photo.jpg'));
      expect(sanitized['mime'], equals('image/jpeg'));
      expect(sanitized['size'], equals(102400));
      expect(sanitized['kind'], equals('image'));
      expect(sanitized['fileName'], equals('photo.jpg'));
      expect(sanitized.containsKey('forged_admin_field'), isFalse);
    });
  });

  group('promote_message_status Negative Authorization Tests', () {
    late Map<String, Map<String, dynamic>> messages;
    late PromoteStatusSimulator simulator;

    setUp(() {
      messages = {
        messageId: {
          'id': messageId,
          'chat_id': chatId,
          'sender_id': senderId,
          'status': 1,
        },
      };

      simulator = PromoteStatusSimulator(
        messages: messages,
        chatMemberships: {'$chatId:$senderId', '$chatId:$recipientId'},
      );
    });

    test('Prevents sender from self-promoting message status', () {
      final updated = simulator.promoteStatus(
        callerId: senderId,
        messageIds: [messageId],
        newStatus: 2,
      );

      expect(updated, equals(0));
      expect(messages[messageId]!['status'], equals(1)); // unchanged
    });

    test('Prevents non-member from promoting message status', () {
      final updated = simulator.promoteStatus(
        callerId: malloryId,
        messageIds: [messageId],
        newStatus: 2,
      );

      expect(updated, equals(0));
      expect(messages[messageId]!['status'], equals(1));
    });

    test('Prevents status downgrade (status 3 down to 2 or 1)', () {
      messages[messageId]!['status'] = 3;

      final updated = simulator.promoteStatus(
        callerId: recipientId,
        messageIds: [messageId],
        newStatus: 2,
      );

      expect(updated, equals(0));
      expect(messages[messageId]!['status'], equals(3)); // remains read
    });

    test('Rejects invalid target status', () {
      expect(
        () => simulator.promoteStatus(
          callerId: recipientId,
          messageIds: [messageId],
          newStatus: 4, // invalid
        ),
        throwsA(
          isA<PostgrestException>().having((e) => e.code, 'code', '22023'),
        ),
      );
    });

    test('Allows recipient forward promotion to delivered and read', () {
      final deliveredCount = simulator.promoteStatus(
        callerId: recipientId,
        messageIds: [messageId],
        newStatus: 2,
      );
      expect(deliveredCount, equals(1));
      expect(messages[messageId]!['status'], equals(2));

      final readCount = simulator.promoteStatus(
        callerId: recipientId,
        messageIds: [messageId],
        newStatus: 3,
      );
      expect(readCount, equals(1));
      expect(messages[messageId]!['status'], equals(3));
    });
  });

  group('Realtime Private Channel Authorization Tests', () {
    late RealtimeTopicAuthorizer authorizer;

    setUp(() {
      authorizer = RealtimeTopicAuthorizer(
        chatMemberships: {'$chatId:$senderId', '$chatId:$recipientId'},
      );
    });

    test('Authorizes broadcast for active chat members', () {
      expect(
        authorizer.authorizeBroadcast(
          callerId: senderId,
          topic: 'chat_typing:$chatId',
          extension: 'broadcast',
        ),
        isTrue,
      );

      expect(
        authorizer.authorizeBroadcast(
          callerId: recipientId,
          topic: 'chat_typing:$chatId',
          extension: 'broadcast',
        ),
        isTrue,
      );
    });

    test('Rejects broadcast for non-members', () {
      expect(
        authorizer.authorizeBroadcast(
          callerId: malloryId,
          topic: 'chat_typing:$chatId',
          extension: 'broadcast',
        ),
        isFalse,
      );
    });

    test(
      'Safely handles malformed non-UUID topic without unhandled errors',
      () {
        expect(
          authorizer.authorizeBroadcast(
            callerId: senderId,
            topic: 'chat_typing:invalid-topic-string',
            extension: 'broadcast',
          ),
          isFalse,
        );

        expect(
          authorizer.authorizeBroadcast(
            callerId: senderId,
            topic: 'other_topic:$chatId',
            extension: 'broadcast',
          ),
          isFalse,
        );
      },
    );
  });

  group('Outbox Retry Idempotency (SQLSTATE 23505) Tests', () {
    test(
      'Resolves 23505 duplicate UUID collision cleanly when sender and chat match',
      () {
        final resolver = OutboxIdempotencyResolver(
          serverMessages: {
            messageId: {
              'id': messageId,
              'chat_id': chatId,
              'sender_id': senderId,
            },
          },
        );

        final msg = ChatMessage(
          id: messageId,
          chatId: chatId,
          senderId: senderId,
          text: 'Duplicate delivery test message',
          type: MessageType.text,
          sentAt: DateTime.now().toUtc(),
          deliveryState: DeliveryState.sending,
        );

        final outcome = resolver.resolveConflict(
          msg: msg,
          exception: const PostgrestException(
            message:
                'duplicate key value violates unique constraint "messages_pkey"',
            code: '23505',
          ),
        );

        expect(outcome, equals(DeliveryState.sent));
      },
    );

    test(
      'Rejects 23505 resolution when sender or chat does not match (collision attack)',
      () {
        final foreignSenderId = 'ffffffff-ffff-ffff-ffff-ffffffffffff';
        final resolver = OutboxIdempotencyResolver(
          serverMessages: {
            messageId: {
              'id': messageId,
              'chat_id': chatId,
              'sender_id': foreignSenderId, // Different sender!
            },
          },
        );

        final msg = ChatMessage(
          id: messageId,
          chatId: chatId,
          senderId: senderId,
          text: 'Forged duplicate attempt',
          type: MessageType.text,
          sentAt: DateTime.now().toUtc(),
          deliveryState: DeliveryState.sending,
        );

        final outcome = resolver.resolveConflict(
          msg: msg,
          exception: const PostgrestException(
            message:
                'duplicate key value violates unique constraint "messages_pkey"',
            code: '23505',
          ),
        );

        expect(outcome, equals(DeliveryState.sending)); // Not marked as sent
      },
    );
  });
}
