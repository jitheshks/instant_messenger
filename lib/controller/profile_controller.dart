import 'dart:async';
import 'package:cross_file/cross_file.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:instant_messenger/services/uploads/upload_orchestrator.dart';

import 'settings_controller.dart';
import 'package:instant_messenger/services/user_service.dart';

class ProfileController extends ChangeNotifier {
  ProfileController({
    FirebaseAuth? auth,
    required SettingsController settings,
    UserService? userService,
      required UploadOrchestrator uploadOrchestrator,
  })  : _auth = auth ?? FirebaseAuth.instance,
        _settings = settings,
        _userService = userService ?? UserService(auth: auth),_uploadOrchestrator = uploadOrchestrator;

  // ------------------------------------------------------------
  // DEPENDENCIES
  // ------------------------------------------------------------
  final FirebaseAuth _auth;
  final SettingsController _settings;
  final UserService _userService;
  final UploadOrchestrator _uploadOrchestrator;



  // ------------------------------------------------------------
  // UI STATE
  // ------------------------------------------------------------
  String displayName = '';
  String about = '';
  String phoneE164 = '';
  String? avatarUrl;
  List<String> links = [];

  bool loading = true;

  // ------------------------------------------------------------
  // PUBLIC STATE (for UI)
  // ------------------------------------------------------------
  bool get hasStarted => _started;
  bool get isUploadingAvatar => _uploadingAvatar;


  // ------------------------------------------------------------
  // INTERNAL STATE
  // ------------------------------------------------------------
  bool _started = false;
  bool _starting = false;
  bool _uploadingAvatar = false;
  bool _disposed = false;

  String? error;

  // ------------------------------------------------------------
  // START (BOOTSTRAP)
  // ------------------------------------------------------------
  Future<void> start() async {
    if (_started || _starting) return;
    _starting = true;

    final uid = _auth.currentUser?.uid;
    if (uid == null) {
      loading = false;
      error = 'Not signed in';
      _starting = false;
      if (!_disposed) notifyListeners();
      return;
    }

    _syncFromSettings();
    _settings.addListener(_syncFromSettings);

    loading = false;
    _started = true;
    _starting = false;

    if (!_disposed) notifyListeners();
  }

  // ------------------------------------------------------------
  // SETTINGS → UI SYNC
  // ------------------------------------------------------------
  void _syncFromSettings() {
    final changed =
        displayName != _settings.displayName ||
        about != _settings.bio ||
        avatarUrl != _settings.avatarUrl ||
        phoneE164 != _settings.phoneE164;

    if (!changed) return;

    displayName = _settings.displayName;
    about = _settings.bio;
    avatarUrl = _settings.avatarUrl;
    phoneE164 = _settings.phoneE164;

    if (!_disposed) notifyListeners();
  }

  // ------------------------------------------------------------
  // PROFILE UPDATES
  // ------------------------------------------------------------
  Future<void> updateName(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    await _userService.updateName(trimmed);
  }

  Future<void> updateAbout(String value) async {
    await _userService.updateBio(value.trim());
  }

  Future<void> addLink(String url) async {
    await _userService.addLink(url);
    links = [...links, url];
    if (!_disposed) notifyListeners();
  }

  Future<void> removeLink(String url) async {
    await _userService.removeLink(url);
    links.remove(url);
    if (!_disposed) notifyListeners();
  }

Future<void> updateAvatarFromFile(XFile file) async {
  if (_disposed || _uploadingAvatar) return;

  final uid = _auth.currentUser?.uid;
  if (uid == null) return;

  _uploadingAvatar = true;
  error = null;

  // 1️⃣ Optimistic preview
  avatarUrl = file.path;
  if (!_disposed) notifyListeners();

  try {
    // 2️⃣ Foreground upload
    final url = await _uploadOrchestrator.uploadAvatar(
      ownerType: 'user',
      ownerId: uid,
      filePath: file.path,
    );

    // 3️⃣ Persist
    await _userService.updateAvatar(url);

    // 4️⃣ Final UI update
    avatarUrl = url;
    if (!_disposed) notifyListeners();

    debugPrint('[Profile] avatar updated successfully');
  } catch (e) {
    // 🔁 Revert preview
    avatarUrl = _settings.avatarUrl;

    error = 'Avatar upload failed. Will retry automatically.';
    if (!_disposed) notifyListeners();

    debugPrint('[Profile] avatar upload failed → retry scheduled');
  } finally {
    _uploadingAvatar = false;
  }
}

  // ------------------------------------------------------------
  // DISPOSE
  // ------------------------------------------------------------
  @override
  void dispose() {
    _disposed = true;
    _settings.removeListener(_syncFromSettings);
    super.dispose();
  }
}
