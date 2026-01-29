import 'package:flutter/material.dart';

// Wrap any icon with a small dot badge (no number).
class SmallDotBadgeIcon extends StatelessWidget {
  const SmallDotBadgeIcon({
    super.key,
    required this.child,
    this.show = false,
    this.color = const Color(0xFF25D366), // primary green
    this.size = 8,
    this.alignment = AlignmentDirectional.topEnd,
    this.offset = const Offset(0, 0),
  });

  final Widget child;
  final bool show;
  final Color color;
  final double size;
  final AlignmentGeometry alignment;
  final Offset offset;

  @override
  Widget build(BuildContext context) {
    if (!show) return child;
    // Using Badge with empty label to draw a dot; or a positioned Container
    return Badge(
      alignment: alignment,
      backgroundColor: color,
      smallSize: size, // dot size (Material 3 Badge API) [web:646]
      child: child,
    );
  }
}
