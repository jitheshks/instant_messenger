import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:instant_messenger/core/network/connectivity_service.dart';
import 'package:instant_messenger/core/persistence/hive_init.dart';
import 'package:instant_messenger/core/persistence/stores/chats_store.dart';
import 'package:instant_messenger/core/persistence/stores/messages_store.dart';
import 'package:instant_messenger/core/sync/reconciliation_service.dart';
import 'package:instant_messenger/features/messaging/data/messages_repository.dart';
import 'package:instant_messenger/features/messaging/domain/models/chat_message.dart';
import 'package:instant_messenger/app/theme/chat_theme_extension.dart';
import 'package:instant_messenger/features/messaging/presentation/widgets/chat_delivery_row.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _FakeConnectivityService extends ConnectivityService {
  bool _online;
  final _controller = StreamController<NetworkInterfaceStatus>.broadcast();

  _FakeConnectivityService({bool initialOnline = true})
      : _online = initialOnline;

  @override
  bool get hasNetworkInterface => _online;

  @override
  Stream<NetworkInterfaceStatus> get onStatusChanged => _controller.stream;

  void setOnline(bool online) {
    _online = online;
    _controller.add(
      NetworkInterfaceStatus([
        online ? NetworkInterfaceType.wifi : NetworkInterfaceType.none,
      ]),
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Message Delivery & Read Receipts Comprehensive Verification', () {
    late Directory tempDir;
    late Box<ChatMessage> msgBox;
    late Box chatBox;
    late MessagesStore messagesStore;
    late ChatsStore chatsStore;

    const senderUid = 'user-alice-sender';
    const recipientUid = 'user-bob-recipient';
    const chatId = 'chat-receipt-test-101';

    setUp(() async {
      tempDir = Directory.systemTemp.createTempSync('receipt_test_');
      Hive.init(tempDir.path);
      HiveInit.registerAdapters();

      msgBox = await Hive.openBox<ChatMessage>('cache_msgs_$recipientUid');
      chatBox = await Hive.openBox('chats_cache_$recipientUid');

      messagesStore = MessagesStore(msgBox);
      chatsStore = ChatsStore(chatBox);
    });

    tearDown(() async {
      if (msgBox.isOpen) await msgBox.close();
      if (chatBox.isOpen) await chatBox.close();
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
    });

    // -------------------------------------------------------------------------
    // Requirement 1: A sent message displays one grey tick
    // -------------------------------------------------------------------------
    testWidgets('1. A sent message displays one grey tick', (tester) async {
      final msg = ChatMessage(
        id: 'msg-sent-1',
        chatId: chatId,
        senderId: senderUid,
        text: 'Hello Bob',
        sentAt: DateTime.now(),
        type: MessageType.text,
        deliveryState: DeliveryState.sent,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChatDeliveryRow(msg: msg),
          ),
        ),
      );

      final iconFinder = find.byIcon(Icons.done);
      expect(iconFinder, findsOneWidget);
      final icon = tester.widget<Icon>(iconFinder);
      expect(icon.color, equals(ChatThemeExtension.light.tickDelivered));
    });

    // -------------------------------------------------------------------------
    // Requirement 2: Delivery acknowledgement changes it to two grey ticks
    // -------------------------------------------------------------------------
    testWidgets('2. Delivery acknowledgement changes it to two grey ticks', (tester) async {
      final msg = ChatMessage(
        id: 'msg-delivered-1',
        chatId: chatId,
        senderId: senderUid,
        text: 'Delivered to Bob',
        sentAt: DateTime.now(),
        type: MessageType.text,
        deliveryState: DeliveryState.delivered,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChatDeliveryRow(msg: msg),
          ),
        ),
      );

      final iconFinder = find.byIcon(Icons.done_all);
      expect(iconFinder, findsOneWidget);
      final icon = tester.widget<Icon>(iconFinder);
      expect(icon.color, equals(ChatThemeExtension.light.tickDelivered));
    });

    // -------------------------------------------------------------------------
    // Requirement 3: Read acknowledgement changes it to two blue ticks
    // -------------------------------------------------------------------------
    testWidgets('3. Read acknowledgement changes it to two blue ticks', (tester) async {
      final msg = ChatMessage(
        id: 'msg-read-1',
        chatId: chatId,
        senderId: senderUid,
        text: 'Read by Bob',
        sentAt: DateTime.now(),
        type: MessageType.text,
        deliveryState: DeliveryState.read,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChatDeliveryRow(msg: msg),
          ),
        ),
      );

      final iconFinder = find.byIcon(Icons.done_all);
      expect(iconFinder, findsOneWidget);
      final icon = tester.widget<Icon>(iconFinder);
      expect(icon.color, equals(ChatThemeExtension.light.tickRead));
    });

    // -------------------------------------------------------------------------
    // Requirement 4: A read message cannot regress to delivered/unread because of stale Realtime events
    // -------------------------------------------------------------------------
    test('4. A read message cannot regress to delivered/unread because of stale Realtime events', () async {
      final service = ReconciliationService(
        accountId: recipientUid,
        messagesStore: messagesStore,
        chatsStore: chatsStore,
      );

      const msgId = 'msg-monotonic-check-1';
      final sentAt = DateTime.utc(2026, 10, 28, 10, 0, 0);

      // Local store already marked message as read (status = 3)
      final readMsg = ChatMessage(
        id: msgId,
        chatId: chatId,
        senderId: senderUid,
        text: 'Already read message',
        sentAt: sentAt,
        type: MessageType.text,
        deliveryState: DeliveryState.read,
        isIncoming: true,
      );
      await messagesStore.saveMessage(readMsg);
      expect(messagesStore.getMessage(msgId)?.deliveryState, equals(DeliveryState.read));

      // Stale / out-of-order Realtime event arrives with status: 2 (delivered)
      final staleDeliveredRow = {
        'id': msgId,
        'chat_id': chatId,
        'sender_id': senderUid,
        'text': 'Already read message',
        'type': 'text',
        'status': 2, // delivered
        'sent_at': sentAt.toIso8601String(),
      };
      await service.reconcileRemoteMessage(staleDeliveredRow);

      // Must remain read (index 3)
      expect(messagesStore.getMessage(msgId)?.deliveryState, equals(DeliveryState.read));

      // Another stale event arrives with status: 1 (sent)
      final staleSentRow = {
        'id': msgId,
        'chat_id': chatId,
        'sender_id': senderUid,
        'text': 'Already read message',
        'type': 'text',
        'status': 1, // sent
        'sent_at': sentAt.toIso8601String(),
      };
      await service.reconcileRemoteMessage(staleSentRow);

      // Must strictly remain read (never downgrade)
      expect(messagesStore.getMessage(msgId)?.deliveryState, equals(DeliveryState.read));

      await service.stop();
    });

    // -------------------------------------------------------------------------
    // Requirement 5: Only the intended recipient can acknowledge delivery or reading
    // -------------------------------------------------------------------------
    test('5. Senders do not self-acknowledge delivery of their own outgoing messages', () async {
      final dispatchedRpcMessageIds = <String>[];

      final mockHttp = MockClient((request) async {
        if (request.url.path.contains('/rest/v1/rpc/promote_message_status')) {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          dispatchedRpcMessageIds.addAll(
            (body['p_message_ids'] as List).map((e) => e.toString()),
          );
          return http.Response(
            jsonEncode(1),
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

      // Alice (sender) reconciles an outgoing message she sent
      final aliceService = ReconciliationService(
        accountId: senderUid,
        messagesStore: messagesStore,
        supabaseClient: client,
      );

      final outgoingRow = {
        'id': 'msg-outgoing-alice',
        'chat_id': chatId,
        'sender_id': senderUid, // Alice sent this!
        'text': 'Outgoing message from Alice',
        'type': 'text',
        'status': 1,
        'sent_at': DateTime.utc(2026, 10, 28, 10, 5, 0).toIso8601String(),
      };

      await aliceService.reconcileRemoteMessage(outgoingRow);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      // Alice must NOT send delivery acknowledgement for her own message
      expect(dispatchedRpcMessageIds, isEmpty);

      // Now Bob (recipient) reconciles the incoming message
      final bobService = ReconciliationService(
        accountId: recipientUid,
        messagesStore: messagesStore,
        supabaseClient: client,
      );

      await bobService.reconcileRemoteMessage(outgoingRow);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      // Bob (recipient) properly dispatches delivery acknowledgement
      expect(dispatchedRpcMessageIds, contains('msg-outgoing-alice'));

      await aliceService.stop();
      await bobService.stop();
    });

    // -------------------------------------------------------------------------
    // Requirement 6: Duplicate acknowledgements do not cause errors or unnecessary updates
    // -------------------------------------------------------------------------
    test('6. Duplicate acknowledgements are deduplicated and do not cause repeated RPC dispatches', () async {
      int rpcCallCount = 0;
      final dispatchedIds = <String>[];

      final mockHttp = MockClient((request) async {
        if (request.url.path.contains('/rest/v1/rpc/promote_message_status')) {
          rpcCallCount++;
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          dispatchedIds.addAll((body['p_message_ids'] as List).cast<String>());
          return http.Response(
            jsonEncode(1),
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

      final service = ReconciliationService(
        accountId: recipientUid,
        messagesStore: messagesStore,
        supabaseClient: client,
      );

      const msgId = 'msg-dedup-check-1';
      final incomingRow = {
        'id': msgId,
        'chat_id': chatId,
        'sender_id': senderUid,
        'text': 'Dedup incoming test',
        'type': 'text',
        'status': 1,
        'sent_at': DateTime.utc(2026, 10, 28, 10, 10, 0).toIso8601String(),
      };

      // 1. Initial reconciliation dispatches RPC
      await service.reconcileRemoteMessage(incomingRow);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(rpcCallCount, equals(1));
      expect(dispatchedIds, equals([msgId]));

      // 2. Immediate duplicate reconciliation (e.g. rapid Realtime redelivery)
      await service.reconcileRemoteMessage(incomingRow);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      // RPC call count must still be 1 (strictly deduplicated)
      expect(rpcCallCount, equals(1));

      // 3. Direct acknowledgeDelivery call for same ID is also deduplicated
      await service.acknowledgeDelivery([msgId]);
      expect(rpcCallCount, equals(1));

      await service.stop();
    });

    // -------------------------------------------------------------------------
    // Requirement 7: Receipt updates from Supabase Realtime refresh the sender's UI
    // -------------------------------------------------------------------------
    test('7. Receipt updates from Realtime / local store transition sender message delivery state', () async {
      const msgId = 'msg-sender-realtime-update';
      final sentAt = DateTime.utc(2026, 10, 28, 10, 15, 0);

      final aliceMsgBox = await Hive.openBox<ChatMessage>('cache_msgs_$senderUid');
      final aliceMessagesStore = MessagesStore(aliceMsgBox);
      final aliceRepo = MessagesRepository(messagesStore: aliceMessagesStore);

      // Sender (Alice) has sent a message that is currently marked 'sent'
      final initialSentMsg = ChatMessage(
        id: msgId,
        chatId: chatId,
        senderId: senderUid,
        text: 'Hey Bob, status check',
        sentAt: sentAt,
        type: MessageType.text,
        deliveryState: DeliveryState.sent,
      );
      await aliceMessagesStore.saveMessage(initialSentMsg);

      final states = <List<ChatMessage>>[];
      final sub = aliceRepo.watchLocalMessages(chatId)!.listen(states.add);

      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(states.last.first.deliveryState, equals(DeliveryState.sent));

      // Realtime delivers status: 2 (delivered)
      await aliceMessagesStore.updateDelivery(msgId, DeliveryState.delivered);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(states.last.first.deliveryState, equals(DeliveryState.delivered));

      // Recipient opens chat, Realtime delivers status: 3 (read)
      await aliceMessagesStore.updateDelivery(msgId, DeliveryState.read);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(states.last.first.deliveryState, equals(DeliveryState.read));

      await sub.cancel();
      await aliceMsgBox.close();
    });

    // -------------------------------------------------------------------------
    // Requirement 8: Offline recipients do not cause messages to be marked delivered prematurely
    // -------------------------------------------------------------------------
    test('8. Offline recipients do not cause messages to be marked delivered prematurely', () async {
      int rpcCount = 0;
      final mockHttp = MockClient((request) async {
        if (request.url.path.contains('/rest/v1/rpc/promote_message_status')) {
          rpcCount++;
          return http.Response(
            jsonEncode(1),
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

      final connectivity = _FakeConnectivityService(initialOnline: false);

      final service = ReconciliationService(
        accountId: recipientUid,
        messagesStore: messagesStore,
        supabaseClient: client,
        connectivityService: connectivity,
      );

      const msgId = 'msg-offline-recipient-1';

      // Recipient device is offline
      expect(connectivity.hasNetworkInterface, isFalse);

      // Attempting delivery acknowledgement while offline does NOT dispatch RPC
      await service.acknowledgeDelivery([msgId]);
      expect(rpcCount, equals(0));

      // Now network is restored
      connectivity.setOnline(true);
      expect(connectivity.hasNetworkInterface, isTrue);

      // Online delivery acknowledgement successfully dispatches RPC
      await service.acknowledgeDelivery([msgId]);
      expect(rpcCount, equals(1));

      await service.stop();
    });

    // -------------------------------------------------------------------------
    // MessagesRepository.markRead tests
    // -------------------------------------------------------------------------
    test('MessagesRepository.markRead dispatches mark_chat_read and updates local messages store to read', () async {
      bool markChatReadCalled = false;
      final mockHttp = MockClient((request) async {
        if (request.url.path.contains('/rest/v1/rpc/mark_chat_read')) {
          markChatReadCalled = true;
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

      final repo = MessagesRepository(
        supabaseClient: client,
        messagesStore: messagesStore,
      );

      // Save an incoming message in 'delivered' state
      final unreadIncoming = ChatMessage(
        id: 'msg-unread-incoming-1',
        chatId: chatId,
        senderId: senderUid,
        text: 'Unread incoming from Alice',
        sentAt: DateTime.now(),
        type: MessageType.text,
        deliveryState: DeliveryState.delivered,
        isIncoming: true,
      );
      await messagesStore.saveMessage(unreadIncoming);
      expect(messagesStore.getMessage('msg-unread-incoming-1')?.deliveryState, equals(DeliveryState.delivered));

      // Bob marks the chat as read
      await repo.markRead(chatId, recipientUid);

      // RPC was dispatched
      expect(markChatReadCalled, isTrue);

      // Local store was immediately updated to read
      expect(messagesStore.getMessage('msg-unread-incoming-1')?.deliveryState, equals(DeliveryState.read));
    });
  });
}
