import 'package:flutter/widgets.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import 'package:instant_messenger/controller/push_controller.dart';

class RouterNotifier extends ChangeNotifier {
  bool _isAuthed = false;
  bool _requiresName = false;
  bool _bootstrapped = false;

  bool _pushInitDone = false;

  // ───────────────── GETTERS ─────────────────

  bool get isAuthed => _isAuthed;
  bool get requiresName => _requiresName;
  bool get bootstrapped => _bootstrapped;

  // ───────────────── AUTH STATE ─────────────────

  void setAuthed(bool value) {
    if (_isAuthed == value) return;
    _isAuthed = value;
    notifyListeners();
  }

  // ───────────────── NAME STATE ─────────────────

  void setRequiresName(bool value) {
    if (_requiresName == value) return;
    _requiresName = value;
    notifyListeners();
  }

  // ───────────────── BOOTSTRAP STATE ─────────────────

  void setBootstrapped(bool value) {
    if (_bootstrapped == value) return;
    _bootstrapped = value;
    notifyListeners();
  }

  // ───────────────── PUSH INIT (SAFE, ONE-TIME) ─────────────────

  /// Call from GoRouter builder / redirect AFTER auth
  void attachPushInit(BuildContext context) {
    if (_pushInitDone) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final push = context.read<PushController>();
    push.init(uid: user.uid);

    _pushInitDone = true;
  }

  // ───────────────── RESET (ON LOGOUT / TOKEN LOSS) ─────────────────

  void reset() {
    _isAuthed = false;
    _requiresName = false;
    _bootstrapped = false;
    _pushInitDone = false;
    notifyListeners();
  }
}
