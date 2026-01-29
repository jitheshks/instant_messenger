// lib/app_router/app_router.dart

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:instant_messenger/controller/chat_screen_selection_controller.dart';
import 'package:instant_messenger/main.dart';
import 'package:instant_messenger/services/app_bootstrap.dart';
import 'package:instant_messenger/view/screens/call_screen.dart';
import 'package:instant_messenger/widgets/chat_route_observer.dart';
import 'package:provider/provider.dart';

// Controllers
import 'package:instant_messenger/controller/chat_screen_controller.dart';
import 'package:instant_messenger/controller/chats_tab_selection_controller.dart';
import 'package:instant_messenger/controller/push_controller.dart';
import 'package:instant_messenger/controller/contacts_screen_controller.dart';

// Repos/Services
import 'package:instant_messenger/services/chat_repository.dart';
import 'package:instant_messenger/services/message_cache.dart';
import 'package:instant_messenger/services/outbox_service.dart';

// Models
import 'package:instant_messenger/models/tab_controller_model.dart';

// Screens
import 'package:instant_messenger/view/screens/splash_screen.dart';
import 'package:instant_messenger/view/screens/login_screen.dart';
import 'package:instant_messenger/view/screens/otp_screen.dart';
import 'package:instant_messenger/view/screens/settings_screen.dart';
import 'package:instant_messenger/view/screens/profile_screen.dart';
import 'package:instant_messenger/view/screens/edit_name_screen.dart';
import 'package:instant_messenger/view/screens/chat_screen.dart';
import 'package:instant_messenger/view/screens/contacts_screen.dart';
import 'package:instant_messenger/view/screens/chats_tab_screen.dart';
import 'package:instant_messenger/view/screens/updates_tab.dart';
import 'package:instant_messenger/view/screens/communities_tab.dart';
import 'package:instant_messenger/view/screens/calls_tab.dart';

// Shared
import 'router_notifier.dart';
import 'package:instant_messenger/widgets/custom_navigation_bar.dart';


// Single place that builds ChatScreen from path + extras
Widget _buildChatRoute(BuildContext context, GoRouterState state) {
  // 1️⃣ Read chatId ONLY from path
  final chatId = state.pathParameters['chatId'] ?? '';

  // 2️⃣ Read extras (optional metadata only)
  final extra = (state.extra as Map?) ?? const {};

 final currentUserId = extra['currentUserId'] as String? ?? '';


  final contactName = (extra['contactName'] as String?) ?? 'Chat';
  final contactAvatar = (extra['contactAvatar'] as String?) ?? '';
  final otherUserId = (extra['otherUserId'] as String?) ?? '';

if (chatId.isEmpty || currentUserId.isEmpty || otherUserId.isEmpty) {
  debugPrint('[Router] ❌ Missing chat route params');
  return const Scaffold(
    body: Center(child: Text('Invalid chat parameters')),
  );
}

  debugPrint(
    '[Router] open chat → chatId=$chatId, currentUserId=$currentUserId',
  );


  // 4️⃣ Inject dependencies
  return Consumer4<
      ChatRepository?,
      OutboxService?,
      MessageCache?,
      PushController?>(
    builder: (context, repo, outbox, cache, push, _) {
      if (repo == null || outbox == null || cache == null || push == null) {
        return const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        );
      }

      // 5️⃣ Create controller 
      final chatController = ChatScreenController(
        repo: repo,
        outbox: outbox,
        chatId: chatId,
        currentUserId: currentUserId,
         otherUserId: otherUserId,
        onPush: ({
          required String chatId,
          required String senderId,
          required String preview,
          required String type,
          required String messageId,
          List<String>? recipientUserIds,
          List<String>? recipientPlayerIds,
          String? senderName,
          String? avatarUrl,
        }) async {
          await push.onMessageSent(
            chatId: chatId,
            senderId: senderId,
            preview: preview,
            type: type,
            messageId: messageId,
            senderName: senderName,
            avatarUrl: avatarUrl,
            recipientUserIds: recipientUserIds,
          );
        },
      );

      // 6️⃣ Provide controller + selection controller
      return MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: chatController),
          ChangeNotifierProvider(
            create: (_) => ChatScreenSelectionController(),
          ),
        ],
        child: ChatRouteObserver(
          chatId: chatId,
          child: ChatScreen(
            chatId: chatId,
            currentUserId: currentUserId,
              peerUserId: otherUserId, 
            contactName: contactName,
            contactAvatar: contactAvatar,
          ),
        ),
      );
    },
  );
}



GoRouter buildRouter(RouterNotifier guard) {
  return GoRouter(
    navigatorKey: rootNavKey,
    observers: [routeObserver],
    initialLocation: '/splash',
    refreshListenable: guard,

redirect: (context, state) {
  final loc = state.matchedLocation;
  final guard = context.read<RouterNotifier>();

  final authed = guard.isAuthed;
  final bootstrapped = guard.bootstrapped;
  final needName = guard.requiresName;

  debugPrint(
    '🔁 REDIRECT loc=$loc authed=$authed boot=$bootstrapped needName=$needName',
  );

  // 1️⃣ NOT AUTHENTICATED → LOGIN
  if (!authed) {
    return (loc == '/login' || loc == '/otp') ? null : '/login';
  }

  // 2️⃣ AUTHENTICATED BUT BOOTSTRAP NOT DONE
  if (!bootstrapped) {
    return loc == '/splash' ? null : '/splash';
  }

  // 3️⃣ NEED DISPLAY NAME
  if (needName) {
    return loc == '/editName' ? null : '/editName';
  }

  // 4️⃣ AUTHED + READY → BLOCK AUTH SCREENS
  if (loc == '/login' || loc == '/otp' || loc == '/splash') {
    return '/chats';
  }

  return null;
},



    routes: [
      // ───────────────── ROOT ROUTES ─────────────────

      GoRoute(path: '/splash', builder: (_, _) => const SplashScreen()),
      GoRoute(path: '/login', builder: (_, _) => LoginScreen()),
      GoRoute(path: '/otp', builder: (_, _) => const OtpScreen()),
GoRoute(
  path: '/editName',
  builder: (context, state) {
    final boot = context.read<AppBootstrapResult?>();

    debugPrint(
      '[EditName] initial="${boot?.displayName}"',
    );

    return EditNameScreen(
      initial: boot?.displayName ?? '',
    );
  },
),


    GoRoute(
  path: '/settings',
  builder: (_, _) => const SettingsScreen(),
),


GoRoute(
  path: '/profile',
  builder: (_, _) => const ProfileScreen(),
),


      GoRoute(
        path: '/contacts',
        builder: (context, state) => ChangeNotifierProvider(
          create: (_) => ContactsScreenController(),
          child: const ContactsScreen(),
        ),
      ),

      GoRoute(
        path: '/call/:callId',
        builder: (context, state) {
          final callId = state.pathParameters['callId'] ?? '';
          final userID = state.uri.queryParameters['userID'] ?? '';
          final userName = state.uri.queryParameters['userName'] ?? '';

          return CallScreen(
            callID: callId,
            userID: userID,
            userName: userName,
          );
        },
      ),

      // 🔥 CHAT ROUTE — MUST BE ROOT LEVEL
      GoRoute(
        path: '/chats/chat/:chatId',
        parentNavigatorKey: rootNavKey,
        builder: _buildChatRoute,
      ),

      // ───────────────── SHELL ROUTE (TABS) ─────────────────

      ShellRoute(
        builder: (context, state, child) {

      
          final loc = GoRouterState.of(context).matchedLocation;
          const tabs = TabControllerModel.tabs;
          var idx = 0;
          for (var i = 0; i < tabs.length; i++) {
            if (loc.startsWith(tabs[i])) {
              idx = i;
              break;
            }
          }

          return MultiProvider(
            providers: [
              ChangeNotifierProvider(
                create: (_) => TabControllerModel(initialIndex: idx),
              ),





              ChangeNotifierProvider(
                create: (_) => ChatsTabSelectionController(),
              ),
            ],
            child: TabScaffold(child: child),
          );
        },

        routes: [
          GoRoute(path: '/chats', builder: (_, _) => const ChatsTabScreen()),
          GoRoute(path: '/updates', builder: (_, _) => const UpdatesTab()),
          GoRoute(path: '/communities', builder: (_, _) => const CommunitiesTab()),
          GoRoute(path: '/calls', builder: (_, _) => const CallsTab()),
        ],
      ),
    ],

    errorBuilder: (context, state) => Scaffold(
      appBar: AppBar(title: const Text('Not found')),
      body: Center(
        child: Text(state.error?.toString() ?? 'Page not found'),
      ),
    ),
  );
}
