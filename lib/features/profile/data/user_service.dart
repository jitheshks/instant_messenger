import 'package:instant_messenger/core/config/supabase_config.dart';
import 'package:instant_messenger/core/persistence/local_cache.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:instant_messenger/features/profile/domain/models/user_profile.dart';

class UserService {
  final SupabaseClient? _client;

  UserService({SupabaseClient? client}) : _client = client;

  SupabaseClient get _supabase => _client ?? Supabase.instance.client;

  // ------------------------------------------------------------
  // CACHED SIGNED-IN PROFILE
  // ------------------------------------------------------------

  UserProfile? _me;

  // Public getters (used by notifications / UI)
  UserProfile? get currentProfile => _me;
  String? get displayName => _me?.displayName;
  String? get avatarUrl => _me?.avatarUrl;

  String? get _currentUid => SupabaseConfig.currentUserId;

  // ------------------------------------------------------------
  // PROFILE READS
  // ------------------------------------------------------------

  /// Live stream of the logged-in user's profile
  Stream<UserProfile> watchMe() {
    final uid = _currentUid;
    if (uid == null) return const Stream.empty();

    return _supabase
        .from('profiles')
        .stream(primaryKey: ['id'])
        .eq('id', uid)
        .map((rows) {
          if (rows.isEmpty) return _me ?? UserProfile.fromMap(uid, const {});
          final data = rows.first;
          _me = UserProfile.fromMap(
            uid,
            data,
            fallbackPhone: _supabase.auth.currentUser?.phone,
          );
          return _me!;
        });
  }

  /// Fetch the logged-in user's profile once
  Future<UserProfile?> getMe() async {
    final uid = _currentUid;
    if (uid == null) return null;

    final row = await _supabase
        .from('profiles')
        .select()
        .eq('id', uid)
        .maybeSingle();
    if (row == null) return null;

    _me = UserProfile.fromMap(
      uid,
      row,
      fallbackPhone: _supabase.auth.currentUser?.phone,
    );
    return _me;
  }

  /// Fetch any user's profile by their UID (if permitted by RLS mutual chat rule).
  Future<UserProfile?> fetchUserProfile(String uid) async {
    try {
      final row = await _supabase
          .from('profiles')
          .select()
          .eq('id', uid)
          .maybeSingle();
      if (row == null) return null;
      return UserProfile.fromMap(uid, row);
    } catch (_) {
      return null;
    }
  }

  /// Explicit load and cache (optional)
  Future<void> loadCurrentProfile(String uid) async {
    final row = await _supabase
        .from('profiles')
        .select()
        .eq('id', uid)
        .maybeSingle();
    if (row != null) {
      _me = UserProfile.fromMap(
        uid,
        row,
        fallbackPhone: _supabase.auth.currentUser?.phone,
      );
    }
  }

  // ------------------------------------------------------------
  // PROFILE WRITES
  // ------------------------------------------------------------

  /// Update display name
  Future<void> updateName(String name) async {
    final uid = _currentUid;
    if (uid == null) return;

    final trimmed = name.trim();
    if (trimmed.isEmpty) return;

    await _supabase
        .from('profiles')
        .update({
          'display_name': trimmed,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', uid);
    await LocalCache.setProfile(displayName: trimmed);
  }

  /// Update bio
  Future<void> updateBio(String bio) async {
    final uid = _currentUid;
    if (uid == null) return;

    final trimmed = bio.trim();

    await _supabase
        .from('profiles')
        .update({
          'about': trimmed,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', uid);
    await LocalCache.setProfile(bio: trimmed);
  }

  /// Update avatar
  Future<void> updateAvatar(String url) async {
    final uid = _currentUid;
    if (uid == null) return;

    final trimmed = url.trim();

    await _supabase
        .from('profiles')
        .update({
          'avatar_url': trimmed,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', uid);
    await LocalCache.setProfile(avatarUrl: trimmed);
  }

  // ------------------------------------------------------------
  // LINKS
  // ------------------------------------------------------------

  Future<void> addLink(String url) async {
    final uid = _currentUid;
    if (uid == null) return;

    final trimmed = url.trim();
    if (trimmed.isEmpty) return;

    final currentLinks = List<String>.from(_me?.links ?? []);
    if (!currentLinks.contains(trimmed)) {
      currentLinks.add(trimmed);
      await _supabase
          .from('profiles')
          .update({
            'links': currentLinks,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', uid);
      _me = _me?.copyWith(links: currentLinks);
    }
  }

  Future<void> removeLink(String url) async {
    final uid = _currentUid;
    if (uid == null) return;

    final trimmed = url.trim();

    final currentLinks = List<String>.from(_me?.links ?? []);
    if (currentLinks.remove(trimmed)) {
      await _supabase
          .from('profiles')
          .update({
            'links': currentLinks,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', uid);
      _me = _me?.copyWith(links: currentLinks);
    }
  }

  // ------------------------------------------------------------
  // PUSH / ONESIGNAL (DEVICE REGISTRATION LOOKUP)
  // ------------------------------------------------------------

  /// Fetch OneSignal player IDs for a recipient user from Supabase user_devices
  Future<List<String>> fetchRecipientPlayerIds(String uid) async {
    try {
      final rows = await _supabase
          .from('user_devices')
          .select('player_id')
          .eq('user_id', uid)
          .eq('subscribed', true);
      return (rows as List)
          .map((r) => r['player_id'] as String?)
          .whereType<String>()
          .where((id) => id.isNotEmpty)
          .toList();
    } catch (_) {
      return [];
    }
  }
}
