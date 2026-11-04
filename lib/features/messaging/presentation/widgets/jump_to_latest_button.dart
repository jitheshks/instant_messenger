import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:instant_messenger/features/messaging/presentation/providers/messaging_providers.dart';
import 'package:instant_messenger/features/chats/presentation/widgets/chats_badge_icon.dart';

class JumpToLatestButton extends ConsumerWidget {
  const JumpToLatestButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scrollCtrl = ref.watch(chatScrollControllerProvider);

    if (!scrollCtrl.showJumpButton) {
      return const SizedBox.shrink();
    }

    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final buttonBg = isDark ? cs.surfaceContainerHigh : Colors.white;
    final iconColor = cs.onSurface;

    return Positioned(
      right: 16,
      bottom: 80, // 👈 above ChatInput (WhatsApp-style)
      child: GestureDetector(
        onTap: () =>
            ref.read(chatScrollControllerProvider.notifier).jumpToLatest(),
        child: AnimatedScale(
          duration: const Duration(milliseconds: 180),
          scale: scrollCtrl.showJumpButton ? 1 : 0,
          child: ChatsBadgeIcon(
            count: scrollCtrl.unreadCount,
            alignment: Alignment.topRight,
            badgeColor: cs.primary,
            icon: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: buttonBg,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    blurRadius: 8,
                    color: Colors.black.withValues(alpha: 0.25),
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Icon(
                Icons.keyboard_arrow_down,
                size: 28,
                color: iconColor,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
