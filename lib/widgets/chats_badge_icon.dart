// lib/widgets/chats_badge_icon.dart
import 'package:flutter/material.dart';

class ChatsBadgeIcon extends StatelessWidget {
  const ChatsBadgeIcon({
    super.key,
    this.count,
    this.badgeColor = const Color(0xFF25D366),
    this.textColor = Colors.white,
    this.maxDisplay = 99,
    this.alignment = AlignmentDirectional.topEnd,
    this.icon = const Icon(Icons.chat_bubble_outline),
  });

  final int? count;
  final Color badgeColor;
  final Color textColor;
  final int maxDisplay;
  final AlignmentGeometry alignment;
  final Widget icon;

  @override
  Widget build(BuildContext context) {
    final c = count ?? 0;
    if (c <= 0) return icon;

    final labelText = c > maxDisplay ? '$maxDisplay+' : '$c';

    return Badge(
      alignment: alignment,
      backgroundColor: badgeColor,
      textColor: textColor,
      label: Text(
        labelText,
        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600),
      ),
      child: icon,
    );
  }
}
