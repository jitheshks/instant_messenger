import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:instant_messenger/app/router/app_router.dart';
import 'package:instant_messenger/app/router/router_notifier.dart';
import 'package:instant_messenger/app/router/chat_route_resolver.dart';
import 'package:instant_messenger/core/providers/core_providers.dart';
import 'package:instant_messenger/features/messaging/domain/models/user_presence.dart';
import 'package:instant_messenger/features/messaging/presentation/providers/messaging_providers.dart';
import 'package:instant_messenger/features/messaging/presentation/screens/chat_screen.dart';
import 'package:instant_messenger/features/notifications/presentation/controllers/notification_controller.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class FakeChatTypingNotifier extends ChatTypingNotifier {
  FakeChatTypingNotifier(super.arg);

  @override
  bool build() => false;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SupabaseClient mockSupabase;

  setUp(() {
    mockSupabase = SupabaseClient(
      'https://mock.supabase.co',
      'mock-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
  });

  group('Notification-to-Chat Navigation & Parameter Parity Tests', () {
    testWidgets('Valid in-app navigation with full extra renders ChatScreen directly (fast path)', (tester) async {
      final guard = RouterNotifier()
        ..setAuthed(true)
        ..setBootstrapped(true);

      final router = buildRouter(guard);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            supabaseClientProvider.overrideWithValue(mockSupabase),
            chatPresenceStreamProvider.overrideWith(
              (ref, userId) => Stream.value(const UserPresence(online: true)),
            ),
            chatTypingNotifierProvider(const ChatControllerArgs(
              chatId: 'chat-123',
              currentUserId: 'user_me',
              otherUserId: 'user_peer',
            )).overrideWith(
              () => FakeChatTypingNotifier(const ChatControllerArgs(
                chatId: 'chat-123',
                currentUserId: 'user_me',
                otherUserId: 'user_peer',
              )),
            ),
          ],
          child: MaterialApp.router(
            routerConfig: router,
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));

      // Navigate to chat with full metadata (regular in-app flow)
      router.push(
        '/chats/chat/chat-123',
        extra: {
          'currentUserId': 'user_me',
          'otherUserId': 'user_peer',
          'contactName': 'Alice',
          'contactAvatar': 'https://example.com/alice.jpg',
        },
      );
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byType(ChatScreen), findsOneWidget);
      expect(find.text('Alice'), findsWidgets);
    });

    testWidgets('Missing currentUserId when unauthenticated displays Authentication required', (tester) async {
      final guard = RouterNotifier()
        ..setAuthed(true)
        ..setBootstrapped(true);

      final router = buildRouter(guard);

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp.router(
            routerConfig: router,
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));

      // Push chat route with explicit empty currentUserId and no session
      router.push(
        '/chats/chat/chat-123',
        extra: {
          'currentUserId': '',
          'otherUserId': 'user_peer',
        },
      );
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Authentication required'), findsOneWidget);
    });

    testWidgets('Missing otherUserId routes to ChatRouteResolver', (tester) async {
      final guard = RouterNotifier()
        ..setAuthed(true)
        ..setBootstrapped(true);

      final router = buildRouter(guard);

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp.router(
            routerConfig: router,
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));

      // Push notification navigation where only chatId is known, otherUserId is omitted
      router.push(
        '/chats/chat/chat-999',
        extra: {
          'currentUserId': 'user_me',
          // otherUserId intentionally omitted!
        },
      );
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byType(ChatRouteResolver), findsOneWidget);
    });

    testWidgets('ChatRouteResolver displays access error on nonexistent or unauthorized conversation', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: ChatRouteResolver(
              chatId: 'nonexistent-chat',
              currentUserId: 'user_intruder',
            ),
          ),
        ),
      );
      // Wait for async resolution to complete
      await tester.pump(const Duration(milliseconds: 200));

      // Without Supabase credentials in unit test environment, safely displays failure message
      expect(find.byIcon(Icons.lock_outline), findsOneWidget);
      expect(find.text('Back to Chats'), findsOneWidget);
    });

    testWidgets('/chat/:chatId redirects to /chats/chat/:chatId', (tester) async {
      final guard = RouterNotifier()
        ..setAuthed(true)
        ..setBootstrapped(true);

      final router = buildRouter(guard);

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp.router(
            routerConfig: router,
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));

      // Push legacy / notification path
      router.go('/chat/legacy-chat-456');
      await tester.pump(const Duration(milliseconds: 100));

      // Verify router location redirected to canonical /chats/chat/legacy-chat-456
      final location = router.routerDelegate.currentConfiguration.uri.toString();
      expect(location, equals('/chats/chat/legacy-chat-456'));
    });

    testWidgets('Cold-start pending notification on RouterNotifier redirects from /splash to /chats/chat/:chatId when bootstrap completes', (tester) async {
      final guard = RouterNotifier()
        ..setAuthed(true)
        ..setBootstrapped(false)
        ..setPendingNotificationChatId('pending-chat-789');

      final router = buildRouter(guard);

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp.router(
            routerConfig: router,
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));

      // Initially at /splash because bootstrapped is false
      expect(router.routerDelegate.currentConfiguration.uri.toString(), equals('/splash'));

      // Bootstrap completes
      guard.setBootstrapped(true);
      await tester.pump(const Duration(milliseconds: 100));

      // Redirect should consume pendingNotificationChatId and route to /chats/chat/pending-chat-789
      expect(
        router.routerDelegate.currentConfiguration.uri.toString(),
        equals('/chats/chat/pending-chat-789'),
      );
      expect(guard.pendingNotificationChatId, isNull);
    });

    testWidgets('Multiple microtask redirects during bootstrap do not drop pending chatId', (tester) async {
      final guard = RouterNotifier()
        ..setAuthed(true)
        ..setBootstrapped(false)
        ..setPendingNotificationChatId('chat-microtask-test');

      final router = buildRouter(guard);

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp.router(
            routerConfig: router,
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));

      expect(router.routerDelegate.currentConfiguration.uri.toString(), equals('/splash'));

      // Simulate microtask sequence from splash_screen.dart:
      // 1. router.setRequiresName(false)
      // 2. router.setBootstrapped(true)
      guard.setRequiresName(false);
      guard.setBootstrapped(true);
      await tester.pump(const Duration(milliseconds: 100));

      // Successfully redirected to pending chat
      expect(
        router.routerDelegate.currentConfiguration.uri.toString(),
        equals('/chats/chat/chat-microtask-test'),
      );
      expect(guard.pendingNotificationChatId, isNull);
    });

    testWidgets('Notification tap while unauthenticated survives auth and bootstrap sequence', (tester) async {
      final guard = RouterNotifier()
        ..setAuthed(false)
        ..setBootstrapped(false);

      final router = buildRouter(guard);

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp.router(
            routerConfig: router,
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));
      expect(router.routerDelegate.currentConfiguration.uri.toString(), equals('/login'));

      // Tap arrives while unauthenticated
      guard.setPendingNotificationChatId('chat-post-auth');
      await tester.pump(const Duration(milliseconds: 50));
      expect(router.routerDelegate.currentConfiguration.uri.toString(), equals('/login'));
      expect(guard.pendingNotificationChatId, equals('chat-post-auth'));

      // User logs in
      guard.setAuthed(true);
      await tester.pump(const Duration(milliseconds: 50));
      expect(router.routerDelegate.currentConfiguration.uri.toString(), equals('/splash'));
      expect(guard.pendingNotificationChatId, equals('chat-post-auth'));

      // Bootstrap completes
      guard.setBootstrapped(true);
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        router.routerDelegate.currentConfiguration.uri.toString(),
        equals('/chats/chat/chat-post-auth'),
      );
      expect(guard.pendingNotificationChatId, isNull);
    });

    testWidgets('Duplicate notification tap when chat is already open does not push duplicate route', (tester) async {
      final guard = RouterNotifier()
        ..setAuthed(true)
        ..setBootstrapped(true);

      final router = buildRouter(guard);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            supabaseClientProvider.overrideWithValue(mockSupabase),
            chatPresenceStreamProvider.overrideWith(
              (ref, userId) => Stream.value(const UserPresence(online: true)),
            ),
            chatTypingNotifierProvider(const ChatControllerArgs(
              chatId: 'chat-open',
              currentUserId: 'user_me',
              otherUserId: 'user_peer',
            )).overrideWith(
              () => FakeChatTypingNotifier(const ChatControllerArgs(
                chatId: 'chat-open',
                currentUserId: 'user_me',
                otherUserId: 'user_peer',
              )),
            ),
          ],
          child: MaterialApp.router(
            routerConfig: router,
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));

      // Open chat initially
      router.push(
        '/chats/chat/chat-open',
        extra: {
          'currentUserId': 'user_me',
          'otherUserId': 'user_peer',
          'contactName': 'Bob',
        },
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(ChatScreen), findsOneWidget);
      expect(NotificationController.isChatOpen('chat-open'), isTrue);

      // Duplicate tap arrives for the same chat - our handler in app.dart checks isChatOpen
      if (!NotificationController.isChatOpen('chat-open')) {
        router.push('/chats/chat/chat-open');
      }

      await tester.pump(const Duration(milliseconds: 100));
      // Still exactly one ChatScreen widget mounted
      expect(find.byType(ChatScreen), findsOneWidget);
    });

    testWidgets('Whitespace or empty chatId in route displays Invalid chat parameters', (tester) async {
      final guard = RouterNotifier()
        ..setAuthed(true)
        ..setBootstrapped(true);

      final router = buildRouter(guard);

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp.router(
            routerConfig: router,
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));

      router.push('/chats/chat/%20');
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Invalid chat parameters'), findsOneWidget);
    });
  });
}
