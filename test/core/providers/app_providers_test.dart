import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:instant_messenger/app/router/router_providers.dart';
import 'package:instant_messenger/app/bootstrap/app_bootstrap_providers.dart';
import 'package:instant_messenger/features/auth/presentation/providers/auth_providers.dart';
import 'package:instant_messenger/features/chats/presentation/providers/chats_providers.dart';
import 'package:instant_messenger/features/contacts/presentation/providers/contacts_providers.dart';
import 'package:instant_messenger/features/media/presentation/providers/media_providers.dart';
import 'package:instant_messenger/features/messaging/presentation/providers/messaging_providers.dart';
import 'package:instant_messenger/features/notifications/presentation/providers/notification_providers.dart';
import 'package:instant_messenger/features/profile/presentation/providers/profile_providers.dart';
import 'package:instant_messenger/shared/widgets/bars/search_bar_notifier.dart';
import 'package:instant_messenger/features/messaging/domain/models/chat_message.dart';
import 'package:instant_messenger/app/bootstrap/app_bootstrap.dart';
import 'package:instant_messenger/features/auth/data/auth_service.dart';
import 'package:instant_messenger/features/chats/data/chats_repository.dart';
import 'package:instant_messenger/features/messaging/data/messages_repository.dart';
import 'package:instant_messenger/features/contacts/data/contact_repository.dart';
import 'package:instant_messenger/features/media/data/media_storage_service.dart';
import 'package:instant_messenger/features/messaging/data/message_cache.dart';
import 'package:instant_messenger/features/messaging/data/outbox_service.dart';
import 'package:instant_messenger/core/persistence/stores/messages_store.dart';
import 'package:instant_messenger/features/profile/data/user_bootstrap.dart';
import 'package:instant_messenger/features/profile/data/user_service.dart';

class _MockBox implements Box<ChatMessage> {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MockOutboxService implements OutboxService {
  final List<ChatMessage> pending = [];

  @override
  MessageCache get messageCache => _MockMessageCache();

  @override
  Stream<List<ChatMessage>> watchForChat(String chatId) => const Stream.empty();

  Future<void> enqueue(ChatMessage message) async {
    pending.add(message);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MockMessagesRepository implements MessagesRepository {
  @override
  MessagesStore? get messagesStore => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MockMessageCache implements MessageCache {
  @override
  List<ChatMessage> getRecent(String chatId) => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Riverpod App Providers Verification (Phase 4.5 Stage A & B)', () {
    test(
      'Core singleton providers resolve successfully with correct types',
      () {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        final auth = container.read(authServiceProvider);
        expect(auth, isA<AuthService>());

        final user = container.read(userServiceProvider);
        expect(user, isA<UserService>());

        final contactsRepo = container.read(contactsRepositoryProvider);
        expect(contactsRepo, isA<ContactsRepository>());

        final chatsRepo = container.read(chatsRepositoryProvider);
        expect(chatsRepo, isA<ChatsRepository>());

        final mediaStorage = container.read(mediaStorageServiceProvider);
        expect(mediaStorage, isA<MediaStorageService>());

        final pushDispatch = container.read(pushDispatchServiceProvider);
        expect(pushDispatch, isNotNull);
      },
    );

    test(
      'Unauthenticated session yields null bootstrap and un-scoped dependents',
      () async {
        final container = ProviderContainer(
          overrides: [currentUserIdProvider.overrideWithValue(null)],
        );
        addTearDown(container.dispose);

        final bootAsync = await container.read(
          appBootstrapResultProvider.future,
        );
        expect(bootAsync, isNull);

        final outbox = container.read(outboxServiceProvider);
        expect(outbox, isNull);

        final repo = container.read(messagesRepositoryProvider);
        expect(repo, isNull);

        final cache = container.read(messageCacheProvider);
        expect(cache, isNull);

        final orchestrator = container.read(uploadOrchestratorProvider);
        expect(orchestrator, isNull);
      },
    );

    test(
      'AutoDispose screen controllers clean up state when container/scope disposed',
      () {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        final scroll1 = container.read(chatScrollControllerProvider);
        expect(scroll1, isNotNull);

        final sel1 = container.read(chatScreenSelectionControllerProvider);
        expect(sel1, isNotNull);

        final search1 = container.read(searchBarControllerProvider);
        expect(search1, isNotNull);
      },
    );

    test('RouterNotifier reflects auth transitions and resets correctly', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final router = container.read(routerNotifierProvider);
      expect(router.isAuthed, isFalse);
      expect(router.bootstrapped, isFalse);

      router.setAuthed(true);
      expect(router.isAuthed, isTrue);

      router.setBootstrapped(true);
      expect(router.bootstrapped, isTrue);

      router.reset();
      expect(router.isAuthed, isFalse);
      expect(router.bootstrapped, isFalse);
    });
  });

  group(
    'Riverpod Session & Account Lifecycle Regression Tests (Phase 4.5 Task 6)',
    () {
      test(
        'Switching from account A to account B properly resets and isolates session providers',
        () async {
          final mockOutboxA = _MockOutboxService();
          final mockOutboxB = _MockOutboxService();

          final mockBootResultA = AppBootstrapResult(
            outbox: mockOutboxA,
            repo: _MockMessagesRepository(),
            cache: _MockMessageCache(),
            outboxBox: _MockBox(),
            nextRoute: NextRoute.chats,
            displayName: 'User A',
          );

          final mockBootResultB = AppBootstrapResult(
            outbox: mockOutboxB,
            repo: _MockMessagesRepository(),
            cache: _MockMessageCache(),
            outboxBox: _MockBox(),
            nextRoute: NextRoute.chats,
            displayName: 'User B',
          );

          // Session A
          final containerA = ProviderContainer(
            overrides: [
              currentUserIdProvider.overrideWithValue('user_a'),
              appBootstrapResultProvider.overrideWith(
                (ref) => Future.value(mockBootResultA),
              ),
            ],
          );
          addTearDown(containerA.dispose);

          final bootA = await containerA.read(
            appBootstrapResultProvider.future,
          );
          expect(bootA?.displayName, equals('User A'));
          expect(containerA.read(outboxServiceProvider), same(mockOutboxA));

          // Sign out -> unauthenticated
          final containerUnauth = ProviderContainer(
            overrides: [currentUserIdProvider.overrideWithValue(null)],
          );
          addTearDown(containerUnauth.dispose);

          final bootUnauth = await containerUnauth.read(
            appBootstrapResultProvider.future,
          );
          expect(bootUnauth, isNull);
          expect(containerUnauth.read(outboxServiceProvider), isNull);

          // Session B
          final containerB = ProviderContainer(
            overrides: [
              currentUserIdProvider.overrideWithValue('user_b'),
              appBootstrapResultProvider.overrideWith(
                (ref) => Future.value(mockBootResultB),
              ),
            ],
          );
          addTearDown(containerB.dispose);

          final bootB = await containerB.read(
            appBootstrapResultProvider.future,
          );
          expect(bootB?.displayName, equals('User B'));
          expect(containerB.read(outboxServiceProvider), same(mockOutboxB));
          expect(
            containerB.read(outboxServiceProvider),
            isNot(same(mockOutboxA)),
          );
        },
      );

      test(
        'Pending outbox mutations are preserved in owning account queue across sessions',
        () async {
          final mockOutboxA = _MockOutboxService();
          final mutation = ChatMessage(
            id: 'msg-123',
            chatId: 'chat-abc',
            senderId: 'user_a',
            text: 'Offline hello',
            type: MessageType.text,
            sentAt: DateTime.now(),
            deliveryState: DeliveryState.sending,
          );

          // Enqueue in User A
          await mockOutboxA.enqueue(mutation);
          expect(mockOutboxA.pending.length, equals(1));
          expect(mockOutboxA.pending.first.id, equals('msg-123'));

          // Simulate session transition: User B logs in with empty outbox
          final mockOutboxB = _MockOutboxService();
          expect(mockOutboxB.pending, isEmpty);

          // User A logs back in: User A's outbox still has pending mutation
          expect(mockOutboxA.pending.length, equals(1));
          expect(mockOutboxA.pending.first.text, equals('Offline hello'));
        },
      );

      test(
        'Chat timeline notifier family autoDisposes when leaving chat and recreates cleanly',
        () {
          final mockRepo = _MockMessagesRepository();
          final mockOutbox = _MockOutboxService();

          final container = ProviderContainer(
            overrides: [
              messagesRepositoryProvider.overrideWithValue(mockRepo),
              outboxServiceProvider.overrideWithValue(mockOutbox),
            ],
          );
          addTearDown(container.dispose);

          const args = ChatControllerArgs(
            chatId: 'chat-test-1',
            currentUserId: 'user_a',
            otherUserId: 'user_b',
          );

          final sub1 =
              container.listen(chatTimelineNotifierProvider(args), (_, _) {});
          final state1 = container.read(chatTimelineNotifierProvider(args));
          expect(state1.isLoading, isTrue);
          expect(state1.messages, isEmpty);

          // Second read returns identical state while alive
          final state2 = container.read(chatTimelineNotifierProvider(args));
          expect(state1, equals(state2));
          sub1.close();
        },
      );
    },
  );
}
