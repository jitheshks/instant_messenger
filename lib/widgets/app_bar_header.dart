import 'package:flutter/material.dart';
import 'package:instant_messenger/widgets/safe_avatar.dart';

class AppBarHeader extends StatelessWidget {
  const AppBarHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.avatarUrl,
    this.radius = 16,
    this.spacing = 12,
    this.avatarBg,
    this.avatarIconColor,
    this.avatarTextColor,
    this.maxLinesTitle = 1,
  });

  final String title;
  final Widget? subtitle;

  final String? avatarUrl;
  final double radius;
  final double spacing;

  final Color? avatarBg;
  final Color? avatarIconColor;
  final Color? avatarTextColor;

  final int maxLinesTitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SafeAvatar(
          radius: radius,
          avatarUrl: avatarUrl,
          fallbackName: title,
          backgroundColor: avatarBg,
          iconColor: avatarIconColor,
          textColor: avatarTextColor,
        ),

        SizedBox(width: spacing),

        Expanded(
          child: AnimatedSize(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            alignment: Alignment.topLeft,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: maxLinesTitle,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),

                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 150),
                  switchInCurve: Curves.easeOut,
                  switchOutCurve: Curves.easeIn,
                  child: subtitle == null
                      ? const SizedBox(
                          key: ValueKey('empty'),
                          height: 0,
                        )
                      : Padding(
                          key: const ValueKey('subtitle'),
                          padding: const EdgeInsets.only(top: 2),
                          child: subtitle!,
                        ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
