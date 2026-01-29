import 'package:flutter/material.dart';
import '../controller/notification_controller.dart';

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

class _ChatRouteObserverState extends State<ChatRouteObserver>
    with RouteAware {


final RouteObserver<ModalRoute<void>> routeObserver =
    RouteObserver<ModalRoute<void>>();

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
    NotificationController.onChatOpen(widget.chatId);
  }

  @override
  void didPop() {
    NotificationController.onChatClose(widget.chatId);
  }

  @override
  void didPushNext() {
    NotificationController.onChatClose(widget.chatId);
  }

  @override
  void didPopNext() {
    NotificationController.onChatOpen(widget.chatId);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
