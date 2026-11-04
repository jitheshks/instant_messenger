import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:instant_messenger/app/bootstrap/app_bootstrap_providers.dart';
import 'package:instant_messenger/core/persistence/stores/messages_store.dart';
import 'package:instant_messenger/core/sync/outbox_daemon.dart';
import 'package:instant_messenger/features/messaging/data/messages_repository.dart';
import 'package:instant_messenger/features/messaging/data/outbox_service.dart';
import 'package:instant_messenger/features/messaging/domain/models/chat_message.dart';
import 'package:instant_messenger/features/messaging/presentation/providers/messaging_providers.dart';
import 'package:instant_messenger/features/messaging/presentation/widgets/chat_input.dart';
import 'package:instant_messenger/features/notifications/presentation/controllers/push_controller.dart';
import 'package:instant_messenger/features/notifications/presentation/providers/notification_providers.dart';

class FakeMessagesRepository extends Fake implements MessagesRepository {
  final Map<String, Completer<String>> sendCompleters = {};
  final List<ChatMessage> sentMessages = [];
  final Completer<void> ensureChatDocCompleter = Completer<void>();
  final List<ChatMessage> olderMessagesToReturn = [];
  Completer<List<ChatMessage>>? loadOlderCompleter;

  @override
  MessagesStore? get messagesStore => null;

  @override
  OutboxDaemon? get outboxDaemon => null;

  @override
  Future<String> sendMessage(
    String chatId,
    ChatMessage msg, {
    required String otherUserId,
    required String otherName,
    String? otherAvatar,
  }) async {
    sentMessages.add(msg);
    final completer = sendCompleters.putIfAbsent(
      msg.id,
      () => Completer<String>(),
    );
    return completer.future;
  }

  @override
  Future<void> ensureChatDoc({
    required String chatId,
    required String uidA,
    required String uidB,
    required String title,
    String? avatarUrl,
  }) async {
    await ensureChatDocCompleter.future;
  }

  @override
  Future<List<ChatMessage>> loadOlderMessages(
    String chatId,
    dynamic lastDocOrSentAt, {
    int limit = 30,
  }) async {
    if (loadOlderCompleter != null) {
      return loadOlderCompleter!.future;
    }
    return olderMessagesToReturn;
  }
}

class FakePushController extends Fake implements PushController {
  final List<Map<String, dynamic>> pushDispatches = [];

  @override
  Future<void> onMessageSent({
    required String chatId,
    required String senderId,
    required String preview,
    required String messageId,
    String type = 'text',
    String? senderName,
    String? avatarUrl,
    List<String>? recipientPlayerIds,
    List<String>? recipientUserIds,
  }) async {
    pushDispatches.add({
      'chatId': chatId,
      'senderId': senderId,
      'preview': preview,
      'messageId': messageId,
      'recipientUserIds': recipientUserIds,
    });
  }
}

class FakeOutboxService extends Fake implements OutboxService {
  final List<ChatMessage> savedMessages = [];
  final List<String> retriedMessageIds = [];
  final List<String> cancelledMessageIds = [];
  Completer<void>? retryCompleter;

  @override
  Future<void> savePending(
    ChatMessage msg, {
    String? otherUserId,
    String? otherAvatar,
  }) async {
    savedMessages.add(msg);
  }

  @override
  Future<void> retryMessage(String messageId) async {
    retriedMessageIds.add(messageId);
    if (retryCompleter != null) {
      await retryCompleter!.future;
    }
  }

  @override
  Future<void> cancelMessage(String messageId) async {
    cancelledMessageIds.add(messageId);
  }
}

class FakeChatTypingNotifier extends ChatTypingNotifier {
  FakeChatTypingNotifier(super.arg);

  @override
  bool build() => false;

  @override
  void onTypingChanged(String text) {}

  @override
  void clearTyping() {}
}

void main() {
  group('ChatSendNotifier Lifecycle & Async Safety Tests', () {
    late FakeMessagesRepository fakeRepo;
    late FakePushController fakePush;
    late FakeOutboxService fakeOutbox;
    late ProviderContainer container;

    setUp(() {
      fakeRepo = FakeMessagesRepository();
      fakePush = FakePushController();
      fakeOutbox = FakeOutboxService();
      container = ProviderContainer(
        overrides: [
          messagesRepositoryProvider.overrideWithValue(fakeRepo),
          pushControllerProvider.overrideWithValue(fakePush),
          outboxServiceProvider.overrideWithValue(fakeOutbox),
        ],
      );
    });

    tearDown(() {
      container.dispose();
    });

    test(
      'Normal message sending initializes state, calls repo, pushes notification, and resets state',
      () async {
        const args = ChatControllerArgs(
          chatId: 'chat-normal',
          currentUserId: 'user-me',
          otherUserId: 'user-peer',
        );

        final sub = container.listen(chatSendNotifierProvider(args), (_, _) {});

        final future = container
            .read(chatSendNotifierProvider(args).notifier)
            .sendText('Hello world', otherName: 'Peer');

        expect(container.read(chatSendNotifierProvider(args)).isSending, isTrue);
        expect(fakeRepo.sentMessages.length, equals(1));
        final sentMsg = fakeRepo.sentMessages.first;
        expect(sentMsg.text, equals('Hello world'));
        expect(sentMsg.chatId, equals('chat-normal'));
        expect(sentMsg.senderId, equals('user-me'));

        fakeRepo.sendCompleters[sentMsg.id]!.complete('srv-101');
        await future;

        expect(container.read(chatSendNotifierProvider(args)).isSending, isFalse);
        expect(fakePush.pushDispatches.length, equals(1));
        expect(fakePush.pushDispatches.first['messageId'], equals('srv-101'));
        expect(fakePush.pushDispatches.first['chatId'], equals('chat-normal'));

        sub.close();
      },
    );

    test(
      'Unmounted autoDispose provider does NOT throw UnmountedRefException across async gap',
      () async {
        const args = ChatControllerArgs(
          chatId: 'chat-unmounted-safe',
          currentUserId: 'me',
          otherUserId: 'peer',
        );

        // Access via read without active watcher
        final future = container
            .read(chatSendNotifierProvider(args).notifier)
            .sendText('Testing keepAlive', otherName: 'Peer');

        // Let microtasks run so that standard autoDispose would dispose unreferenced provider
        await Future<void>.delayed(Duration.zero);

        final msg = fakeRepo.sentMessages.first;
        fakeRepo.sendCompleters[msg.id]!.complete('srv-202');

        // Must complete cleanly without throwing UnmountedRefException
        await expectLater(future, completes);
      },
    );

    test(
      'ProviderContainer disposed while message is sending does not crash on return',
      () async {
        final localContainer = ProviderContainer(
          overrides: [
            messagesRepositoryProvider.overrideWithValue(fakeRepo),
            pushControllerProvider.overrideWithValue(fakePush),
            outboxServiceProvider.overrideWithValue(fakeOutbox),
          ],
        );

        const args = ChatControllerArgs(
          chatId: 'chat-dispose-container',
          currentUserId: 'me',
          otherUserId: 'peer',
        );

        final future = localContainer
            .read(chatSendNotifierProvider(args).notifier)
            .sendText('Will be disposed', otherName: 'Peer');

        // Dispose the entire container while repo.sendMessage is pending
        localContainer.dispose();

        final msg = fakeRepo.sentMessages.first;
        fakeRepo.sendCompleters[msg.id]!.complete('srv-303');

        // Should exit cleanly due to ref.mounted check
        await expectLater(future, completes);
      },
    );

    test(
      'Send error updates error state safely without throwing unhandled exceptions',
      () async {
        const args = ChatControllerArgs(
          chatId: 'chat-err',
          currentUserId: 'me',
          otherUserId: 'peer',
        );

        final sub = container.listen(chatSendNotifierProvider(args), (_, _) {});

        final future = container
            .read(chatSendNotifierProvider(args).notifier)
            .sendText('Failing text', otherName: 'Peer');

        final msg = fakeRepo.sentMessages.first;
        fakeRepo.sendCompleters[msg.id]!.completeError(
          Exception('Database connection failed'),
        );

        await future;

        final state = container.read(chatSendNotifierProvider(args));
        expect(state.isSending, isFalse);
        expect(state.error, contains('Database connection failed'));

        sub.close();
      },
    );

    test(
      'Rapidly switching between two conversations maintains strict isolation and does not cross-contaminate',
      () async {
        const argsChat1 = ChatControllerArgs(
          chatId: 'chat-111',
          currentUserId: 'me',
          otherUserId: 'alice',
        );

        const argsChat2 = ChatControllerArgs(
          chatId: 'chat-222',
          currentUserId: 'me',
          otherUserId: 'bob',
        );

        final sub1 = container.listen(chatSendNotifierProvider(argsChat1), (_, _) {});
        final sub2 = container.listen(chatSendNotifierProvider(argsChat2), (_, _) {});

        // 1. Send message in Chat 1 (pending)
        final future1 = container
            .read(chatSendNotifierProvider(argsChat1).notifier)
            .sendText('Hello Alice', otherName: 'Alice');

        // 2. Rapid switch to Chat 2 and send message
        final future2 = container
            .read(chatSendNotifierProvider(argsChat2).notifier)
            .sendText('Hello Bob', otherName: 'Bob');

        // Verify Chat 1 and Chat 2 notifiers are independent
        expect(container.read(chatSendNotifierProvider(argsChat1)).isSending, isTrue);
        expect(container.read(chatSendNotifierProvider(argsChat2)).isSending, isTrue);
        expect(fakeRepo.sentMessages.length, equals(2));

        final msgAlice = fakeRepo.sentMessages.firstWhere((m) => m.chatId == 'chat-111');
        final msgBob = fakeRepo.sentMessages.firstWhere((m) => m.chatId == 'chat-222');

        expect(msgAlice.text, equals('Hello Alice'));
        expect(msgBob.text, equals('Hello Bob'));

        // 3. User leaves Chat 1 (sub1 closed) while its send is still pending
        sub1.close();

        // 4. Complete Bob's message in Chat 2
        fakeRepo.sendCompleters[msgBob.id]!.complete('srv-bob');
        await future2;

        expect(container.read(chatSendNotifierProvider(argsChat2)).isSending, isFalse);
        expect(container.read(chatSendNotifierProvider(argsChat2)).error, isNull);

        // 5. Complete Alice's message in Chat 1 (now unmounted from UI)
        fakeRepo.sendCompleters[msgAlice.id]!.complete('srv-alice');
        await future1;

        // Verify Chat 2 was completely unaffected by Chat 1 completing
        expect(container.read(chatSendNotifierProvider(argsChat2)).isSending, isFalse);

        sub2.close();
      },
    );

    test(
      'Retry and cancel media message hold keepAlive and execute safely',
      () async {
        const args = ChatControllerArgs(
          chatId: 'chat-media-ops',
          currentUserId: 'me',
          otherUserId: 'peer',
        );

        fakeOutbox.retryCompleter = Completer<void>();

        final future = container
            .read(chatSendNotifierProvider(args).notifier)
            .retryMediaMessage('msg-media-1');

        await Future<void>.delayed(Duration.zero);
        expect(fakeOutbox.retriedMessageIds, contains('msg-media-1'));

        fakeOutbox.retryCompleter!.complete();
        await future;

        await container
            .read(chatSendNotifierProvider(args).notifier)
            .cancelMediaMessage('msg-media-1');
        expect(fakeOutbox.cancelledMessageIds, contains('msg-media-1'));
      },
    );
  });

  group('ChatTimelineNotifier Lifecycle Safety Tests', () {
    late FakeMessagesRepository fakeRepo;
    late ProviderContainer container;

    setUp(() {
      fakeRepo = FakeMessagesRepository();
      container = ProviderContainer(
        overrides: [
          messagesRepositoryProvider.overrideWithValue(fakeRepo),
        ],
      );
    });

    tearDown(() {
      container.dispose();
    });

    test('Disposing timeline notifier while ensureInit is in flight does not throw', () async {
      const args = ChatControllerArgs(
        chatId: 'chat-timeline-init',
        currentUserId: 'me',
        otherUserId: 'peer',
      );

      final notifier = container.read(chatTimelineNotifierProvider(args).notifier);
      final future = notifier.ensureInit(otherName: 'Peer');

      // Dispose container while ensureChatDoc is pending
      container.dispose();

      fakeRepo.ensureChatDocCompleter.complete();
      await expectLater(future, completes);
    });

    test('Disposing timeline notifier while loadOlder is in flight does not throw', () async {
      final localContainer = ProviderContainer(
        overrides: [
          messagesRepositoryProvider.overrideWithValue(fakeRepo),
        ],
      );

      const args = ChatControllerArgs(
        chatId: 'chat-timeline-older',
        currentUserId: 'me',
        otherUserId: 'peer',
      );

      fakeRepo.loadOlderCompleter = Completer<List<ChatMessage>>();

      final notifier = localContainer.read(chatTimelineNotifierProvider(args).notifier);
      final future = notifier.loadOlder();

      localContainer.dispose();

      fakeRepo.loadOlderCompleter!.complete([]);
      await expectLater(future, completes);
    });
  });

  group('ChatInput Widget Integration Tests', () {
    testWidgets('ChatInput watches chatSendNotifierProvider and retains it during send', (
      tester,
    ) async {
      final fakeRepo = FakeMessagesRepository();
      final fakePush = FakePushController();

      const args = ChatControllerArgs(
        chatId: 'chat-widget-test',
        currentUserId: 'me',
        otherUserId: 'peer',
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            messagesRepositoryProvider.overrideWithValue(fakeRepo),
            pushControllerProvider.overrideWithValue(fakePush),
            chatTypingNotifierProvider(args).overrideWith(
              () => FakeChatTypingNotifier(args),
            ),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: ChatInput(
                args: args,
                otherName: 'Peer',
              ),
            ),
          ),
        ),
      );

      // Enter text
      final textField = find.byType(TextField);
      expect(textField, findsOneWidget);
      await tester.enterText(textField, 'Testing widget send');
      await tester.pumpAndSettle();

      // Tap send button
      final sendBtn = find.byIcon(Icons.send);
      expect(sendBtn, findsOneWidget);
      await tester.tap(sendBtn, warnIfMissed: false);
      await tester.pump();

      expect(fakeRepo.sentMessages.length, equals(1));
      expect(fakeRepo.sentMessages.first.text, equals('Testing widget send'));

      // Complete async message sending while widget is still mounted
      final msg = fakeRepo.sentMessages.first;
      fakeRepo.sendCompleters[msg.id]!.complete('srv-widget-ok');
      await tester.pumpAndSettle();

      expect(fakePush.pushDispatches.length, equals(1));
    });

    testWidgets('ChatInput unmounting while send is in flight completes gracefully without crash', (
      tester,
    ) async {
      final fakeRepo = FakeMessagesRepository();
      final fakePush = FakePushController();

      const args = ChatControllerArgs(
        chatId: 'chat-unmount-flight',
        currentUserId: 'me',
        otherUserId: 'peer',
      );

      bool showInput = true;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            messagesRepositoryProvider.overrideWithValue(fakeRepo),
            pushControllerProvider.overrideWithValue(fakePush),
            chatTypingNotifierProvider(args).overrideWith(
              () => FakeChatTypingNotifier(args),
            ),
          ],
          child: MaterialApp(
            home: StatefulBuilder(
              builder: (context, setState) {
                return Scaffold(
                  floatingActionButton: FloatingActionButton(
                    onPressed: () => setState(() => showInput = false),
                    child: const Icon(Icons.close),
                  ),
                  body: showInput
                      ? const ChatInput(
                          args: args,
                          otherName: 'Peer',
                        )
                      : const Text('Input closed'),
                );
              },
            ),
          ),
        ),
      );

      // Enter text and send
      await tester.enterText(find.byType(TextField), 'Unmount while sending');
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.send), warnIfMissed: false);
      await tester.pump();

      expect(fakeRepo.sentMessages.length, equals(1));

      // Now unmount ChatInput before message resolves
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      expect(find.text('Input closed'), findsOneWidget);
      expect(find.byType(ChatInput), findsNothing);

      // Complete the in-flight server send
      final msg = fakeRepo.sentMessages.first;
      fakeRepo.sendCompleters[msg.id]!.complete('srv-unmounted-ok');
      await tester.pumpAndSettle();

      // Check push was dispatched cleanly without UnmountedRefException
      expect(fakePush.pushDispatches.length, equals(1));
      expect(fakePush.pushDispatches.first['messageId'], equals('srv-unmounted-ok'));
    });
  });
}
