// lib/features/profile/presentation/providers/profile_providers.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:instant_messenger/features/profile/data/user_bootstrap.dart';
import 'package:instant_messenger/features/profile/data/user_service.dart';
import 'package:instant_messenger/features/profile/presentation/controllers/profile_notifier.dart';
import 'package:instant_messenger/features/profile/presentation/controllers/edit_name_notifier.dart';

final userServiceProvider = Provider<UserService>((ref) {
  return UserService();
});

final userBootstrapProvider = Provider<UserBootstrap>((ref) {
  return UserBootstrap();
});

final profileControllerProvider =
    NotifierProvider<ProfileNotifier, ProfileState>(ProfileNotifier.new);

final editNameControllerFamily = NotifierProvider.autoDispose
    .family<EditNameNotifier, EditNameState, String>(EditNameNotifier.new);
