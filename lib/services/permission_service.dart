import 'dart:io';
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';

/// PermissionService
///
/// Design principles:
/// - Never trigger multiple permission dialogs together
/// - Reusable single-permission helpers (ensureCamera, ensureContacts, etc.)
/// - ONE safe sequential flow for first login
///
/// This matches WhatsApp / Telegram permission behavior.
class PermissionService {
  /// Global guard to prevent overlapping permission dialogs
  static bool _requestInProgress = false;

  /// Internal guard wrapper
  static Future<bool> _runGuarded(Future<bool> Function() action) async {
    if (_requestInProgress) {
      debugPrint('[Perms] request already in progress → skipping');
      return false;
    }

    _requestInProgress = true;
    try {
      return await action();
    } finally {
      _requestInProgress = false;
    }
  }

  // ---------------------------------------------------------------------------
  // INDIVIDUAL PERMISSION METHODS (REUSABLE ANYWHERE)
  // ---------------------------------------------------------------------------

  /// Photos / Storage (Android + iOS aware)
  static Future<bool> ensurePhotoRead() {
    return _runGuarded(() async {
      if (Platform.isIOS) {
        final st = await Permission.photos.request();
        if (st.isPermanentlyDenied) await openAppSettings();
        debugPrint('[Perms] photos status=$st');
        return st.isGranted || st.isLimited;
      }

      final sdk = (await DeviceInfoPlugin().androidInfo).version.sdkInt;

      // Android 13+
      if (sdk >= 33) {
        final st = await Permission.photos.request(); // READ_MEDIA_*
        debugPrint('[Perms] photos(READ_MEDIA_*) status=$st');
        return st.isGranted || st.isLimited;
      }

      // Android <= 12
      final st = await Permission.storage.request();
      debugPrint('[Perms] storage status=$st');
      return st.isGranted;
    });
  }

  /// Camera
  static Future<bool> ensureCamera() {
    return _runGuarded(() async {
      final st = await Permission.camera.request();
      if (st.isPermanentlyDenied) await openAppSettings();
      debugPrint('[Perms] camera status=$st');
      return st.isGranted;
    });
  }

  /// Microphone
  static Future<bool> ensureMicrophone() {
    return _runGuarded(() async {
      final st = await Permission.microphone.request();
      if (st.isPermanentlyDenied) await openAppSettings();
      debugPrint('[Perms] microphone status=$st');
      return st.isGranted;
    });
  }

  /// Location (optional)
  static Future<bool> ensureLocationWhenInUse() {
    return _runGuarded(() async {
      final st = await Permission.locationWhenInUse.request();
      if (st.isPermanentlyDenied) await openAppSettings();
      debugPrint('[Perms] location status=$st');
      return st.isGranted;
    });
  }

  /// Contacts (critical for chat apps)
  static Future<bool> ensureContacts() {
    return _runGuarded(() async {
      final st = await Permission.contacts.request();
      if (st.isPermanentlyDenied) await openAppSettings();
      debugPrint('[Perms] contacts status=$st');
      return st.isGranted;
    });
  }

  /// Notifications
  static Future<bool> ensureNotifications() {
    return _runGuarded(() async {
      final st = await Permission.notification.request();
      if (st.isPermanentlyDenied) await openAppSettings();
      debugPrint('[Perms] notifications status=$st');
      return st.isGranted;
    });
  }

  // ---------------------------------------------------------------------------
  // 🔥 SAFE SEQUENTIAL FIRST-LOGIN FLOW (USE THIS ONLY)
  // ---------------------------------------------------------------------------

  /// Requests permissions one-by-one with delays.
  ///
  /// Call this ONCE after OTP success / login.
  /// Contacts permission is GUARANTEED to show if included.
  static Future<bool> requestFirstLoginPermissions({
    bool includeContacts = false,
    bool includeMicrophone = false,
    bool includeLocation = false,
  }) async {
    bool ok = true;

    // 🔔 Notifications
    ok &= await ensureNotifications();
    await Future.delayed(const Duration(milliseconds: 300));

    // 🖼️ Photos / Storage
    ok &= await ensurePhotoRead();
    await Future.delayed(const Duration(milliseconds: 300));

    // 📷 Camera
    ok &= await ensureCamera();
    await Future.delayed(const Duration(milliseconds: 300));

    // 👥 Contacts
    if (includeContacts) {
      ok &= await ensureContacts();
      await Future.delayed(const Duration(milliseconds: 300));
    }

    // 🎙️ Optional
    if (includeMicrophone) {
      ok &= await ensureMicrophone();
      await Future.delayed(const Duration(milliseconds: 300));
    }

    // 📍 Optional
    if (includeLocation) {
      ok &= await ensureLocationWhenInUse();
    }

    debugPrint('[Perms] first-login SEQUENTIAL -> ok=$ok');
    return ok;
  }
}
