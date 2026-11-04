import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Represents a completed or failed background upload event recorded
/// by a background Workmanager isolate for consumption by the main isolate.
class BackgroundUploadHandoffEvent {
  final String accountId;
  final String messageId;
  final String chatId;
  final bool isSuccess;
  final String? publicUrl;
  final String? mimeType;
  final int? fileSizeBytes;
  final String? kind;
  final String? errorMessage;
  final DateTime timestamp;

  const BackgroundUploadHandoffEvent({
    required this.accountId,
    required this.messageId,
    required this.chatId,
    required this.isSuccess,
    this.publicUrl,
    this.mimeType,
    this.fileSizeBytes,
    this.kind,
    this.errorMessage,
    required this.timestamp,
  });

  Map<String, dynamic> toMap() => {
    'accountId': accountId,
    'messageId': messageId,
    'chatId': chatId,
    'isSuccess': isSuccess,
    'publicUrl': publicUrl,
    'mimeType': mimeType,
    'fileSizeBytes': fileSizeBytes,
    'kind': kind,
    'errorMessage': errorMessage,
    'timestamp': timestamp.toIso8601String(),
  };

  factory BackgroundUploadHandoffEvent.fromMap(Map<String, dynamic> map) =>
      BackgroundUploadHandoffEvent(
        accountId: map['accountId'] as String? ?? '',
        messageId: map['messageId'] as String? ?? '',
        chatId: map['chatId'] as String? ?? '',
        isSuccess: map['isSuccess'] as bool? ?? false,
        publicUrl: map['publicUrl'] as String?,
        mimeType: map['mimeType'] as String?,
        fileSizeBytes: map['fileSizeBytes'] as int?,
        kind: map['kind'] as String?,
        errorMessage: map['errorMessage'] as String?,
        timestamp:
            DateTime.tryParse(map['timestamp'] as String? ?? '') ??
            DateTime.now(),
      );

  String toJson() => jsonEncode(toMap());

  factory BackgroundUploadHandoffEvent.fromJson(String source) =>
      BackgroundUploadHandoffEvent.fromMap(
        jsonDecode(source) as Map<String, dynamic>,
      );
}

/// Durable, isolate-safe handoff channel between background Workmanager isolates
/// and the foreground main isolate.
///
/// Standard Hive does not support multi-isolate concurrent access to account-scoped
/// boxes without corruption risks. To maintain the single-writer principle (where the
/// main isolate is the sole writer to account-scoped boxes), the background isolate
/// persists completion state to this handoff queue. The main isolate then drains and
/// commits the updates into the account-scoped store upon app resume or resync.
class BackgroundUploadHandoff {
  static const String _keyPrefix = 'bg_upload_handoff_queue_';

  static String _storageKey(String accountId) => '$_keyPrefix$accountId';

  /// Records a successfully completed background upload from the background isolate.
  static Future<void> recordCompletion({
    required String accountId,
    required String messageId,
    required String chatId,
    required String publicUrl,
    String? mimeType,
    required int fileSizeBytes,
    required String kind,
  }) async {
    if (accountId.isEmpty) {
      debugPrint('[BackgroundUploadHandoff] Error: accountId is empty');
      return;
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final key = _storageKey(accountId);
      final existing = prefs.getStringList(key) ?? <String>[];

      final event = BackgroundUploadHandoffEvent(
        accountId: accountId,
        messageId: messageId,
        chatId: chatId,
        isSuccess: true,
        publicUrl: publicUrl,
        mimeType: mimeType,
        fileSizeBytes: fileSizeBytes,
        kind: kind,
        timestamp: DateTime.now().toUtc(),
      );

      existing.add(event.toJson());
      await prefs.setStringList(key, existing);
      debugPrint(
        '[BackgroundUploadHandoff] Recorded completion for msg=$messageId account=$accountId',
      );
    } catch (e) {
      debugPrint('[BackgroundUploadHandoff] Record completion error: $e');
    }
  }

  /// Records a failed background upload from the background isolate.
  static Future<void> recordFailure({
    required String accountId,
    required String messageId,
    required String chatId,
    required String errorMessage,
  }) async {
    if (accountId.isEmpty) {
      debugPrint('[BackgroundUploadHandoff] Error: accountId is empty');
      return;
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final key = _storageKey(accountId);
      final existing = prefs.getStringList(key) ?? <String>[];

      final event = BackgroundUploadHandoffEvent(
        accountId: accountId,
        messageId: messageId,
        chatId: chatId,
        isSuccess: false,
        errorMessage: errorMessage,
        timestamp: DateTime.now().toUtc(),
      );

      existing.add(event.toJson());
      await prefs.setStringList(key, existing);
      debugPrint(
        '[BackgroundUploadHandoff] Recorded failure for msg=$messageId account=$accountId',
      );
    } catch (e) {
      debugPrint('[BackgroundUploadHandoff] Record failure error: $e');
    }
  }

  /// Peeks pending handoff events for the specified [accountId] without removing them.
  static Future<List<BackgroundUploadHandoffEvent>> peekForAccount(
    String accountId,
  ) async {
    if (accountId.isEmpty) return const [];
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = _storageKey(accountId);
      final list = prefs.getStringList(key);
      if (list == null || list.isEmpty) return const [];

      final events = <BackgroundUploadHandoffEvent>[];
      for (final raw in list) {
        try {
          events.add(BackgroundUploadHandoffEvent.fromJson(raw));
        } catch (_) {}
      }
      return events;
    } catch (e) {
      debugPrint('[BackgroundUploadHandoff] Peek error: $e');
      return const [];
    }
  }

  /// Acknowledges and removes specific processed events by their [messageIds] for [accountId].
  /// Preserves any unacknowledged events or concurrently added events in the queue.
  static Future<void> acknowledgeEvents(
    String accountId,
    Iterable<String> messageIds,
  ) async {
    if (accountId.isEmpty || messageIds.isEmpty) return;
    try {
      final idSet = messageIds.toSet();
      final prefs = await SharedPreferences.getInstance();
      final key = _storageKey(accountId);
      final currentList = prefs.getStringList(key);
      if (currentList == null || currentList.isEmpty) return;

      final updatedList = <String>[];
      for (final raw in currentList) {
        try {
          final event = BackgroundUploadHandoffEvent.fromJson(raw);
          if (!idSet.contains(event.messageId)) {
            updatedList.add(raw);
          }
        } catch (_) {}
      }

      if (updatedList.isEmpty) {
        await prefs.remove(key);
      } else {
        await prefs.setStringList(key, updatedList);
      }
    } catch (e) {
      debugPrint('[BackgroundUploadHandoff] Acknowledge error: $e');
    }
  }

  /// Drains and clears handoff events for the specified [accountId].
  ///
  /// If [onProcessEvent] is provided, each event is delivered to [onProcessEvent].
  /// An event is acknowledged and removed from persistent storage ONLY after [onProcessEvent]
  /// completes successfully. If [onProcessEvent] throws or the process terminates,
  /// unacknowledged events remain in SharedPreferences for subsequent retry.
  ///
  /// If [onProcessEvent] is null (legacy usage), events that were snapshot at drain time
  /// are removed while preserving any concurrently appended events added by background isolates.
  ///
  /// MUST be invoked only from the main/foreground isolate to ensure the
  /// single-writer invariant on account-scoped stores.
  static Future<List<BackgroundUploadHandoffEvent>> drainForAccount(
    String accountId, {
    Future<void> Function(BackgroundUploadHandoffEvent event)? onProcessEvent,
  }) async {
    if (accountId.isEmpty) return const [];

    try {
      final prefs = await SharedPreferences.getInstance();
      final key = _storageKey(accountId);
      final list = prefs.getStringList(key);

      if (list == null || list.isEmpty) {
        return const [];
      }

      final parsedEvents = <(String, BackgroundUploadHandoffEvent)>[];
      for (final raw in list) {
        try {
          parsedEvents.add((raw, BackgroundUploadHandoffEvent.fromJson(raw)));
        } catch (_) {}
      }

      if (parsedEvents.isEmpty) {
        await prefs.remove(key);
        return const [];
      }

      final processedEvents = <BackgroundUploadHandoffEvent>[];
      final acknowledgedRaws = <String>{};

      for (final (raw, event) in parsedEvents) {
        if (onProcessEvent != null) {
          try {
            await onProcessEvent(event);
            acknowledgedRaws.add(raw);
            processedEvents.add(event);
          } catch (e) {
            debugPrint(
              '[BackgroundUploadHandoff] Processing failed for msg=${event.messageId}, leaving in queue: $e',
            );
            // Break processing to preserve ordering and retry later
            break;
          }
        } else {
          // Legacy drain: mark all snapshot elements as acknowledged
          acknowledgedRaws.add(raw);
          processedEvents.add(event);
        }
      }

      if (acknowledgedRaws.isNotEmpty) {
        // Non-destructive removal: re-read the fresh list to preserve any events
        // appended concurrently by background isolates while processing occurred.
        final freshList = prefs.getStringList(key) ?? <String>[];
        final remaining =
            freshList.where((raw) => !acknowledgedRaws.contains(raw)).toList();
        if (remaining.isEmpty) {
          await prefs.remove(key);
        } else {
          await prefs.setStringList(key, remaining);
        }
      }

      return processedEvents;
    } catch (e) {
      debugPrint('[BackgroundUploadHandoff] Drain error: $e');
      return const [];
    }
  }
}
