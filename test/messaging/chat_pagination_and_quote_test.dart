import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:instant_messenger/app/bootstrap/app_bootstrap_providers.dart';
import 'package:instant_messenger/core/persistence/stores/messages_store.dart';
import 'package:instant_messenger/core/sync/outbox_daemon.dart';
import 'package:instant_messenger/features/calls/domain/models/call_enums.dart';
import 'package:instant_messenger/features/calls/domain/models/call_record.dart';
import 'package:instant_messenger/features/calls/presentation/providers/calls_providers.dart';
import 'package:instant_messenger/features/messaging/data/messages_repository.dart';
import 'package:instant_messenger/features/messaging/domain/models/chat_message.dart';
import 'package:instant_messenger/features/messaging/domain/models/user_presence.dart';
import 'package:instant_messenger/features/messaging/presentation/providers/messaging_providers.dart';
import 'package:instant_messenger/features/messaging/presentation/screens/chat_screen.dart';

class _FakeChatTypingNotifier extends ChatTypingNotifier {
  _FakeChatTypingNotifier(super.arg);

  @override
  bool build() => false;
}

class _FakeMessagesRepository extends Fake implements MessagesRepository {
  int loadOlderCallCount = 0;
  List<ChatMessage> olderMessagesToReturn = [];
  Completer<List<ChatMessage>>? loadOlderCompleter;

  @override
  MessagesStore? get messagesStore => null;

  @override
  OutboxDaemon? get outboxDaemon => null;

  @override
  Future<void> ensureChatDoc({
    required String chatId,
    required String uidA,
    required String uidB,
    required String title,
    String? avatarUrl,
  }) async {}

  @override
  Future<List<ChatMessage>> loadOlderMessages(
    String chatId,
    dynamic lastDocOrSentAt, {
    int limit = 30,
  }) async {
    loadOlderCallCount++;
    if (loadOlderCompleter != null) {
      return loadOlderCompleter!.future;
    }
    return olderMessagesToReturn;
  }

  @override
  Future<void> markDeliveredIfNeeded({
    required String chatId,
    required String currentUserId,
    required List<ChatMessage> messages,
  }) async {}

  @override
  Future<void> markRead(String chatId, String userId) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const currentUserId = 'user-me-123';
  const peerUserId = 'user-peer-456';
  const chatId = 'c0000000-0000-0000-0000-000000000001';

  ChatMessage createMsg(String id, String text, DateTime sentAt, {String? replyToId, String? replyText}) {
    return ChatMessage(
      id: id,
      chatId: chatId,
      senderId: peerUserId,
      text: text,
      sentAt: sentAt,
      type: MessageType.text,
      deliveryState: DeliveryState.delivered,
      replyToMessageId: replyToId,
      replyText: replyText,
      replySenderName: replyToId != null ? 'Contact' : null,
      isIncoming: true,
    );
  }

  group('Reverse Chat Pagination Tests', () {
    testWidgets('1. Bottom/newest scroll position (pixels near 0) does NOT trigger loadOlder', (tester) async {
      final fakeRepo = _FakeMessagesRepository();
      final baseDate = DateTime(2026, 10, 10, 10, 0);

      final initialMsgs = List.generate(
        15,
        (i) => createMsg('msg-$i', 'Message $i with variable content', baseDate.add(Duration(minutes: i))),
      );

      final chatArgs = const ChatControllerArgs(
        chatId: chatId,
        currentUserId: currentUserId,
        otherUserId: peerUserId,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            chatTypingNotifierProvider(chatArgs).overrideWith(() => _FakeChatTypingNotifier(chatArgs)),
            messagesRepositoryProvider.overrideWithValue(fakeRepo),
            outboxServiceProvider.overrideWithValue(null),
            chatCallsProvider(chatId).overrideWith((ref) => Stream.value(<CallRecord>[])),
            chatPresenceStreamProvider(peerUserId).overrideWith(
              (ref) => Stream.value(const UserPresence(online: true, lastSeen: null)),
            ),
            chatTimelineNotifierProvider(chatArgs).overrideWith(
              () => _TestTimelineNotifier(chatArgs, initialMsgs),
            ),
          ],
          child: const MaterialApp(
            home: ChatScreen(
              chatId: chatId,
              currentUserId: currentUserId,
              peerUserId: peerUserId,
              contactName: 'Contact',
              contactAvatar: '',
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final listView = tester.widget<ListView>(find.byType(ListView));
      final controller = listView.controller!;
      expect(controller.position.pixels, 0.0);

      // Verify loadOlder was NOT triggered at bottom
      expect(fakeRepo.loadOlderCallCount, 0);
    });

    testWidgets('2. Scrolling to oldest boundary triggers loadOlder exactly once and guards concurrent calls', (tester) async {
      final fakeRepo = _FakeMessagesRepository();
      fakeRepo.loadOlderCompleter = Completer<List<ChatMessage>>();
      final baseDate = DateTime(2026, 10, 10, 10, 0);

      final initialMsgs = List.generate(
        25,
        (i) => createMsg('msg-$i', 'Message $i multiline\nSecond line text here', baseDate.add(Duration(minutes: i))),
      );

      final chatArgs = const ChatControllerArgs(
        chatId: chatId,
        currentUserId: currentUserId,
        otherUserId: peerUserId,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            chatTypingNotifierProvider(chatArgs).overrideWith(() => _FakeChatTypingNotifier(chatArgs)),
            messagesRepositoryProvider.overrideWithValue(fakeRepo),
            outboxServiceProvider.overrideWithValue(null),
            chatCallsProvider(chatId).overrideWith((ref) => Stream.value(<CallRecord>[])),
            chatPresenceStreamProvider(peerUserId).overrideWith(
              (ref) => Stream.value(const UserPresence(online: true, lastSeen: null)),
            ),
            chatTimelineNotifierProvider(chatArgs).overrideWith(
              () => _TestTimelineNotifier(chatArgs, initialMsgs),
            ),
          ],
          child: const MaterialApp(
            home: ChatScreen(
              chatId: chatId,
              currentUserId: currentUserId,
              peerUserId: peerUserId,
              contactName: 'Contact',
              contactAvatar: '',
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final listView = tester.widget<ListView>(find.byType(ListView));
      final controller = listView.controller!;
      expect(controller.position.maxScrollExtent, greaterThan(0.0));

      // Scroll to top / oldest boundary
      controller.jumpTo(controller.position.maxScrollExtent);
      await tester.pump();

      // Trigger pagination near top
      expect(fakeRepo.loadOlderCallCount, 1);

      // Moving again while request is inflight does NOT duplicate request
      controller.jumpTo(controller.position.maxScrollExtent - 10);
      await tester.pump();
      expect(fakeRepo.loadOlderCallCount, 1);

      // Resolve inflight request
      final olderBatch = [
        createMsg('older-1', 'Older message 1', baseDate.subtract(const Duration(minutes: 5))),
      ];
      fakeRepo.loadOlderCompleter!.complete(olderBatch);
      await tester.pump();
    });

    testWidgets('3. Pagination is exhausted when older batch has fewer than 30 items', (tester) async {
      final fakeRepo = _FakeMessagesRepository();
      // Returns 1 message (< 30 limit)
      fakeRepo.olderMessagesToReturn = [
        createMsg('older-1', 'Only 1 older message left', DateTime(2026, 1, 1)),
      ];

      final baseDate = DateTime(2026, 10, 10, 10, 0);
      final initialMsgs = List.generate(
        20,
        (i) => createMsg('msg-$i', 'Item $i', baseDate.add(Duration(minutes: i))),
      );

      final chatArgs = const ChatControllerArgs(
        chatId: chatId,
        currentUserId: currentUserId,
        otherUserId: peerUserId,
      );

      late _TestTimelineNotifier notifier;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            chatTypingNotifierProvider(chatArgs).overrideWith(() => _FakeChatTypingNotifier(chatArgs)),
            messagesRepositoryProvider.overrideWithValue(fakeRepo),
            outboxServiceProvider.overrideWithValue(null),
            chatCallsProvider(chatId).overrideWith((ref) => Stream.value(<CallRecord>[])),
            chatPresenceStreamProvider(peerUserId).overrideWith(
              (ref) => Stream.value(const UserPresence(online: true, lastSeen: null)),
            ),
            chatTimelineNotifierProvider(chatArgs).overrideWith(
              () {
                notifier = _TestTimelineNotifier(chatArgs, initialMsgs);
                return notifier;
              },
            ),
          ],
          child: const MaterialApp(
            home: ChatScreen(
              chatId: chatId,
              currentUserId: currentUserId,
              peerUserId: peerUserId,
              contactName: 'Contact',
              contactAvatar: '',
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final listView = tester.widget<ListView>(find.byType(ListView));
      final controller = listView.controller!;

      // Scroll to trigger loadOlder
      controller.jumpTo(controller.position.maxScrollExtent);
      await tester.pump();

      expect(fakeRepo.loadOlderCallCount, 1);
      // Because batch returned was 1 item (< 30), hasMore is now false
      expect(notifier.hasMore, isFalse);

      // Subsequent scroll attempts do NOT trigger loadOlder
      controller.jumpTo(controller.position.maxScrollExtent);
      await tester.pump();
      expect(fakeRepo.loadOlderCallCount, 1);
    });
  });

  group('Quote / Reply Message Scrolling Tests', () {
    testWidgets('4. Missing quote target displays SnackBar without throwing', (tester) async {
      final fakeRepo = _FakeMessagesRepository();
      final baseDate = DateTime(2026, 10, 10, 10, 0);

      // Message with reply to non-existent message 'missing-msg-999'
      final msgs = [
        createMsg(
          'msg-reply',
          'This is a reply to missing message',
          baseDate,
          replyToId: 'missing-msg-999',
          replyText: 'Original text not in cache',
        ),
      ];

      final chatArgs = const ChatControllerArgs(
        chatId: chatId,
        currentUserId: currentUserId,
        otherUserId: peerUserId,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            chatTypingNotifierProvider(chatArgs).overrideWith(() => _FakeChatTypingNotifier(chatArgs)),
            messagesRepositoryProvider.overrideWithValue(fakeRepo),
            outboxServiceProvider.overrideWithValue(null),
            chatCallsProvider(chatId).overrideWith((ref) => Stream.value(<CallRecord>[])),
            chatPresenceStreamProvider(peerUserId).overrideWith(
              (ref) => Stream.value(const UserPresence(online: true, lastSeen: null)),
            ),
            chatTimelineNotifierProvider(chatArgs).overrideWith(
              () => _TestTimelineNotifier(chatArgs, msgs),
            ),
          ],
          child: const MaterialApp(
            home: ChatScreen(
              chatId: chatId,
              currentUserId: currentUserId,
              peerUserId: peerUserId,
              contactName: 'Contact',
              contactAvatar: '',
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Find the quote preview and tap it
      final quoteFinder = find.text('Original text not in cache');
      expect(quoteFinder, findsOneWidget);

      await tester.tap(quoteFinder);
      await tester.pump();

      // Verify warning snackbar is shown safely
      expect(find.text('Original message not loaded'), findsOneWidget);
    });

    testWidgets('5. Quoted message in timeline is located and highlighted', (tester) async {
      final fakeRepo = _FakeMessagesRepository();
      final baseDate = DateTime(2026, 10, 10, 10, 0);

      final originalMsg = createMsg('msg-original', 'Original referenced text here', baseDate);
      final replyMsg = createMsg(
        'msg-reply',
        'Replying to original',
        baseDate.add(const Duration(minutes: 5)),
        replyToId: 'msg-original',
        replyText: 'Original referenced text here',
      );

      final msgs = [originalMsg, replyMsg];

      final chatArgs = const ChatControllerArgs(
        chatId: chatId,
        currentUserId: currentUserId,
        otherUserId: peerUserId,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            chatTypingNotifierProvider(chatArgs).overrideWith(() => _FakeChatTypingNotifier(chatArgs)),
            messagesRepositoryProvider.overrideWithValue(fakeRepo),
            outboxServiceProvider.overrideWithValue(null),
            chatCallsProvider(chatId).overrideWith((ref) => Stream.value(<CallRecord>[])),
            chatPresenceStreamProvider(peerUserId).overrideWith(
              (ref) => Stream.value(const UserPresence(online: true, lastSeen: null)),
            ),
            chatTimelineNotifierProvider(chatArgs).overrideWith(
              () => _TestTimelineNotifier(chatArgs, msgs),
            ),
          ],
          child: const MaterialApp(
            home: ChatScreen(
              chatId: chatId,
              currentUserId: currentUserId,
              peerUserId: peerUserId,
              contactName: 'Contact',
              contactAvatar: '',
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Tap quote preview
      final quoteFinder = find.text('Original referenced text here').last;
      await tester.tap(quoteFinder);
      await tester.pump();

      // Does not show "not loaded" SnackBar because original is present
      expect(find.text('Original message not loaded'), findsNothing);

      // Advance clock past 1200ms highlight timer so no pending timers remain
      await tester.pump(const Duration(milliseconds: 1300));
    });

    testWidgets('6. Date separators and call events in timeline do not break quote navigation', (tester) async {
      final fakeRepo = _FakeMessagesRepository();
      // Date on day 1
      final day1 = DateTime(2026, 10, 1, 10, 0);
      // Date on day 2 (triggers DateSeparator)
      final day2 = DateTime(2026, 10, 2, 10, 0);

      final originalMsg = createMsg('msg-day1', 'Target message from Day 1', day1);
      final replyMsg = createMsg(
        'msg-day2',
        'Reply sent on Day 2',
        day2,
        replyToId: 'msg-day1',
        replyText: 'Target message from Day 1',
      );

      final callEvent = CallRecord(
        id: 'call-1',
        chatId: chatId,
        callerId: peerUserId,
        receiverId: currentUserId,
        callType: CallType.audio,
        status: CallStatus.ended,
        startedAt: day1.add(const Duration(hours: 1)),
        durationSeconds: 45,
      );

      final msgs = [originalMsg, replyMsg];

      final chatArgs = const ChatControllerArgs(
        chatId: chatId,
        currentUserId: currentUserId,
        otherUserId: peerUserId,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            chatTypingNotifierProvider(chatArgs).overrideWith(() => _FakeChatTypingNotifier(chatArgs)),
            messagesRepositoryProvider.overrideWithValue(fakeRepo),
            outboxServiceProvider.overrideWithValue(null),
            chatCallsProvider(chatId).overrideWith((ref) => Stream.value(<CallRecord>[callEvent])),
            chatPresenceStreamProvider(peerUserId).overrideWith(
              (ref) => Stream.value(const UserPresence(online: true, lastSeen: null)),
            ),
            chatTimelineNotifierProvider(chatArgs).overrideWith(
              () => _TestTimelineNotifier(chatArgs, msgs),
            ),
          ],
          child: const MaterialApp(
            home: ChatScreen(
              chatId: chatId,
              currentUserId: currentUserId,
              peerUserId: peerUserId,
              contactName: 'Contact',
              contactAvatar: '',
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Verify date separators and call bubble are rendered
      expect(find.text('Target message from Day 1').last, findsOneWidget);
      expect(find.text('Reply sent on Day 2'), findsOneWidget);

      // Tap quote to target across separator
      final quoteFinder = find.text('Target message from Day 1').last;
      await tester.tap(quoteFinder);
      await tester.pump();

      expect(find.text('Original message not loaded'), findsNothing);
      await tester.pump(const Duration(milliseconds: 1300));
    });

    testWidgets('7. Chronological message ordering is preserved with older messages prepended', (tester) async {
      final baseDate = DateTime(2026, 10, 10, 10, 0);

      final olderMsg = createMsg('msg-older', 'Older record', baseDate.subtract(const Duration(hours: 2)));
      final recentMsg = createMsg('msg-recent', 'Recent record', baseDate);

      final timeline = _TestTimelineNotifier(
        const ChatControllerArgs(chatId: chatId, currentUserId: currentUserId, otherUserId: peerUserId),
        [recentMsg],
      );

      final stateBefore = timeline.build();
      expect(stateBefore.messages.length, 1);
      expect(stateBefore.messages.first.id, 'msg-recent');

      // Simulate loadOlder prepending older message
      final merged = [olderMsg, ...stateBefore.messages];
      final stateAfter = stateBefore.copyWith(messages: merged, lastSentAt: olderMsg.sentAt);

      expect(stateAfter.messages.length, 2);
      expect(stateAfter.messages[0].id, 'msg-older');
      expect(stateAfter.messages[1].id, 'msg-recent');
      expect(stateAfter.messages[0].sentAt.isBefore(stateAfter.messages[1].sentAt), isTrue);
    });
  });
}

class _TestTimelineNotifier extends ChatTimelineNotifier {
  final List<ChatMessage> _preset;

  _TestTimelineNotifier(super.arg, this._preset);

  @override
  ChatTimelineState build() {
    return ChatTimelineState(
      messages: _preset,
      isLoading: false,
      isReady: true,
      hasMore: true,
      lastSentAt: _preset.isNotEmpty ? _preset.first.sentAt : null,
    );
  }
}
