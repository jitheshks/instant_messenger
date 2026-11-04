// lib/features/notifications/presentation/controllers/notification_navigation_coordinator.dart

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:instant_messenger/app/router/router_notifier.dart';
import 'package:instant_messenger/core/persistence/local_cache.dart';
import 'package:instant_messenger/features/calls/domain/models/call_enums.dart';
import 'package:instant_messenger/features/calls/domain/repositories/calls_repository.dart';
import 'package:instant_messenger/features/calls/presentation/controllers/call_controller.dart';
import 'package:instant_messenger/features/notifications/domain/models/notification_payload.dart';
import 'package:instant_messenger/features/notifications/presentation/controllers/notification_controller.dart';

/// Central coordinator responsible for processing notification interactions and
/// driving declarative GoRouter navigation across all lifecycle states:
/// Foreground, Background, and Cold-Start (Terminated).
class NotificationNavigationCoordinator extends ChangeNotifier {
  final RouterNotifier routerNotifier;
  final GoRouter goRouter;
  final CallsRepository callsRepository;
  final CallController Function()? callControllerResolver;

  NotificationPayload? _pendingPayload;
  DateTime? _lastNavigationAt;
  String? _lastNavigationSignature;

  NotificationPayload? get pendingPayload => _pendingPayload;

  NotificationNavigationCoordinator({
    required this.routerNotifier,
    required this.goRouter,
    required this.callsRepository,
    this.callControllerResolver,
  }) {
    routerNotifier.addListener(_onRouterStateChanged);
  }

  String _getPayloadSignature(NotificationPayload payload) {
    if (payload.isCall) {
      return 'call:${payload.callId}:${payload.callActionIntent}';
    } else if (payload.isChat) {
      return 'chat:${payload.chatId}:${payload.messageId ?? ''}';
    }
    return 'type:${payload.type}';
  }

  @override
  void dispose() {
    routerNotifier.removeListener(_onRouterStateChanged);
    super.dispose();
  }

  void _onRouterStateChanged() {
    if (_pendingPayload != null && _isNavigationReady) {
      debugPrint(
        '[NotificationNavigationCoordinator] Router became ready; inspecting buffered payload: $_pendingPayload',
      );
      final payload = _pendingPayload!;
      _pendingPayload = null;

      // When the current location is an auth screen (/splash, /login, /otp),
      // GoRouter's declarative redirect mechanism is triggered by routerNotifier.setBootstrapped(true)
      // and will evaluate routerNotifier.pendingNotification to navigate to the target route.
      // We must NOT clear routerNotifier.pendingNotification prematurely, nor push
      // concurrently while GoRouter is processing its redirect from /splash to the destination.
      final currentLoc =
          goRouter.routerDelegate.currentConfiguration.uri.toString();
      if (currentLoc == '/splash' ||
          currentLoc == '/login' ||
          currentLoc == '/otp') {
        debugPrint(
          '[NotificationNavigationCoordinator] Current route is $currentLoc; delegating cold-start navigation to GoRouter redirect for payload: $payload',
        );
        return;
      }

      routerNotifier.clearPendingNotification();
      _executeNavigation(payload);
    }
  }

  bool get _isNavigationReady =>
      routerNotifier.isAuthed &&
      routerNotifier.bootstrapped &&
      !routerNotifier.requiresName;

  /// Main entry point for all notification taps across FCM, OneSignal,
  /// and FlutterLocalNotifications.
  Future<void> handleNotificationPayload(NotificationPayload payload) async {
    debugPrint(
      '[NotificationNavigationCoordinator] Received payload: $payload (ready=$_isNavigationReady)',
    );

    if (payload.type == NotificationType.unknown) {
      debugPrint(
        '[NotificationNavigationCoordinator] ⚠️ Ignoring unknown notification payload.',
      );
      return;
    }

    if (payload.type == NotificationType.callCancelled) {
      debugPrint(
        '[NotificationNavigationCoordinator] Call cancelled event received for callId: ${payload.callId}',
      );
      return;
    }

    // Rapid duplicate tap / dual-provider push debouncing (1000ms window)
    final signature = _getPayloadSignature(payload);
    final now = DateTime.now();
    if (_lastNavigationSignature == signature &&
        _lastNavigationAt != null &&
        now.difference(_lastNavigationAt!).inMilliseconds < 1000) {
      debugPrint(
        '[NotificationNavigationCoordinator] ⚠️ Debounced rapid duplicate notification tap for $signature',
      );
      return;
    }
    _lastNavigationSignature = signature;
    _lastNavigationAt = now;

    if (!_isNavigationReady) {
      debugPrint(
        '[NotificationNavigationCoordinator] Router not ready yet; buffering pending payload: $payload',
      );
      _pendingPayload = payload;
      routerNotifier.setPendingNotification(payload);
      notifyListeners();
      return;
    }

    await _executeNavigation(payload);
  }

  Future<void> _executeNavigation(NotificationPayload payload) async {
    switch (payload.type) {
      case NotificationType.chat:
        _navigateToChat(payload);
        break;
      case NotificationType.call:
        await _navigateToCall(payload);
        break;
      case NotificationType.callCancelled:
      case NotificationType.unknown:
        break;
    }
  }

  void _navigateToChat(NotificationPayload payload) {
    final chatId = payload.chatId?.trim();
    if (chatId == null || chatId.isEmpty) {
      debugPrint(
        '[NotificationNavigationCoordinator] ⚠️ Cannot navigate: missing chatId',
      );
      return;
    }

    // Prevent redundant push if target chat is already the active foreground screen
    final currentUri = goRouter.routerDelegate.currentConfiguration.uri.toString();
    if (NotificationController.isChatOpen(chatId) || currentUri.contains('/chats/chat/$chatId')) {
      debugPrint(
        '[NotificationNavigationCoordinator] Chat $chatId is already open in foreground; skipping duplicate navigation.',
      );
      return;
    }

    debugPrint(
      '[NotificationNavigationCoordinator] Navigating to /chats/chat/$chatId (messageId: ${payload.messageId})',
    );

    try {
      goRouter.push(
        '/chats/chat/$chatId',
        extra: {
          if (payload.messageId != null) 'targetMessageId': payload.messageId,
        },
      );
    } catch (e, st) {
      debugPrint(
        '[NotificationNavigationCoordinator] GoRouter.push failed: $e\n$st',
      );
    }
  }

  Future<void> _navigateToCall(NotificationPayload payload) async {
    final callId = payload.callId?.trim();
    if (callId == null || callId.isEmpty) {
      debugPrint(
        '[NotificationNavigationCoordinator] ⚠️ Cannot navigate: missing callId',
      );
      return;
    }

    // 1. Decline Action: User clicked explicit 'Decline' action button on notification banner
    if (payload.callActionIntent == CallActionIntent.decline) {
      debugPrint(
        '[NotificationNavigationCoordinator] User declined call $callId via notification action button.',
      );
      try {
        await callsRepository.rejectCall(callId);
      } catch (e) {
        debugPrint(
          '[NotificationNavigationCoordinator] Error rejecting call on decline action: $e',
        );
      }
      return;
    }

    final callerId = payload.callerId ?? '';
    final callerName = payload.callerName ?? 'Caller';
    final callType = payload.callType ?? 'audio';
    final isExplicitAccept =
        payload.callActionIntent == CallActionIntent.accept;

    // Route state guard: Check if call screen for this callId is already the active foreground route
    final currentUri = goRouter.routerDelegate.currentConfiguration.uri.toString();
    if (currentUri.contains('/call/$callId')) {
      debugPrint(
        '[NotificationNavigationCoordinator] Call $callId is already active in current route ($currentUri); skipping duplicate push.',
      );
      if (isExplicitAccept) {
        final controller = callControllerResolver?.call();
        if (controller != null) {
          await controller.acceptIncomingCall(
            callId: callId,
            callType:
                callType == 'video' ? CallType.video : CallType.audio,
            localUserName: LocalCache.displayName ?? 'User',
          );
        }
      }
      return;
    }

    // MANDATORY RULE:
    // If not an explicit 'Accept' button click, incoming must be TRUE.
    // Tapping the notification body MUST navigate to incoming call UI
    // with Accept and Decline buttons, and NEVER auto-join ZEGO RTC!
    final isIncoming = !isExplicitAccept;
    final encodedName = Uri.encodeComponent(callerName);
    final targetUri =
        '/call/$callId?userID=$callerId&userName=$encodedName&callType=$callType&incoming=$isIncoming';

    debugPrint(
      '[NotificationNavigationCoordinator] Navigating to call screen: $targetUri (incoming=$isIncoming, explicitAccept=$isExplicitAccept)',
    );

    try {
      goRouter.push(targetUri);

      if (isExplicitAccept) {
        debugPrint(
          '[NotificationNavigationCoordinator] Executing explicit accept action for callId: $callId',
        );
        final controller = callControllerResolver?.call();
        if (controller != null) {
          await controller.acceptIncomingCall(
            callId: callId,
            callType:
                callType == 'video' ? CallType.video : CallType.audio,
            localUserName: LocalCache.displayName ?? 'User',
          );
        }
      }
    } catch (e, st) {
      debugPrint(
        '[NotificationNavigationCoordinator] Error navigating to call: $e\n$st',
      );
    }
  }
}
