import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:instant_messenger/core/config/supabase_config.dart';
import 'package:instant_messenger/features/messaging/domain/models/chat_message.dart';
import 'package:instant_messenger/features/chats/domain/models/chat_summary.dart';
import 'package:instant_messenger/features/contacts/domain/models/contact_list_entry.dart';
import 'package:instant_messenger/features/messaging/domain/models/user_presence.dart';
import 'package:instant_messenger/features/messaging/data/messages_repository.dart';
import 'package:instant_messenger/features/chats/data/chats_repository.dart';
import 'package:instant_messenger/features/contacts/data/contact_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:instant_messenger/core/providers/core_providers.dart';
import 'package:instant_messenger/features/messaging/presentation/providers/messaging_providers.dart';
import 'package:instant_messenger/features/messaging/data/outbox_service.dart';
import 'package:instant_messenger/features/messaging/data/outbox_meta.dart';
import 'package:instant_messenger/features/messaging/data/message_cache.dart';
import 'package:instant_messenger/features/profile/data/user_bootstrap.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SupabaseConfig.setTargetForTesting(
      BackendTarget.supabase,
      initialized: true,
    );
  });

  group('ChatMessage & ChatSummary Supabase Deserialization Tests', () {
    test(
      'ChatMessage.fromSupabase parses full payload and status accurately',
      () {
        final now = DateTime.now().toUtc();
        final row = {
          'id': '7b140df0-141a-4d2a-8c67-6ce2b0277f24',
          'chat_id': '4580f488-ea9e-4b77-a89c-d0c3eb1a9d18',
          'sender_id': 'c9ccc86c-cd42-40bb-8678-d9a30964ce30',
          'type': 'media',
          'text': 'Here is the project proposal',
          'media': {
            'url': '4580f488-ea9e-4b77-a89c-d0c3eb1a9d18/proposal.pdf',
            'kind': 'document',
            'mime': 'application/pdf',
            'size': 204850,
            'fileName': 'proposal.pdf',
          },
          'status': 2,
          'sent_at': now.toIso8601String(),
        };

        // When caller is recipient
        final incomingMsg = ChatMessage.fromSupabase(row, 'peer-user-uuid');
        expect(incomingMsg.id, equals('7b140df0-141a-4d2a-8c67-6ce2b0277f24'));
        expect(
          incomingMsg.chatId,
          equals('4580f488-ea9e-4b77-a89c-d0c3eb1a9d18'),
        );
        expect(incomingMsg.isIncoming, isTrue);
        expect(incomingMsg.deliveryState, equals(DeliveryState.delivered));
        expect(incomingMsg.media, isNotNull);
        expect(incomingMsg.media!.kind, equals(MediaKind.document));
        expect(incomingMsg.media!.size, equals(204850));

        // When caller is sender
        final outgoingMsg = ChatMessage.fromSupabase(
          row,
          'c9ccc86c-cd42-40bb-8678-d9a30964ce30',
        );
        expect(outgoingMsg.isIncoming, isFalse);
      },
    );

    test(
      'ChatSummary.fromSupabase extracts direct chat metadata and unread counts',
      () {
        final row = {
          'id': '4580f488-ea9e-4b77-a89c-d0c3eb1a9d18',
          'type': 'direct',
          'last_message': 'See you tomorrow!',
          'last_message_time': '2026-10-21T21:00:00Z',
          'last_sender_id': 'peer-user-uuid',
          'last_message_status': 2,
          'avatar_url': null,
          'chat_members': [
            {'user_id': 'my-user-uuid', 'unread_count': 3, 'muted': false},
            {
              'user_id': 'peer-user-uuid',
              'unread_count': 0,
              'muted': false,
              'profile': {
                'id': 'peer-user-uuid',
                'display_name': 'Jane Doe',
                'avatar_url':
                    'https://mock.supabase.co/storage/v1/object/public/avatars/peer/avatar.jpg',
                'phone_e164': '+919876543210',
              },
            },
          ],
        };

        final summary = ChatSummary.fromSupabase(row, 'my-user-uuid');
        expect(summary.id, equals('4580f488-ea9e-4b77-a89c-d0c3eb1a9d18'));
        expect(summary.otherUserId, equals('peer-user-uuid'));
        expect(summary.otherPhoneE164, equals('+919876543210'));
        expect(summary.avatarUrl, contains('https://mock.supabase.co'));
        expect(summary.unread, equals(3));
        expect(summary.lastMessage, equals('See you tomorrow!'));
        expect(summary.lastMessageStatus, equals(2));
      },
    );

    test(
      'ContactListEntry.fromSupabase preserves device address book priority',
      () {
        final row = {
          'uid': 'user-111',
          'display_name': 'Remote Nickname',
          'about': 'Hey there!',
          'avatar_url': 'https://example.com/avatar.jpg',
          'phone_e164': '+919876543210',
        };

        // With local address book name
        final entryLocal = ContactListEntry.fromSupabase(
          row,
          fallbackSavedName: 'Mom',
        );
        expect(entryLocal.displayName, equals('Mom'));
        expect(entryLocal.phoneE164, equals('+919876543210'));

        // Without local address book name
        final entryRemote = ContactListEntry.fromSupabase(row);
        expect(entryRemote.displayName, equals('Remote Nickname'));
      },
    );

    test(
      'UserPresence.fromMap parses Supabase ISO-8601 strings and handles malformed gracefully',
      () {
        final valid = UserPresence.fromMap({
          'is_online': true,
          'last_seen': '2026-10-21T21:00:00Z',
        });
        expect(valid.online, isTrue);
        expect(valid.lastSeen, equals(DateTime.utc(2026, 10, 21, 21, 0, 0)));
        expect(valid.toMap()['online'], isTrue);
        expect(valid.toMap()['last_seen'], equals('2026-10-21T21:00:00.000Z'));

        final offline = UserPresence.fromMap({
          'online': false,
          'last_seen': null,
        });
        expect(offline.online, isFalse);
        expect(offline.lastSeen, isNull);
        expect(offline.toMap()['online'], isFalse);
        expect(offline.toMap().containsKey('last_seen'), isFalse);

        final malformed = UserPresence.fromMap({
          'is_online': true,
          'last_seen': 'invalid-not-iso8601',
        });
        expect(malformed.online, isTrue);
        expect(malformed.lastSeen, isNull);
      },
    );

    test(
      'MessageFailureReason maintains Hive adapter byte layout and retry rules',
      () {
        final adapter = MessageFailureReasonAdapter();
        expect(adapter.typeId, equals(6));

        // Deserialization of byte ordinals matching chat_message.g.dart
        expect(
          adapter.read(_FakeBinaryReader(0)),
          equals(MessageFailureReason.uploadFailed),
        );
        expect(
          adapter.read(_FakeBinaryReader(1)),
          equals(MessageFailureReason.firestoreFailed),
        );
        expect(
          adapter.read(_FakeBinaryReader(2)),
          equals(MessageFailureReason.unknown),
        );
        expect(
          adapter.read(_FakeBinaryReader(99)),
          equals(MessageFailureReason.uploadFailed),
        );

        // Serialization of enums and transitional aliases
        final writer = _FakeBinaryWriter();
        adapter.write(writer, MessageFailureReason.uploadFailed);
        expect(writer.writtenByte, equals(0));

        adapter.write(writer, MessageFailureReason.firestoreFailed);
        expect(writer.writtenByte, equals(1));

        adapter.write(writer, MessageFailureReason.serverFailed);
        expect(writer.writtenByte, equals(1));

        adapter.write(writer, MessageFailureReason.unknown);
        expect(writer.writtenByte, equals(2));

        // ChatMessage canRetry contract
        final baseMsg = ChatMessage(
          id: 'msg-1',
          chatId: 'chat-1',
          senderId: 'user-1',
          text: 'hello',
          sentAt: DateTime.now(),
          deliveryState: DeliveryState.sending,
          type: MessageType.text,
        );

        expect(
          baseMsg.copyWith(failure: MessageFailureReason.uploadFailed).canRetry,
          isTrue,
        );
        expect(
          baseMsg
              .copyWith(failure: MessageFailureReason.firestoreFailed)
              .canRetry,
          isTrue,
        );
        expect(
          baseMsg.copyWith(failure: MessageFailureReason.serverFailed).canRetry,
          isTrue,
        );
        expect(
          baseMsg.copyWith(failure: MessageFailureReason.unknown).canRetry,
          isFalse,
        );
      },
    );
  });

  group('Supabase MessagesRepository Operations Tests', () {
    test(
      'sendMessage: inserts into public.messages with RFC 4122 UUID and status = 1',
      () async {
        String? interceptedBody;
        String? interceptedMethod;

        final mockHttp = MockClient((request) async {
          if (request.method == 'POST' &&
              request.url.path.contains('/rest/v1/messages')) {
            interceptedMethod = request.method;
            interceptedBody = request.body;
            return http.Response(
              jsonEncode([
                {'id': 'msg-uuid'},
              ]),
              201,
              headers: {'content-type': 'application/json'},
              request: request,
            );
          }
          if (request.url.path.contains(
            '/rest/v1/rpc/get_or_create_direct_chat',
          )) {
            return http.Response(
              jsonEncode('4580f488-ea9e-4b77-a89c-d0c3eb1a9d18'),
              200,
              headers: {'content-type': 'application/json'},
              request: request,
            );
          }
          return http.Response('Not Found', 404, request: request);
        });

        final client = SupabaseClient(
          'https://mock.supabase.co',
          'mock-key',
          httpClient: mockHttp,
        );
        final repo = MessagesRepository(supabaseClient: client);

        final msgId = const Uuid().v4();
        final msg = ChatMessage(
          id: msgId,
          chatId: '4580f488-ea9e-4b77-a89c-d0c3eb1a9d18',
          senderId: 'my-uid',
          text: 'Hello from Supabase repository',
          sentAt: DateTime.now().toUtc(),
          deliveryState: DeliveryState.sent,
          type: MessageType.text,
        );

        final returnedId = await repo.sendMessage(
          '4580f488-ea9e-4b77-a89c-d0c3eb1a9d18',
          msg,
          otherUserId: 'peer-uid',
          otherName: 'Jane',
        );

        expect(returnedId, equals(msgId));
        expect(interceptedMethod, equals('POST'));
        expect(interceptedBody, contains('"status":1'));
        expect(
          interceptedBody,
          contains('"text":"Hello from Supabase repository"'),
        );
      },
    );

    test(
      'promoteStatusBatch: dispatches promote_message_status RPC with parameters',
      () async {
        String? interceptedRpcPath;
        String? interceptedRpcBody;

        final mockHttp = MockClient((request) async {
          if (request.url.path.contains(
            '/rest/v1/rpc/promote_message_status',
          )) {
            interceptedRpcPath = request.url.path;
            interceptedRpcBody = request.body;
            return http.Response(
              jsonEncode(2),
              200,
              headers: {'content-type': 'application/json'},
              request: request,
            );
          }
          return http.Response('Not Found', 404, request: request);
        });

        final client = SupabaseClient(
          'https://mock.supabase.co',
          'mock-key',
          httpClient: mockHttp,
        );
        final repo = MessagesRepository(supabaseClient: client);

        await repo.promoteStatusBatch(
          chatId: 'chat-uuid',
          messageIds: ['msg-1', 'msg-2'],
          newStatus: 2,
        );

        expect(interceptedRpcPath, contains('promote_message_status'));
        expect(interceptedRpcBody, contains('"p_new_status":2'));
        expect(
          interceptedRpcBody,
          contains('"p_message_ids":["msg-1","msg-2"]'),
        );
      },
    );

    test('markRead: dispatches mark_chat_read RPC with p_chat_id', () async {
      String? interceptedRpcBody;

      final mockHttp = MockClient((request) async {
        if (request.url.path.contains('/rest/v1/rpc/mark_chat_read')) {
          interceptedRpcBody = request.body;
          return http.Response(
            '',
            204,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }
        return http.Response('Not Found', 404, request: request);
      });

      final client = SupabaseClient(
        'https://mock.supabase.co',
        'mock-key',
        httpClient: mockHttp,
      );
      final repo = MessagesRepository(supabaseClient: client);

      await repo.markRead('chat-uuid-777', 'my-uid');

      expect(interceptedRpcBody, contains('"p_chat_id":"chat-uuid-777"'));
    });

    test(
      'ensureChatDoc: dispatches get_or_create_direct_chat RPC for direct peer',
      () async {
        String? interceptedRpcBody;

        final mockHttp = MockClient((request) async {
          if (request.url.path.contains(
            '/rest/v1/rpc/get_or_create_direct_chat',
          )) {
            interceptedRpcBody = request.body;
            return http.Response(
              jsonEncode('chat-uuid-777'),
              200,
              headers: {'content-type': 'application/json'},
              request: request,
            );
          }
          return http.Response('Not Found', 404, request: request);
        });

        final client = SupabaseClient(
          'https://mock.supabase.co',
          'mock-key',
          httpClient: mockHttp,
        );
        final repo = MessagesRepository(supabaseClient: client);

        await repo.ensureChatDoc(
          chatId: 'dummy',
          uidA: 'user-a',
          uidB: 'user-b',
          title: 'Direct Chat',
        );

        expect(interceptedRpcBody, isNotNull);
      },
    );

    test(
      'loadLatestMessages: fetches latest messages ordered by sent_at desc',
      () async {
        String? interceptedQuery;
        final mockHttp = MockClient((request) async {
          if (request.url.path.contains('/rest/v1/messages')) {
            interceptedQuery = request.url.query;
            final sampleMessages = [
              {
                'id': 'msg-1',
                'chat_id': 'chat-1',
                'sender_id': 'user-1',
                'type': 'text',
                'text': 'Latest message',
                'status': 2,
                'sent_at': '2026-10-21T21:00:00Z',
              },
            ];
            return http.Response(
              jsonEncode(sampleMessages),
              200,
              headers: {'content-type': 'application/json'},
              request: request,
            );
          }
          return http.Response('Not Found', 404, request: request);
        });

        final client = SupabaseClient(
          'https://mock.supabase.co',
          'mock-key',
          httpClient: mockHttp,
        );
        final repo = MessagesRepository(supabaseClient: client);

        final msgs = await repo.loadLatestMessages('chat-1', limit: 15);
        expect(msgs.length, equals(1));
        expect(msgs.first.id, equals('msg-1'));
        expect(msgs.first.text, equals('Latest message'));
        expect(interceptedQuery, contains('order=sent_at.desc'));
        expect(interceptedQuery, contains('limit=15'));
      },
    );

    test('loadOlderMessages: queries with lt sent_at filter', () async {
      String? interceptedQuery;
      final mockHttp = MockClient((request) async {
        if (request.url.path.contains('/rest/v1/messages')) {
          interceptedQuery = request.url.query;
          return http.Response(
            jsonEncode([]),
            200,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }
        return http.Response('Not Found', 404, request: request);
      });

      final client = SupabaseClient(
        'https://mock.supabase.co',
        'mock-key',
        httpClient: mockHttp,
      );
      final repo = MessagesRepository(supabaseClient: client);

      final cursor = DateTime.utc(2026, 10, 21, 20, 0, 0);
      await repo.loadOlderMessages('chat-1', cursor, limit: 20);

      expect(interceptedQuery, contains('sent_at=lt.'));
      expect(interceptedQuery, contains('limit=20'));
    });

    test(
      'watchChat: initial load emits messages and cancel cleans up cleanly',
      () async {
        final mockHttp = MockClient((request) async {
          if (request.url.path.contains('/rest/v1/messages')) {
            final sampleMessages = [
              {
                'id': 'msg-1',
                'chat_id': 'chat-1',
                'sender_id': 'user-1',
                'type': 'text',
                'text': 'Initial stream message',
                'status': 1,
                'sent_at': '2026-10-21T21:00:00Z',
              },
            ];
            return http.Response(
              jsonEncode(sampleMessages),
              200,
              headers: {'content-type': 'application/json'},
              request: request,
            );
          }
          return http.Response('Not Found', 404, request: request);
        });

        final client = SupabaseClient(
          'https://mock.supabase.co',
          'mock-key',
          httpClient: mockHttp,
        );
        final repo = MessagesRepository(supabaseClient: client);

        final stream = repo.watchChat('chat-1');
        final firstEmission = await stream.first;

        expect(firstEmission.length, equals(1));
        expect(firstEmission.first.text, equals('Initial stream message'));
      },
    );
  });

  group('Typing & Realtime Controller Lifecycle Tests', () {
    test('ChatTypingNotifier disposes channel cleanly', () {
      final mockClient = SupabaseClient('https://mock.supabase.co', 'mock-key');
      final container = ProviderContainer(
        overrides: [
          supabaseClientProvider.overrideWithValue(mockClient),
        ],
      );
      addTearDown(container.dispose);

      const args = ChatControllerArgs(
        chatId: 'test-chat',
        currentUserId: 'test-user',
        otherUserId: 'test-user-2',
      );

      final notifier =
          container.read(chatTypingNotifierProvider(args).notifier);
      expect(container.read(chatTypingNotifierProvider(args)), isFalse);

      // Verify clear does not throw
      notifier.clearTyping();
    });
  });

  group('ChatsRepository watchUserChats Lifecycle & Concurrency Tests', () {
    test(
      'watchUserChats with unauthenticated user emits empty list immediately',
      () async {
        final mockClient = SupabaseClient(
          'https://mock.supabase.co',
          'mock-key',
        );
        final repo = ChatsRepository(supabaseClient: mockClient);

        final result = await repo.watchUserChats().first;
        expect(result, isEmpty);
      },
    );

    test(
      'watchUserChats fetches on listen, maps rows, and handles cancellation cleanly',
      () async {
        int fetchCount = 0;
        final mockHttp = MockClient((request) async {
          if (request.url.path.contains('/rest/v1/chats')) {
            fetchCount++;
            final sampleRows = [
              {
                'id': 'chat-101',
                'type': 'direct',
                'last_message': 'Hello there',
                'last_message_time': '2026-10-21T21:00:00Z',
                'last_sender_id': 'peer-uuid',
                'last_message_status': 2,
                'updated_at': '2026-10-21T21:00:00Z',
                'chat_members': [
                  {
                    'user_id': 'my-user-uuid',
                    'unread_count': 1,
                    'muted': false,
                  },
                  {
                    'user_id': 'peer-uuid',
                    'unread_count': 0,
                    'muted': false,
                    'profile': {
                      'id': 'peer-uuid',
                      'display_name': 'Alice',
                      'avatar_url': null,
                      'phone_e164': '+1234567890',
                    },
                  },
                ],
              },
            ];
            return http.Response(
              jsonEncode(sampleRows),
              200,
              headers: {'content-type': 'application/json'},
              request: request,
            );
          }
          return http.Response('Not Found', 404);
        });

        final mockClient = SupabaseClient(
          'https://mock.supabase.co',
          'mock-key',
          httpClient: mockHttp,
        );
        final repo = ChatsRepository(supabaseClient: mockClient);

        final stream = repo.watchUserChats('my-user-uuid');
        final firstEmission = await stream.first;

        expect(fetchCount, equals(1));
        expect(firstEmission.length, equals(1));
        expect(firstEmission.first.id, equals('chat-101'));
        expect(firstEmission.first.otherUserId, equals('peer-uuid'));
        expect(firstEmission.first.unread, equals(1));
      },
    );

    test(
      'watchUserChats stream cancellation unsubscribes and closes cleanly',
      () async {
        final mockClient = SupabaseClient(
          'https://mock.supabase.co',
          'mock-key',
        );
        final repo = ChatsRepository(supabaseClient: mockClient);

        final stream = repo.watchUserChats('test-user');
        final sub = stream.listen((_) {});

        await sub.cancel();
        // Cancellation clean without throwing
      },
    );
  });

  group('ContactsRepository Operations Tests', () {
    test('watchDirectory with unauthenticated user emits empty list', () async {
      final mockClient = SupabaseClient('https://mock.supabase.co', 'mock-key');
      final repo = ContactsRepository(supabaseClient: mockClient);

      final result = await repo.watchDirectory().first;
      expect(result, isEmpty);
    });

    test('watchMatched with unauthenticated user emits empty list', () async {
      final mockClient = SupabaseClient('https://mock.supabase.co', 'mock-key');
      final repo = ContactsRepository(supabaseClient: mockClient);

      final result = await repo.watchMatched().first;
      expect(result, isEmpty);
    });
  });

  group('Supabase OutboxService Operations & Concurrency Tests', () {
    test(
      'savePending stores local state and dispatches remote insert',
      () async {
        Map<String, dynamic>? interceptedBody;
        final mockHttp = MockClient((request) async {
          if (request.url.path.contains('/rest/v1/messages')) {
            interceptedBody = jsonDecode(request.body) as Map<String, dynamic>;
            return http.Response(
              jsonEncode([interceptedBody]),
              201,
              headers: {'content-type': 'application/json'},
              request: request,
            );
          }
          return http.Response('Not Found', 404, request: request);
        });

        final client = SupabaseClient(
          'https://mock.supabase.co',
          'mock-key',
          httpClient: mockHttp,
        );
        final msgBox = _FakeBox<ChatMessage>();
        final metaBox = _FakeBox<dynamic>();
        final cache = _FakeMessageCache();

        final outbox = OutboxService(
          messageBox: msgBox,
          metaBox: metaBox,
          messageCache: cache,
          supabaseClient: client,
        );

        final msg = ChatMessage(
          id: const Uuid().v4(),
          chatId: const Uuid().v4(),
          senderId: 'user-sender',
          text: 'Hello from Outbox',
          sentAt: DateTime.utc(2026, 10, 21, 22, 0, 0),
          type: MessageType.text,
          deliveryState: DeliveryState.sending,
        );

        await outbox.savePending(msg);
        // Allow async unawaited insert to settle
        await Future<void>.delayed(const Duration(milliseconds: 50));

        expect(interceptedBody, isNotNull);
        expect(interceptedBody!['text'], equals('Hello from Outbox'));
        expect(interceptedBody!['status'], equals(1));
        expect(msgBox.get(msg.id)?.deliveryState, equals(DeliveryState.sent));
        expect(msgBox.get(msg.id)?.failure, isNull);
      },
    );

    test('insertToSupabase recovers on 23505 idempotent duplicate', () async {
      int insertCalls = 0;
      final msgId = const Uuid().v4();
      final chatId = const Uuid().v4();

      final mockHttp = MockClient((request) async {
        if (request.url.path.contains('/rest/v1/messages')) {
          if (request.method == 'POST') {
            insertCalls++;
            return http.Response(
              jsonEncode({
                'code': '23505',
                'message': 'duplicate key value violates unique constraint',
                'details': 'Key (id)=($msgId) already exists.',
              }),
              409,
              headers: {'content-type': 'application/json'},
              request: request,
            );
          } else if (request.method == 'GET') {
            return http.Response(
              jsonEncode({
                'id': msgId,
                'chat_id': chatId,
                'sender_id': 'user-1',
              }),
              200,
              headers: {'content-type': 'application/json'},
              request: request,
            );
          }
        }
        return http.Response('Not Found', 404, request: request);
      });

      final client = SupabaseClient(
        'https://mock.supabase.co',
        'mock-key',
        httpClient: mockHttp,
      );
      final msgBox = _FakeBox<ChatMessage>();
      final metaBox = _FakeBox<dynamic>();
      final cache = _FakeMessageCache();

      final outbox = OutboxService(
        messageBox: msgBox,
        metaBox: metaBox,
        messageCache: cache,
        supabaseClient: client,
      );

      final msg = ChatMessage(
        id: msgId,
        chatId: chatId,
        senderId: 'user-1',
        text: 'Duplicate retry message',
        sentAt: DateTime.utc(2026, 10, 21, 22, 0, 0),
        type: MessageType.text,
        deliveryState: DeliveryState.sending,
      );

      await outbox.insertToSupabase(msg);

      expect(insertCalls, equals(1));
      expect(msgBox.get(msgId)?.deliveryState, equals(DeliveryState.sent));
      expect(msgBox.get(msgId)?.failure, isNull);
    });

    test(
      'insertToSupabase classifies transient network errors as retryable serverFailed',
      () async {
        final mockHttp = MockClient((request) async {
          if (request.url.path.contains('/rest/v1/messages')) {
            return http.Response(
              'Internal Server Error',
              500,
              headers: {'content-type': 'text/plain'},
              request: request,
            );
          }
          return http.Response('Not Found', 404, request: request);
        });

        final client = SupabaseClient(
          'https://mock.supabase.co',
          'mock-key',
          httpClient: mockHttp,
        );
        final msgBox = _FakeBox<ChatMessage>();
        final metaBox = _FakeBox<dynamic>();
        final cache = _FakeMessageCache();

        final outbox = OutboxService(
          messageBox: msgBox,
          metaBox: metaBox,
          messageCache: cache,
          supabaseClient: client,
        );

        final msg = ChatMessage(
          id: const Uuid().v4(),
          chatId: const Uuid().v4(),
          senderId: 'user-1',
          text: 'Network error test',
          sentAt: DateTime.now(),
          type: MessageType.text,
          deliveryState: DeliveryState.sending,
        );

        await outbox.insertToSupabase(msg);

        final stored = msgBox.get(msg.id);
        expect(stored?.failure, equals(MessageFailureReason.serverFailed));
        expect(stored?.canRetry, isTrue);
      },
    );

    test(
      'insertToSupabase classifies permanent RLS/schema errors as unknown and non-retryable',
      () async {
        final mockHttp = MockClient((request) async {
          if (request.url.path.contains('/rest/v1/messages')) {
            return http.Response(
              jsonEncode({
                'code': '42501',
                'message':
                    'new row violates row-level security policy for table "messages"',
              }),
              403,
              headers: {'content-type': 'application/json'},
              request: request,
            );
          }
          return http.Response('Not Found', 404, request: request);
        });

        final client = SupabaseClient(
          'https://mock.supabase.co',
          'mock-key',
          httpClient: mockHttp,
        );
        final msgBox = _FakeBox<ChatMessage>();
        final metaBox = _FakeBox<dynamic>();
        final cache = _FakeMessageCache();

        final outbox = OutboxService(
          messageBox: msgBox,
          metaBox: metaBox,
          messageCache: cache,
          supabaseClient: client,
        );

        final msg = ChatMessage(
          id: const Uuid().v4(),
          chatId: const Uuid().v4(),
          senderId: 'user-unauthorized',
          text: 'RLS denied message',
          sentAt: DateTime.now(),
          type: MessageType.text,
          deliveryState: DeliveryState.sending,
        );

        await outbox.insertToSupabase(msg);

        final stored = msgBox.get(msg.id);
        expect(stored?.failure, equals(MessageFailureReason.unknown));
        expect(stored?.canRetry, isFalse);
      },
    );

    test(
      'cancelMessage deletes metadata, marks uploadFailed, and preserves cancellation',
      () async {
        final msgId = const Uuid().v4();
        final chatId = const Uuid().v4();

        final mockHttp = MockClient((request) async {
          await Future<void>.delayed(const Duration(milliseconds: 50));
          return http.Response(
            jsonEncode([
              {'id': msgId},
            ]),
            201,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        });

        final client = SupabaseClient(
          'https://mock.supabase.co',
          'mock-key',
          httpClient: mockHttp,
        );
        final msgBox = _FakeBox<ChatMessage>();
        final metaBox = _FakeBox<dynamic>();
        final cache = _FakeMessageCache();

        final outbox = OutboxService(
          messageBox: msgBox,
          metaBox: metaBox,
          messageCache: cache,
          supabaseClient: client,
        );

        final msg = ChatMessage(
          id: msgId,
          chatId: chatId,
          senderId: 'user-1',
          text: 'Will cancel',
          sentAt: DateTime.now(),
          type: MessageType.media,
          deliveryState: DeliveryState.sending,
          media: MessageMedia(
            url: '/tmp/test.jpg',
            kind: MediaKind.image,
            mime: 'image/jpeg',
            size: 100,
          ),
        );

        await msgBox.put(msgId, msg);
        await metaBox.put(msgId, {'dummy': true});

        // User initiates cancellation
        await outbox.cancelMessage(msgId);

        expect(metaBox.containsKey(msgId), isFalse);
        expect(
          msgBox.get(msgId)?.failure,
          equals(MessageFailureReason.uploadFailed),
        );
      },
    );

    test(
      'isSending tracks active in-flight status and retryMessage resets failure state',
      () async {
        final msgId = const Uuid().v4();
        final chatId = const Uuid().v4();

        final mockHttp = MockClient((request) async {
          if (request.url.path.contains('/rest/v1/messages')) {
            return http.Response(
              jsonEncode([
                {'id': msgId},
              ]),
              201,
              headers: {'content-type': 'application/json'},
              request: request,
            );
          }
          return http.Response('Not Found', 404, request: request);
        });

        final client = SupabaseClient(
          'https://mock.supabase.co',
          'mock-key',
          httpClient: mockHttp,
        );
        final msgBox = _FakeBox<ChatMessage>();
        final metaBox = _FakeBox<dynamic>();
        final cache = _FakeMessageCache();

        final outbox = OutboxService(
          messageBox: msgBox,
          metaBox: metaBox,
          messageCache: cache,
          supabaseClient: client,
        );

        final msg = ChatMessage(
          id: msgId,
          chatId: chatId,
          senderId: 'user-1',
          text: 'Retrying message',
          sentAt: DateTime.now(),
          type: MessageType.text,
          deliveryState: DeliveryState.sending,
          failure: MessageFailureReason.serverFailed,
        );

        await msgBox.put(msgId, msg);
        await metaBox.put(
          msgId,
          OutboxMeta(
            messageId: msgId,
            chatId: chatId,
            filePath: '',
            mediaKind: MediaKind.image,
            retryCount: 0,
            nextAttemptAt: DateTime.now(),
          ).toMap(),
        );

        await outbox.retryMessage(msgId);

        expect(msgBox.get(msgId)?.deliveryState, equals(DeliveryState.sent));
        expect(msgBox.get(msgId)?.failure, isNull);
        expect(outbox.isSending(msgId), isFalse);
      },
    );
  });

  group('Supabase UserBootstrap Lifecycle Tests', () {
    test(
      'bootstrap without authenticated user returns NextRoute.profile',
      () async {
        final mockClient = SupabaseClient(
          'https://mock.supabase.co',
          'mock-key',
        );
        final boot = UserBootstrap(supabase: mockClient);

        final route = await boot.bootstrap();
        expect(route, equals(NextRoute.profile));
      },
    );

    test(
      'setDisplayName without authenticated user throws StateError',
      () async {
        final mockClient = SupabaseClient(
          'https://mock.supabase.co',
          'mock-key',
        );
        final boot = UserBootstrap(supabase: mockClient);

        expect(() => boot.setDisplayName('Alice'), throwsStateError);
      },
    );
  });
}

class _FakeBox<T> extends Fake implements Box<T> {
  final Map<dynamic, T> _storage = {};

  @override
  Iterable<T> get values => _storage.values;

  @override
  T? get(dynamic key, {T? defaultValue}) => _storage[key] ?? defaultValue;

  @override
  Future<void> put(dynamic key, T value) async {
    _storage[key] = value;
  }

  @override
  Future<void> delete(dynamic key) async {
    _storage.remove(key);
  }

  @override
  bool containsKey(dynamic key) => _storage.containsKey(key);
}

class _FakeMessageCache extends Fake implements MessageCache {}

class _FakeBinaryReader extends Fake implements BinaryReader {
  final int byte;
  _FakeBinaryReader(this.byte);

  @override
  int readByte() => byte;
}

class _FakeBinaryWriter extends Fake implements BinaryWriter {
  int? writtenByte;

  @override
  void writeByte(int byte) {
    writtenByte = byte;
  }
}
