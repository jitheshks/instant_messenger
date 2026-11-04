import 'dart:async';
import 'package:cross_file/cross_file.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:instant_messenger/core/config/supabase_config.dart';
import 'package:instant_messenger/features/media/presentation/providers/media_providers.dart';
import 'package:instant_messenger/features/profile/presentation/providers/profile_providers.dart';
import 'package:instant_messenger/features/settings/presentation/providers/settings_providers.dart';

@immutable
class ProfileState {
  final String displayName;
  final String about;
  final String phoneE164;
  final String? avatarUrl;
  final List<String> links;
  final bool loading;
  final bool isUploadingAvatar;
  final bool hasStarted;
  final String? error;

  const ProfileState({
    this.displayName = '',
    this.about = '',
    this.phoneE164 = '',
    this.avatarUrl,
    this.links = const [],
    this.loading = true,
    this.isUploadingAvatar = false,
    this.hasStarted = false,
    this.error,
  });

  ProfileState copyWith({
    String? displayName,
    String? about,
    String? phoneE164,
    String? avatarUrl,
    List<String>? links,
    bool? loading,
    bool? isUploadingAvatar,
    bool? hasStarted,
    String? error,
  }) {
    return ProfileState(
      displayName: displayName ?? this.displayName,
      about: about ?? this.about,
      phoneE164: phoneE164 ?? this.phoneE164,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      links: links ?? this.links,
      loading: loading ?? this.loading,
      isUploadingAvatar: isUploadingAvatar ?? this.isUploadingAvatar,
      hasStarted: hasStarted ?? this.hasStarted,
      error: error ?? this.error,
    );
  }
}

class ProfileNotifier extends Notifier<ProfileState> {
  @override
  ProfileState build() {
    final settings = ref.watch(settingsControllerProvider);
    return ProfileState(
      displayName: settings.displayName,
      about: settings.bio,
      phoneE164: settings.phoneE164,
      avatarUrl: settings.avatarUrl,
      loading: false,
    );
  }

  String get displayName => state.displayName;
  String get about => state.about;
  String get phoneE164 => state.phoneE164;
  String? get avatarUrl => state.avatarUrl;
  List<String> get links => state.links;
  bool get loading => state.loading;
  bool get hasStarted => state.hasStarted;
  bool get isUploadingAvatar => state.isUploadingAvatar;
  String? get error => state.error;

  Future<void> start() async {
    if (state.hasStarted) return;
    state = state.copyWith(hasStarted: true, loading: true);

    final uid = SupabaseConfig.currentUserId;
    if (uid == null) {
      state = state.copyWith(loading: false, error: 'User not signed in');
      return;
    }

    try {
      final p = await ref.read(userServiceProvider).getMe();
      if (p != null) {
        state = state.copyWith(
          displayName: p.displayName,
          about: p.bio,
          avatarUrl: p.avatarUrl,
          phoneE164: p.phoneE164,
          loading: false,
        );
      } else {
        state = state.copyWith(loading: false);
      }
    } catch (e) {
      state = state.copyWith(loading: false, error: e.toString());
    }
  }

  Future<void> updateName(String name) async {
    state = state.copyWith(displayName: name);
    await ref.read(settingsControllerProvider.notifier).updateDisplayName(name);
  }

  Future<void> updateAbout(String about) async {
    state = state.copyWith(about: about);
    await ref.read(settingsControllerProvider.notifier).updateBio(about);
  }

  Future<void> updateAvatarFromFile(XFile xfile) => uploadAndSetAvatar(xfile);

  Future<void> uploadAndSetAvatar(XFile xfile) async {
    final uid = SupabaseConfig.currentUserId;
    if (uid == null) return;

    final orchestrator = ref.read(uploadOrchestratorProvider);
    if (orchestrator == null) return;

    state = state.copyWith(isUploadingAvatar: true);

    try {
      final downloadUrl = await orchestrator.uploadAvatar(
        ownerType: 'user',
        ownerId: uid,
        filePath: xfile.path,
      );

      if (downloadUrl.isNotEmpty) {
        state = state.copyWith(avatarUrl: downloadUrl);
        await ref
            .read(settingsControllerProvider.notifier)
            .updateAvatar(downloadUrl);
      }
    } finally {
      state = state.copyWith(isUploadingAvatar: false);
    }
  }
}
