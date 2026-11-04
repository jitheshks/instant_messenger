import 'package:flutter/foundation.dart';
import 'package:instant_messenger/core/config/supabase_config.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Result status of a push notification dispatch attempt.
enum PushDispatchStatus {
  /// The push notification request was accepted by the provider for delivery.
  dispatched,

  /// Skipped safely without sending (e.g. duplicate, invalid UUID, unauthenticated caller).
  skipped,

  /// The server processed the request, but there were no eligible recipients or registered devices.
  noEligibleRecipients,

  /// The dispatch attempt failed due to a network error, HTTP rejection, or exception.
  failed,
}

/// Details of a push notification dispatch operation.
class PushDispatchResult {
  final PushDispatchStatus status;
  final String? message;
  final int? statusCode;
  final int? deliveredCount;
  final String? reason;

  const PushDispatchResult({
    required this.status,
    this.message,
    this.statusCode,
    this.deliveredCount,
    this.reason,
  });

  bool get isSuccess => status == PushDispatchStatus.dispatched;
  bool get hasDeliveredRecipients => (deliveredCount ?? 0) > 0;
}

/// Service that securely dispatches push notifications by invoking the Supabase
/// `send-push` Edge Function using the active user's authenticated session.
///
/// **Security & Integrity Constraints:**
/// - Never includes OneSignal REST API master keys or service-role secrets in client code.
/// - Requires an authenticated user JWT; does not bypass backend authorization.
/// - Validates RFC-4122 UUID format for `chat_id` and `message_id` before invocation.
/// - Sanitizes preview text (max 120 chars) and sender name (max 50 chars).
/// - Enforces message type whitelist: `{'text', 'media', 'call'}`.
/// - Guards against duplicate dispatches for the same `message_id` within a session.
/// - Fails safely: push failures are logged and never undo or alter a message that
///   was already persisted in the database.
class PushDispatchService {
  final SupabaseClient? _supabaseClient;
  final String? Function()? _currentUserIdProvider;
  final String? Function()? _currentUserNameProvider;
  final Future<FunctionResponse> Function(
    String functionName, {
    Map<String, dynamic>? body,
  })?
  _functionInvoker;

  static const int maxPreviewLength = 120;
  static const int maxSenderNameLength = 50;
  static const Set<String> allowedTypes = {'text', 'media', 'call'};
  static final RegExp uuidRegex = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
    caseSensitive: false,
  );

  /// In-memory bounded cache of message IDs for which push dispatch was executed or in flight.
  final Set<String> _dispatchedMessageIds = {};
  static const int _maxDispatchedCacheSize = 500;

  PushDispatchService({
    SupabaseClient? client,
    String? Function()? currentUserIdProvider,
    String? Function()? currentUserNameProvider,
    @visibleForTesting
    Future<FunctionResponse> Function(
      String functionName, {
      Map<String, dynamic>? body,
    })?
    functionInvoker,
  }) : _supabaseClient = client,
       _currentUserIdProvider = currentUserIdProvider,
       _currentUserNameProvider = currentUserNameProvider,
       _functionInvoker = functionInvoker;

  SupabaseClient get _supabase => _supabaseClient ?? Supabase.instance.client;

  /// Validates RFC-4122 UUID syntax.
  static bool isValidUuid(String? value) {
    if (value == null || value.trim().isEmpty) return false;
    return uuidRegex.hasMatch(value.trim());
  }

  /// Sanitizes preview text to max 120 characters without control character corruption.
  static String sanitizePreview(String? preview) {
    if (preview == null || preview.trim().isEmpty) return 'New message';
    final trimmed = preview.trim();
    return trimmed.length > maxPreviewLength
        ? trimmed.substring(0, maxPreviewLength)
        : trimmed;
  }

  /// Sanitizes message type to the permitted whitelist ('text', 'media', 'call').
  static String sanitizeType(String? type) {
    if (type != null && allowedTypes.contains(type.trim().toLowerCase())) {
      return type.trim().toLowerCase();
    }
    return 'text';
  }

  /// Sanitizes sender name to max 50 characters.
  static String sanitizeSenderName(String? name) {
    if (name == null || name.trim().isEmpty) return 'New message';
    final trimmed = name.trim();
    return trimmed.length > maxSenderNameLength
        ? trimmed.substring(0, maxSenderNameLength)
        : trimmed;
  }

  /// Builds the canonical request payload matching `supabase/functions/send-push/index.ts`.
  static Map<String, dynamic>? buildPayload({
    required String chatId,
    required String messageId,
    String? preview,
    String? type,
    String? senderName,
  }) {
    final cleanChatId = chatId.trim();
    final cleanMessageId = messageId.trim();

    if (!isValidUuid(cleanChatId) || !isValidUuid(cleanMessageId)) {
      return null;
    }

    return {
      'chat_id': cleanChatId,
      'message_id': cleanMessageId,
      'preview': sanitizePreview(preview),
      'type': sanitizeType(type),
      'sender_name': sanitizeSenderName(senderName),
    };
  }

  /// Whether a push dispatch for [messageId] was already processed during this session.
  bool isDispatched(String messageId) =>
      _dispatchedMessageIds.contains(messageId);

  void _markDispatched(String messageId) {
    if (_dispatchedMessageIds.length >= _maxDispatchedCacheSize) {
      _dispatchedMessageIds.remove(_dispatchedMessageIds.first);
    }
    _dispatchedMessageIds.add(messageId);
  }

  /// Dispatches push notification by invoking the `send-push` Edge Function.
  ///
  /// Matches the signature required by [PushController.serverSend].
  Future<PushDispatchResult> dispatch({
    required String chatId,
    required String senderId,
    required String preview,
    required String type,
    String? messageId,
    String? senderName,
  }) async {
    // 1. Validate required identifiers
    if (messageId == null || messageId.trim().isEmpty) {
      if (kDebugMode) {
        debugPrint(
          '[PushDispatchService] Skip: messageId is required but was null or empty.',
        );
      }
      return const PushDispatchResult(
        status: PushDispatchStatus.skipped,
        message: 'Missing required messageId',
      );
    }

    final cleanMessageId = messageId.trim();
    final cleanChatId = chatId.trim();

    // 2. Validate UUID formats
    if (!isValidUuid(cleanChatId)) {
      if (kDebugMode) {
        debugPrint(
          '[PushDispatchService] Skip: invalid UUID chatId "$chatId".',
        );
      }
      return const PushDispatchResult(
        status: PushDispatchStatus.skipped,
        message: 'Invalid UUID chatId',
      );
    }

    if (!isValidUuid(cleanMessageId)) {
      if (kDebugMode) {
        debugPrint(
          '[PushDispatchService] Skip: invalid UUID messageId "$cleanMessageId".',
        );
      }
      return const PushDispatchResult(
        status: PushDispatchStatus.skipped,
        message: 'Invalid UUID messageId',
      );
    }

    // 3. Prevent duplicate dispatch within current session
    if (_dispatchedMessageIds.contains(cleanMessageId)) {
      if (kDebugMode) {
        debugPrint(
          '[PushDispatchService] Skip: push for message $cleanMessageId was already dispatched.',
        );
      }
      return const PushDispatchResult(
        status: PushDispatchStatus.skipped,
        message: 'Duplicate dispatch prevented',
      );
    }

    // 4. Verify authenticated caller
    final currentUid =
        _currentUserIdProvider?.call() ??
        _supabaseClient?.auth.currentUser?.id ??
        SupabaseConfig.currentUserId;
    if (currentUid == null || currentUid.isEmpty) {
      if (kDebugMode) {
        debugPrint(
          '[PushDispatchService] Skip: caller is not authenticated; cannot invoke send-push.',
        );
      }
      return const PushDispatchResult(
        status: PushDispatchStatus.skipped,
        message: 'Unauthenticated caller',
      );
    }

    if (senderId.trim().isNotEmpty && senderId.trim() != currentUid) {
      if (kDebugMode) {
        debugPrint(
          '[PushDispatchService] Skip: senderId ($senderId) does not match authenticated user ($currentUid).',
        );
      }
      return const PushDispatchResult(
        status: PushDispatchStatus.skipped,
        message: 'Sender ID mismatch',
      );
    }

    // 5. Build sanitized payload
    final effectiveSenderName = senderName?.trim().isNotEmpty == true
        ? senderName
        : _currentUserNameProvider?.call();

    final payload = buildPayload(
      chatId: cleanChatId,
      messageId: cleanMessageId,
      preview: preview,
      type: type,
      senderName: effectiveSenderName,
    );

    if (payload == null) {
      return const PushDispatchResult(
        status: PushDispatchStatus.skipped,
        message: 'Failed to build payload',
      );
    }

    // 6. Invoke Edge Function
    try {
      final response = _functionInvoker != null
          ? await _functionInvoker('send-push', body: payload)
          : await _supabase.functions.invoke('send-push', body: payload);

      if (response.status >= 200 && response.status < 300) {
        _markDispatched(cleanMessageId);
        int? delivered;
        String? reason;
        if (response.data is Map) {
          final dataMap = response.data as Map;
          delivered = dataMap['delivered_count'] as int?;
          reason = dataMap['reason'] as String?;
        }

        final isZeroRecipients = (delivered == 0) ||
            reason == 'no_other_recipients' ||
            reason == 'no_registered_devices' ||
            reason == 'no_valid_onesignal_subscriptions';

        final effectiveStatus = isZeroRecipients
            ? PushDispatchStatus.noEligibleRecipients
            : PushDispatchStatus.dispatched;

        if (kDebugMode) {
          debugPrint(
            '[PushDispatchService] send-push completed for message=$cleanMessageId '
            '(status: ${response.status}, delivered: $delivered, reason: $reason, result: ${effectiveStatus.name})',
          );
        }
        return PushDispatchResult(
          status: effectiveStatus,
          statusCode: response.status,
          deliveredCount: delivered,
          reason: reason,
          message: reason != null ? 'No eligible recipients ($reason)' : null,
        );
      } else {
        if (kDebugMode) {
          debugPrint(
            '[PushDispatchService] send-push returned non-success status: ${response.status}',
          );
        }
        return PushDispatchResult(
          status: PushDispatchStatus.failed,
          statusCode: response.status,
          message: 'Server returned non-success status: ${response.status}',
        );
      }
    } on FunctionException catch (e) {
      if (kDebugMode) {
        debugPrint(
          '[PushDispatchService] send-push FunctionException: status=${e.status}',
        );
      }
      return PushDispatchResult(
        status: PushDispatchStatus.failed,
        statusCode: e.status,
        message: 'FunctionException: ${e.status}',
      );
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('[PushDispatchService] send-push invocation exception: $e');
        debugPrintStack(stackTrace: st);
      }
      return PushDispatchResult(
        status: PushDispatchStatus.failed,
        message: e.toString(),
      );
    }
  }
}
