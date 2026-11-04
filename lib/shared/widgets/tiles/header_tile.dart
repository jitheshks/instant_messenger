import 'package:flutter/material.dart';
import 'package:instant_messenger/shared/widgets/avatars/avatar_leading.dart';

class HeaderTile extends StatelessWidget {
  const HeaderTile({
    super.key,
    this.isLastMessageMine = false,
    this.lastMessageStatus = 0,

    // Display text: for contacts or chats
    this.displayName,
    this.bio,
    this.title,
    this.subtitle,

    // Avatar
    this.avatarUrl,
    this.radius = 24,

    // Behavior and badges
    this.selected = false,
    this.unreadCount,
    this.muted = false,
    this.showAdd = false,
    this.onAddPressed,

    // Callbacks
    this.onTap,
    this.onLongPress,

    // Custom trailing widget override
    this.trailing,

    // Avatar appearance overrides
    this.avatarBg,
    this.avatarIconColor,
    this.avatarTextColor,

    // Layout mode
    this.useListTile = true,
  });

  // Display name or title, one of them should be passed
  final String? displayName;
  final String? bio;
  final String? title;
  final String? subtitle;

  final String? avatarUrl;
  final double radius;

  final bool selected;
  final int? unreadCount;
  final bool muted;
  final bool showAdd;
  final VoidCallback? onAddPressed;

  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  final Widget? trailing;

  final Color? avatarBg;
  final Color? avatarIconColor;
  final Color? avatarTextColor;

  final bool useListTile;

  final bool isLastMessageMine;
  final int lastMessageStatus;

  @override
  Widget build(BuildContext context) {
    final name = (displayName ?? title ?? '').trim();
    final about = (bio ?? subtitle ?? '').trim();
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // 🔵 Message delivery status icon (WhatsApp style)
    Widget? statusIcon;

    if (isLastMessageMine) {
      final defaultTickColor = cs.onSurfaceVariant;
      final seenTickColor =
          isDark ? const Color(0xFF79D7FF) : const Color(0xFF027EB5);

      switch (lastMessageStatus) {
        case 0: // sending / pending
          statusIcon = Icon(
            Icons.access_time,
            size: 14,
            color: defaultTickColor,
          );
          break;
        case 1: // sent
          statusIcon = Icon(Icons.check, size: 16, color: defaultTickColor);
          break;
        case 2: // delivered
          statusIcon = Icon(Icons.done_all, size: 16, color: defaultTickColor);
          break;
        case 3: // seen
          statusIcon = Icon(
            Icons.done_all,
            size: 16,
            color: seenTickColor,
          );
          break;
      }
    }

    final bgColor = selected
        ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.08)
        : null;

    final avatar = AvatarLeading(
      avatarUrl: avatarUrl,
      fallbackName: name.isEmpty ? 'User' : name,
      radius: radius,
      showTick: selected,
      avatarBg: avatarBg,
      avatarIconColor: avatarIconColor,
      avatarTextColor: avatarTextColor,
    );

    Widget? trailingWidget;

    final List<Widget> trailingWidgets = [];

    // 🕒 TIME — always show if provided
    if (trailing != null) {
      trailingWidgets.add(trailing!);
    }

    // 🟢 UNREAD BADGE — below time
    if (unreadCount != null && unreadCount! > 0) {
      trailingWidgets.add(
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              unreadCount! > 99 ? '99+' : unreadCount.toString(),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      );
    }

    // 🔇 MUTED ICON (optional)
    if (muted) {
      trailingWidgets.add(
        Padding(
          padding: const EdgeInsets.only(top: 3),
          child: Icon(Icons.volume_off, size: 14, color: cs.onSurfaceVariant),
        ),
      );
    }

    if (trailingWidgets.isNotEmpty) {
      trailingWidget = Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: trailingWidgets,
      );
    }

    if (useListTile) {
      return Ink(
        key: ValueKey(
          '$name|$avatarUrl|$radius|$selected|${unreadCount ?? 0}|$muted',
        ),
        color: bgColor,
        child: ListTile(
          onTap: onTap,
          onLongPress: onLongPress,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14),
          leading: avatar,
          title: Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          subtitle: about.isEmpty
              ? null
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    if (statusIcon != null) ...[
                      statusIcon,
                      const SizedBox(width: 4),
                    ],
                    Expanded(
                      child: Text(
                        about,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: cs.onSurfaceVariant),
                      ),
                    ),
                  ],
                ),
          trailing: trailingWidget,
        ),
      );
    }
    // Optional: Compact inline variant could be implemented here if needed
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        color: bgColor,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            avatar,
            SizedBox(width: radius * 0.66),
            Flexible(
              fit: FlexFit.loose,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (name.isNotEmpty)
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  if (about.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        about,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: Theme.of(context).hintColor),
                      ),
                    ),
                ],
              ),
            ),
            if (trailingWidget != null) ...[
              const SizedBox(width: 12),
              trailingWidget,
            ],
          ],
        ),
      ),
    );
  }
}
