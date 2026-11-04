// lib/app_router/app_router.dart

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:instant_messenger/app/app.dart';
import 'package:instant_messenger/core/persistence/local_cache.dart';
import 'package:instant_messenger/features/calls/domain/models/call_enums.dart';
import 'package:instant_messenger/features/calls/presentation/screens/call_screen.dart';
import 'package:instant_messenger/features/messaging/presentation/widgets/chat_route_observer.dart';
import 'package:instant_messenger/features/notifications/domain/models/notification_payload.dart';

// Screens
import 'package:instant_messenger/features/auth/presentation/screens/splash_screen.dart';
import 'package:instant_messenger/features/auth/presentation/screens/login_screen.dart';
import 'package:instant_messenger/features/auth/presentation/screens/otp_screen.dart';
import 'package:instant_messenger/features/settings/presentation/screens/settings_screen.dart';
import 'package:instant_messenger/features/profile/presentation/screens/profile_screen.dart';
import 'package:instant_messenger/features/profile/presentation/screens/edit_name_screen.dart';
import 'package:instant_messenger/features/profile/presentation/screens/contact_profile_screen.dart';
import 'package:instant_messenger/features/profile/presentation/screens/group_profile_screen.dart';
import 'package:instant_messenger/features/messaging/presentation/screens/chat_screen.dart';
import 'package:instant_messenger/features/contacts/presentation/screens/contacts_screen.dart';
import 'package:instant_messenger/features/chats/presentation/screens/chats_tab_screen.dart';
import 'package:instant_messenger/features/chats/presentation/screens/updates_tab.dart';
import 'package:instant_messenger/features/chats/presentation/screens/communities_tab.dart';
import 'package:instant_messenger/features/calls/presentation/screens/calls_tab.dart';

// Navigation Shell
import 'router_notifier.dart';
import 'chat_route_resolver.dart';
import 'package:instant_messenger/app/navigation/tab_scaffold.dart';
import 'package:instant_messenger/core/config/supabase_config.dart';

// Single place that builds ChatScreen from path + extras
Widget _buildChatRoute(BuildContext context, GoRouterState state) {
  // 1️⃣ Read chatId ONLY from path
  final rawChatId = state.pathParameters['chatId'] ?? '';
  final chatId = rawChatId.trim();

  debugPrint('[NotificationTap] _buildChatRoute building for chatId: "$chatId"');

  if (chatId.isEmpty) {
    debugPrint('[NotificationTap] ❌ Empty chatId in route');
    return const Scaffold(body: Center(child: Text('Invalid chat parameters')));
  }

  // 2️⃣ Resolve current authenticated user from session or extra
  final extra = (state.extra as Map?) ?? const {};
  final sessionUid = SupabaseConfig.currentUserId;
  final currentUserId = (sessionUid != null && sessionUid.isNotEmpty)
      ? sessionUid
      : (extra['currentUserId'] as String? ?? '');

  if (currentUserId.isEmpty) {
    debugPrint('[NotificationTap] ❌ Unauthenticated chat navigation attempt');
    return const Scaffold(body: Center(child: Text('Authentication required')));
  }

  final isGroup = (extra['isGroup'] as bool?) ?? false;
  final otherUserId = (extra['otherUserId'] as String?) ?? '';
  final contactName = (extra['contactName'] as String?) ?? (isGroup ? 'Group' : 'Chat');
  final contactAvatar = (extra['contactAvatar'] as String?) ?? '';

  // 3️⃣ Fast path:
  // If group conversation, peer user ID is intentionally empty; render directly
  if (isGroup) {
    debugPrint(
      '[NotificationTap] open group chat (fast-path) → chatId=$chatId, currentUserId=$currentUserId, title="$contactName"',
    );
    return ChatRouteObserver(
      chatId: chatId,
      child: ChatScreen(
        chatId: chatId,
        currentUserId: currentUserId,
        peerUserId: '',
        isGroup: true,
        contactName: contactName,
        contactAvatar: contactAvatar,
      ),
    );
  }

  // If direct conversation and peer user ID is already provided via extra, render directly
  if (otherUserId.isNotEmpty) {
    debugPrint(
      '[NotificationTap] open chat (fast-path) → chatId=$chatId, currentUserId=$currentUserId, otherUserId=$otherUserId',
    );
    return ChatRouteObserver(
      chatId: chatId,
      child: ChatScreen(
        chatId: chatId,
        currentUserId: currentUserId,
        peerUserId: otherUserId,
        isGroup: false,
        contactName: contactName,
        contactAvatar: contactAvatar,
      ),
    );
  }

  // 4️⃣ Notification / deep-link resolution path: resolve peer and verify participant authorization
  debugPrint(
    '[NotificationTap] open chat (resolver-path) → chatId=$chatId, currentUserId=$currentUserId',
  );
  return ChatRouteResolver(
    chatId: chatId,
    currentUserId: currentUserId,
    initialContactName: contactName,
    initialContactAvatar: contactAvatar,
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

      final authed = guard.isAuthed;
      final bootstrapped = guard.bootstrapped;
      final needName = guard.requiresName;

      debugPrint(
        '🔁 REDIRECT loc=$loc authed=$authed boot=$bootstrapped needName=$needName pending=${guard.pendingNotificationChatId}',
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
        final pendingPayload = guard.pendingNotification;
        if (pendingPayload != null) {
          if (pendingPayload.type == NotificationType.call &&
              pendingPayload.callId != null &&
              pendingPayload.callId!.isNotEmpty) {
            final cid = pendingPayload.callId!;
            final uid = pendingPayload.callerId ?? '';
            final name = Uri.encodeComponent(pendingPayload.callerName ?? 'Caller');
            final ctype = pendingPayload.callType ?? 'audio';
            final incoming = pendingPayload.callActionIntent != CallActionIntent.accept;
            debugPrint('[NotificationTap] Redirecting from $loc to /call/$cid (incoming=$incoming)');
            return '/call/$cid?userID=$uid&userName=$name&callType=$ctype&incoming=$incoming';
          }
          final pending = pendingPayload.chatId ?? guard.pendingNotificationChatId;
          if (pending != null && pending.isNotEmpty) {
            debugPrint(
              '[NotificationTap] Redirecting from $loc to /chats/chat/$pending (preserving pending destination)',
            );
            return '/chats/chat/$pending';
          }
        }
        final pending = guard.pendingNotificationChatId;
        if (pending != null && pending.isNotEmpty) {
          debugPrint(
            '[NotificationTap] Redirecting from $loc to /chats/chat/$pending (preserving pending destination)',
          );
          return '/chats/chat/$pending';
        }
        return '/chats';
      }

      // 5️⃣ PENDING NOTIFICATION NAVIGATION (when already on authed screen)
      final pendingPayload = guard.pendingNotification;
      if (pendingPayload != null) {
        if (pendingPayload.type == NotificationType.call &&
            pendingPayload.callId != null &&
            pendingPayload.callId!.isNotEmpty) {
          final cid = pendingPayload.callId!;
          final uid = pendingPayload.callerId ?? '';
          final name = Uri.encodeComponent(pendingPayload.callerName ?? 'Caller');
          final ctype = pendingPayload.callType ?? 'audio';
          final incoming = pendingPayload.callActionIntent != CallActionIntent.accept;
          final target =
              '/call/$cid?userID=$uid&userName=$name&callType=$ctype&incoming=$incoming';
          if (!loc.startsWith('/call/$cid')) {
            debugPrint(
              '[NotificationTap] Redirecting from $loc to call destination $target',
            );
            return target;
          } else {
            debugPrint(
              '[NotificationTap] Reached target call route ($loc); consuming pending notification',
            );
            guard.consumePendingNotification();
          }
        } else {
          final pending = pendingPayload.chatId ?? guard.pendingNotificationChatId;
          if (pending != null && pending.isNotEmpty) {
            if (loc != '/chats/chat/$pending') {
              debugPrint(
                '[NotificationTap] Redirecting from $loc to /chats/chat/$pending',
              );
              return '/chats/chat/$pending';
            } else {
              debugPrint(
                '[NotificationTap] Reached target chat route ($loc); consuming pending notification: $pending',
              );
              guard.consumePendingNotification();
            }
          }
        }
      } else {
        final pending = guard.pendingNotificationChatId;
        if (pending != null && pending.isNotEmpty) {
          if (loc != '/chats/chat/$pending') {
            debugPrint(
              '[NotificationTap] Redirecting from $loc to /chats/chat/$pending',
            );
            return '/chats/chat/$pending';
          } else {
            debugPrint(
              '[NotificationTap] Reached target chat route ($loc); consuming pending chatId: $pending',
            );
            guard.consumePendingNotificationChatId();
          }
        }
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
          final extra = state.extra;
          final initial = (extra is String)
              ? extra
              : (LocalCache.displayName ?? '');
          final onboarding = extra == null;
          debugPrint('[EditName] initial="$initial" onboarding=$onboarding');
          return EditNameScreen(initial: initial, onboarding: onboarding);
        },
      ),

      GoRoute(path: '/settings', builder: (_, _) => const SettingsScreen()),

      GoRoute(path: '/profile', builder: (_, _) => const ProfileScreen()),

      GoRoute(
        path: '/contacts',
        builder: (context, state) => const ContactsScreen(),
      ),

      GoRoute(
        path: '/call/:callId',
        builder: (context, state) {
          final callId = state.pathParameters['callId'] ?? '';
          final userID = state.uri.queryParameters['userID'] ?? '';
          final userName = state.uri.queryParameters['userName'] ?? '';
          final callTypeParam = state.uri.queryParameters['callType'] ?? 'audio';
          final isIncoming = state.uri.queryParameters['incoming'] == 'true';
          final callType =
              callTypeParam == 'video' ? CallType.video : CallType.audio;

          return CallScreen(
            callID: callId,
            userID: userID,
            userName: userName,
            callType: callType,
            isIncoming: isIncoming,
          );
        },
      ),

      // 🔥 CHAT ROUTE — MUST BE ROOT LEVEL
      GoRoute(
        path: '/chats/chat/:chatId',
        parentNavigatorKey: rootNavKey,
        builder: _buildChatRoute,
      ),

      // Backward-compatible redirect for legacy / notification paths
      GoRoute(
        path: '/chat/:chatId',
        redirect: (context, state) =>
            '/chats/chat/${state.pathParameters['chatId']}',
      ),

      // ───────────────── PROFILE ROUTES ─────────────────
      GoRoute(
        path: '/contact-profile/:chatId',
        parentNavigatorKey: rootNavKey,
        builder: (context, state) {
          final chatId = state.pathParameters['chatId'] ?? '';
          final extra = (state.extra as Map?) ?? const {};
          final peerUserId = (extra['peerUserId'] as String?) ?? '';
          final peerName = (extra['peerName'] as String?) ?? 'Contact';
          final avatarUrl = (extra['avatarUrl'] as String?) ?? '';
          final phone = extra['phone'] as String?;

          return ContactProfileScreen(
            chatId: chatId,
            peerUserId: peerUserId,
            peerName: peerName,
            avatarUrl: avatarUrl,
            phone: phone,
          );
        },
      ),

      GoRoute(
        path: '/group-profile/:chatId',
        parentNavigatorKey: rootNavKey,
        builder: (context, state) {
          final chatId = state.pathParameters['chatId'] ?? '';
          final extra = (state.extra as Map?) ?? const {};
          final title = (extra['title'] as String?) ?? 'Group';
          final avatarUrl = (extra['avatarUrl'] as String?) ?? '';

          return GroupProfileScreen(
            chatId: chatId,
            groupTitle: title,
            avatarUrl: avatarUrl,
          );
        },
      ),

      // ───────────────── SHELL ROUTE (TABS) ─────────────────
      ShellRoute(
        builder: (context, state, child) => TabScaffold(child: child),
        routes: [
          GoRoute(path: '/chats', builder: (_, _) => const ChatsTabScreen()),
          GoRoute(path: '/updates', builder: (_, _) => const UpdatesTab()),
          GoRoute(
            path: '/communities',
            builder: (_, _) => const CommunitiesTab(),
          ),
          GoRoute(path: '/calls', builder: (_, _) => const CallsTab()),
        ],
      ),
    ],

    errorBuilder: (context, state) => Scaffold(
      appBar: AppBar(title: const Text('Not found')),
      body: Center(child: Text(state.error?.toString() ?? 'Page not found')),
    ),
  );
}
