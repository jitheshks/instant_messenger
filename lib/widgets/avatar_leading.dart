import 'package:flutter/material.dart';
import 'package:instant_messenger/widgets/safe_avatar.dart';

class AvatarLeading extends StatelessWidget {
  const AvatarLeading({
    super.key,
    required this.fallbackName,
    this.avatarUrl,
    this.radius = 24,
    this.showTick = false,
    this.tickSize = 18,
    this.avatarBg,
    this.avatarIconColor,
    this.avatarTextColor,
  });

  final String? avatarUrl;
  final String fallbackName;
  final double radius;
  final bool showTick;
  final double tickSize;

  // Optional avatar styling passthroughs for parity
  final Color? avatarBg;
  final Color? avatarIconColor;
  final Color? avatarTextColor;

  @override
  Widget build(BuildContext context) {
    final size = radius * 2;

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.bottomRight,
        children: [
          SafeAvatar(
            key: ValueKey('$avatarUrl|$radius|$fallbackName'),
            radius: radius,
            avatarUrl: avatarUrl,
            fallbackName: fallbackName,
            backgroundColor: avatarBg,
            iconColor: avatarIconColor,
            textColor: avatarTextColor,
          ),
          if (showTick)
            Container(
              width: tickSize,
              height: tickSize,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
              child: Icon(Icons.check, size: tickSize * 0.66, color: Colors.white),
            ),
        ],
      ),
    );
  }
}
