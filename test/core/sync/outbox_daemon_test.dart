import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:instant_messenger/core/network/connectivity_service.dart';
import 'package:instant_messenger/core/network/retry_policy.dart';
import 'package:instant_messenger/core/persistence/models/outbox_entry.dart';
import 'package:instant_messenger/core/persistence/stores/messages_store.dart';
import 'package:instant_messenger/core/persistence/stores/outbox_store.dart';
import 'package:instant_messenger/core/sync/outbox_daemon.dart';
import 'package:instant_messenger/features/messaging/domain/models/chat_message.dart';
import 'package:instant_messenger/core/persistence/hive_init.dart';

class _FakeConnectivityService extends ConnectivityService {
  bool _online = true;
  final _controller = StreamController<NetworkInterfaceStatus>.broadcast();
  final _reachabilityController =
      StreamController<BackendReachabilityStatus>.broadcast();

  _FakeConnectivityService({bool initialOnline = true})
    : _online = initialOnline;

  @override
  bool get hasNetworkInterface => _online;

  @override
  bool get isBackendReachable => _online;

  @override
  BackendReachabilityStatus get backendReachabilityStatus =>
      _online
          ? BackendReachabilityStatus.reachable
          : BackendReachabilityStatus.unreachable;

  @override
  Stream<NetworkInterfaceStatus> get onStatusChanged => _controller.stream;

  @override
  Stream<BackendReachabilityStatus> get onReachabilityChanged =>
      _reachabilityController.stream;

  void setOnline(bool online) {
    _online = online;
    _controller.add(
      NetworkInterfaceStatus([
        online ? NetworkInterfaceType.wifi : NetworkInterfaceType.none,
      ]),
    );
    _reachabilityController.add(
      online
          ? BackendReachabilityStatus.reachable
          : BackendReachabilityStatus.unreachable,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('OutboxDaemon Unit Tests', () {
    late Directory tempDir;
    late Box<ChatMessage> msgBox;
    late Box outboxBox;
    late MessagesStore messagesStore;
    late OutboxStore outboxStore;
    late _FakeConnectivityService connectivity;
    late List<OutboxDaemon> activeDaemons;

    const accountId = 'user-alice-daemon-test';
    const chatId = 'chat-daemon-test';

    setUp(() async {
      activeDaemons = [];
      tempDir = Directory.systemTemp.createTempSync('outbox_daemon_test_');
      Hive.init(tempDir.path);
      HiveInit.registerAdapters();

      msgBox = await Hive.openBox<ChatMessage>('cache_msgs_$accountId');
      outboxBox = await Hive.openBox('outbox_mutations_$accountId');
      messagesStore = MessagesStore(msgBox);
      outboxStore = OutboxStore(outboxBox);
      connectivity = _FakeConnectivityService(initialOnline: true);
    });

    tearDown(() async {
      for (final daemon in activeDaemons) {
        daemon.stop();
      }
      activeDaemons.clear();
      await Hive.close();
      if (tempDir.existsSync()) {
        try {
          tempDir.deleteSync(recursive: true);
        } catch (_) {}
      }
    });

    test(
      'enqueuing a message persists outbox entry and triggers drain to completion',
      () async {
        final now = DateTime.now();
        final msg = ChatMessage(
          id: 'msg-daemon-1',
          chatId: chatId,
          senderId: accountId,
          text: 'Hello from OutboxDaemon',
          sentAt: now,
          deliveryState: DeliveryState.sending,
          type: MessageType.text,
        );

        await messagesStore.saveMessage(msg);

        bool dispatched = false;
        final daemon = OutboxDaemon(
          accountId: accountId,
          outboxStore: outboxStore,
          messagesStore: messagesStore,
          connectivityService: connectivity,
          customHandler: (entry) async {
            expect(entry.id, equals('msg-daemon-1'));
            expect(entry.mutationType, equals('send_message'));
            dispatched = true;
            return true;
          },
        );
        activeDaemons.add(daemon);

        await daemon.start();
        await daemon.enqueueMessage(message: msg, accountId: accountId);

        // Allow async drain microtasks to complete
        await Future<void>.delayed(const Duration(milliseconds: 50));

        expect(dispatched, isTrue);
        // Entry should be removed from outboxStore upon completion
        expect(outboxStore.getById('msg-daemon-1'), isNull);
        // Local message should be marked sent
        expect(
          messagesStore.getMessage('msg-daemon-1')?.deliveryState,
          equals(DeliveryState.sent),
        );

        daemon.dispose();
      },
    );

    test(
      'enqueueMessage is strictly idempotent and does not create duplicates',
      () async {
        final now = DateTime.now();
        final msg = ChatMessage(
          id: 'msg-idempotent-1',
          chatId: chatId,
          senderId: accountId,
          text: 'Duplicate enqueue test',
          sentAt: now,
          deliveryState: DeliveryState.sending,
          type: MessageType.text,
        );

        await messagesStore.saveMessage(msg);

        final daemon = OutboxDaemon(
          accountId: accountId,
          outboxStore: outboxStore,
          messagesStore: messagesStore,
          connectivityService: connectivity,
          customHandler: (entry) async => true,
        );
        activeDaemons.add(daemon);

        await daemon.start();

        // Enqueue twice
        await daemon.enqueueMessage(message: msg, accountId: accountId);
        await daemon.enqueueMessage(message: msg, accountId: accountId);

        await Future<void>.delayed(const Duration(milliseconds: 50));

        expect(outboxStore.getAll(), isEmpty);
        expect(
          messagesStore.getMessage('msg-idempotent-1')?.deliveryState,
          equals(DeliveryState.sent),
        );

        daemon.dispose();
      },
    );

    test(
      'offline message enqueueing leaves mutation queued; connectivity restoration drains automatically',
      () async {
        connectivity.setOnline(false);

        final now = DateTime.now();
        final msg = ChatMessage(
          id: 'msg-offline-1',
          chatId: chatId,
          senderId: accountId,
          text: 'Offline message',
          sentAt: now,
          deliveryState: DeliveryState.sending,
          type: MessageType.text,
        );

        await messagesStore.saveMessage(msg);

        bool dispatched = false;
        final daemon = OutboxDaemon(
          accountId: accountId,
          outboxStore: outboxStore,
          messagesStore: messagesStore,
          connectivityService: connectivity,
          customHandler: (entry) async {
            dispatched = true;
            return true;
          },
        );
        activeDaemons.add(daemon);

        await daemon.start();
        await daemon.enqueueMessage(message: msg, accountId: accountId);

        await Future<void>.delayed(const Duration(milliseconds: 50));

        // Should still be queued because connectivity is offline
        expect(dispatched, isFalse);
        expect(outboxStore.getById('msg-offline-1')?.state, equals('queued'));
        expect(
          messagesStore.getMessage('msg-offline-1')?.deliveryState,
          equals(DeliveryState.sending),
        );

        // Connectivity restored -> should wake daemon and dispatch
        connectivity.setOnline(true);

        await Future<void>.delayed(const Duration(milliseconds: 50));

        expect(dispatched, isTrue);
        expect(outboxStore.getById('msg-offline-1'), isNull);
        expect(
          messagesStore.getMessage('msg-offline-1')?.deliveryState,
          equals(DeliveryState.sent),
        );

        daemon.dispose();
      },
    );

    test(
      'transient failures schedule exponential retry while permanent failures transition to exhausted',
      () async {
        final now = DateTime.now();
        final transientMsg = ChatMessage(
          id: 'msg-transient',
          chatId: chatId,
          senderId: accountId,
          text: 'Transient failure',
          sentAt: now,
          deliveryState: DeliveryState.sending,
          type: MessageType.text,
        );

        final permanentMsg = ChatMessage(
          id: 'msg-perm',
          chatId: chatId,
          senderId: accountId,
          text: 'Permanent failure',
          sentAt: now,
          deliveryState: DeliveryState.sending,
          type: MessageType.text,
        );

        await messagesStore.saveMessage(transientMsg);
        await messagesStore.saveMessage(permanentMsg);

        final daemon = OutboxDaemon(
          accountId: accountId,
          outboxStore: outboxStore,
          messagesStore: messagesStore,
          connectivityService: connectivity,
          retryPolicy: RetryPolicy(initialDelay: const Duration(seconds: 10)),
          customHandler: (entry) async {
            if (entry.id == 'msg-transient') {
              throw const SocketException('Network connection dropped');
            }
            if (entry.id == 'msg-perm') {
              throw const PermanentOutboxException(
                '403 Forbidden: not_a_chat_member',
              );
            }
            return true;
          },
        );
        activeDaemons.add(daemon);

        await daemon.start();
        await daemon.enqueueMessage(
          message: transientMsg,
          accountId: accountId,
        );
        await daemon.enqueueMessage(
          message: permanentMsg,
          accountId: accountId,
        );

        for (var i = 0; i < 20; i++) {
          if (outboxStore.getById('msg-perm')?.state == 'exhausted') break;
          await Future<void>.delayed(const Duration(milliseconds: 25));
        }

        // Permanent message should immediately be exhausted
        final permEntry = outboxStore.getById('msg-perm');
        expect(permEntry, isNotNull);
        expect(permEntry!.state, equals('exhausted'));
        expect(messagesStore.getMessage('msg-perm')?.hasFailed, isTrue);

        // Transient message should remain queued with retryCount incremented
        final transEntry = outboxStore.getById('msg-transient');
        expect(transEntry, isNotNull);
        expect(transEntry!.state, equals('queued'));
        expect(transEntry.retryCount, equals(1));

        daemon.dispose();
      },
    );

    test(
      'retryExhausted resets mutation to queued and triggers immediate dispatch',
      () async {
        final now = DateTime.now();
        final msg = ChatMessage(
          id: 'msg-exhausted',
          chatId: chatId,
          senderId: accountId,
          text: 'Exhausted retry test',
          sentAt: now,
          deliveryState: DeliveryState.sending,
          type: MessageType.text,
        );

        await messagesStore.saveMessage(msg);

        // Pre-seed outbox with an exhausted mutation
        final entry = OutboxEntry(
          id: 'msg-exhausted',
          accountId: accountId,
          mutationType: 'send_message',
          targetId: 'msg-exhausted',
          payloadJson: '{"text": "Exhausted retry test"}',
          createdAt: now,
          retryCount: 5,
          nextAttemptAt: now,
          state: 'exhausted',
        );
        await outboxStore.enqueue(entry);

        bool retried = false;
        final daemon = OutboxDaemon(
          accountId: accountId,
          outboxStore: outboxStore,
          messagesStore: messagesStore,
          connectivityService: connectivity,
          customHandler: (entry) async {
            retried = true;
            return true;
          },
        );
        activeDaemons.add(daemon);

        await daemon.start();
        await daemon.retryExhausted('msg-exhausted');

        await Future<void>.delayed(const Duration(milliseconds: 50));

        expect(retried, isTrue);
        expect(outboxStore.getById('msg-exhausted'), isNull);
        expect(
          messagesStore.getMessage('msg-exhausted')?.deliveryState,
          equals(DeliveryState.sent),
        );

        daemon.dispose();
      },
    );

    test(
      'onMessageConfirmed cleans up outbox mutation when message confirmed externally',
      () async {
        final now = DateTime.now();
        final msg = ChatMessage(
          id: 'msg-realtime-confirm',
          chatId: chatId,
          senderId: accountId,
          text: 'Realtime confirm test',
          sentAt: now,
          deliveryState: DeliveryState.sending,
          type: MessageType.text,
        );
        await messagesStore.saveMessage(msg);

        final entry = OutboxEntry(
          id: 'msg-realtime-confirm',
          accountId: accountId,
          mutationType: 'send_message',
          targetId: 'msg-realtime-confirm',
          payloadJson: '{"text": "Hello"}',
          createdAt: now,
          retryCount: 0,
          nextAttemptAt: now,
          state: 'queued',
        );
        await outboxStore.enqueue(entry);

        final daemon = OutboxDaemon(
          accountId: accountId,
          outboxStore: outboxStore,
          messagesStore: messagesStore,
          connectivityService: connectivity,
        );
        activeDaemons.add(daemon);

        // Simulate Realtime confirming message was sent
        await daemon.onMessageConfirmed('msg-realtime-confirm');

        expect(outboxStore.getById('msg-realtime-confirm'), isNull);
        expect(
          messagesStore.getMessage('msg-realtime-confirm')?.deliveryState,
          equals(DeliveryState.sent),
        );

        daemon.dispose();
      },
    );

    test(
      'onMessageConfirmed does NOT remove attach_media mutation sharing the same messageId',
      () async {
        final now = DateTime.now();
        final msg = ChatMessage(
          id: 'msg-media-pending-1',
          chatId: chatId,
          senderId: accountId,
          text: '',
          sentAt: now,
          deliveryState: DeliveryState.sending,
          type: MessageType.media,
        );
        await messagesStore.saveMessage(msg);

        final mediaEntry = OutboxEntry(
          id: 'msg-media-pending-1',
          accountId: accountId,
          mutationType: 'attach_media',
          targetId: 'msg-media-pending-1',
          payloadJson: '{"filePath": "/tmp/img.png"}',
          createdAt: now,
          retryCount: 0,
          nextAttemptAt: now,
          state: 'queued',
        );
        await outboxStore.enqueue(mediaEntry);

        final daemon = OutboxDaemon(
          accountId: accountId,
          outboxStore: outboxStore,
          messagesStore: messagesStore,
          connectivityService: connectivity,
        );
        activeDaemons.add(daemon);

        // Remote confirmation arrives for msg-media-pending-1
        await daemon.onMessageConfirmed('msg-media-pending-1');

        // Mutation MUST still be present in outboxStore because mutationType == 'attach_media'
        expect(outboxStore.getById('msg-media-pending-1'), isNotNull);
        expect(
          outboxStore.getById('msg-media-pending-1')!.mutationType,
          equals('attach_media'),
        );
        // Delivery state remains untouched (sending) until media mutation completes
        expect(
          messagesStore.getMessage('msg-media-pending-1')?.deliveryState,
          equals(DeliveryState.sending),
        );

        daemon.dispose();
      },
    );
  });
}
