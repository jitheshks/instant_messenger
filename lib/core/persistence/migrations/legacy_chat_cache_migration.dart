import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:instant_messenger/core/persistence/stores/chats_store.dart';
import 'package:instant_messenger/features/chats/domain/models/chat_summary.dart';

/// Safely and idempotently migrates legacy un-scoped `chat_cache` records
/// into an authenticated user's account-scoped `chats_cache_$uid` ([ChatsStore]).
class LegacyChatCacheMigration {
  static const String legacyBoxName = 'chat_cache';

  /// Performs the migration.
  ///
  /// Returns the count of summaries successfully migrated into [targetStore].
  ///
  /// Safety Guarantees:
  /// 1. Idempotent: Executing multiple times produces identical, non-duplicated state.
  /// 2. Ownership verification: Summaries are only migrated if [accountId] is verified
  ///    as a participant (via `members` or composite paired chat ID).
  /// 3. Non-destructive: The legacy [legacyBoxName] box is NOT deleted or cleared.
  /// 4. Resilient: Corrupted, partial, or missing records are safely logged and skipped.
  static Future<int> migrate({
    required String accountId,
    required ChatsStore targetStore,
    Box? legacyBox,
  }) async {
    if (accountId.isEmpty) {
      debugPrint('[LegacyChatCacheMigration] Aborted: accountId is empty');
      return 0;
    }

    Box? box = legacyBox;
    bool shouldClose = false;

    try {
      if (box == null) {
        if (!Hive.isBoxOpen(legacyBoxName)) {
          box = await Hive.openBox(legacyBoxName);
          shouldClose = true;
        } else {
          box = Hive.box(legacyBoxName);
        }
      }

      if (box.isEmpty) {
        return 0;
      }

      final candidates = <ChatSummary>[];

      // Format A: List of maps stored under the single key 'summaries' (MessageCache format)
      final rawSummariesList = box.get('summaries');
      if (rawSummariesList is List) {
        for (final item in rawSummariesList) {
          if (item is Map) {
            try {
              final summary = ChatSummary.fromJson(
                Map<String, dynamic>.from(item),
              );
              if (summary.id.isNotEmpty) {
                candidates.add(summary);
              }
            } catch (e) {
              debugPrint(
                '[LegacyChatCacheMigration] Skipping malformed list item: $e',
              );
            }
          }
        }
      }

      // Format B: Individual keys where key is chatId and value is Map
      for (final key in box.keys) {
        if (key == 'summaries') continue;
        final rawVal = box.get(key);
        if (rawVal is Map) {
          try {
            final summary = ChatSummary.fromJson(
              Map<String, dynamic>.from(rawVal),
            );
            if (summary.id.isNotEmpty) {
              candidates.add(summary);
            }
          } catch (e) {
            debugPrint(
              '[LegacyChatCacheMigration] Skipping malformed keyed record $key: $e',
            );
          }
        }
      }

      var migratedCount = 0;
      for (final candidate in candidates) {
        if (_belongsToAccount(candidate, accountId)) {
          await targetStore.saveChatSummary(candidate);
          migratedCount++;
        } else {
          debugPrint(
            '[LegacyChatCacheMigration] Skipping chat "${candidate.id}" — does not belong to $accountId',
          );
        }
      }

      return migratedCount;
    } catch (e, st) {
      debugPrint('[LegacyChatCacheMigration] Error during migration: $e\n$st');
      return 0;
    } finally {
      if (shouldClose && box != null && box.isOpen) {
        // Keep box open or close safely if we opened it ourselves
        // We do not delete box.
      }
    }
  }

  /// Verifies whether [summary] reliably belongs to [accountId].
  static bool _belongsToAccount(ChatSummary summary, String accountId) {
    // 1. Explicit membership
    if (summary.members.contains(accountId)) {
      return true;
    }

    // 2. Direct chat ID format check (e.g. 'uidA_uidB')
    if (summary.id.contains(accountId)) {
      final parts = summary.id.split('_');
      if (parts.contains(accountId)) {
        return true;
      }
    }

    // 3. Fallback: if otherUserId is distinct from accountId and is the peer
    if (summary.otherUserId.isNotEmpty &&
        summary.otherUserId != accountId &&
        summary.members.isEmpty) {
      if (summary.id.contains(accountId)) {
        return true;
      }
    }

    return false;
  }
}
