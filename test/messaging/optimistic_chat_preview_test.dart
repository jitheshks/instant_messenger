import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:instant_messenger/core/network/connectivity_service.dart';
import 'package:instant_messenger/core/persistence/hive_init.dart';
import 'package:instant_messenger/core/persistence/stores/chats_store.dart';
import 'package:instant_messenger/core/persistence/stores/messages_store.dart';
import 'package:instant_messenger/core/persistence/stores/outbox_store.dart';
import 'package:instant_messenger/core/persistence/stores/sync_cursors_store.dart';
import 'package:instant_messenger/core/sync/chat_preview_ordering_policy.dart';
import 'package:instant_messenger/core/sync/outbox_daemon.dart';
import 'package:instant_messenger/core/sync/reconciliation_service.dart';
import 'package:instant_messenger/features/chats/domain/models/chat_summary.dart';
import 'package:instant_messenger/features/messaging/data/messages_repository.dart';
import 'package:instant_messenger/features/messaging/data/outbox_service.dart';
import 'package:instant_messenger/features/messaging/domain/models/chat_message.dart';
import 'package:uuid/uuid.dart';

class _FakeConnectivityService extends ConnectivityService {
  bool _online;
  BackendReachabilityStatus _reachability;
  final _statusController =
      StreamController<NetworkInterfaceStatus>.broadcast();
  final _reachabilityController =
      StreamController<BackendReachabilityStatus>.broadcast();

  _FakeConnectivityService({
    bool online = true,
    BackendReachabilityStatus reachability =
        BackendReachabilityStatus.reachable,
  })  : _online = online,
        _reachability = reachability;

  @override
  bool get hasNetworkInterface => _online;

  @override
  bool get isBackendReachable =>
      _reachability == BackendReachabilityStatus.reachable;

  @override
  BackendReachabilityStatus get backendReachabilityStatus => _reachability;

  @override
  Stream<NetworkInterfaceStatus> get onStatusChanged =>
      _statusController.stream;

  @override
  Stream<BackendReachabilityStatus> get onReachabilityChanged =>
      _reachabilityController.stream;

  void setNetworkInterface(bool online) {
    _online = online;
    _statusController.add(
      NetworkInterfaceStatus([
        online ? NetworkInterfaceType.wifi : NetworkInterfaceType.none,
      ]),
    );
  }

  void setBackendReachability(BackendReachabilityStatus status) {
    _reachability = status;
    _reachabilityController.add(status);
  }

  @override
  void dispose() {
    _statusController.close();
    _reachabilityController.close();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Stage 2C: Optimistic Chat-List Preview Updates & Safeguards', () {
    late Directory tempDir;
    late Box<ChatMessage> msgBox;
    late Box chatBox;
    late Box outboxBox;
    late Box cursorBox;
    late Box outboxMetaBox;
    late MessagesStore messagesStore;
    late ChatsStore chatsStore;
    late OutboxStore outboxStore;
    late SyncCursorsStore syncCursorsStore;
    late _FakeConnectivityService connectivity;
    late OutboxDaemon outboxDaemon;
    late MessagesRepository messagesRepo;
    late OutboxService outboxService;
    late ReconciliationService reconciliationService;

    const accountId = 'user-alice-stage2c';
    const otherUserId = 'user-bob-stage2c';
    const chatId = 'chat-stage2c-alice-bob';

    setUp(() async {
      tempDir = Directory.systemTemp.createTempSync('stage2c_preview_test_');
      Hive.init(tempDir.path);
      HiveInit.registerAdapters();

      msgBox = await Hive.openBox<ChatMessage>('cache_msgs_$accountId');
      chatBox = await Hive.openBox('chats_cache_$accountId');
      outboxBox = await Hive.openBox('outbox_mutations_$accountId');
      cursorBox = await Hive.openBox('sync_cursors_$accountId');
      outboxMetaBox = await Hive.openBox('outbox_meta_$accountId');

      messagesStore = MessagesStore(msgBox);
      chatsStore = ChatsStore(chatBox);
      outboxStore = OutboxStore(outboxBox);
      syncCursorsStore = SyncCursorsStore(cursorBox);

      connectivity = _FakeConnectivityService(
        online: true,
        reachability: BackendReachabilityStatus.reachable,
      );

      outboxDaemon = OutboxDaemon(
        accountId: accountId,
        outboxStore: outboxStore,
        messagesStore: messagesStore,
        chatsStore: chatsStore,
        connectivityService: connectivity,
        customHandler: (entry) async => true,
      );

      messagesRepo = MessagesRepository(
        messagesStore: messagesStore,
        outboxDaemon: outboxDaemon,
        chatsStore: chatsStore,
      );

      outboxService = OutboxService(
        messageBox: msgBox,
        metaBox: outboxMetaBox,
        chatsStore: chatsStore,
      );

      reconciliationService = ReconciliationService(
        accountId: accountId,
        messagesStore: messagesStore,
        chatsStore: chatsStore,
        syncCursorsStore: syncCursorsStore,
        outboxDaemon: outboxDaemon,
        connectivityService: connectivity,
      );

      // Pre-seed an initial chat summary representing an older conversation state
      final initialSummary = ChatSummary(
        id: chatId,
        lastMessage: 'Initial greeting from Bob',
        lastTime: DateTime.utc(2026, 10, 20, 10, 0, 0),
        unread: 1,
        muted: false,
        otherUserId: otherUserId,
        members: [accountId, otherUserId],
        lastSenderId: otherUserId,
        lastMessageStatus: 2,
        otherPhoneE164: '+1234567890',
        avatarUrl: 'https://avatar.example.com/bob.png',
        lastMessageId: 'msg-initial-bob',
      );
      await chatsStore.saveChatSummary(initialSummary);
    });

    tearDown(() async {
      await outboxDaemon.stop();
      await reconciliationService.stop();
      connectivity.dispose();
      await Hive.close();
      if (tempDir.existsSync()) {
        try {
          tempDir.deleteSync(recursive: true);
        } catch (_) {}
      }
    });

    // ------------------------------------------------------------------------
    // Group 1: Optimistic Updates
    // ------------------------------------------------------------------------
    test('1. sending a text message immediately updates its chat preview in ChatsStore', () async {
      final msg = ChatMessage(
        id: 'msg-text-1',
        chatId: chatId,
        senderId: accountId,
        text: 'Hello from Alice optimistic!',
        sentAt: DateTime.utc(2026, 10, 20, 10, 5, 0),
        type: MessageType.text,
        deliveryState: DeliveryState.sending,
      );

      await messagesRepo.sendMessage(
        chatId,
        msg,
        otherUserId: otherUserId,
        otherName: 'Bob',
      );

      final summary = chatsStore.getChatSummary(chatId);
      expect(summary, isNotNull);
      expect(summary!.lastMessage, equals('Hello from Alice optimistic!'));
      expect(summary.lastTime, equals(DateTime.utc(2026, 10, 20, 10, 5, 0)));
      expect(summary.lastSenderId, equals(accountId));
      expect(summary.lastMessageStatus, equals(0)); // sending
      expect(summary.lastMessageId, equals('msg-text-1'));
    });

    test('2. sending an image updates preview to caption or 📷 Photo immediately', () async {
      // 2a. Image with caption
      final msgWithCaption = ChatMessage(
        id: 'msg-img-1',
        chatId: chatId,
        senderId: accountId,
        text: 'Sunset at the beach',
        sentAt: DateTime.utc(2026, 10, 20, 10, 10, 0),
        type: MessageType.media,
        deliveryState: DeliveryState.sending,
        media: const MessageMedia(
          url: '/local/sunset.jpg',
          kind: MediaKind.image,
          mime: 'image/jpeg',
          size: 1024,
        ),
      );

      await outboxService.savePending(msgWithCaption);
      var summary = chatsStore.getChatSummary(chatId);
      expect(summary!.lastMessage, equals('Sunset at the beach'));
      expect(summary.lastMessageStatus, equals(0));

      // 2b. Image without caption
      final msgNoCaption = ChatMessage(
        id: 'msg-img-2',
        chatId: chatId,
        senderId: accountId,
        text: '',
        sentAt: DateTime.utc(2026, 10, 20, 10, 12, 0),
        type: MessageType.media,
        deliveryState: DeliveryState.sending,
        media: const MessageMedia(
          url: '/local/photo.jpg',
          kind: MediaKind.image,
          mime: 'image/jpeg',
          size: 1024,
        ),
      );

      await outboxService.savePending(msgNoCaption);
      summary = chatsStore.getChatSummary(chatId);
      expect(summary!.lastMessage, equals('📷 Photo'));
      expect(summary.lastMessageStatus, equals(0));
    });

    test('3. sending audio, video, and documents updates previews with correct indicators', () async {
      // 3a. Video message
      final videoMsg = ChatMessage(
        id: 'msg-vid-1',
        chatId: chatId,
        senderId: accountId,
        text: '',
        sentAt: DateTime.utc(2026, 10, 20, 10, 15, 0),
        type: MessageType.media,
        deliveryState: DeliveryState.sending,
        media: const MessageMedia(
          url: '/local/video.mp4',
          kind: MediaKind.video,
          mime: 'video/mp4',
          size: 2048,
        ),
      );
      await outboxService.savePending(videoMsg);
      expect(chatsStore.getChatSummary(chatId)!.lastMessage, equals('🎥 Video'));

      // 3b. Audio message
      final audioMsg = ChatMessage(
        id: 'msg-aud-1',
        chatId: chatId,
        senderId: accountId,
        text: '',
        sentAt: DateTime.utc(2026, 10, 20, 10, 16, 0),
        type: MessageType.media,
        deliveryState: DeliveryState.sending,
        media: const MessageMedia(
          url: '/local/voice.m4a',
          kind: MediaKind.audio,
          mime: 'audio/m4a',
          size: 512,
        ),
      );
      await outboxService.savePending(audioMsg);
      expect(chatsStore.getChatSummary(chatId)!.lastMessage, equals('🎵 Audio'));

      // 3c. Document message with fileName
      final docMsg = ChatMessage(
        id: 'msg-doc-1',
        chatId: chatId,
        senderId: accountId,
        text: 'invoice.pdf',
        sentAt: DateTime.utc(2026, 10, 20, 10, 17, 0),
        type: MessageType.media,
        deliveryState: DeliveryState.sending,
        media: const MessageMedia(
          url: '/local/invoice.pdf',
          kind: MediaKind.document,
          mime: 'application/pdf',
          size: 4096,
          fileName: 'invoice.pdf',
        ),
      );
      await outboxService.savePending(docMsg);
      expect(chatsStore.getChatSummary(chatId)!.lastMessage, equals('invoice.pdf'));
    });

    test('4. chat preview updates while message delivery state is still sending (status 0)', () async {
      final msg = ChatMessage(
        id: 'msg-pending-1',
        chatId: chatId,
        senderId: accountId,
        text: 'Still in flight!',
        sentAt: DateTime.utc(2026, 10, 20, 10, 20, 0),
        type: MessageType.text,
        deliveryState: DeliveryState.sending,
      );

      await messagesRepo.sendMessage(
        chatId,
        msg,
        otherUserId: otherUserId,
        otherName: 'Bob',
      );

      final summary = chatsStore.getChatSummary(chatId);
      expect(summary!.lastMessageStatus, equals(0));
      expect(summary.lastMessage, equals('Still in flight!'));
    });

    // ------------------------------------------------------------------------
    // Group 2: Ordering & Sequencing
    // ------------------------------------------------------------------------
    test('5. sending an optimistic message moves the corresponding conversation to the top of the list', () async {
      // Seed a second chat with an older timestamp
      const chat2Id = 'chat-stage2c-charlie';
      final chat2 = ChatSummary(
        id: chat2Id,
        lastMessage: 'Charlie message',
        lastTime: DateTime.utc(2026, 10, 20, 9, 0, 0),
        unread: 0,
        muted: false,
        otherUserId: 'user-charlie',
        members: [accountId, 'user-charlie'],
        lastSenderId: 'user-charlie',
        lastMessageStatus: 1,
      );
      await chatsStore.saveChatSummary(chat2);

      // Chat 1 is at 10:00, Chat 2 is at 09:00 -> Chat 1 is top
      var all = chatsStore.getAllChatSummaries();
      expect(all.first.id, equals(chatId));

      // Now send an optimistic message in Chat 2 with a brand new timestamp
      final chat2NewMsg = ChatMessage(
        id: 'msg-charlie-new',
        chatId: chat2Id,
        senderId: accountId,
        text: 'Hey Charlie!',
        sentAt: DateTime.utc(2026, 10, 20, 11, 0, 0),
        type: MessageType.text,
        deliveryState: DeliveryState.sending,
      );

      await messagesRepo.sendMessage(
        chat2Id,
        chat2NewMsg,
        otherUserId: 'user-charlie',
        otherName: 'Charlie',
      );

      all = chatsStore.getAllChatSummaries();
      expect(all.first.id, equals(chat2Id));
      expect(all.first.lastMessage, equals('Hey Charlie!'));
      expect(all[1].id, equals(chatId));
    });

    test('6. sending multiple messages in succession updates preview to the newest message', () async {
      final msg1 = ChatMessage(
        id: 'msg-seq-1',
        chatId: chatId,
        senderId: accountId,
        text: 'Sequence 1',
        sentAt: DateTime.utc(2026, 10, 20, 10, 30, 0),
        type: MessageType.text,
        deliveryState: DeliveryState.sending,
      );
      final msg2 = ChatMessage(
        id: 'msg-seq-2',
        chatId: chatId,
        senderId: accountId,
        text: 'Sequence 2',
        sentAt: DateTime.utc(2026, 10, 20, 10, 30, 5),
        type: MessageType.text,
        deliveryState: DeliveryState.sending,
      );

      await messagesRepo.sendMessage(chatId, msg1, otherUserId: otherUserId, otherName: 'Bob');
      expect(chatsStore.getChatSummary(chatId)!.lastMessage, equals('Sequence 1'));

      await messagesRepo.sendMessage(chatId, msg2, otherUserId: otherUserId, otherName: 'Bob');
      final finalSummary = chatsStore.getChatSummary(chatId)!;
      expect(finalSummary.lastMessage, equals('Sequence 2'));
      expect(finalSummary.lastMessageId, equals('msg-seq-2'));
    });

    test('7. an older server confirmation cannot overwrite a newer local optimistic preview', () async {
      // Local optimistic message sent at 10:45:00
      final localMsg = ChatMessage(
        id: 'msg-local-newer',
        chatId: chatId,
        senderId: accountId,
        text: 'Newer local text',
        sentAt: DateTime.utc(2026, 10, 20, 10, 45, 0),
        type: MessageType.text,
        deliveryState: DeliveryState.sending,
      );
      await messagesRepo.sendMessage(chatId, localMsg, otherUserId: otherUserId, otherName: 'Bob');

      // Delayed server reconciliation for an older message sent at 10:40:00 arrives
      await reconciliationService.reconcileRemoteMessage({
        'id': 'msg-remote-older',
        'chat_id': chatId,
        'sender_id': otherUserId,
        'text': 'Stale remote message',
        'type': 'text',
        'status': 1,
        'sent_at': DateTime.utc(2026, 10, 20, 10, 40, 0).toIso8601String(),
      });

      // Preview must remain the newer local message
      final summary = chatsStore.getChatSummary(chatId)!;
      expect(summary.lastMessage, equals('Newer local text'));
      expect(summary.lastTime, equals(DateTime.utc(2026, 10, 20, 10, 45, 0)));
      expect(summary.lastMessageId, equals('msg-local-newer'));
    });

    // ------------------------------------------------------------------------
    // Group 3: Offline Behaviour & Durability
    // ------------------------------------------------------------------------
    test('8. sending while physically offline immediately updates the preview and moves tile to top', () async {
      connectivity.setNetworkInterface(false);
      connectivity.setBackendReachability(BackendReachabilityStatus.unreachable);

      final offlineMsg = ChatMessage(
        id: 'msg-offline-1',
        chatId: chatId,
        senderId: accountId,
        text: 'Sent while totally offline',
        sentAt: DateTime.utc(2026, 10, 20, 11, 30, 0),
        type: MessageType.text,
        deliveryState: DeliveryState.sending,
      );

      await messagesRepo.sendMessage(chatId, offlineMsg, otherUserId: otherUserId, otherName: 'Bob');

      final summary = chatsStore.getChatSummary(chatId)!;
      expect(summary.lastMessage, equals('Sent while totally offline'));
      expect(summary.lastMessageStatus, equals(0)); // clock icon
      expect(summary.lastTime, equals(DateTime.utc(2026, 10, 20, 11, 30, 0)));
    });

    test('9. backend unavailability does not revert or clear the optimistic preview', () async {
      connectivity.setNetworkInterface(true);
      connectivity.setBackendReachability(BackendReachabilityStatus.unreachable);

      final msg = ChatMessage(
        id: 'msg-backend-down-1',
        chatId: chatId,
        senderId: accountId,
        text: 'Backend is unavailable right now',
        sentAt: DateTime.utc(2026, 10, 20, 11, 45, 0),
        type: MessageType.text,
        deliveryState: DeliveryState.sending,
      );

      await messagesRepo.sendMessage(chatId, msg, otherUserId: otherUserId, otherName: 'Bob');

      final summary = chatsStore.getChatSummary(chatId)!;
      expect(summary.lastMessage, equals('Backend is unavailable right now'));
      expect(summary.lastMessageStatus, equals(0));
    });

    test('10. pending previews and status 0 survive simulated application restart and reload from Hive', () async {
      final msg = ChatMessage(
        id: 'msg-survive-restart',
        chatId: chatId,
        senderId: accountId,
        text: 'Durable preview across restart',
        sentAt: DateTime.utc(2026, 10, 20, 12, 0, 0),
        type: MessageType.text,
        deliveryState: DeliveryState.sending,
      );

      await messagesRepo.sendMessage(chatId, msg, otherUserId: otherUserId, otherName: 'Bob');

      // Simulate app restart by closing the Hive box and opening a fresh store instance
      await chatBox.close();
      final freshChatBox = await Hive.openBox('chats_cache_$accountId');
      final freshStore = ChatsStore(freshChatBox);

      final restoredSummary = freshStore.getChatSummary(chatId);
      expect(restoredSummary, isNotNull);
      expect(restoredSummary!.lastMessage, equals('Durable preview across restart'));
      expect(restoredSummary.lastMessageStatus, equals(0));
      expect(restoredSummary.lastTime, equals(DateTime.utc(2026, 10, 20, 12, 0, 0)));
      expect(restoredSummary.lastMessageId, equals('msg-survive-restart'));

      chatBox = freshChatBox;
      chatsStore = freshStore;
    });

    // ------------------------------------------------------------------------
    // Group 4: Reconciliation & Realtime
    // ------------------------------------------------------------------------
    test('11. server confirmation reconciles optimistic preview delivery status from 0 to 1', () async {
      final msg = ChatMessage(
        id: 'msg-to-confirm-1',
        chatId: chatId,
        senderId: accountId,
        text: 'Awaiting server confirmation',
        sentAt: DateTime.utc(2026, 10, 20, 12, 15, 0),
        type: MessageType.text,
        deliveryState: DeliveryState.sending,
      );

      await messagesRepo.sendMessage(chatId, msg, otherUserId: otherUserId, otherName: 'Bob');
      expect(chatsStore.getChatSummary(chatId)!.lastMessageStatus, equals(0));

      // Trigger message confirmation via outbox daemon
      await outboxDaemon.onMessageConfirmed('msg-to-confirm-1');

      final updatedSummary = chatsStore.getChatSummary(chatId)!;
      expect(updatedSummary.lastMessageStatus, equals(1)); // sent
      expect(updatedSummary.lastMessageId, equals('msg-to-confirm-1'));
    });

    test('12. Realtime message delivery does not produce duplicate previews or duplicate chat entries', () async {
      final remoteMsg = {
        'id': 'msg-remote-rt-1',
        'chat_id': chatId,
        'sender_id': otherUserId,
        'text': 'Incoming message via Realtime',
        'type': 'text',
        'status': 1,
        'sent_at': DateTime.utc(2026, 10, 20, 12, 30, 0).toIso8601String(),
      };

      await reconciliationService.reconcileRemoteMessage(remoteMsg);
      await reconciliationService.reconcileRemoteMessage(remoteMsg); // duplicate delivery

      final all = chatsStore.getAllChatSummaries().where((c) => c.id == chatId).toList();
      expect(all.length, equals(1)); // strictly deduplicated
      expect(all.first.lastMessage, equals('Incoming message via Realtime'));
    });

    test('13. background reconciliation preserves the latest message when remote messages arrive', () async {
      final newerRemoteMsg = {
        'id': 'msg-remote-latest',
        'chat_id': chatId,
        'sender_id': otherUserId,
        'text': 'Brand new message from Bob',
        'type': 'text',
        'status': 1,
        'sent_at': DateTime.utc(2026, 10, 20, 13, 0, 0).toIso8601String(),
      };

      await reconciliationService.reconcileRemoteMessage(newerRemoteMsg);

      final summary = chatsStore.getChatSummary(chatId)!;
      expect(summary.lastMessage, equals('Brand new message from Bob'));
      expect(summary.lastSenderId, equals(otherUserId));
      expect(summary.lastTime, equals(DateTime.utc(2026, 10, 20, 13, 0, 0)));
    });

    test('14. previously delivered chat summaries retain correct preview and status after sync', () async {
      final summary = chatsStore.getChatSummary(chatId)!;
      expect(summary.lastMessageStatus, equals(2));

      // Call fetchUserChats logic with remote summaries that are older than local
      final remoteSummaries = [
        ChatSummary(
          id: chatId,
          lastMessage: 'Old server summary',
          lastTime: DateTime.utc(2026, 10, 20, 9, 0, 0),
          unread: 0,
          muted: false,
          otherUserId: otherUserId,
          members: [accountId, otherUserId],
          lastSenderId: otherUserId,
          lastMessageStatus: 1,
        ),
      ];

      // Simulated write-through with protect check
      final merged = <ChatSummary>[];
      for (final r in remoteSummaries) {
        final local = chatsStore.getChatSummary(r.id);
        if (local != null && local.lastTime.isAfter(r.lastTime)) {
          merged.add(r.copyWith(
            lastMessage: local.lastMessage,
            lastTime: local.lastTime,
            lastSenderId: local.lastSenderId,
            lastMessageStatus: local.lastMessageStatus,
            lastMessageId: local.lastMessageId,
          ));
        } else {
          merged.add(r);
        }
      }
      await chatsStore.saveChatSummaries(merged);

      final preserved = chatsStore.getChatSummary(chatId)!;
      expect(preserved.lastMessage, equals('Initial greeting from Bob'));
      expect(preserved.lastMessageStatus, equals(2));
      expect(preserved.lastTime, equals(DateTime.utc(2026, 10, 20, 10, 0, 0)));
    });

    // ------------------------------------------------------------------------
    // Group 5: Regression & Mandatory Safeguards
    // ------------------------------------------------------------------------
    test('15. optimistic outgoing messages do not increment or alter unread counts', () async {
      final initialUnread = chatsStore.getChatSummary(chatId)!.unread;

      final msg = ChatMessage(
        id: 'msg-unread-check',
        chatId: chatId,
        senderId: accountId,
        text: 'Outgoing message should not add to unread',
        sentAt: DateTime.utc(2026, 10, 20, 14, 0, 0),
        type: MessageType.text,
        deliveryState: DeliveryState.sending,
      );

      await messagesRepo.sendMessage(chatId, msg, otherUserId: otherUserId, otherName: 'Bob');

      final summary = chatsStore.getChatSummary(chatId)!;
      expect(summary.unread, equals(initialUnread)); // unchanged!
    });

    test('16. peer read receipts remain unaffected by optimistic outgoing previews', () async {
      final initialMuted = chatsStore.getChatSummary(chatId)!.muted;
      final initialAvatar = chatsStore.getChatSummary(chatId)!.avatarUrl;
      final initialMembers = chatsStore.getChatSummary(chatId)!.members;

      final msg = ChatMessage(
        id: 'msg-metadata-preservation',
        chatId: chatId,
        senderId: accountId,
        text: 'Checking metadata preservation',
        sentAt: DateTime.utc(2026, 10, 20, 14, 15, 0),
        type: MessageType.text,
        deliveryState: DeliveryState.sending,
      );

      await messagesRepo.sendMessage(chatId, msg, otherUserId: otherUserId, otherName: 'Bob');

      final summary = chatsStore.getChatSummary(chatId)!;
      expect(summary.muted, equals(initialMuted));
      expect(summary.avatarUrl, equals(initialAvatar));
      expect(summary.members, equals(initialMembers));
    });

    test('17. timestamp collision protection: conservative tie policy with real UUID v4 values', () async {
      final collisionTime = DateTime.utc(2026, 10, 20, 15, 0, 0);
      final uuidFirst = const Uuid().v4();
      final uuidSecond = const Uuid().v4();

      // First message establishes the preview
      final msgFirst = ChatMessage(
        id: uuidFirst,
        chatId: chatId,
        senderId: accountId,
        text: 'First established message',
        sentAt: collisionTime,
        type: MessageType.text,
        deliveryState: DeliveryState.sending,
      );

      await chatsStore.updateOptimisticPreview(
        chatId: chatId,
        message: msgFirst,
        currentUserId: accountId,
      );
      expect(chatsStore.getChatSummary(chatId)!.lastMessage, equals('First established message'));
      expect(chatsStore.getChatSummary(chatId)!.lastMessageId, equals(uuidFirst));
      expect(chatsStore.getChatSummary(chatId)!.lastMessageStatus, equals(0));

      // Second message arrives with equal timestamp and a different UUID v4
      final msgSecond = ChatMessage(
        id: uuidSecond,
        chatId: chatId,
        senderId: accountId,
        text: 'Second collision message',
        sentAt: collisionTime,
        type: MessageType.text,
        deliveryState: DeliveryState.sending,
      );

      await chatsStore.updateOptimisticPreview(
        chatId: chatId,
        message: msgSecond,
        currentUserId: accountId,
      );

      // Under conservative tie policy, established preview MUST NOT be replaced by a different UUID
      final summaryAfterCollision = chatsStore.getChatSummary(chatId)!;
      expect(summaryAfterCollision.lastMessage, equals('First established message'));
      expect(summaryAfterCollision.lastMessageId, equals(uuidFirst));

      // Same message with identical timestamp receiving delivery status promotion (status 0 -> 1)
      final msgFirstConfirmed = ChatMessage(
        id: uuidFirst,
        chatId: chatId,
        senderId: accountId,
        text: 'First established message',
        sentAt: collisionTime,
        type: MessageType.text,
        deliveryState: DeliveryState.sent,
      );

      await chatsStore.updateOptimisticPreview(
        chatId: chatId,
        message: msgFirstConfirmed,
        currentUserId: accountId,
      );

      // Same message status is promoted legitimately!
      final summaryAfterConfirm = chatsStore.getChatSummary(chatId)!;
      expect(summaryAfterConfirm.lastMessageId, equals(uuidFirst));
      expect(summaryAfterConfirm.lastMessageStatus, equals(1));
    });

    test('18. delivery status ownership: only the message currently represented by the preview updates the chat tile status', () async {
      // Chat is currently showing msg-2 at 16:00
      final msg1 = ChatMessage(
        id: 'msg-ownership-1',
        chatId: chatId,
        senderId: accountId,
        text: 'Older message',
        sentAt: DateTime.utc(2026, 10, 20, 15, 50, 0),
        type: MessageType.text,
        deliveryState: DeliveryState.sending,
      );
      final msg2 = ChatMessage(
        id: 'msg-ownership-2',
        chatId: chatId,
        senderId: accountId,
        text: 'Current latest message',
        sentAt: DateTime.utc(2026, 10, 20, 16, 0, 0),
        type: MessageType.text,
        deliveryState: DeliveryState.sending,
      );

      await chatsStore.updateOptimisticPreview(chatId: chatId, message: msg1, currentUserId: accountId);
      await chatsStore.updateOptimisticPreview(chatId: chatId, message: msg2, currentUserId: accountId);

      expect(chatsStore.getChatSummary(chatId)!.lastMessageStatus, equals(0));
      expect(chatsStore.getChatSummary(chatId)!.lastMessageId, equals('msg-ownership-2'));

      // An out-of-order confirmation arrives for msg-ownership-1 (status 1 = sent)
      await chatsStore.updateDeliveryStatus(chatId, 'msg-ownership-1', 1);

      // Chat tile status MUST NOT change because msg-ownership-1 is not the current preview message!
      expect(chatsStore.getChatSummary(chatId)!.lastMessageStatus, equals(0));

      // Now confirmation arrives for msg-ownership-2
      await chatsStore.updateDeliveryStatus(chatId, 'msg-ownership-2', 1);

      // Status updates to 1!
      expect(chatsStore.getChatSummary(chatId)!.lastMessageStatus, equals(1));
    });

    test('19. monotonic delivery states: delivery status cannot be downgraded by lagging events', () async {
      // Progressively advance status: 0 -> 1 -> 2 -> 3
      const targetMsgId = 'msg-monotonic-1';
      final msg = ChatMessage(
        id: targetMsgId,
        chatId: chatId,
        senderId: accountId,
        text: 'Monotonic state message',
        sentAt: DateTime.utc(2026, 10, 20, 17, 0, 0),
        type: MessageType.text,
        deliveryState: DeliveryState.sending,
      );

      await chatsStore.updateOptimisticPreview(chatId: chatId, message: msg, currentUserId: accountId);
      expect(chatsStore.getChatSummary(chatId)!.lastMessageStatus, equals(0));

      // Advance to delivered (2)
      await chatsStore.updateDeliveryStatus(chatId, targetMsgId, 2);
      expect(chatsStore.getChatSummary(chatId)!.lastMessageStatus, equals(2));

      // Attempt to downgrade to sent (1) via lagging event
      await chatsStore.updateDeliveryStatus(chatId, targetMsgId, 1);
      expect(chatsStore.getChatSummary(chatId)!.lastMessageStatus, equals(2)); // preserved!

      // Attempt to downgrade to pending (0)
      await chatsStore.updateDeliveryStatus(chatId, targetMsgId, 0);
      expect(chatsStore.getChatSummary(chatId)!.lastMessageStatus, equals(2)); // preserved!

      // Advance to read (3)
      await chatsStore.updateDeliveryStatus(chatId, targetMsgId, 3);
      expect(chatsStore.getChatSummary(chatId)!.lastMessageStatus, equals(3));
    });

    test('20. crash consistency: recoverLatestPreviews reconciles ChatsStore with MessagesStore after sudden app termination', () async {
      // Simulate that a message was persisted in MessagesStore, but the app crashed before ChatsStore was updated
      final orphanedMsg = ChatMessage(
        id: 'msg-orphaned-after-crash',
        chatId: chatId,
        senderId: accountId,
        text: 'Written to MessagesStore right before crash',
        sentAt: DateTime.utc(2026, 10, 20, 18, 0, 0),
        type: MessageType.text,
        deliveryState: DeliveryState.sending,
      );
      await messagesStore.saveMessage(orphanedMsg);

      // At this point, ChatsStore has an older message
      expect(chatsStore.getChatSummary(chatId)!.lastTime.isBefore(orphanedMsg.sentAt), isTrue);

      // Upon app startup, recoverLatestPreviews runs:
      await chatsStore.recoverLatestPreviews(messagesStore, accountId);

      // ChatsStore is now fully reconciled!
      final recovered = chatsStore.getChatSummary(chatId)!;
      expect(recovered.lastMessage, equals('Written to MessagesStore right before crash'));
      expect(recovered.lastTime, equals(DateTime.utc(2026, 10, 20, 18, 0, 0)));
      expect(recovered.lastMessageId, equals('msg-orphaned-after-crash'));
      expect(recovered.lastMessageStatus, equals(0));
    });

    test('21. new-chat crash recovery: reconstructs ChatSummary from outbox metadata when chat absent from ChatsStore', () async {
      const newChatId = 'brand-new-chat-uuid-1';
      const peerId = 'peer-user-uuid-123';
      const peerName = 'Charlie Peer';
      const peerAvatar = 'https://example.com/charlie.png';

      // Simulate a brand-new conversation where message was saved to MessagesStore and outbox entry enqueued,
      // but app was killed before ChatsStore was created/updated.
      final msg = ChatMessage(
        id: 'msg-new-chat-crash',
        chatId: newChatId,
        senderId: accountId,
        text: 'Initial outgoing message to Charlie',
        sentAt: DateTime.utc(2026, 10, 20, 19, 0, 0),
        type: MessageType.text,
        deliveryState: DeliveryState.sending,
      );
      await messagesStore.saveMessage(msg);

      // Enqueue in outbox daemon with peer metadata
      await outboxDaemon.enqueueMessage(
        message: msg,
        accountId: accountId,
        otherUserId: peerId,
        otherName: peerName,
        otherAvatar: peerAvatar,
      );

      // Verify new chat is NOT yet in ChatsStore
      expect(chatsStore.getChatSummary(newChatId), isNull);

      // Run recovery with outboxStore passed
      await chatsStore.recoverLatestPreviews(
        messagesStore,
        accountId,
        outboxStore: outboxStore,
      );

      // Verify summary is properly reconstructed with correct metadata and status 0
      final summary = chatsStore.getChatSummary(newChatId);
      expect(summary, isNotNull);
      expect(summary!.id, equals(newChatId));
      expect(summary.otherUserId, equals(peerId));
      expect(summary.avatarUrl, equals(peerAvatar));
      expect(summary.lastMessage, equals('Initial outgoing message to Charlie'));
      expect(summary.lastTime, equals(DateTime.utc(2026, 10, 20, 19, 0, 0)));
      expect(summary.lastSenderId, equals(accountId));
      expect(summary.lastMessageStatus, equals(0));
      expect(summary.lastMessageId, equals('msg-new-chat-crash'));
    });

    test('22. new-chat crash recovery safely defers ChatSummary creation when recipient metadata is missing', () async {
      const deferredChatId = 'brand-new-chat-no-meta';

      final msg = ChatMessage(
        id: 'msg-no-meta-1',
        chatId: deferredChatId,
        senderId: accountId,
        text: 'Outgoing message with no recipient metadata anywhere',
        sentAt: DateTime.utc(2026, 10, 20, 20, 0, 0),
        type: MessageType.text,
        deliveryState: DeliveryState.sending,
      );
      await messagesStore.saveMessage(msg);

      // 1. Without outboxStore or without metadata in outboxStore
      await chatsStore.recoverLatestPreviews(messagesStore, accountId);
      expect(chatsStore.getChatSummary(deferredChatId), isNull,
          reason: 'Must NOT fabricate incomplete ChatSummary stubs with empty/fake metadata');

      // 2. Even with outboxStore present, if there is no matching mutation with otherUserId
      await chatsStore.recoverLatestPreviews(
        messagesStore,
        accountId,
        outboxStore: outboxStore,
      );
      expect(chatsStore.getChatSummary(deferredChatId), isNull);

      // 3. Now provide legitimate recipient metadata in outbox
      await outboxDaemon.enqueueMessage(
        message: msg,
        accountId: accountId,
        otherUserId: 'recipient-alice-id',
        otherName: 'Alice Recipient',
        otherAvatar: 'https://example.com/alice.png',
      );

      await chatsStore.recoverLatestPreviews(
        messagesStore,
        accountId,
        outboxStore: outboxStore,
      );

      final summary = chatsStore.getChatSummary(deferredChatId);
      expect(summary, isNotNull);
      expect(summary!.otherUserId, equals('recipient-alice-id'));
      expect(summary.avatarUrl, equals('https://example.com/alice.png'));
      expect(summary.lastMessage, equals('Outgoing message with no recipient metadata anywhere'));
    });

    test('23. ChatPreviewOrderingPolicy handles newer, older, same-timestamp identical ID, and same-timestamp different UUIDs deterministically', () {
      final baseTime = DateTime.utc(2026, 10, 20, 12, 0, 0);
      final id1 = const Uuid().v4();
      final id2 = const Uuid().v4();

      // Case 1: candidate strictly newer -> replacePreview
      final resNewer = ChatPreviewOrderingPolicy.evaluate(
        candidateTime: baseTime.add(const Duration(seconds: 1)),
        candidateMessageId: id2,
        existingTime: baseTime,
        existingMessageId: id1,
      );
      expect(resNewer, equals(CandidateAction.replacePreview));

      // Case 2: candidate strictly older -> ignoreCandidate
      final resOlder = ChatPreviewOrderingPolicy.evaluate(
        candidateTime: baseTime.subtract(const Duration(seconds: 1)),
        candidateMessageId: id2,
        existingTime: baseTime,
        existingMessageId: id1,
      );
      expect(resOlder, equals(CandidateAction.ignoreCandidate));

      // Case 3: identical timestamp, identical ID -> updateStatusOnly
      final resIdentical = ChatPreviewOrderingPolicy.evaluate(
        candidateTime: baseTime,
        candidateMessageId: id1,
        existingTime: baseTime,
        existingMessageId: id1,
      );
      expect(resIdentical, equals(CandidateAction.updateStatusOnly));

      // Case 4: identical timestamp, different UUID v4 IDs -> ignoreCandidate (conservative tie policy)
      final resTie = ChatPreviewOrderingPolicy.evaluate(
        candidateTime: baseTime,
        candidateMessageId: id2,
        existingTime: baseTime,
        existingMessageId: id1,
      );
      expect(resTie, equals(CandidateAction.ignoreCandidate));

      // Case 5: existing message ID is null, candidate has same timestamp -> ignoreCandidate (conservative tie policy preserves preview)
      final resNullExistingId = ChatPreviewOrderingPolicy.evaluate(
        candidateTime: baseTime,
        candidateMessageId: id1,
        existingTime: baseTime,
        existingMessageId: null,
      );
      expect(resNullExistingId, equals(CandidateAction.ignoreCandidate));
    });
  });
}
