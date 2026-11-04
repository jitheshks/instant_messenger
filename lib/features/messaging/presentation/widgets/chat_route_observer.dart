import 'package:flutter/material.dart';
import 'package:instant_messenger/app/app.dart' show routeObserver;
import 'package:instant_messenger/features/notifications/presentation/controllers/notification_controller.dart';

class ChatRouteObserver extends StatefulWidget {
  final String chatId;
  final Widget child;

  const ChatRouteObserver({
    super.key,
    required this.chatId,
    required this.child,
  });

  @override
  State<ChatRouteObserver> createState() => _ChatRouteObserverState();
}

class _ChatRouteObserverState extends State<ChatRouteObserver> with RouteAware {
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute) {
      routeObserver.subscribe(this, route);
    }
  }

  @override
  void dispose() {
    routeObserver.unsubscribe(this);
    super.dispose();
  }

  @override
  void didPush() {
    debugPrint('[NotificationTap] ChatRouteObserver.didPush for chatId: ${widget.chatId}');
    NotificationController.onChatOpen(widget.chatId);
  }

  @override
  void didPop() {
    debugPrint('[NotificationTap] ChatRouteObserver.didPop for chatId: ${widget.chatId}');
    NotificationController.onChatClose(widget.chatId);
  }

  @override
  void didPushNext() {
    debugPrint('[NotificationTap] ChatRouteObserver.didPushNext for chatId: ${widget.chatId}');
    NotificationController.onChatClose(widget.chatId);
  }

  @override
  void didPopNext() {
    debugPrint('[NotificationTap] ChatRouteObserver.didPopNext for chatId: ${widget.chatId}');
    NotificationController.onChatOpen(widget.chatId);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
