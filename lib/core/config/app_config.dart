import 'dart:io' show File;

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Central immutable application configuration model for Instant Messenger.
///
/// Flow: Root .env -> AppConfig.initialize() -> AppConfig.current -> SupabaseConfig / PushController
@immutable
class AppConfig {
  /// The base HTTP/HTTPS URL for the Supabase backend.
  final String supabaseUrl;

  /// The public API key used for anonymous/authenticated requests to Supabase.
  ///
  /// Protected by Row-Level Security (RLS) on PostgreSQL.
  final String supabasePublishableKey;

  /// The public application identifier for the OneSignal push notification SDK.
  final String oneSignalAppId;

  const AppConfig({
    required this.supabaseUrl,
    required this.supabasePublishableKey,
    this.oneSignalAppId = '',
  });

  /// Compile-time configuration populated via `--dart-define` or `--dart-define-from-file`.
  ///
  /// Fallbacks:
  /// - `SUPABASE_PUBLISHABLE_KEY` falls back to legacy `SUPABASE_ANON_KEY` if omitted.
  static const AppConfig fromEnvironment = AppConfig(
    supabaseUrl: String.fromEnvironment('SUPABASE_URL'),
    supabasePublishableKey: String.fromEnvironment(
      'SUPABASE_PUBLISHABLE_KEY',
      defaultValue: String.fromEnvironment('SUPABASE_ANON_KEY'),
    ),
    oneSignalAppId: String.fromEnvironment('ONESIGNAL_APP_ID'),
  );

  /// Constructs an [AppConfig] from a key-value map (e.g. from `.env` or parsed config).
  ///
  /// Supports fallback to `SUPABASE_ANON_KEY` if `SUPABASE_PUBLISHABLE_KEY` is not present.
  factory AppConfig.fromMap(Map<String, String> map) {
    final rawUrl = map['SUPABASE_URL']?.trim() ?? '';
    final rawKey =
        map['SUPABASE_PUBLISHABLE_KEY']?.trim() ??
        map['SUPABASE_ANON_KEY']?.trim() ??
        '';
    final rawOneSignal = map['ONESIGNAL_APP_ID']?.trim() ?? '';

    return AppConfig(
      supabaseUrl: rawUrl,
      supabasePublishableKey: rawKey,
      oneSignalAppId: rawOneSignal,
    );
  }

  static AppConfig? _testOverride;
  static AppConfig? _runtimeConfig;

  /// Whether an explicit testing override is currently active.
  static bool get hasTestOverride => _testOverride != null;

  /// Whether runtime configuration or test override has been initialized.
  static bool get isInitialized =>
      _testOverride != null || _runtimeConfig != null;

  /// The currently active configuration.
  ///
  /// Precedence:
  /// 1. [overrideForTesting] (explicit unit/widget test override)
  /// 2. [_runtimeConfig] (loaded via [initialize] from `.env`)
  /// 3. [fromEnvironment] (compile-time defines)
  static AppConfig get current =>
      _testOverride ?? _runtimeConfig ?? fromEnvironment;

  /// Central runtime configuration loader.
  ///
  /// Loads `.env` via [flutter_dotenv] (with fallback to local filesystem on desktop/tests
  /// or compile-time defines if present), populates [current], and validates presence
  /// and format of required keys.
  static Future<AppConfig> initialize({
    String fileName = '.env',
    DotEnv? customDotEnv,
    Map<String, String>? customMap,
  }) async {
    if (_testOverride != null) {
      _testOverride!.validate();
      return _testOverride!;
    }

    if (customMap != null) {
      final config = AppConfig.fromMap(customMap);
      config.validate();
      _runtimeConfig = config;
      return config;
    }

    final activeDotEnv = customDotEnv ?? dotenv;
    bool loaded = false;

    // 1. Try loading via flutter_dotenv (asset bundle on mobile/web/desktop)
    try {
      if (!activeDotEnv.isInitialized) {
        await activeDotEnv.load(fileName: fileName);
      }
      loaded = activeDotEnv.isInitialized && activeDotEnv.env.isNotEmpty;
    } catch (_) {
      // Asset not found or not in bundle
    }

    // 2. If not loaded via asset, try reading directly from local filesystem (desktop / test runner)
    if (!loaded && !kIsWeb) {
      try {
        final file = File(fileName);
        if (file.existsSync()) {
          final content = file.readAsStringSync();
          if (content.trim().isNotEmpty) {
            activeDotEnv.loadFromString(envString: content);
            loaded = activeDotEnv.isInitialized && activeDotEnv.env.isNotEmpty;
          }
        }
      } catch (_) {
        // Filesystem access restricted or file not found
      }
    }

    // 3. Populate runtime config
    if (loaded) {
      _runtimeConfig = AppConfig.fromMap(activeDotEnv.env);
    } else if (fromEnvironment.hasAnySupabaseConfig) {
      _runtimeConfig = fromEnvironment;
    }

    final config = current;
    config.validate();
    return config;
  }

  /// Whether required Supabase credentials are present.
  bool get isConfigured =>
      supabaseUrl.trim().isNotEmpty && supabasePublishableKey.trim().isNotEmpty;

  /// Whether any Supabase configuration parameter was provided.
  bool get hasAnySupabaseConfig =>
      supabaseUrl.trim().isNotEmpty || supabasePublishableKey.trim().isNotEmpty;

  /// Validates format and presence of required backend configuration.
  ///
  /// Throws a [StateError] if required credentials are missing, or a [FormatException]
  /// if [supabaseUrl] is not a valid HTTP/HTTPS URL with a non-empty host.
  ///
  /// Note: Sensitive credential values and raw URLs are never included in error messages or logs.
  void validate() {
    final trimmedUrl = supabaseUrl.trim();
    final trimmedKey = supabasePublishableKey.trim();

    if (trimmedUrl.isEmpty || trimmedKey.isEmpty) {
      throw StateError(
        'Missing required Supabase environment configuration. '
        'SUPABASE_URL and SUPABASE_PUBLISHABLE_KEY (or SUPABASE_ANON_KEY) must be provided in .env.',
      );
    }

    final uri = Uri.tryParse(trimmedUrl);
    final isHttpOrHttps =
        uri != null && (uri.scheme == 'http' || uri.scheme == 'https');
    final hasValidHost = uri != null && uri.host.isNotEmpty;

    if (uri == null || !isHttpOrHttps || !hasValidHost) {
      throw const FormatException(
        'Invalid Supabase URL format. A valid HTTP or HTTPS URL with a non-empty host is required.',
      );
    }
  }

  /// Sets an explicit configuration override for unit and widget tests.
  ///
  /// Pass `null` to clear the override and restore default resolution.
  @visibleForTesting
  static void overrideForTesting(AppConfig? config) {
    _testOverride = config;
  }

  /// Resets internal runtime configuration state for unit test isolation.
  @visibleForTesting
  static void resetForTesting() {
    _testOverride = null;
    _runtimeConfig = null;
  }
}
