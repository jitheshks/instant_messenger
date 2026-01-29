// lib/controller/settings_controller.dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/user_profile.dart';
import 'package:instant_messenger/services/local_cache.dart';
import 'package:instant_messenger/services/user_service.dart';

class SettingsController extends ChangeNotifier {
  SettingsController({
    FirebaseAuth? auth,
    UserService? userService,
  })  : _auth = auth ?? FirebaseAuth.instance,
        _user = userService ?? UserService(auth: auth);

  final FirebaseAuth _auth;
  final UserService _user;

  // Profile state
  String displayName = '';
  String bio = '';
  String phoneE164 = '';
  String? avatarUrl;

  // Preferences
  String appLanguage = "English (device's language)";

  // UI state
  bool loading = true;
  String? error;

  bool _started = false;
  StreamSubscription<UserProfile>? _sub;

  Future<void> start() async {
    if (_started) return;
    _started = true;

    // Cache-first paint
    await _loadFromCache();

    final uid = _auth.currentUser?.uid;
    if (uid == null) {
      loading = false;
      error = 'Not signed in';
      notifyListeners();
      return;
    }

    _sub?.cancel();
    _sub = _user.watchMe().listen((UserProfile p) {
      // Check if values actually changed
      final changed = displayName != p.displayName ||
          bio != p.bio ||
          avatarUrl != p.avatarUrl ||
          phoneE164 != p.phoneE164;

      // Update state
      displayName = p.displayName;
      bio = p.bio;
      avatarUrl = p.avatarUrl;
      phoneE164 = p.phoneE164;

      // Write cache only if changed (debounce)
      if (changed) {
        LocalCache.setProfile(
          displayName: displayName,
          bio: bio,
          avatarUrl: avatarUrl,
          phoneE164: phoneE164,
        );
      }

      loading = false;
      error = null;
      notifyListeners();
    }, onError: (e, st) {
      if (kDebugMode) debugPrintStack(stackTrace: st);
      loading = false;
      error = e.toString();
      notifyListeners();
    });
  }

  Future<void> _loadFromCache() async {
    final dn = LocalCache.displayName ?? '';
    final b = LocalCache.bio ?? '';
    final av = LocalCache.avatarUrl;
    final ph = LocalCache.phoneE164 ?? '';

    if (dn.isNotEmpty ||
        b.isNotEmpty ||
        (av != null && av.isNotEmpty) ||
        ph.isNotEmpty) {
      displayName = dn;
      bio = b;
      avatarUrl = av;
      phoneE164 = ph;
      loading = false;
      notifyListeners();
    }
  }

  // Setters for mirroring from ProfileController (optional)
  void setDisplayName(String name) {
    if (displayName == name) return;
    displayName = name;
    notifyListeners();
  }

  void setBio(String value) {
    if (bio == value) return;
    bio = value;
    notifyListeners();
  }

  void setAvatarUrl(String? url) {
    if (avatarUrl == url) return;
    avatarUrl = url;
    notifyListeners();
  }

  void setPhoneE164(String phone) {
    if (phoneE164 == phone) return;
    phoneE164 = phone;
    notifyListeners();
  }

  void setAppLanguage(String lang) {
    if (appLanguage == lang) return;
    appLanguage = lang;
    notifyListeners();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
