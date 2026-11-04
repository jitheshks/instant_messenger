import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:instant_messenger/app/bootstrap/app_bootstrap.dart';
import 'package:instant_messenger/app/bootstrap/app_bootstrap_providers.dart';
import 'package:instant_messenger/app/router/app_router.dart';
import 'package:instant_messenger/app/router/router_notifier.dart';
import 'package:instant_messenger/app/router/router_providers.dart';
import 'package:instant_messenger/core/persistence/hive_init.dart';
import 'package:instant_messenger/core/providers/core_providers.dart';
import 'package:instant_messenger/features/auth/presentation/screens/login_screen.dart';
import 'package:instant_messenger/features/auth/presentation/screens/otp_screen.dart';
import 'package:instant_messenger/features/auth/presentation/screens/splash_screen.dart';
import 'package:instant_messenger/features/calls/presentation/screens/call_screen.dart';
import 'package:instant_messenger/features/calls/presentation/screens/calls_tab.dart';
import 'package:instant_messenger/features/chats/presentation/screens/chats_tab_screen.dart';
import 'package:instant_messenger/features/chats/presentation/screens/communities_tab.dart';
import 'package:instant_messenger/features/chats/presentation/screens/updates_tab.dart';
import 'package:instant_messenger/features/contacts/presentation/screens/contacts_screen.dart';
import 'package:instant_messenger/features/messaging/domain/models/user_presence.dart';
import 'package:instant_messenger/features/messaging/presentation/providers/messaging_providers.dart';
import 'package:instant_messenger/features/messaging/presentation/screens/chat_screen.dart';
import 'package:instant_messenger/features/profile/presentation/screens/edit_name_screen.dart';
import 'package:instant_messenger/features/profile/presentation/screens/profile_screen.dart';
import 'package:instant_messenger/features/settings/presentation/screens/settings_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _FakeChatTypingNotifier extends ChatTypingNotifier {
  _FakeChatTypingNotifier(super.arg);

  @override
  bool build() => false;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late SupabaseClient mockSupabase;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('full_route_audit_');
    Hive.init(tempDir.path);
    HiveInit.registerAdapters();
    await Hive.openBox('profile');
    await Hive.openBox('contacts');
    await Hive.openBox('chats_meta');

    mockSupabase = SupabaseClient(
      'https://mock.supabase.co',
      'mock-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
  });

  tearDownAll(() async {
    await Hive.close();
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  Widget buildApp(RouterNotifier guard) {
    final router = buildRouter(guard);
    return ProviderScope(
      overrides: [
        routerNotifierProvider.overrideWithValue(guard),
        supabaseClientProvider.overrideWithValue(mockSupabase),
        chatPresenceStreamProvider.overrideWith(
          (ref, userId) => Stream.value(const UserPresence(online: true)),
        ),
        chatTypingNotifierProvider(const ChatControllerArgs(
          chatId: 'test-chat-1',
          currentUserId: 'user-me',
          otherUserId: 'user-peer',
        )).overrideWith(
          () => _FakeChatTypingNotifier(const ChatControllerArgs(
            chatId: 'test-chat-1',
            currentUserId: 'user-me',
            otherUserId: 'user-peer',
          )),
        ),
      ],
      child: MaterialApp.router(
        routerConfig: router,
      ),
    );
  }

  group('Full Route Audit & Navigation Guards (All 14 Routes)', () {
    // ───────────────── 1. UNAUTHENTICATED GUARD AUDIT ─────────────────
    testWidgets('1. Unauthenticated: accessing protected route redirects to /login', (tester) async {
      final guard = RouterNotifier()
        ..setAuthed(false)
        ..setBootstrapped(true);

      await tester.pumpWidget(buildApp(guard));
      await tester.pump(const Duration(milliseconds: 100));

      // Root redirected to /login
      expect(find.byType(LoginScreen), findsOneWidget);
    });

    testWidgets('2. Unauthenticated: /login and /otp remain accessible', (tester) async {
      final guard = RouterNotifier()
        ..setAuthed(false)
        ..setBootstrapped(true);

      final router = buildRouter(guard);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            routerNotifierProvider.overrideWithValue(guard),
            supabaseClientProvider.overrideWithValue(mockSupabase),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byType(LoginScreen), findsOneWidget);

      router.go('/otp');
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(OtpScreen), findsOneWidget);
    });

    // ───────────────── 2. BOOTSTRAP GUARD AUDIT ─────────────────
    testWidgets('3. Authenticated but not bootstrapped: redirects to /splash', (tester) async {
      final guard = RouterNotifier()
        ..setAuthed(true)
        ..setBootstrapped(false);

      final router = buildRouter(guard);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            routerNotifierProvider.overrideWithValue(guard),
            supabaseClientProvider.overrideWithValue(mockSupabase),
            appBootstrapResultProvider.overrideWith(
              (ref) => Completer<AppBootstrapResult?>().future,
            ),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byType(SplashScreen), findsOneWidget);
    });

    // ───────────────── 3. PROFILE INCOMPLETE GUARD AUDIT ─────────────────
    testWidgets('4. Authenticated + bootstrapped + requiresName=true: redirects to /editName', (tester) async {
      final guard = RouterNotifier()
        ..setAuthed(true)
        ..setBootstrapped(true)
        ..setRequiresName(true);

      final router = buildRouter(guard);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            routerNotifierProvider.overrideWithValue(guard),
            supabaseClientProvider.overrideWithValue(mockSupabase),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));

      // Guard strictly redirects to /editName
      expect(find.byType(EditNameScreen), findsOneWidget);
    });

    // ───────────────── 4. BLOCK AUTH SCREENS FOR COMPLETED USERS ─────────────────
    testWidgets('5. Fully authenticated user is blocked from auth screens (/login, /otp, /splash)', (tester) async {
      final guard = RouterNotifier()
        ..setAuthed(true)
        ..setBootstrapped(true)
        ..setRequiresName(false);

      final router = buildRouter(guard);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            routerNotifierProvider.overrideWithValue(guard),
            supabaseClientProvider.overrideWithValue(mockSupabase),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));

      // Attempt navigating to /login
      router.go('/login');
      await tester.pump(const Duration(milliseconds: 100));
      // Blocked and bounced to /chats
      expect(find.byType(LoginScreen), findsNothing);
      expect(find.byType(ChatsTabScreen), findsOneWidget);

      // Attempt navigating to /splash
      router.go('/splash');
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(SplashScreen), findsNothing);
      expect(find.byType(ChatsTabScreen), findsOneWidget);
    });

    // ───────────────── 5. ALL 4 SHELL TAB ROUTES ─────────────────
    testWidgets('6. Shell tab routes navigation: /chats, /updates, /communities, /calls', (tester) async {
      final guard = RouterNotifier()
        ..setAuthed(true)
        ..setBootstrapped(true)
        ..setRequiresName(false);

      final router = buildRouter(guard);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            routerNotifierProvider.overrideWithValue(guard),
            supabaseClientProvider.overrideWithValue(mockSupabase),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));

      // Tab 1: /chats
      router.go('/chats');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(ChatsTabScreen), findsOneWidget);

      // Tab 2: /updates
      router.go('/updates');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(UpdatesTab), findsOneWidget);

      // Tab 3: /communities
      router.go('/communities');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(CommunitiesTab), findsOneWidget);

      // Tab 4: /calls
      router.go('/calls');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(CallsTab), findsOneWidget);
    });

    // ───────────────── 6. STANDALONE ROOT ROUTES ─────────────────
    testWidgets('7. Standalone routes navigation: /settings, /profile, /contacts, /call/:callId', (tester) async {
      final guard = RouterNotifier()
        ..setAuthed(true)
        ..setBootstrapped(true)
        ..setRequiresName(false);

      final router = buildRouter(guard);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            routerNotifierProvider.overrideWithValue(guard),
            supabaseClientProvider.overrideWithValue(mockSupabase),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));

      // Route: /settings
      router.push('/settings');
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(SettingsScreen), findsOneWidget);

      // Route: /profile
      router.push('/profile');
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(ProfileScreen), findsOneWidget);

      // Route: /contacts
      router.push('/contacts');
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(ContactsScreen), findsOneWidget);

      // Route: /call/:callId
      router.push('/call/call-abc-123?userID=user-1&userName=Alice');
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(CallScreen), findsOneWidget);
    });

    // ───────────────── 7. CHAT & LEGACY REDIRECT ROUTES ─────────────────
    testWidgets('8. Chat route /chats/chat/:chatId renders and /chat/:chatId legacy redirects', (tester) async {
      final guard = RouterNotifier()
        ..setAuthed(true)
        ..setBootstrapped(true)
        ..setRequiresName(false);

      final router = buildRouter(guard);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            routerNotifierProvider.overrideWithValue(guard),
            supabaseClientProvider.overrideWithValue(mockSupabase),
            chatPresenceStreamProvider.overrideWith(
              (ref, userId) => Stream.value(const UserPresence(online: true)),
            ),
            chatTypingNotifierProvider(const ChatControllerArgs(
              chatId: 'test-chat-1',
              currentUserId: 'user-me',
              otherUserId: 'user-peer',
            )).overrideWith(
              () => _FakeChatTypingNotifier(const ChatControllerArgs(
                chatId: 'test-chat-1',
                currentUserId: 'user-me',
                otherUserId: 'user-peer',
              )),
            ),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));

      // Fast-path /chats/chat/:chatId with metadata
      router.push(
        '/chats/chat/test-chat-1',
        extra: {
          'currentUserId': 'user-me',
          'otherUserId': 'user-peer',
          'contactName': 'Peer Contact',
        },
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(ChatScreen), findsOneWidget);

      // Legacy redirect: /chat/test-chat-1 -> /chats/chat/test-chat-1
      router.go('/chat/test-chat-1');
      await tester.pump(const Duration(milliseconds: 100));
      expect(router.state.matchedLocation, equals('/chats/chat/test-chat-1'));
    });
  });
}
