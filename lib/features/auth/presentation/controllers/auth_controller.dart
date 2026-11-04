import 'package:flutter/foundation.dart';
import 'package:instant_messenger/app/router/router_notifier.dart';
import 'package:instant_messenger/features/notifications/presentation/controllers/push_controller.dart';
import 'package:instant_messenger/core/config/supabase_config.dart';
import 'package:instant_messenger/core/persistence/hive_database.dart';
import 'package:instant_messenger/features/auth/data/auth_service.dart';
import 'package:instant_messenger/core/persistence/local_cache.dart';

/// AuthController coordinates authentication actions and secure session termination.
class AuthController extends ChangeNotifier {
  final RouterNotifier routerGuard;
  final AuthService? _authService;
  final PushController? _pushController;

  AuthController(
    this.routerGuard, {
    AuthService? authService,
    PushController? pushController,
  }) : _authService = authService,
       _pushController = pushController;

  bool _loading = false;
  bool get loading => _loading;

  /// Call after successful authentication
  Future<void> signInWithPhone(String e164) async {
    _loading = true;
    notifyListeners();

    try {
      routerGuard.setAuthed(true);
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Sign out the current user with hardened ordering:
  /// 1. While the session is still valid, attempt device registration removal under self-only RLS.
  /// 2. Disassociate OneSignal user via OneSignal.logout().
  /// 3. Complete Supabase sign-out via AuthService.signOut().
  /// 4. In all cases (even on failure), reset router state and clear authenticated state.
  Future<void> signOut() async {
    _loading = true;
    notifyListeners();

    try {
      // 1 & 2: Push device cleanup & OneSignal logout while session is still valid
      final currentUid =
          _authService?.currentUserId ?? SupabaseConfig.currentUserId;
      final push = _pushController;
      if (push != null && currentUid != null && currentUid.isNotEmpty) {
        try {
          await push.cleanupOnSignOut(currentUid);
        } catch (e, st) {
          if (kDebugMode) {
            debugPrint('[AuthController] Push cleanup on signOut failed: $e');
            debugPrintStack(stackTrace: st);
          }
        }
      }

      // 3: Complete Supabase sign-out
      final auth = _authService;
      if (auth != null) {
        try {
          await auth.signOut();
        } catch (e, st) {
          if (kDebugMode) {
            debugPrint('[AuthController] AuthService signOut failed: $e');
            debugPrintStack(stackTrace: st);
          }
        }
      }

      // 4: Close active account database stores cleanly (releases file locks, preserves disk cache)
      try {
        await HiveDatabaseManager.instance.closeCurrentAccount();
        await LocalCache.onSignOut();
      } catch (e, st) {
        if (kDebugMode) {
          debugPrint(
            '[AuthController] HiveDatabase closeCurrentAccount error: $e',
          );
          debugPrintStack(stackTrace: st);
        }
      }
    } finally {
      // 4: Always reset router and auth state
      routerGuard.reset();
      routerGuard.setAuthed(false);
      _loading = false;
      notifyListeners();
    }
  }
}
