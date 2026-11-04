import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:instant_messenger/core/config/supabase_config.dart';
import 'package:instant_messenger/features/profile/domain/models/user_profile.dart';
import 'package:instant_messenger/core/persistence/local_cache.dart';
import 'package:instant_messenger/features/profile/data/user_service.dart';

@immutable
class SettingsState {
  final String displayName;
  final String bio;
  final String phoneE164;
  final String? avatarUrl;
  final String appLanguage;
  final bool loading;
  final String? error;

  const SettingsState({
    this.displayName = '',
    this.bio = '',
    this.phoneE164 = '',
    this.avatarUrl,
    this.appLanguage = "English (device's language)",
    this.loading = true,
    this.error,
  });

  SettingsState copyWith({
    String? displayName,
    String? bio,
    String? phoneE164,
    String? avatarUrl,
    String? appLanguage,
    bool? loading,
    String? error,
  }) {
    return SettingsState(
      displayName: displayName ?? this.displayName,
      bio: bio ?? this.bio,
      phoneE164: phoneE164 ?? this.phoneE164,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      appLanguage: appLanguage ?? this.appLanguage,
      loading: loading ?? this.loading,
      error: error ?? this.error,
    );
  }
}

class SettingsNotifier extends Notifier<SettingsState> {
  final UserService _user;
  StreamSubscription<UserProfile>? _sub;
  bool _started = false;

  SettingsNotifier({UserService? userService})
    : _user = userService ?? UserService();

  @override
  SettingsState build() {
    ref.onDispose(() {
      _sub?.cancel();
    });
    // Auto-init with cached data if available
    final cachedName = LocalCache.displayName ?? '';
    final cachedBio = LocalCache.bio ?? '';
    final cachedAvatar = LocalCache.avatarUrl;
    final cachedPhone = LocalCache.phoneE164 ?? '';

    return SettingsState(
      displayName: cachedName,
      bio: cachedBio,
      avatarUrl: cachedAvatar,
      phoneE164: cachedPhone,
      loading: cachedName.isEmpty && cachedPhone.isEmpty,
    );
  }

  // Getters for controller compatibility
  String get displayName => state.displayName;
  String get bio => state.bio;
  String get phoneE164 => state.phoneE164;
  String? get avatarUrl => state.avatarUrl;
  String get appLanguage => state.appLanguage;
  bool get loading => state.loading;
  String? get error => state.error;

  Future<void> start() async {
    if (_started) return;
    _started = true;

    await _loadFromCache();

    final uid = SupabaseConfig.currentUserId;
    if (uid == null) {
      state = state.copyWith(loading: false, error: 'Not signed in');
      return;
    }

    _sub?.cancel();
    _sub = _user.watchMe().listen(
      (UserProfile p) {
        state = state.copyWith(
          displayName: p.displayName,
          bio: p.bio,
          avatarUrl: p.avatarUrl,
          phoneE164: p.phoneE164,
          loading: false,
          error: null,
        );

        LocalCache.setProfile(
          displayName: p.displayName,
          bio: p.bio,
          avatarUrl: p.avatarUrl,
          phoneE164: p.phoneE164,
        );
      },
      onError: (err) {
        state = state.copyWith(loading: false, error: err.toString());
      },
    );
  }

  Future<void> _loadFromCache() async {
    final cachedName = LocalCache.displayName;
    final cachedBio = LocalCache.bio;
    final cachedAvatar = LocalCache.avatarUrl;
    final cachedPhone = LocalCache.phoneE164;

    if (cachedName != null || cachedBio != null || cachedAvatar != null) {
      state = state.copyWith(
        displayName: cachedName ?? state.displayName,
        bio: cachedBio ?? state.bio,
        avatarUrl: cachedAvatar ?? state.avatarUrl,
        phoneE164: cachedPhone ?? state.phoneE164,
        loading: false,
      );
    }
  }

  Future<void> updateDisplayName(String name) async {
    state = state.copyWith(displayName: name);
    await LocalCache.setProfile(displayName: name);
    await _user.updateName(name);
  }

  Future<void> updateBio(String newBio) async {
    state = state.copyWith(bio: newBio);
    await LocalCache.setProfile(bio: newBio);
    await _user.updateBio(newBio);
  }

  Future<void> updateAvatar(String? url) async {
    state = state.copyWith(avatarUrl: url);
    await LocalCache.setProfile(avatarUrl: url);
    if (url != null) {
      await _user.updateAvatar(url);
    }
  }

  void changeLanguage(String newLanguage) {
    state = state.copyWith(appLanguage: newLanguage);
  }
}
