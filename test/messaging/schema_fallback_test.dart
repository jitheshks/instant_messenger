import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:instant_messenger/features/messaging/data/messages_repository.dart';
import 'package:instant_messenger/features/messaging/domain/models/chat_message.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MessagesRepository Schema Fallback & Error Handling Tests', () {
    const chatId = 'chat-fallback-test-111';
    const currentUserId = 'user-alice-123';
    const peerUserId = 'user-bob-456';

    test('1. PGRST204 missing column in schema cache triggers legacy insert fallback', () async {
      var callCount = 0;
      Map<String, dynamic>? firstPayload;
      Map<String, dynamic>? fallbackPayload;

      final mockHttp = MockClient((request) async {
        if (request.url.path.contains('/rest/v1/rpc/get_or_create_direct_chat')) {
          return http.Response(
            jsonEncode(chatId),
            200,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }

        if (request.url.path.contains('/rest/v1/messages')) {
          callCount++;
          final body = jsonDecode(request.body) as Map<String, dynamic>;

          if (callCount == 1) {
            firstPayload = body;
            return http.Response(
              jsonEncode({
                'code': 'PGRST204',
                'message': "Could not find the 'is_forwarded' column of 'messages' in the schema cache",
                'details': null,
                'hint': null,
              }),
              400,
              headers: {'content-type': 'application/json'},
              request: request,
            );
          } else {
            fallbackPayload = body;
            return http.Response(
              jsonEncode([{'id': body['id'], 'status': 1}]),
              201,
              headers: {'content-type': 'application/json'},
              request: request,
            );
          }
        }

        return http.Response('{}', 200, headers: {'content-type': 'application/json'}, request: request);
      });

      final client = SupabaseClient('https://mock.supabase.co', 'mock-key', httpClient: mockHttp);
      final repo = MessagesRepository(supabaseClient: client);

      final msg = ChatMessage(
        id: 'msg-pgrst204-1',
        chatId: chatId,
        senderId: currentUserId,
        text: 'Forwarded message testing PGRST204',
        sentAt: DateTime.now(),
        deliveryState: DeliveryState.sending,
        type: MessageType.text,
        isForwarded: true,
        replyToMessageId: 'orig-quote-999',
        replyText: 'Original text',
      );

      final resultId = await repo.sendMessage(
        chatId,
        msg,
        otherUserId: peerUserId,
        otherName: 'Bob',
      );

      expect(resultId, equals('msg-pgrst204-1'));
      expect(callCount, equals(2));
      // First attempt included forward and reply metadata
      expect(firstPayload?['is_forwarded'], isTrue);
      expect(firstPayload?['reply_to_message_id'], equals('orig-quote-999'));
      expect(firstPayload?['reply_snapshot'], isNotNull);

      // Fallback stripped the metadata
      expect(fallbackPayload?['is_forwarded'], isNull);
      expect(fallbackPayload?['reply_to_message_id'], isNull);
      expect(fallbackPayload?['reply_snapshot'], isNull);
      expect(fallbackPayload?['text'], equals('Forwarded message testing PGRST204'));
    });

    test('2. 42703 undefined column triggers legacy insert fallback', () async {
      var callCount = 0;
      Map<String, dynamic>? fallbackPayload;

      final mockHttp = MockClient((request) async {
        if (request.url.path.contains('/rest/v1/rpc/get_or_create_direct_chat')) {
          return http.Response(
            jsonEncode(chatId),
            200,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }

        if (request.url.path.contains('/rest/v1/messages')) {
          callCount++;
          final body = jsonDecode(request.body) as Map<String, dynamic>;

          if (callCount == 1) {
            return http.Response(
              jsonEncode({
                'code': '42703',
                'message': 'column "reply_to_message_id" of relation "messages" does not exist',
                'details': null,
                'hint': null,
              }),
              400,
              headers: {'content-type': 'application/json'},
              request: request,
            );
          } else {
            fallbackPayload = body;
            return http.Response(
              jsonEncode([{'id': body['id'], 'status': 1}]),
              201,
              headers: {'content-type': 'application/json'},
              request: request,
            );
          }
        }

        return http.Response('{}', 200, headers: {'content-type': 'application/json'}, request: request);
      });

      final client = SupabaseClient('https://mock.supabase.co', 'mock-key', httpClient: mockHttp);
      final repo = MessagesRepository(supabaseClient: client);

      final msg = ChatMessage(
        id: 'msg-42703-1',
        chatId: chatId,
        senderId: currentUserId,
        text: 'Testing 42703 undefined column',
        sentAt: DateTime.now(),
        deliveryState: DeliveryState.sending,
        type: MessageType.text,
        replyToMessageId: 'reply-target-001',
      );

      final resultId = await repo.sendMessage(
        chatId,
        msg,
        otherUserId: peerUserId,
        otherName: 'Bob',
      );

      expect(resultId, equals('msg-42703-1'));
      expect(callCount, equals(2));
      expect(fallbackPayload?['reply_to_message_id'], isNull);
      expect(fallbackPayload?['text'], equals('Testing 42703 undefined column'));
    });

    test('3. 42501 column-level permission denied triggers fallback', () async {
      var callCount = 0;

      final mockHttp = MockClient((request) async {
        if (request.url.path.contains('/rest/v1/rpc/get_or_create_direct_chat')) {
          return http.Response(
            jsonEncode(chatId),
            200,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }

        if (request.url.path.contains('/rest/v1/messages')) {
          callCount++;
          if (callCount == 1) {
            return http.Response(
              jsonEncode({
                'code': '42501',
                'message': 'permission denied for column is_forwarded of relation messages',
                'details': null,
                'hint': null,
              }),
              403,
              headers: {'content-type': 'application/json'},
              request: request,
            );
          } else {
            return http.Response(
              jsonEncode([{'id': 'msg-col-perm', 'status': 1}]),
              201,
              headers: {'content-type': 'application/json'},
              request: request,
            );
          }
        }

        return http.Response('{}', 200, headers: {'content-type': 'application/json'}, request: request);
      });

      final client = SupabaseClient('https://mock.supabase.co', 'mock-key', httpClient: mockHttp);
      final repo = MessagesRepository(supabaseClient: client);

      final msg = ChatMessage(
        id: 'msg-col-perm',
        chatId: chatId,
        senderId: currentUserId,
        text: 'Testing column permission fallback',
        sentAt: DateTime.now(),
        deliveryState: DeliveryState.sending,
        type: MessageType.text,
        isForwarded: true,
      );

      final resultId = await repo.sendMessage(
        chatId,
        msg,
        otherUserId: peerUserId,
        otherName: 'Bob',
      );

      expect(resultId, equals('msg-col-perm'));
      expect(callCount, equals(2));
    });

    test('4. RLS violations (42501) are NOT swallowed and do NOT fallback', () async {
      var callCount = 0;

      final mockHttp = MockClient((request) async {
        if (request.url.path.contains('/rest/v1/rpc/get_or_create_direct_chat')) {
          return http.Response(
            jsonEncode(chatId),
            200,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }

        if (request.url.path.contains('/rest/v1/messages')) {
          callCount++;
          return http.Response(
            jsonEncode({
              'code': '42501',
              'message': 'new row violates row-level security policy for table "messages"',
              'details': null,
              'hint': null,
            }),
            403,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }

        return http.Response('{}', 200, headers: {'content-type': 'application/json'}, request: request);
      });

      final client = SupabaseClient('https://mock.supabase.co', 'mock-key', httpClient: mockHttp);
      final repo = MessagesRepository(supabaseClient: client);

      final msg = ChatMessage(
        id: 'msg-rls-denied',
        chatId: chatId,
        senderId: currentUserId,
        text: 'Testing RLS rejection',
        sentAt: DateTime.now(),
        deliveryState: DeliveryState.sending,
        type: MessageType.text,
        isForwarded: true,
      );

      await expectLater(
        repo.sendMessage(chatId, msg, otherUserId: peerUserId, otherName: 'Bob'),
        throwsA(isA<PostgrestException>().having(
          (e) => e.code,
          'code',
          equals('42501'),
        )),
      );

      // Must fail immediately on the 1st attempt without fallback!
      expect(callCount, equals(1));
    });

    test('5. Unrelated network and server errors are rethrown without fallback', () async {
      var callCount = 0;

      final mockHttp = MockClient((request) async {
        if (request.url.path.contains('/rest/v1/rpc/get_or_create_direct_chat')) {
          return http.Response(
            jsonEncode(chatId),
            200,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }

        if (request.url.path.contains('/rest/v1/messages')) {
          callCount++;
          return http.Response(
            jsonEncode({
              'code': '500',
              'message': 'Internal Server Error',
              'details': null,
              'hint': null,
            }),
            500,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }

        return http.Response('{}', 200, headers: {'content-type': 'application/json'}, request: request);
      });

      final client = SupabaseClient('https://mock.supabase.co', 'mock-key', httpClient: mockHttp);
      final repo = MessagesRepository(supabaseClient: client);

      final msg = ChatMessage(
        id: 'msg-500-error',
        chatId: chatId,
        senderId: currentUserId,
        text: 'Testing 500 error',
        sentAt: DateTime.now(),
        deliveryState: DeliveryState.sending,
        type: MessageType.text,
      );

      await expectLater(
        repo.sendMessage(chatId, msg, otherUserId: peerUserId, otherName: 'Bob'),
        throwsA(isA<PostgrestException>()),
      );

      expect(callCount, equals(1));
    });
  });
}
