import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:instant_messenger/app/bootstrap/app_bootstrap.dart';
import 'package:instant_messenger/app/bootstrap/app_lifecycle_service.dart';
import 'package:instant_messenger/app/router/router_providers.dart';
import 'package:instant_messenger/core/config/first_launch_service.dart';
import 'package:instant_messenger/core/providers/core_providers.dart';
import 'package:instant_messenger/core/utils/permission_service.dart';
import 'package:instant_messenger/features/auth/presentation/providers/auth_providers.dart';
import 'package:instant_messenger/features/contacts/presentation/providers/contacts_providers.dart';
import 'package:instant_messenger/features/messaging/data/outbox_service.dart';
import 'package:instant_messenger/features/profile/data/user_bootstrap.dart';
import 'package:instant_messenger/features/profile/presentation/providers/profile_providers.dart';
import 'package:instant_messenger/core/persistence/local_cache.dart';

/// Bootstraps session-scoped services for the currently authenticated user.
final appBootstrapResultProvider = FutureProvider<AppBootstrapResult?>((
  ref,
) async {
  final uid = ref.watch(currentUserIdProvider);
  final router = ref.read(routerNotifierProvider);

  if (uid == null || uid.isEmpty) {
    Future.microtask(() => router.setBootstrapped(true));
    return null;
  }

  debugPrint('[BOOTSTRAP] start uid=$uid');

  final bootstrap = ref.read(userBootstrapProvider);
  final nextRoute = await bootstrap.bootstrap();

  String displayName = LocalCache.displayName ?? '';
  if (displayName.isEmpty) {
    try {
      final row = await ref
          .read(supabaseClientProvider)
          .from('profiles')
          .select('display_name')
          .eq('id', uid)
          .maybeSingle();
      displayName = (row?['display_name'] as String?)?.trim() ?? '';
    } catch (_) {}
  }

  debugPrint('[BOOTSTRAP] nextRoute=$nextRoute displayName="$displayName"');

  final result = await bootstrapAppServices(
    uid: uid,
    nextRoute: nextRoute,
    displayName: displayName,
  );

  AppLifecycleService().attachOutbox(result.outbox);

  Future.microtask(() {
    router
      ..setRequiresName(nextRoute == NextRoute.editName)
      ..setBootstrapped(true);
  });

  final alreadyAsked = await FirstLaunchService.isDone();
  if (!alreadyAsked) {
    await FirstLaunchService.markDone();
    unawaited(() async {
      try {
        await PermissionService.requestFirstLoginPermissions(
          includeMicrophone: true,
          includeContacts: true,
        );
        await PermissionService.ensureNotifications();
        await ref
            .read(contactsDataControllerProvider.notifier)
            .refreshIfPermitted();
      } catch (e) {
        debugPrint('[BOOTSTRAP] Permission request notice: $e');
      }
    }());
  }

  debugPrint('[BOOTSTRAP] completed');
  return result;
});

/// Exposes the active session's [OutboxService].
final outboxServiceProvider = Provider<OutboxService?>((ref) {
  return ref.watch(appBootstrapResultProvider).value?.outbox;
});
