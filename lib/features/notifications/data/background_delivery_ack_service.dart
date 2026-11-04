import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io' show SocketException;

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:instant_messenger/core/config/app_config.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Service responsible for executing authenticated delivery receipt
/// acknowledgements from background Dart isolates (e.g. FCM background handler).
///
/// Context & Architecture:
/// - In background isolates, the foreground Supabase singleton is not initialized.
/// - Rather than instantiating the heavy `SupabaseClient` (which spawns realtime
///   connection managers, auth listeners, and timer loops), this service uses a
///   lightweight, authenticated HTTP POST directly to the PostgREST RPC:
///   `public.acknowledge_delivery_token(p_message_id, p_receipt_token)`.
/// - Mirrors the proven native pattern from `InstantMessengerNotificationExtension.kt`.
/// - Restores session context deterministically from [SharedPreferences] and safely
///   defers expired tokens to foreground catch-up sync without cross-isolate token rotation.
/// - Bounded 5-second network timeout ensures the background execution window is respected.
/// - Monotonic forward-only status progression (`status < 2 -> status = 2`) is
///   strictly enforced by the database RPC and cannot downgrade read messages.
class BackgroundDeliveryAckService {
  BackgroundDeliveryAckService._();

  static const String tag = 'BackgroundDeliveryAck';
  static const int connectTimeoutSeconds = 5;
  static const int maxRecentAcks = 200;

  /// UUID validation pattern for message IDs.
  static final RegExp uuidRegex = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
    caseSensitive: false,
  );

  /// In-memory LRU deduplication set of recently processed message IDs.
  static final LinkedHashSet<String> _recentAcks = LinkedHashSet<String>();

  @visibleForTesting
  static void clearRecentAcksForTesting() {
    _recentAcks.clear();
  }

  @visibleForTesting
  static Set<String> get recentAcksForTesting => Set.unmodifiable(_recentAcks);

  /// Records an acknowledged message ID into the deduplication cache.
  static void _recordAck(String messageId) {
    if (_recentAcks.contains(messageId)) {
      _recentAcks.remove(messageId);
    }
    _recentAcks.add(messageId);
    if (_recentAcks.length > maxRecentAcks) {
      _recentAcks.remove(_recentAcks.first);
    }
  }

  /// Acknowledges delivery of a message parsed from a Firebase [RemoteMessage].
  static Future<bool> acknowledgeFromRemoteMessage(
    RemoteMessage message, {
    http.Client? httpClient,
    SharedPreferences? preferences,
    DateTime Function()? clock,
  }) async {
    return acknowledgeFromPayload(
      message.data,
      httpClient: httpClient,
      preferences: preferences,
      clock: clock,
    );
  }

  /// Acknowledges delivery from a raw push data map.
  ///
  /// Extracts:
  /// - `messageId` or `message_id`
  /// - `receiptToken` or `receipt_token`
  /// - `recipientId` or `recipient_id` (optional recipient validation)
  static Future<bool> acknowledgeFromPayload(
    Map<dynamic, dynamic>? data, {
    http.Client? httpClient,
    SharedPreferences? preferences,
    DateTime Function()? clock,
  }) async {
    if (data == null || data.isEmpty) {
      if (kDebugMode) {
        debugPrint('[$tag] Push data is null or empty; skipping delivery ack.');
      }
      return false;
    }

    final rawMsgId = data['messageId'] ?? data['message_id'];
    final messageId = rawMsgId?.toString().trim();

    final rawReceiptToken = data['receiptToken'] ?? data['receipt_token'];
    final receiptToken = rawReceiptToken?.toString().trim();

    final rawRecipientId = data['recipientId'] ?? data['recipient_id'];
    final recipientId = rawRecipientId?.toString().trim();

    if (messageId == null || messageId.isEmpty) {
      if (kDebugMode) {
        debugPrint('[$tag] Missing messageId in payload; skipping delivery ack.');
      }
      return false;
    }

    if (!uuidRegex.hasMatch(messageId)) {
      if (kDebugMode) {
        debugPrint('[$tag] Malformed messageId "$messageId"; skipping delivery ack.');
      }
      return false;
    }

    if (receiptToken == null || receiptToken.isEmpty) {
      if (kDebugMode) {
        debugPrint('[$tag] Missing receiptToken in payload; skipping delivery ack.');
      }
      return false;
    }

    return acknowledgeDelivery(
      messageId: messageId,
      receiptToken: receiptToken,
      expectedRecipientId: recipientId,
      httpClient: httpClient,
      preferences: preferences,
      clock: clock,
    );
  }

  /// Dispatches an authenticated HTTP POST directly to the Supabase RPC
  /// `public.acknowledge_delivery_token(p_message_id, p_receipt_token)`.
  ///
  /// Returns `true` if the delivery was confirmed or already processed,
  /// or `false` if skipped, unauthorized, or network failed.
  static Future<bool> acknowledgeDelivery({
    required String messageId,
    required String receiptToken,
    String? expectedRecipientId,
    http.Client? httpClient,
    SharedPreferences? preferences,
    DateTime Function()? clock,
  }) async {
    final cleanMsgId = messageId.trim();
    final cleanToken = receiptToken.trim();

    if (!uuidRegex.hasMatch(cleanMsgId) || cleanToken.isEmpty) {
      return false;
    }

    // 1. Deduplication check
    if (_recentAcks.contains(cleanMsgId)) {
      if (kDebugMode) {
        debugPrint('[$tag] Message $cleanMsgId already acknowledged; skipping duplicate.');
      }
      return true;
    }

    final client = httpClient ?? http.Client();
    final shouldCloseClient = httpClient == null;

    try {
      final prefs = preferences ?? await SharedPreferences.getInstance();

      // 2. Resolve Supabase project URL and anon/publishable key
      final url = _resolveSupabaseUrl(prefs);
      final anonKey = _resolveAnonKey(prefs);

      if (url == null || url.isEmpty || anonKey == null || anonKey.isEmpty) {
        debugPrint('[$tag] Supabase URL or Anon Key not found; skipping delivery ack.');
        return false;
      }

      // 3. Resolve authenticated user session
      final sessionData = _resolveSession(prefs, url);
      if (sessionData == null) {
        debugPrint('[$tag] Recipient is logged out (no session found); skipping delivery ack.');
        return false;
      }

      final accessToken = (sessionData['access_token'] as String?)?.trim();
      final userObj = sessionData['user'] as Map<String, dynamic>?;
      final currentUserId = (userObj?['id'] as String?)?.trim();

      if (accessToken == null || accessToken.isEmpty || currentUserId == null || currentUserId.isEmpty) {
        debugPrint('[$tag] Recipient session missing accessToken or userId; skipping delivery ack.');
        return false;
      }

      // 4. Validate recipient identity matches current logged-in user
      if (expectedRecipientId != null && expectedRecipientId.isNotEmpty) {
        if (!expectedRecipientId.trim().toLowerCase().contains(currentUserId.toLowerCase()) &&
            expectedRecipientId.trim().toLowerCase() != currentUserId.toLowerCase()) {
          debugPrint(
            '[$tag] Recipient mismatch: push target=$expectedRecipientId, active user=$currentUserId; skipping.',
          );
          return false;
        }
      }

      // 5. Expiration check — strictly non-mutating
      final nowSeconds = ((clock?.call() ?? DateTime.now()).toUtc().millisecondsSinceEpoch) ~/ 1000;
      final expiresAt = (sessionData['expires_at'] as num?)?.toInt();
      final isExpired = expiresAt != null && expiresAt <= (nowSeconds + 30);

      if (isExpired) {
        debugPrint(
          '[$tag] Recipient session expired; skipping background delivery ack (deferred to foreground catch-up sync).',
        );
        return false;
      }

      // 6. Dispatch atomic RPC to Supabase
      final endpoint = Uri.parse('${url.replaceAll(RegExp(r'/+$'), '')}/rest/v1/rpc/acknowledge_delivery_token');
      final payload = jsonEncode({
        'p_message_id': cleanMsgId,
        'p_receipt_token': cleanToken,
      });

      final response = await client
          .post(
            endpoint,
            headers: {
              'Content-Type': 'application/json',
              'apikey': anonKey,
              'Authorization': 'Bearer $accessToken',
            },
            body: payload,
          )
          .timeout(const Duration(seconds: connectTimeoutSeconds));

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final bodyText = response.body.trim().toLowerCase();
        if (bodyText == 'true') {
          _recordAck(cleanMsgId);
          if (kDebugMode) {
            debugPrint('[$tag] ✅ Delivery ack confirmed for messageId=$cleanMsgId (HTTP ${response.statusCode})');
          }
          return true;
        } else {
          if (kDebugMode) {
            debugPrint(
              '[$tag] ℹ️ Delivery ack returned false for messageId=$cleanMsgId (token invalid, expired, or already consumed)',
            );
          }
          return false;
        }
      } else if (response.statusCode == 401 || response.statusCode == 403) {
        debugPrint('[$tag] ⚠️ Delivery ack unauthorized (HTTP ${response.statusCode})');
        return false;
      } else {
        debugPrint('[$tag] ⚠️ Delivery ack rejected (HTTP ${response.statusCode}): ${response.body}');
        return false;
      }
    } on TimeoutException {
      debugPrint('[$tag] Delivery ack for messageId=$cleanMsgId timed out after ${connectTimeoutSeconds}s; deferred to catch-up sync.');
      return false;
    } on SocketException catch (e) {
      debugPrint('[$tag] Delivery ack network error ($cleanMsgId): ${e.message}; deferred to catch-up sync.');
      return false;
    } on http.ClientException catch (e) {
      debugPrint('[$tag] Delivery ack HTTP client error ($cleanMsgId): ${e.message}; deferred to catch-up sync.');
      return false;
    } catch (e) {
      debugPrint('[$tag] Unexpected error awaiting delivery ack for messageId=$cleanMsgId: $e');
      return false;
    } finally {
      if (shouldCloseClient) {
        client.close();
      }
    }
  }

  /// Resolves the configured Supabase URL.
  static String? _resolveSupabaseUrl(SharedPreferences prefs) {
    final fromPrefs = prefs.getString('supabase_url') ?? prefs.getString('flutter.supabase_url');
    if (fromPrefs != null && fromPrefs.trim().isNotEmpty) {
      return fromPrefs.trim();
    }
    if (AppConfig.isInitialized && AppConfig.current.supabaseUrl.isNotEmpty) {
      return AppConfig.current.supabaseUrl.trim();
    }
    if (AppConfig.fromEnvironment.supabaseUrl.isNotEmpty) {
      return AppConfig.fromEnvironment.supabaseUrl.trim();
    }
    return null;
  }

  /// Resolves the configured Supabase public anon key.
  static String? _resolveAnonKey(SharedPreferences prefs) {
    final fromPrefs = prefs.getString('supabase_anon_key') ?? prefs.getString('flutter.supabase_anon_key');
    if (fromPrefs != null && fromPrefs.trim().isNotEmpty) {
      return fromPrefs.trim();
    }
    if (AppConfig.isInitialized && AppConfig.current.supabasePublishableKey.isNotEmpty) {
      return AppConfig.current.supabasePublishableKey.trim();
    }
    if (AppConfig.fromEnvironment.supabasePublishableKey.isNotEmpty) {
      return AppConfig.fromEnvironment.supabasePublishableKey.trim();
    }
    return null;
  }

  /// Locates and decodes the Supabase auth session deterministically from [SharedPreferences].
  ///
  /// Strictly derives the project-specific session key from [supabaseUrl]
  /// (`sb-$projectRef-auth-token`) to prevent selecting an arbitrary session
  /// from another Supabase project.
  static Map<String, dynamic>? _resolveSession(SharedPreferences prefs, String supabaseUrl) {
    final projectRef = Uri.tryParse(supabaseUrl)?.host.split('.').first;
    if (projectRef == null || projectRef.isEmpty) {
      return null;
    }

    final candidateKeys = <String>[
      'sb-$projectRef-auth-token',
      'flutter.sb-$projectRef-auth-token',
      'supabase.auth.token',
      'flutter.supabase.auth.token',
    ];

    for (final key in candidateKeys) {
      final raw = prefs.getString(key)?.trim();
      if (raw != null && raw.isNotEmpty) {
        try {
          final decoded = jsonDecode(raw);
          if (decoded is Map<String, dynamic>) {
            return decoded;
          }
        } catch (_) {}
      }
    }
    return null;
  }
}
