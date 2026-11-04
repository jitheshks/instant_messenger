import 'package:flutter_test/flutter_test.dart';
import 'package:instant_messenger/features/messaging/domain/models/chat_message.dart';
import 'package:instant_messenger/shared/utils/chat_date.dart';

void main() {
  group('Timestamp Lifecycle & Timezone Consistency Tests', () {
    // Fixed instant: 2026-10-31 13:05:00.000 UTC
    // In IST (+05:30), this corresponds to 2026-10-31 18:35:00 (6:35 PM).
    final fixedUtcInstant = DateTime.utc(2026, 10, 31, 13, 5, 0);

    test('1. Local message creation stores UTC instant consistently', () {
      final msg = ChatMessage(
        id: 'msg-local-1',
        chatId: 'chat-1',
        senderId: 'user-sender',
        text: 'Hello from local sender',
        sentAt: fixedUtcInstant,
        deliveryState: DeliveryState.sending,
        type: MessageType.text,
      );

      expect(msg.sentAt.isUtc, isTrue);
      expect(msg.sentAt.year, equals(2026));
      expect(msg.sentAt.month, equals(10));
      expect(msg.sentAt.day, equals(31));
      expect(msg.sentAt.hour, equals(13));
      expect(msg.sentAt.minute, equals(5));

      // Serialization produces ISO 8601 with Z or UTC representation
      final map = msg.toMap();
      expect(map['sentAt'], contains('Z'));
    });

    test('2. ChatMessage.fromSupabase parses ISO-8601 with timezone into UTC instant', () {
      final supabaseRow = {
        'id': 'msg-sb-1',
        'chat_id': 'c9ccc86c-cd42-40bb-8678-d9a30964ce30',
        'sender_id': '11111111-1111-1111-1111-111111111111',
        'text': 'Persisted in PostgreSQL timestamptz',
        'sent_at': '2026-10-31T13:05:00.000000+00:00',
        'type': 'text',
        'status': 1,
      };

      final msg = ChatMessage.fromSupabase(supabaseRow);
      expect(msg.sentAt.isUtc, isTrue);
      expect(msg.sentAt.toUtc(), equals(fixedUtcInstant));
    });

    test('3. ChatMessage.fromMap parses serialized map into UTC instant', () {
      final serializedMap = {
        'id': 'msg-cache-1',
        'chatId': 'chat-1',
        'senderId': 'user-1',
        'text': 'Cached in local store',
        'sentAt': '2026-10-31T13:05:00.000Z',
        'deliveryState': 1,
        'type': 'text',
      };

      final msg = ChatMessage.fromMap(serializedMap);
      expect(msg.sentAt.isUtc, isTrue);
      expect(msg.sentAt, equals(fixedUtcInstant));
    });

    test('4. Sender and recipient parse identical database timestamp to same instant', () {
      final dbPayload = {
        'id': 'msg-shared-1',
        'chat_id': 'chat-shared',
        'sender_id': 'sender-uid',
        'text': 'Synchronized message',
        'sent_at': '2026-10-31T13:05:00.123456Z',
        'type': 'text',
        'status': 1,
      };

      final senderMsg = ChatMessage.fromSupabase(dbPayload, 'sender-uid');
      final recipientMsg = ChatMessage.fromSupabase(dbPayload, 'recipient-uid');

      expect(senderMsg.isIncoming, isFalse);
      expect(recipientMsg.isIncoming, isTrue);
      expect(senderMsg.sentAt, equals(recipientMsg.sentAt));
      expect(senderMsg.sentAt.isAtSameMomentAs(recipientMsg.sentAt), isTrue);
    });

    test('5. ISO-8601 with UTC "Z" suffix produces exact UTC instant', () {
      final msg = ChatMessage.fromSupabase({
        'id': 'msg-z-1',
        'chat_id': 'c1',
        'sender_id': 'u1',
        'text': 'Z timestamp',
        'sent_at': '2026-10-31T13:05:00Z',
        'type': 'text',
        'status': 1,
      });

      expect(msg.sentAt.isUtc, isTrue);
      expect(msg.sentAt.millisecondsSinceEpoch, equals(fixedUtcInstant.millisecondsSinceEpoch));
    });

    test('6. Timestamp with explicit nonzero timezone offset normalizes to UTC instant', () {
      // 18:35 at +05:30 offset is exactly 13:05 UTC
      final msg = ChatMessage.fromSupabase({
        'id': 'msg-offset-1',
        'chat_id': 'c1',
        'sender_id': 'u1',
        'text': 'Offset timestamp',
        'sent_at': '2026-10-31T18:35:00+05:30',
        'type': 'text',
        'status': 1,
      });

      expect(msg.sentAt.isUtc, isTrue);
      expect(msg.sentAt.millisecondsSinceEpoch, equals(fixedUtcInstant.millisecondsSinceEpoch));
    });

    test('7. Cache serialization and deserialization roundtrip preserves UTC instant', () {
      final original = ChatMessage(
        id: 'msg-roundtrip',
        chatId: 'c1',
        senderId: 'u1',
        text: 'Roundtrip test',
        sentAt: fixedUtcInstant,
        deliveryState: DeliveryState.delivered,
        type: MessageType.text,
      );

      final map = original.toMap();
      final restored = ChatMessage.fromMap(map);

      expect(restored.sentAt.isUtc, isTrue);
      expect(restored.sentAt, equals(original.sentAt));
      expect(restored.sentAt.millisecondsSinceEpoch, equals(original.sentAt.millisecondsSinceEpoch));
    });

    test('8. Messages around midnight convert accurately relative to local date boundaries', () {
      // 2026-10-31 23:55:00 local time
      final justBeforeMidnightLocal = DateTime(2026, 10, 31, 23, 55, 0);
      // 2026-11-01 00:05:00 local time
      final justAfterMidnightLocal = DateTime(2026, 11, 1, 0, 5, 0);

      // Now at 2026-11-01 09:00:00 local time
      final nowLocal = DateTime(2026, 11, 1, 9, 0, 0);

      // UTC representations
      final msg1Utc = justBeforeMidnightLocal.toUtc();
      final msg2Utc = justAfterMidnightLocal.toUtc();

      // Ensure dayKey groups into separate local calendar days
      final key1 = dayKey(msg1Utc);
      final key2 = dayKey(msg2Utc);

      expect(key1, equals('2026-10-31'));
      expect(key2, equals('2026-11-01'));
      expect(key1, isNot(equals(key2)));

      // Ensure chatDateLabel labels msg1 as Yesterday and msg2 as Today
      expect(chatDateLabel(msg1Utc, nowLocal), equals('Yesterday'));
      expect(chatDateLabel(msg2Utc, nowLocal), equals('Today'));
    });

    test('9. Sorting and pagination around timestamp boundaries is chronological and monotonic', () {
      final t1 = DateTime.utc(2026, 10, 31, 23, 58, 0);
      final t2 = DateTime.utc(2026, 10, 31, 23, 59, 0);
      final t3 = DateTime.utc(2026, 11, 1, 0, 1, 0);

      final msg1 = ChatMessage(id: 'm1', chatId: 'c1', senderId: 'u1', text: '1', sentAt: t1, deliveryState: DeliveryState.sent, type: MessageType.text);
      final msg2 = ChatMessage(id: 'm2', chatId: 'c1', senderId: 'u1', text: '2', sentAt: t2, deliveryState: DeliveryState.sent, type: MessageType.text);
      final msg3 = ChatMessage(id: 'm3', chatId: 'c1', senderId: 'u1', text: '3', sentAt: t3, deliveryState: DeliveryState.sent, type: MessageType.text);

      final list = [msg3, msg1, msg2]..sort((a, b) => a.sentAt.compareTo(b.sentAt));

      expect(list.map((m) => m.id).toList(), equals(['m1', 'm2', 'm3']));
      expect(msg1.sentAt.isBefore(msg2.sentAt), isTrue);
      expect(msg2.sentAt.isBefore(msg3.sentAt), isTrue);
    });
  });
}
