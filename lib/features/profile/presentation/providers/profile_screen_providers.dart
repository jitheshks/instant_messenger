import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:instant_messenger/features/profile/data/group_repository.dart';
import 'package:instant_messenger/features/profile/presentation/controllers/contact_profile_notifier.dart';
import 'package:instant_messenger/features/profile/presentation/controllers/group_profile_notifier.dart';

/// Provider for [GroupRepository].
final groupRepositoryProvider = Provider<GroupRepository>((ref) {
  return GroupRepository();
});

/// Family notifier provider managing Contact Profile state.
final contactProfileControllerProvider = NotifierProvider.autoDispose
    .family<ContactProfileNotifier, ContactProfileState, ContactProfileArgs>(
  (arg) => ContactProfileNotifier(arg),
);

/// Family notifier provider managing Group Profile state.
final groupProfileControllerProvider = NotifierProvider.autoDispose
    .family<GroupProfileNotifier, GroupProfileState, GroupProfileArgs>(
  (arg) => GroupProfileNotifier(arg),
);
