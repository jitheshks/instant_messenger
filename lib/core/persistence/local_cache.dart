// lib/services/local_cache.dart
import 'package:hive/hive.dart';
import 'package:instant_messenger/core/config/supabase_config.dart';

/// Centralized fast-path metadata cache with multi-account isolation.
///
/// Ensures account-specific fields (profile, contacts, chats_meta) are strictly scoped per account
/// so that logging out and signing in with a different account cannot leak cached state.
class LocalCache {
  static Box get _profile => Hive.box('profile');
  static Box get _contacts => Hive.box('contacts');
  static Box get _chatsMeta => Hive.box('chats_meta');

  static String? _activeAccountId;

  /// The active account identifier used to isolate cached profile data.
  static String? get activeAccountId =>
      _activeAccountId ?? SupabaseConfig.currentUserId;

  /// Explicitly sets the active account ID and performs safe one-time migration of any legacy un-scoped data.
  static void setActiveAccount(String? accountId) {
    _activeAccountId = accountId;
    if (accountId != null && accountId.isNotEmpty) {
      _migrateLegacyDataIfNeeded(accountId);
    }
  }

  /// One-time safe migration for legacy installs that stored un-scoped keys.
  /// Converts legacy un-scoped keys to `<accountId>_...` and purges un-scoped keys immediately.
  static void _migrateLegacyDataIfNeeded(String accountId) {
    if (!_profile.isOpen) return;
    final migratedTo = _profile.get('legacy_migrated_to');
    if (migratedTo != null) return; // already migrated

    final legacyDisplayName = _profile.get('display_name') as String?;
    final legacyBio = _profile.get('bio') as String?;
    final legacyAvatar = _profile.get('avatar_url') as String?;
    final legacyPhone = _profile.get('phone_e164') as String?;

    if (legacyDisplayName != null &&
        _profile.get('${accountId}_display_name') == null) {
      _profile.put('${accountId}_display_name', legacyDisplayName);
    }
    if (legacyBio != null && _profile.get('${accountId}_bio') == null) {
      _profile.put('${accountId}_bio', legacyBio);
    }
    if (legacyAvatar != null &&
        _profile.get('${accountId}_avatar_url') == null) {
      _profile.put('${accountId}_avatar_url', legacyAvatar);
    }
    if (legacyPhone != null &&
        _profile.get('${accountId}_phone_e164') == null) {
      _profile.put('${accountId}_phone_e164', legacyPhone);
    }

    _profile.put('legacy_migrated_to', accountId);

    // Delete un-scoped keys immediately to prevent cross-account leakage
    _profile.delete('display_name');
    _profile.delete('bio');
    _profile.delete('avatar_url');
    _profile.delete('phone_e164');
  }

  /// Clears in-memory account binding and purges un-scoped legacy fallback keys on sign out.
  /// Account-scoped entries (e.g. `<uid>_display_name`) are safely preserved on disk for re-login.
  static Future<void> onSignOut() async {
    _activeAccountId = null;
    if (_profile.isOpen) {
      await _profile.delete('display_name');
      await _profile.delete('bio');
      await _profile.delete('avatar_url');
      await _profile.delete('phone_e164');
      await _profile.delete('active_account_id');
    }
  }

  // ───────────────── PROFILE CACHE GETTERS ─────────────────

  static String? get displayName {
    if (!_profile.isOpen) return null;
    final acc = activeAccountId;
    if (acc != null && acc.isNotEmpty) {
      return _profile.get('${acc}_display_name') as String?;
    }
    return null;
  }

  static String? get bio {
    if (!_profile.isOpen) return null;
    final acc = activeAccountId;
    if (acc != null && acc.isNotEmpty) {
      return _profile.get('${acc}_bio') as String?;
    }
    return null;
  }

  static String? get avatarUrl {
    if (!_profile.isOpen) return null;
    final acc = activeAccountId;
    if (acc != null && acc.isNotEmpty) {
      return _profile.get('${acc}_avatar_url') as String?;
    }
    return null;
  }

  static String? get phoneE164 {
    if (!_profile.isOpen) return null;
    final acc = activeAccountId;
    if (acc != null && acc.isNotEmpty) {
      return _profile.get('${acc}_phone_e164') as String?;
    }
    return null;
  }

  // ───────────────── PROFILE CACHE SETTER ─────────────────

  static Future<void> setProfile({
    String? displayName,
    String? bio,
    String? avatarUrl,
    String? phoneE164,
  }) async {
    if (!_profile.isOpen) return;
    final acc = activeAccountId;
    if (acc != null && acc.isNotEmpty) {
      await _profile.put('active_account_id', acc);
      if (displayName != null) {
        await _profile.put('${acc}_display_name', displayName);
      }
      if (bio != null) {
        await _profile.put('${acc}_bio', bio);
      }
      if (avatarUrl != null) {
        await _profile.put('${acc}_avatar_url', avatarUrl);
      }
      if (phoneE164 != null) {
        await _profile.put('${acc}_phone_e164', phoneE164);
      }
    }
  }

  // ───────────────── CONTACTS CACHE ─────────────────

  static Map<String, dynamic>? getContact(String uid) {
    if (!_contacts.isOpen) return null;
    final acc = activeAccountId;
    if (acc != null && acc.isNotEmpty) {
      final m = _contacts.get('${acc}_$uid');
      return (m is Map) ? Map<String, dynamic>.from(m) : null;
    }
    return null;
  }

  static Future<void> setContact(String uid, Map<String, dynamic> data) async {
    if (!_contacts.isOpen) return;
    final acc = activeAccountId;
    if (acc != null && acc.isNotEmpty) {
      await _contacts.put('${acc}_$uid', data);
    }
  }

  // ───────────────── CHAT METADATA CACHE ─────────────────

  static Map<String, dynamic>? getChatMeta(String chatId) {
    if (!_chatsMeta.isOpen) return null;
    final acc = activeAccountId;
    if (acc != null && acc.isNotEmpty) {
      final m = _chatsMeta.get('${acc}_$chatId');
      return (m is Map) ? Map<String, dynamic>.from(m) : null;
    }
    return null;
  }

  static Future<void> setChatMeta(
    String chatId,
    Map<String, dynamic> data,
  ) async {
    if (!_chatsMeta.isOpen) return;
    final acc = activeAccountId;
    if (acc != null && acc.isNotEmpty) {
      await _chatsMeta.put('${acc}_$chatId', data);
    }
  }
}
