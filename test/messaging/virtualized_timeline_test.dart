// test/messaging/virtualized_timeline_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:instant_messenger/features/calls/domain/models/call_enums.dart';
import 'package:instant_messenger/features/calls/domain/models/call_record.dart';
import 'package:instant_messenger/features/messaging/domain/models/chat_message.dart';
import 'package:instant_messenger/features/messaging/presentation/controllers/selection_notifier.dart';
import 'package:instant_messenger/features/messaging/presentation/providers/messaging_providers.dart';
import 'package:instant_messenger/features/messaging/presentation/widgets/chat_timeline_entry.dart';
import 'package:instant_messenger/features/messaging/presentation/widgets/chat_timeline_view.dart';

class _TestTimelineNotifier extends ChatTimelineNotifier {
  final List<ChatMessage> initialMsgs;
  _TestTimelineNotifier(super.arg, this.initialMsgs);

  @override
  ChatTimelineState build() {
    return ChatTimelineState(
      isReady: true,
      messages: initialMsgs,
      hasMore: true,
    );
  }

  @override
  Future<void> maybeMarkRead([ChatMessage? newest]) async {}

  @override
  Future<void> loadOlder() async {}
}

void main() {
  group('Virtualized Timeline Entry Construction Tests', () {
    final day1 = DateTime(2026, 10, 10, 10, 0);
    final day2 = DateTime(2026, 10, 11, 14, 0);

    ChatMessage createMsg(String id, DateTime sentAt, String text) {
      return ChatMessage(
        id: id,
        chatId: 'chat-1',
        senderId: 'user-1',
        text: text,
        sentAt: sentAt,
        type: MessageType.text,
        deliveryState: DeliveryState.delivered,
      );
    }

    CallRecord createCall(String id, DateTime startedAt) {
      return CallRecord(
        id: id,
        chatId: 'chat-1',
        callerId: 'user-1',
        callType: CallType.audio,
        status: CallStatus.ended,
        startedAt: startedAt,
      );
    }

    test('1. Interleaves messages and calls in chronological order with date separators and reverses for reverse: true', () {
      final msg1 = createMsg('m1', day1, 'Hello');
      final call1 = createCall('c1', day1.add(const Duration(minutes: 5)));
      final msg2 = createMsg('m2', day2, 'World');

      final entries = buildTimelineEntries(
        messages: [msg1, msg2],
        calls: [call1],
        loadingMore: false,
      );

      // Chronological order before reverse would be:
      // [DateSep Day 1, msg1, call1, DateSep Day 2, msg2]
      // Reversed list (index 0 is newest, rendered at bottom):
      // [msg2, DateSep Day 2, call1, msg1, DateSep Day 1]
      expect(entries.length, 5);

      expect(entries[0], isA<MessageTimelineEntry>());
      expect((entries[0] as MessageTimelineEntry).message.id, 'm2');

      expect(entries[1], isA<DateSeparatorTimelineEntry>());
      expect((entries[1] as DateSeparatorTimelineEntry).date, day2);

      expect(entries[2], isA<CallTimelineEntry>());
      expect((entries[2] as CallTimelineEntry).call.id, 'c1');

      expect(entries[3], isA<MessageTimelineEntry>());
      expect((entries[3] as MessageTimelineEntry).message.id, 'm1');

      expect(entries[4], isA<DateSeparatorTimelineEntry>());
      expect((entries[4] as DateSeparatorTimelineEntry).date, day1);
    });

    test('2. Appends LoadingMoreTimelineEntry at the oldest boundary (last index in reversed list)', () {
      final msg1 = createMsg('m1', day1, 'Hello');

      final entries = buildTimelineEntries(
        messages: [msg1],
        calls: [],
        loadingMore: true,
      );

      expect(entries.length, 3);
      expect(entries[0], isA<MessageTimelineEntry>());
      expect(entries[1], isA<DateSeparatorTimelineEntry>());
      expect(entries[2], isA<LoadingMoreTimelineEntry>());
    });

    test('3. Empty messages and calls returns empty list', () {
      final entries = buildTimelineEntries(
        messages: [],
        calls: [],
        loadingMore: false,
      );
      expect(entries, isEmpty);
    });
  });

  group('MessageKeyRegistry Bounded Lifecycle Tests', () {
    test('1. Registers and unregisters keys dynamically without leaking unbounded maps', () {
      final registry = MessageKeyRegistry();

      expect(registry.isMounted('msg-1'), isFalse);

      final key1 = registry.register('msg-1');
      expect(key1, isNotNull);
      expect(registry.getKey('msg-1'), same(key1));
      expect(registry['msg-1'], same(key1));

      // Same ID returns same key
      final key1Again = registry.register('msg-1');
      expect(key1Again, same(key1));

      // Unregister frees the key
      registry.unregister('msg-1');
      expect(registry.getKey('msg-1'), isNull);
      expect(registry['msg-1'], isNull);
      expect(registry.isMounted('msg-1'), isFalse);
    });
  });

  group('ChatTimelineView Virtualized Rendering & Quote Scrolling Tests', () {
    const currentUserId = 'user-me-123';
    const peerUserId = 'user-peer-456';
    const chatId = 'c0000000-0000-0000-0000-000000000001';

    ChatMessage createMsg(String id, String text, DateTime sentAt) {
      return ChatMessage(
        id: id,
        chatId: chatId,
        senderId: peerUserId,
        text: text,
        sentAt: sentAt,
        type: MessageType.text,
        deliveryState: DeliveryState.delivered,
        isIncoming: true,
      );
    }

    testWidgets('1. Lazily renders only visible items and mounts hosts on demand', (tester) async {
      final baseDate = DateTime(2026, 10, 10, 10, 0);
      final manyMessages = List.generate(
        60,
        (i) => createMsg('msg-$i', 'Long text message number $i', baseDate.add(Duration(minutes: i))),
      );

      final scrollController = ScrollController();
      final chatArgs = const ChatControllerArgs(
        chatId: chatId,
        currentUserId: currentUserId,
        otherUserId: peerUserId,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            chatTimelineNotifierProvider(chatArgs).overrideWith(
              () => _TestTimelineNotifier(chatArgs, manyMessages),
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: SizedBox(
                height: 400,
                child: Consumer(
                  builder: (context, ref, _) {
                    final activeState = ref.watch(chatTimelineNotifierProvider(chatArgs));
                    final notifier = ref.read(chatTimelineNotifierProvider(chatArgs).notifier);
                    return ChatTimelineView(
                      chatArgs: chatArgs,
                      currentUserId: currentUserId,
                      peerUserId: peerUserId,
                      contactName: 'Peer User',
                      contactAvatar: '',
                      scrollController: scrollController,
                      timelineState: activeState,
                      timelineNotifier: notifier,
                      selectionState: const {},
                      selectionNotifier: ChatScreenSelectionNotifier(),
                      calls: const [],
                      onSwipeReply: (_) {},
                      onCallBack: (_) {},
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // In a 400px height viewport, only the newest items (e.g. msg-59, msg-58, msg-57...) are mounted!
      // Oldest items (msg-0, msg-1, msg-2) are virtualized and NOT built into the element tree.
      expect(find.text('Long text message number 59'), findsOneWidget);
      expect(find.text('Long text message number 0'), findsNothing);
    });

    testWidgets('2. Staged quote navigation scrolls to off-screen virtualized message and highlights it', (tester) async {
      final baseDate = DateTime(2026, 10, 10, 10, 0);
      final manyMessages = List.generate(
        50,
        (i) => createMsg('msg-$i', 'Indexed message $i', baseDate.add(Duration(minutes: i))),
      );

      final scrollController = ScrollController();
      final chatArgs = const ChatControllerArgs(
        chatId: chatId,
        currentUserId: currentUserId,
        otherUserId: peerUserId,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            chatTimelineNotifierProvider(chatArgs).overrideWith(
              () => _TestTimelineNotifier(chatArgs, manyMessages),
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: SizedBox(
                height: 400,
                child: Consumer(
                  builder: (context, ref, _) {
                    final activeState = ref.watch(chatTimelineNotifierProvider(chatArgs));
                    final notifier = ref.read(chatTimelineNotifierProvider(chatArgs).notifier);
                    return ChatTimelineView(
                      chatArgs: chatArgs,
                      currentUserId: currentUserId,
                      peerUserId: peerUserId,
                      contactName: 'Peer User',
                      contactAvatar: '',
                      scrollController: scrollController,
                      timelineState: activeState,
                      timelineNotifier: notifier,
                      selectionState: const {},
                      selectionNotifier: ChatScreenSelectionNotifier(),
                      calls: const [],
                      onSwipeReply: (_) {},
                      onCallBack: (_) {},
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      final state = tester.state<ChatTimelineViewState>(find.byType(ChatTimelineView));
      final entries = buildTimelineEntries(messages: manyMessages, calls: [], loadingMore: false);

      // msg-5 is far off-screen initially
      expect(find.text('Indexed message 5'), findsNothing);

      // Invoke quote navigation
      state.scrollToMessage('msg-5', entries);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      // Now msg-5 is brought into view by virtualized scrolling!
      expect(find.text('Indexed message 5'), findsOneWidget);

      // Clean up highlight timer
      await tester.pump(const Duration(milliseconds: 1300));
    });
  });
}
