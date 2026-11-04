import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:instant_messenger/app/bootstrap/app_bootstrap_providers.dart';
import 'package:instant_messenger/app/router/chat_route_resolver.dart';
import 'package:instant_messenger/core/persistence/hive_database.dart';
import 'package:instant_messenger/core/persistence/stores/chats_store.dart';
import 'package:instant_messenger/core/providers/core_providers.dart';
import 'package:instant_messenger/features/calls/domain/models/call_record.dart';
import 'package:instant_messenger/features/calls/presentation/providers/calls_providers.dart';
import 'package:instant_messenger/features/chats/domain/models/chat_summary.dart';
import 'package:instant_messenger/features/messaging/data/messages_repository.dart';
import 'package:instant_messenger/features/messaging/domain/models/user_presence.dart';
import 'package:instant_messenger/features/messaging/presentation/providers/messaging_providers.dart';
import 'package:instant_messenger/features/messaging/presentation/screens/chat_screen.dart';
import 'package:instant_messenger/shared/utils/chat_route.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _FakeChatsStore extends Fake implements ChatsStore {
  final Map<String, ChatSummary> summaries = {};

  @override
  ChatSummary? getChatSummary(String chatId) => summaries[chatId];
}

class _FakeHiveDatabase extends Fake implements HiveDatabase {
  final _FakeChatsStore _store = _FakeChatsStore();

  @override
  ChatsStore get chatsStore => _store;
}

class _FakeMessagesRepository extends Fake implements MessagesRepository {
  @override
  Future<void> ensureChatDoc({
    required String chatId,
    required String uidA,
    required String uidB,
    required String title,
    String? avatarUrl,
  }) async {}

  @override
  Future<void> markDeliveredIfNeeded({
    required String chatId,
    required String currentUserId,
    required List<dynamic> messages,
  }) async {}

  @override
  Future<void> markRead(String chatId, String userId) async {}
}

class _FakeChatTypingNotifier extends ChatTypingNotifier {
  _FakeChatTypingNotifier(super.arg);

  @override
  bool build() => false;
}

class _FakeTimelineNotifier extends ChatTimelineNotifier {
  _FakeTimelineNotifier(super.arg);

  @override
  ChatTimelineState build() {
    return const ChatTimelineState(
      messages: [],
      isLoading: false,
      isReady: true,
      hasMore: false,
    );
  }
}

class _FakeSupabaseClient extends Fake implements SupabaseClient {
  @override
  Future<void> dispose() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const currentUserId = 'user-me-123';
  const groupChatId = 'c0000000-0000-0000-0000-000000000099';
  const directChatId = 'c0000000-0000-0000-0000-000000000001';

  const groupArgs = ChatControllerArgs(chatId: groupChatId, currentUserId: currentUserId, otherUserId: '', isGroup: true);
  const directArgs = ChatControllerArgs(chatId: directChatId, currentUserId: currentUserId, otherUserId: 'peer-alice-789', isGroup: false);

  final commonOverrides = [
    supabaseClientProvider.overrideWithValue(_FakeSupabaseClient()),
    messagesRepositoryProvider.overrideWithValue(_FakeMessagesRepository()),
    outboxServiceProvider.overrideWithValue(null),
    chatCallsProvider(groupChatId).overrideWith((ref) => Stream.value(<CallRecord>[])),
    chatCallsProvider(directChatId).overrideWith((ref) => Stream.value(<CallRecord>[])),
    chatPresenceStreamProvider('').overrideWith(
      (ref) => Stream.value(const UserPresence(online: false, lastSeen: null)),
    ),
    chatPresenceStreamProvider('peer-alice-789').overrideWith(
      (ref) => Stream.value(const UserPresence(online: true, lastSeen: null)),
    ),
    chatTypingNotifierProvider(groupArgs).overrideWith(
      () => _FakeChatTypingNotifier(groupArgs),
    ),
    chatTypingNotifierProvider(directArgs).overrideWith(
      () => _FakeChatTypingNotifier(directArgs),
    ),
    chatTimelineNotifierProvider(groupArgs).overrideWith(
      () => _FakeTimelineNotifier(groupArgs),
    ),
    chatTimelineNotifierProvider(directArgs).overrideWith(
      () => _FakeTimelineNotifier(directArgs),
    ),
  ];

  group('Group Navigation Identity and Metadata Tests', () {
    testWidgets('1. Fast-path group route preserves group title, avatar, and empty peerUserId', (tester) async {
      final router = GoRouter(
        initialLocation: '/chats/chat/$groupChatId',
        initialExtra: {
          'currentUserId': currentUserId,
          'isGroup': true,
          'contactName': 'Flutter Developers Community',
          'contactAvatar': 'https://example.com/avatar.png',
        },
        routes: [
          GoRoute(
            path: '/chats/chat/:chatId',
            builder: (context, state) {
              final extra = (state.extra as Map?) ?? const {};
              final isGroup = (extra['isGroup'] as bool?) ?? false;
              final otherUserId = (extra['otherUserId'] as String?) ?? '';
              final contactName = (extra['contactName'] as String?) ?? 'Chat';
              final contactAvatar = (extra['contactAvatar'] as String?) ?? '';

              return ChatScreen(
                chatId: state.pathParameters['chatId']!,
                currentUserId: currentUserId,
                peerUserId: isGroup ? '' : otherUserId,
                isGroup: isGroup,
                contactName: contactName,
                contactAvatar: contactAvatar,
              );
            },
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: commonOverrides,
          child: MaterialApp.router(
            routerConfig: router,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      final chatScreenFinder = find.byType(ChatScreen);
      expect(chatScreenFinder, findsOneWidget);

      final chatScreen = tester.widget<ChatScreen>(chatScreenFinder);
      expect(chatScreen.isGroup, isTrue);
      expect(chatScreen.peerUserId, isEmpty);
      expect(chatScreen.contactName, 'Flutter Developers Community');
      expect(chatScreen.contactAvatar, 'https://example.com/avatar.png');
    });

    testWidgets('2. Fast-path direct chat route preserves peerUserId and direct metadata', (tester) async {
      final router = GoRouter(
        initialLocation: '/chats/chat/$directChatId',
        initialExtra: {
          'currentUserId': currentUserId,
          'otherUserId': 'peer-alice-789',
          'isGroup': false,
          'contactName': 'Alice Smith',
          'contactAvatar': 'https://example.com/alice.png',
        },
        routes: [
          GoRoute(
            path: '/chats/chat/:chatId',
            builder: (context, state) {
              final extra = (state.extra as Map?) ?? const {};
              final isGroup = (extra['isGroup'] as bool?) ?? false;
              final otherUserId = (extra['otherUserId'] as String?) ?? '';
              final contactName = (extra['contactName'] as String?) ?? 'Chat';
              final contactAvatar = (extra['contactAvatar'] as String?) ?? '';

              return ChatScreen(
                chatId: state.pathParameters['chatId']!,
                currentUserId: currentUserId,
                peerUserId: isGroup ? '' : otherUserId,
                isGroup: isGroup,
                contactName: contactName,
                contactAvatar: contactAvatar,
              );
            },
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: commonOverrides,
          child: MaterialApp.router(
            routerConfig: router,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      final chatScreenFinder = find.byType(ChatScreen);
      expect(chatScreenFinder, findsOneWidget);

      final chatScreen = tester.widget<ChatScreen>(chatScreenFinder);
      expect(chatScreen.isGroup, isFalse);
      expect(chatScreen.peerUserId, 'peer-alice-789');
      expect(chatScreen.contactName, 'Alice Smith');
      expect(chatScreen.contactAvatar, 'https://example.com/alice.png');
    });

    testWidgets('3. openChat utility forwards isGroup: true and empties otherUserId for group chats', (tester) async {
      Map<String, dynamic>? capturedExtra;
      String? capturedPath;

      final router = GoRouter(
        initialLocation: '/',
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) => Scaffold(
              body: ElevatedButton(
                onPressed: () {
                  openChat(
                    context,
                    chatId: groupChatId,
                    currentUserId: currentUserId,
                    isGroup: true,
                    contactName: 'Dart Team',
                    contactAvatar: 'https://example.com/group.png',
                  );
                },
                child: const Text('Open Group'),
              ),
            ),
          ),
          GoRoute(
            path: '/chats/chat/:chatId',
            builder: (context, state) {
              capturedPath = state.uri.toString();
              capturedExtra = (state.extra as Map?)?.cast<String, dynamic>();
              return const Scaffold(body: Text('Chat Target'));
            },
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp.router(
          routerConfig: router,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open Group'));
      await tester.pumpAndSettle();

      expect(capturedPath, '/chats/chat/$groupChatId');
      expect(capturedExtra, isNotNull);
      expect(capturedExtra!['isGroup'], isTrue);
      expect(capturedExtra!['otherUserId'], isEmpty);
      expect(capturedExtra!['contactName'], 'Dart Team');
      expect(capturedExtra!['contactAvatar'], 'https://example.com/group.png');
    });

    testWidgets('4. ChatRouteResolver resolves group from local cache without resolving arbitrary peer', (tester) async {
      final fakeDb = _FakeHiveDatabase();
      final groupSummary = ChatSummary(
        id: groupChatId,
        lastMessage: 'Welcome everyone!',
        lastTime: DateTime(2026, 11, 1),
        unread: 0,
        muted: false,
        otherUserId: '',
        members: [currentUserId, 'member-1', 'member-2', 'member-3'],
        lastSenderId: 'member-1',
        lastMessageStatus: 2,
        isGroup: true,
        title: 'Project Phoenix',
        avatarUrl: 'https://example.com/phoenix.png',
      );
      fakeDb._store.summaries[groupChatId] = groupSummary;

      HiveDatabaseManager.instance.setActiveDatabaseForTesting(fakeDb);

      await tester.pumpWidget(
        ProviderScope(
          overrides: commonOverrides,
          child: const MaterialApp(
            home: Scaffold(
              body: ChatRouteResolver(
                chatId: groupChatId,
                currentUserId: currentUserId,
                initialContactName: 'Group',
                initialContactAvatar: '',
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      final chatScreenFinder = find.byType(ChatScreen);
      expect(chatScreenFinder, findsOneWidget);

      final chatScreen = tester.widget<ChatScreen>(chatScreenFinder);
      expect(chatScreen.isGroup, isTrue);
      expect(chatScreen.peerUserId, isEmpty);
      expect(chatScreen.contactName, 'Project Phoenix');
      expect(chatScreen.contactAvatar, 'https://example.com/phoenix.png');
    });
  });
}
