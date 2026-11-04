import 'package:flutter/material.dart';

/// Wrap any icon with a small dot badge (no number).
class SmallDotBadgeIcon extends StatelessWidget {
  const SmallDotBadgeIcon({
    super.key,
    required this.child,
    this.show = false,
    this.color,
    this.size = 8,
    this.alignment = AlignmentDirectional.topEnd,
    this.offset = const Offset(0, 0),
  });

  final Widget child;
  final bool show;
  final Color? color;
  final double size;
  final AlignmentGeometry alignment;
  final Offset offset;

  @override
  Widget build(BuildContext context) {
    if (!show) return child;
    final effectiveColor = color ?? Theme.of(context).colorScheme.primary;
    return Badge(
      alignment: alignment,
      backgroundColor: effectiveColor,
      smallSize: size,
      child: child,
    );
  }
}
