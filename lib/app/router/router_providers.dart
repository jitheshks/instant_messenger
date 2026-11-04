import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:instant_messenger/app/router/app_router.dart';
import 'package:instant_messenger/app/router/router_notifier.dart';
import 'package:instant_messenger/features/auth/presentation/providers/auth_providers.dart';

/// Notifier bridging Riverpod authentication changes to GoRouter refresh.
final routerNotifierProvider = Provider<RouterNotifier>((ref) {
  final router = RouterNotifier();
  final auth = ref.watch(authServiceProvider);

  // Synchronously seed initial auth state if session is already active
  final initialUid = auth.currentUserId;
  if (initialUid != null && initialUid.isNotEmpty) {
    debugPrint(
      '[NotificationTap] Seeding initial auth state on RouterNotifier: uid=$initialUid',
    );
    router.setAuthed(true);
  }

  final sub = auth.authStateChanges().listen(
    (isAuthed) {
      debugPrint('[NotificationTap] authStateChanges emitted isAuthed=$isAuthed');
      router.setAuthed(isAuthed);
      if (!isAuthed) {
        // Preserve any pending notification tap so post-login redirect can fulfill it
        router.reset(clearPendingNotification: false);
      }
    },
    onError: (err, st) {
      debugPrint('[NotificationTap] authStateChanges stream error: $err');
    },
  );

  ref.onDispose(sub.cancel);
  return router;
});

/// Root declarative GoRouter configuration.
final goRouterProvider = Provider<GoRouter>((ref) {
  final guard = ref.watch(routerNotifierProvider);
  return buildRouter(guard);
});
