// lib/features/notifications/presentation/providers/notification_providers.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:instant_messenger/app/router/router_providers.dart';
import 'package:instant_messenger/core/providers/core_providers.dart';
import 'package:instant_messenger/features/calls/presentation/providers/calls_providers.dart';
import 'package:instant_messenger/features/notifications/presentation/controllers/notification_navigation_coordinator.dart';
import 'package:instant_messenger/features/profile/presentation/providers/profile_providers.dart';
import 'package:instant_messenger/features/notifications/data/fcm_service.dart';
import 'package:instant_messenger/features/notifications/data/onesignal_service.dart';
import 'package:instant_messenger/features/notifications/data/push_dispatch_service.dart';
import 'package:instant_messenger/features/notifications/presentation/controllers/push_controller.dart';

final oneSignalServiceProvider = Provider<OneSignalService>((ref) {
  final appInfo = ref.watch(appInfoServiceProvider);
  return OneSignalService(null, appInfo);
});

final fcmServiceProvider = Provider<FcmService>((ref) {
  final appInfo = ref.watch(appInfoServiceProvider);
  return FcmService(appInfo: appInfo);
});

final pushDispatchServiceProvider = Provider<PushDispatchService>((ref) {
  final user = ref.watch(userServiceProvider);
  return PushDispatchService(currentUserNameProvider: () => user.displayName);
});

final pushControllerProvider = Provider<PushController>((ref) {
  const kOneSignalAppId = '70142ddd-32be-40e0-b1ce-97a1b958e3f4';
  return PushController(
    oneSignal: ref.watch(oneSignalServiceProvider),
    oneSignalAppId: kOneSignalAppId,
    fcmService: ref.watch(fcmServiceProvider),
    serverSend: ref.watch(pushDispatchServiceProvider).dispatch,
  );
});

final notificationNavigationCoordinatorProvider =
    Provider<NotificationNavigationCoordinator>((ref) {
  final routerNotifier = ref.watch(routerNotifierProvider);
  final goRouter = ref.watch(goRouterProvider);
  final callsRepo = ref.watch(callsRepositoryProvider);
  return NotificationNavigationCoordinator(
    routerNotifier: routerNotifier,
    goRouter: goRouter,
    callsRepository: callsRepo,
    callControllerResolver: () => ref.read(callControllerProvider.notifier),
  );
});
