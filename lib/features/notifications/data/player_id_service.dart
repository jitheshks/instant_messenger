import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PlayerIdService {
  /// Returns all active OneSignal player IDs for a user [uid] from Supabase `user_devices`.
  ///
  /// Under Row Level Security (RLS policy `user_devices_all_self`), authenticated clients
  /// can only query their own registered devices (`auth.uid() == user_id`). If queried for a peer user,
  /// PostgREST will return an empty list unless executed in a privileged context (e.g., Edge Function).
  ///
  /// An optional [client] can be provided for dependency injection / testing.
  static Future<List<String>> fetchPlayerIdsForUid(
    String uid, {
    SupabaseClient? client,
  }) async {
    final trimmedUid = uid.trim();
    if (trimmedUid.isEmpty) return const [];

    try {
      final sb = client ?? Supabase.instance.client;
      final response = await sb
          .from('user_devices')
          .select('player_id')
          .eq('user_id', trimmedUid);

      final ids = <String>{};
      for (final row in response) {
        final pid = row['player_id'];
        if (pid is String && pid.trim().isNotEmpty) {
          ids.add(pid.trim());
        }
      }

      return ids.toList();
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint(
          '[PlayerIdService] fetchPlayerIdsForUid error for uid=$trimmedUid: $e',
        );
        debugPrintStack(stackTrace: st);
      }
      return const [];
    }
  }
}
