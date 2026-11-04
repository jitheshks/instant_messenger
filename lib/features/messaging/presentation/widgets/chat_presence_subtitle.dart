import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:instant_messenger/features/messaging/domain/models/user_presence.dart';
import 'package:instant_messenger/features/messaging/presentation/widgets/typing_dots.dart';
import 'package:instant_messenger/shared/utils/chat_date.dart';

/// Reusable subtitle widget displaying real-time typing indicators or presence status
/// with smooth [AnimatedSwitcher] transitions.
class ChatPresenceSubtitle extends StatelessWidget {
  final bool isTyping;
  final AsyncValue<UserPresence> presenceAsync;

  const ChatPresenceSubtitle({
    super.key,
    required this.isTyping,
    required this.presenceAsync,
  });

  @override
  Widget build(BuildContext context) {
    Widget subtitleWidget;

    if (isTyping) {
      subtitleWidget = const TypingDots();
    } else if (presenceAsync.hasValue && presenceAsync.value!.online) {
      subtitleWidget = Text(
        formatPresenceSubtitle(
          online: presenceAsync.value!.online,
          lastSeen: presenceAsync.value!.lastSeen,
        ),
        style: TextStyle(
          fontSize: 13,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      );
    } else {
      subtitleWidget = const SizedBox.shrink();
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      child: subtitleWidget is SizedBox
          ? const SizedBox(key: ValueKey('empty'))
          : Container(
              key: const ValueKey('visible'),
              child: subtitleWidget,
            ),
    );
  }
}
