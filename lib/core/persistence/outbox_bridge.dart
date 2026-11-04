import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:instant_messenger/core/persistence/models/outbox_entry.dart';
import 'package:instant_messenger/core/persistence/stores/outbox_store.dart';
import 'package:instant_messenger/features/messaging/data/outbox_meta.dart';

/// Bridges legacy media upload retry metadata (`outbox_meta`) with the
/// account-scoped mutation outbox ([OutboxStore]), while guaranteeing zero
/// data loss, crash recovery, and full backward compatibility with Workmanager.
class OutboxBridge {
  static const String legacyMetaBoxName = 'outbox_meta';

  /// Bridges pending `OutboxMeta` upload records into the user's [OutboxStore].
  ///
  /// Guarantees:
  /// 1. Non-destructive: Does NOT delete legacy `outbox_meta` records, preserving
  ///    compatibility with the active Workmanager background upload worker.
  /// 2. Idempotent: If an `OutboxEntry` with `entry.id == meta.messageId` already exists,
  ///    it is not duplicated or overwritten with stale state.
  /// 3. Attribution: Each bridged entry is attributed to [accountId].
  static Future<int> bridgeLegacyMeta({
    required String accountId,
    required Box metaBox,
    required OutboxStore outboxStore,
  }) async {
    if (accountId.isEmpty) {
      debugPrint('[OutboxBridge] Aborted: accountId is empty');
      return 0;
    }

    var bridgedCount = 0;

    for (final key in metaBox.keys) {
      final raw = metaBox.get(key);
      if (raw is Map) {
        try {
          final meta = OutboxMeta.fromMap(raw);
          if (meta.messageId.isEmpty) continue;

          // Check if already present in target outboxStore
          final existing = outboxStore.getById(meta.messageId);
          if (existing != null) {
            // Already tracked in OutboxStore, skip to prevent duplicates
            continue;
          }

          final payloadJson = jsonEncode({
            'chatId': meta.chatId,
            'filePath': meta.filePath,
            'mediaKind': meta.mediaKind.name,
            'isGroup': meta.isGroup,
          });

          final entry = OutboxEntry(
            id: meta.messageId,
            accountId: accountId,
            mutationType: 'attach_media',
            targetId: meta.messageId,
            payloadJson: payloadJson,
            createdAt: DateTime.now(),
            retryCount: meta.retryCount,
            nextAttemptAt: meta.nextAttemptAt,
            state: 'queued',
          );

          await outboxStore.enqueue(entry);
          bridgedCount++;
        } catch (e) {
          debugPrint('[OutboxBridge] Failed to bridge record $key: $e');
        }
      }
    }

    return bridgedCount;
  }

  /// Recovers in-flight mutations left abandoned after an app crash or termination.
  static Future<int> recoverInFlight(
    OutboxStore outboxStore, {
    int maxRetries = 5,
  }) async {
    return await outboxStore.recoverInFlight(maxRetries: maxRetries);
  }
}
