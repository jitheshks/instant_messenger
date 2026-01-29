import 'package:flutter/foundation.dart';
import 'package:instant_messenger/app_router/router_notifier.dart';

/// AuthController is now RESPONSIBLE ONLY FOR:
/// 1) triggering auth flows
/// 2) updating router auth state
///
/// ❌ No push logic
/// ❌ No Firestore listeners
/// ❌ No PushRequestListener
///
/// Push is initialized elsewhere (main.dart / bootstrap)
class AuthController extends ChangeNotifier {
  final RouterNotifier routerGuard;

  AuthController(this.routerGuard);

  bool _loading = false;
  bool get loading => _loading;

  /// Call after successful Firebase Auth sign-in
  Future<void> signInWithPhone(String e164) async {
    _loading = true;
    notifyListeners();

    try {
      // TODO: Your Firebase phone auth flow here
      // After this completes, FirebaseAuth.instance.currentUser must be valid

      // ✅ ONLY tell the router that the user is authenticated
      routerGuard.setAuthed(true);
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Sign out the current user
  Future<void> signOut() async {
    // TODO: Firebase sign out if not already handled elsewhere
    // await FirebaseAuth.instance.signOut();

    // ✅ Update router auth state
    routerGuard.setAuthed(false);
  }
}
