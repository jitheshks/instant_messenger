import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:instant_messenger/core/providers/core_providers.dart';
import 'package:instant_messenger/features/messaging/domain/models/user_presence.dart';

/// Reactive real-time stream provider for another user's online presence.
final chatPresenceStreamProvider =
    StreamProvider.autoDispose.family<UserPresence, String>((ref, userId) async* {
  if (userId.isEmpty) {
    yield const UserPresence(online: false);
    return;
  }

  final client = ref.watch(supabaseClientProvider);

  // Small debounce to avoid UI startup jitter
  await Future.delayed(const Duration(milliseconds: 120));
  if (!ref.mounted) return;

  yield* client
      .from('profiles')
      .stream(primaryKey: ['id'])
      .eq('id', userId)
      .map((rows) {
        if (rows.isEmpty) return const UserPresence(online: false);
        final row = rows.first;
        final lastSeenStr = row['last_seen'] as String?;
        if (lastSeenStr == null) return const UserPresence(online: false);

        final lastSeen = DateTime.tryParse(lastSeenStr);
        if (lastSeen == null) return const UserPresence(online: false);

        final isRecent =
            DateTime.now().toUtc().difference(lastSeen).inMinutes < 2;
        return UserPresence(online: isRecent, lastSeen: lastSeen);
      });
});
