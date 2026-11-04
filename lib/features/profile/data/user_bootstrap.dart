import 'package:flutter/foundation.dart';
import 'package:instant_messenger/core/persistence/local_cache.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

enum NextRoute { editName, profile, chats }

class UserBootstrap {
  final SupabaseClient? _supabase;

  UserBootstrap({
    @Deprecated(
      'Unused. Maintained temporarily for backwards compatibility with legacy callers.',
    )
    dynamic auth,
    @Deprecated(
      'Unused. Maintained temporarily for backwards compatibility with legacy callers.',
    )
    dynamic db,
    SupabaseClient? supabase,
  }) : _supabase = supabase;

  SupabaseClient? get _activeSupabase {
    if (_supabase != null) return _supabase;
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }

  // ------------------------------------------------------------
  // BOOTSTRAP FLOW (WHATSAPP STYLE) — SUPABASE
  // ------------------------------------------------------------
  Future<NextRoute> bootstrap() async {
    final sb = _activeSupabase;
    final sbUser = sb?.auth.currentUser;

    // No active Supabase session
    if (sbUser == null) {
      return NextRoute.profile;
    }

    LocalCache.setActiveAccount(sbUser.id);

    final cachedName = LocalCache.displayName;
    debugPrint('[Bootstrap] Supabase cached display_name="$cachedName"');

    if (cachedName != null && cachedName.isNotEmpty) {
      _syncProfileFromSupabase(sbUser.id);
      return NextRoute.chats;
    }

    try {
      final row = await sb!
          .from('profiles')
          .select('display_name, avatar_url, phone_e164')
          .eq('id', sbUser.id)
          .maybeSingle();

      final rawName = row?['display_name'];
      final name = (rawName is String && rawName.trim().isNotEmpty)
          ? rawName.trim()
          : null;

      if (name == null) {
        return NextRoute.editName;
      }

      await LocalCache.setProfile(
        displayName: name,
        avatarUrl: row?['avatar_url'] as String?,
        phoneE164: row?['phone_e164'] as String?,
      );
      return NextRoute.chats;
    } catch (e) {
      debugPrint('[Bootstrap] Supabase profile check error: $e');
      rethrow;
    }
  }

  // ------------------------------------------------------------
  // UPDATE DISPLAY NAME & OPTIONAL AVATAR (LOCAL → SUPABASE)
  // ------------------------------------------------------------
  Future<void> setDisplayName(String displayName, {String? avatarUrl}) async {
    final sb = _activeSupabase;
    final sbUser = sb?.auth.currentUser;

    if (sbUser == null) {
      throw StateError('Not signed in');
    }

    LocalCache.setActiveAccount(sbUser.id);
    final trimmed = displayName.trim();
    try {
      await LocalCache.setProfile(
        displayName: trimmed,
        avatarUrl: avatarUrl,
      );
    } catch (e) {
      debugPrint('[Bootstrap] LocalCache.setProfile warning: $e');
    }

    final updatePayload = <String, dynamic>{
      'display_name': trimmed,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
    if (avatarUrl != null && avatarUrl.isNotEmpty) {
      updatePayload['avatar_url'] = avatarUrl;
    }

    try {
      await sb!
          .from('profiles')
          .update(updatePayload)
          .eq('id', sbUser.id);
      debugPrint(
        '[Bootstrap] Supabase profile updated with display_name="$trimmed"',
      );
    } catch (e) {
      debugPrint(
        '[Bootstrap] Failed to update Supabase profile display_name: $e',
      );
      rethrow;
    }
  }

  // ------------------------------------------------------------
  // BACKGROUND PROFILE SYNC
  // ------------------------------------------------------------
  Future<void> _syncProfileFromSupabase(String uid) async {
    final sb = _activeSupabase;
    if (sb == null) return;
    try {
      final row = await sb
          .from('profiles')
          .select('display_name, avatar_url, phone_e164')
          .eq('id', uid)
          .maybeSingle();
      if (row == null) return;

      await LocalCache.setProfile(
        displayName: row['display_name'] as String?,
        avatarUrl: row['avatar_url'] as String?,
        phoneE164: row['phone_e164'] as String?,
      );
      debugPrint('[Bootstrap] Profile synced from Supabase');
    } catch (e) {
      debugPrint('[Bootstrap] Supabase profile sync failed: $e');
    }
  }
}
