import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controller/chat_scroll_controller.dart';
import 'chats_badge_icon.dart';

class JumpToLatestButton extends StatelessWidget {
  const JumpToLatestButton({super.key});

  @override
  Widget build(BuildContext context) {
    final scrollCtrl = context.watch<ChatScrollController>();

    if (!scrollCtrl.showJumpButton) {
      return const SizedBox.shrink();
    }

    return Positioned(
      right: 16,
      bottom: 80, // 👈 above ChatInput (WhatsApp-style)
      child: GestureDetector(
        onTap: scrollCtrl.jumpToLatest,
        child: AnimatedScale(
          duration: const Duration(milliseconds: 180),
          scale: scrollCtrl.showJumpButton ? 1 : 0,
          child: ChatsBadgeIcon(
            count: scrollCtrl.unreadCount,
            alignment: Alignment.topRight,
            badgeColor: const Color(0xFF25D366),
            icon: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    blurRadius: 8,
                    color: Colors.black.withOpacity(0.25),
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: const Icon(
                Icons.keyboard_arrow_down,
                size: 28,
                color: Colors.black87,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
