import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:instant_messenger/features/messaging/presentation/controllers/chat_send_controller.dart';
import 'package:instant_messenger/core/network/connectivity_service.dart';
import 'package:instant_messenger/core/persistence/hive_database.dart';
import 'package:instant_messenger/core/sync/outbox_daemon.dart';
import 'package:instant_messenger/features/messaging/domain/models/chat_message.dart';
import 'package:instant_messenger/features/messaging/data/messages_repository.dart';
import 'package:instant_messenger/core/persistence/hive_init.dart';
import 'package:instant_messenger/features/messaging/data/message_cache.dart';
import 'package:instant_messenger/features/messaging/data/outbox_service.dart';

class _FakeConnectivityService extends ConnectivityService {
  bool _online;
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

  group('Outbox Offline Delivery & Lifecycle Integration Tests', () {
    late Directory tempDir;
    late _FakeConnectivityService fakeConnectivity;
    final manager = HiveDatabaseManager.instance;

    const accountId = 'user-alice-offline-test';
    const peerId = 'user-bob-offline-test';
    const chatId = 'chat-alice-bob-offline';

    setUp(() async {
      tempDir = Directory.systemTemp.createTempSync('outbox_offline_test_');
      Hive.init(tempDir.path);
      HiveInit.registerAdapters();
      fakeConnectivity = _FakeConnectivityService(initialOnline: false);
      await manager.closeCurrentAccount();
    });

    tearDown(() async {
      await manager.closeCurrentAccount();
      await Hive.close();
      if (tempDir.existsSync()) {
        try {
          tempDir.deleteSync(recursive: true);
        } catch (_) {}
      }
    });

    test(
      'offline message enqueueing leaves mutation queued across app restarts and drains on network restore',
      () async {
        final dispatchedMessages = <String>[];

        // 1. Open account database while offline with custom handler daemon
        final db = await manager.openAccount(accountId);

        final daemon = OutboxDaemon(
          accountId: accountId,
          outboxStore: db.outboxStore,
          messagesStore: db.messagesStore,
          connectivityService: fakeConnectivity,
          customHandler: (entry) async {
            dispatchedMessages.add(entry.targetId);
            return true;
          },
        );
        await daemon.start();
        db.outboxDaemon = daemon;

        final repo = MessagesRepository(
          messagesStore: db.messagesStore,
          outboxDaemon: daemon,
        );

        final msg = ChatMessage(
          id: 'msg-offline-restart-1',
          chatId: chatId,
          senderId: accountId,
          text: 'Hello while offline',
          sentAt: DateTime.now(),
          type: MessageType.text,
          deliveryState: DeliveryState.sending,
        );

        // 2. Send message via repository while offline
        await repo.sendMessage(
          chatId,
          msg,
          otherUserId: peerId,
          otherName: 'Bob',
        );

        // Verify immediate local persistence
        final localBeforeRestart = db.messagesStore.getMessage(msg.id);
        expect(localBeforeRestart, isNotNull);
        expect(
          localBeforeRestart!.deliveryState,
          equals(DeliveryState.sending),
        );

        // Verify outbox queue entry
        final outboxBeforeRestart = db.outboxStore.getById(msg.id);
        expect(outboxBeforeRestart, isNotNull);
        expect(outboxBeforeRestart!.state, equals('queued'));
        expect(dispatchedMessages, isEmpty);

        // 3. Simulate app shutdown (close database)
        await manager.closeCurrentAccount();

        // 4. Reopen account database (simulated app restart)
        final reopenedDb = await manager.openAccount(accountId);

        // Ensure outbox mutation survived shutdown
        final outboxAfterRestart = reopenedDb.outboxStore.getById(msg.id);
        expect(outboxAfterRestart, isNotNull);
        expect(outboxAfterRestart!.state, equals('queued'));

        // Attach new daemon to the reopened session
        final reopenedDaemon = OutboxDaemon(
          accountId: accountId,
          outboxStore: reopenedDb.outboxStore,
          messagesStore: reopenedDb.messagesStore,
          connectivityService: fakeConnectivity,
          customHandler: (entry) async {
            dispatchedMessages.add(entry.targetId);
            return true;
          },
        );
        await reopenedDaemon.start();
        reopenedDb.outboxDaemon = reopenedDaemon;

        expect(dispatchedMessages, isEmpty);

        // 5. Restore network connectivity
        fakeConnectivity.setOnline(true);

        // Allow background drain to process
        await Future<void>.delayed(const Duration(milliseconds: 60));

        // Verify dispatch occurred
        expect(dispatchedMessages, contains(msg.id));

        // Verify outbox cleaned up
        expect(reopenedDb.outboxStore.getById(msg.id), isNull);

        // Verify delivery state updated to sent
        final localAfterDrain = reopenedDb.messagesStore.getMessage(msg.id);
        expect(localAfterDrain, isNotNull);
        expect(localAfterDrain!.deliveryState, equals(DeliveryState.sent));
      },
    );

    test(
      'ChatSendController sends text through OutboxDaemon without blocking UI',
      () async {
        fakeConnectivity.setOnline(true);
        final db = await manager.openAccount(accountId);

        final dispatched = <String>[];
        final daemon = OutboxDaemon(
          accountId: accountId,
          outboxStore: db.outboxStore,
          messagesStore: db.messagesStore,
          connectivityService: fakeConnectivity,
          customHandler: (entry) async {
            dispatched.add(entry.targetId);
            return true;
          },
        );
        await daemon.start();
        db.outboxDaemon = daemon;

        final repo = MessagesRepository(
          messagesStore: db.messagesStore,
          outboxDaemon: daemon,
        );

        final legacyBox = await Hive.openBox<ChatMessage>('outbox_$accountId');
        final legacyMeta = await Hive.openBox('outbox_meta');
        final cache = await MessageCache.open(
          uid: accountId,
          chatsStore: db.chatsStore,
        );
        final outboxService = OutboxService(
          messageBox: legacyBox,
          metaBox: legacyMeta,
          messageCache: cache,
        );

        final controller = ChatSendController(
          repo: repo,
          outbox: outboxService,
          outboxDaemon: daemon,
          chatId: chatId,
          currentUserId: accountId,
          otherUserId: peerId,
          otherName: 'Bob',
          otherAvatar: null,
        );

        // Send text message through controller
        await controller.sendCurrentText('Fast UI text');

        await Future<void>.delayed(const Duration(milliseconds: 50));

        expect(dispatched.length, equals(1));
        final messages = db.messagesStore.getMessagesForChat(chatId);
        expect(messages.length, equals(1));
        expect(messages.first.text, equals('Fast UI text'));
        expect(messages.first.deliveryState, equals(DeliveryState.sent));
      },
    );
  });
}
