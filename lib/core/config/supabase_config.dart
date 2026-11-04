import 'package:flutter/foundation.dart';
import 'package:instant_messenger/core/config/app_config.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Supported backend targets for Instant Messenger.
enum BackendTarget {
  /// Hosted Supabase PostgreSQL, Auth, Realtime, and Storage.
  supabase,
}

/// Central configuration manager for Supabase backend initialization.
class SupabaseConfig {
  static BackendTarget _activeTarget = BackendTarget.supabase;
  static bool _isInitialized = false;
  static String? _configuredUrl;

  /// The active backend target (always [BackendTarget.supabase]).
  static BackendTarget get activeTarget => _activeTarget;

  /// Transitional getter indicating whether Supabase is the active backend.
  ///
  /// Deprecated: Supabase is now the only backend. This getter should be
  /// removed and all callers simplified directly in subsequent steps.
  @Deprecated(
    'Supabase is the only backend. Simplify callers directly in Step 2B+.',
  )
  static bool get isSupabaseTarget => _activeTarget == BackendTarget.supabase;

  /// Returns the current authenticated user's ID according to the active backend.
  static String? get currentUserId {
    try {
      return Supabase.instance.client.auth.currentUser?.id;
    } catch (_) {
      return null;
    }
  }

  /// The active [SupabaseClient] instance.
  static SupabaseClient get client => Supabase.instance.client;

  /// Whether the Supabase client SDK has successfully initialized.
  static bool get isInitialized => _isInitialized;

  /// The configured Supabase project URL, or null if unconfigured.
  static String? get configuredUrl => _configuredUrl;

  /// Initializes Supabase using [AppConfig].
  ///
  /// Throws a [StateError] if required credentials are missing,
  /// or a [FormatException] if the configured URL format is invalid.
  static Future<void> initialize([AppConfig? customConfig]) async {
    if (customConfig == null && !AppConfig.isInitialized) {
      await AppConfig.initialize();
    }
    final config = customConfig ?? AppConfig.current;

    try {
      config.validate();
    } catch (_) {
      _isInitialized = false;
      _configuredUrl = null;
      rethrow;
    }

    final url = config.supabaseUrl.trim();
    final anonKey = config.supabasePublishableKey.trim();

    _activeTarget = BackendTarget.supabase;

    try {
      await _initializeClient(url: url, anonKey: anonKey);
      _configuredUrl = url;
      _isInitialized = true;
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('supabase_url', url);
        await prefs.setString('supabase_anon_key', anonKey);
      } catch (_) {}
      debugPrint(
        '[SupabaseConfig] Supabase initialized successfully (Target: $url)',
      );
    } catch (e) {
      _isInitialized = false;
      _configuredUrl = null;
      debugPrint('[SupabaseConfig] Failed to initialize Supabase client: $e');
      rethrow;
    }
  }

  /// Hook to initialize the Supabase client SDK. Defaults to [Supabase.initialize].
  static Future<void> Function({required String url, required String anonKey})
  _initializeClient = ({required String url, required String anonKey}) =>
      Supabase.initialize(url: url, publishableKey: anonKey);

  /// Sets a custom client initializer for unit test isolation.
  @visibleForTesting
  static void setInitializerForTesting(
    Future<void> Function({required String url, required String anonKey})?
    initializer,
  ) {
    _initializeClient =
        initializer ??
        (({required String url, required String anonKey}) =>
            Supabase.initialize(url: url, publishableKey: anonKey));
  }

  /// Manually set target state for testing purposes.
  @visibleForTesting
  static void setTargetForTesting(
    BackendTarget target, {
    bool initialized = false,
    String? configuredUrl,
  }) {
    _activeTarget = target;
    _isInitialized = initialized;
    _configuredUrl = configuredUrl;
  }

  /// Resets internal state for unit test isolation.
  @visibleForTesting
  static void resetForTesting() {
    _activeTarget = BackendTarget.supabase;
    _isInitialized = false;
    _configuredUrl = null;
    _initializeClient = ({required String url, required String anonKey}) =>
        Supabase.initialize(url: url, publishableKey: anonKey);
  }
}
