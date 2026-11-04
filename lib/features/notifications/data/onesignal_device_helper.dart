import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:instant_messenger/core/utils/app_info_service.dart';

/// Helper utilities for OneSignal push subscription validation, platform normalization,
/// device telemetry collection, and database payload generation.
class OneSignalDeviceHelper {
  /// Checks whether an identifier is a valid OneSignal push subscription ID.
  /// OneSignal v5 subscription IDs are 36-character RFC-4122 UUIDs.
  /// Rejects null, empty, whitespace, non-UUID identifiers, colons, or FCM tokens.
  static bool isValidSubscriptionId(String? id) {
    if (id == null) return false;
    final trimmed = id.trim();
    if (trimmed.isEmpty) return false;
    return RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
      caseSensitive: false,
    ).hasMatch(trimmed);
  }

  /// Checks whether push notifications are supported on the target platform.
  /// OneSignal Flutter officially supports Android and iOS (and Web when configured).
  /// Desktop platforms (Linux, macOS, Windows) and unknown targets are unsupported.
  static bool isSupportedPlatform({
    TargetPlatform? targetPlatform,
    bool isWeb = kIsWeb,
  }) {
    if (isWeb) return true;
    final tp = targetPlatform ?? defaultTargetPlatform;
    return tp == TargetPlatform.android || tp == TargetPlatform.iOS;
  }

  /// Normalizes a platform string to match the PostgreSQL constraint:
  /// `check (platform in ('android', 'ios', 'web'))`.
  /// Returns `null` for unsupported, unknown, or null platforms.
  static String? normalizePlatform(String? rawPlatform) {
    if (rawPlatform == null) return null;
    final normalized = rawPlatform.trim().toLowerCase();
    if (normalized == 'android') return 'android';
    if (normalized == 'ios') return 'ios';
    if (normalized == 'web') return 'web';
    return null;
  }

  /// Computes the subscription state from OneSignal SDK properties.
  ///
  /// Returns `false` if the user has opted out (`optedIn == false`)
  /// or if notification permissions were denied (`permission == false`).
  static bool computeSubscribed({
    required bool? optedIn,
    required bool? permission,
  }) {
    if (optedIn == false) return false;
    if (permission == false) return false;
    // User is considered subscribed only if explicitly opted in and permission is not denied
    return optedIn == true && (permission == true || permission == null);
  }

  /// Builds the canonical registration payload for `user_devices`.
  ///
  /// Contract:
  /// - `user_id`: String (UUID)
  /// - `player_id`: String
  /// - `platform`: 'android' | 'ios' | 'web'
  /// - `app_version`: String?
  /// - `subscribed`: bool
  /// - `last_seen`: ISO-8601 UTC string
  static Map<String, dynamic> buildDevicePayload({
    required String uid,
    required String playerId,
    required String platform,
    required String? appVersion,
    required bool subscribed,
    DateTime? timestamp,
  }) {
    final normalized = normalizePlatform(platform);
    if (normalized == null) {
      throw ArgumentError(
        'Platform "$platform" is unsupported. Must be android, ios, or web.',
      );
    }
    final now = (timestamp ?? DateTime.now()).toUtc();
    return {
      'user_id': uid,
      'player_id': playerId,
      'platform': normalized,
      if (appVersion != null && appVersion.trim().isNotEmpty)
        'app_version': appVersion.trim(),
      'subscribed': subscribed,
      'last_seen': now.toIso8601String(),
    };
  }

  /// Collects platform and device information for telemetry and device records.
  static Future<Map<String, dynamic>> collectDeviceInfo(
    AppInfoService appInfo,
  ) async {
    final versionPlusBuild = await appInfo.versionPlusBuild();
    final dev = DeviceInfoPlugin();

    String platform = 'android';
    String model = 'unknown';
    String osVersion = 'unknown';
    String sdkVersion = 'unknown';

    if (kIsWeb) {
      platform = 'web';
      model = 'browser';
      osVersion = 'browser';
      sdkVersion = 'unknown';
    } else {
      switch (defaultTargetPlatform) {
        case TargetPlatform.android:
          platform = 'android';
          try {
            final a = await dev.androidInfo;
            model = '${a.manufacturer} ${a.model}'.trim();
            final rel = a.version.release;
            final sdkInt = a.version.sdkInt;
            osVersion = 'Android $rel (SDK ${sdkInt.toString()})';
            sdkVersion = sdkInt.toString();
          } catch (_) {
            model = 'android';
            osVersion = 'Android unknown';
            sdkVersion = 'unknown';
          }
          break;

        case TargetPlatform.iOS:
          platform = 'ios';
          try {
            final i = await dev.iosInfo;
            model = i.utsname.machine;
            osVersion = 'iOS ${i.systemVersion}';
            sdkVersion = i.systemVersion;
          } catch (_) {
            model = 'iphone';
            osVersion = 'iOS unknown';
            sdkVersion = 'unknown';
          }
          break;

        case TargetPlatform.linux:
          platform = 'linux';
          model = 'linux-desktop';
          osVersion = 'Linux';
          break;

        case TargetPlatform.macOS:
          platform = 'macos';
          model = 'mac-desktop';
          osVersion = 'macOS';
          break;

        case TargetPlatform.windows:
          platform = 'windows';
          model = 'windows-desktop';
          osVersion = 'Windows';
          break;

        default:
          platform = 'unknown';
          model = 'device';
      }
    }

    return {
      'platform': platform,
      'model': model,
      'os_version': osVersion,
      'sdk_version': sdkVersion,
      'app_version': versionPlusBuild,
    };
  }
}
