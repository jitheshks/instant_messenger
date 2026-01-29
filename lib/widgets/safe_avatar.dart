import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

class SafeAvatar extends StatelessWidget {
  const SafeAvatar({
    super.key,
    required this.radius,
    this.avatarUrl,
    this.backgroundColor,
    this.fallbackIcon = Icons.person,
    this.fallbackName,
    this.iconColor,
    this.textColor,
    this.initialsScale = 0.72, // slightly larger than 0.65; tweakable
    this.iconScale = 0.9,
  });

  final double radius;
  final String? avatarUrl;
  final Color? backgroundColor;
  final IconData fallbackIcon;
  final String? fallbackName;
  final Color? iconColor;
  final Color? textColor;

  final double initialsScale;
  final double iconScale;

  @override
  Widget build(BuildContext context) {
    final url = (avatarUrl ?? '').trim();
    final hasImage = url.isNotEmpty;

    final initials = fallbackName == null ? null : _initials(fallbackName!);

    return CircleAvatar(
      radius: radius,
      backgroundColor: backgroundColor ?? _themeBg(context),
      // Use CachedNetworkImage for the avatar image
      child: hasImage
          ? ClipOval(
              child: SizedBox(
                width: radius * 2,
                height: radius * 2,
                child: CachedNetworkImage(
                  imageUrl: url,
                  fit: BoxFit.cover,
                  placeholder: (_, _) => const SizedBox(),
                  errorWidget: (_, _, _) => _buildFallback(initials),
                ),
              ),
            )
          : _buildFallback(initials),
    );
  }

  Widget _buildFallback(String? initials) {
    if (initials != null && initials.isNotEmpty) {
      return Center(
        child: Text(
          initials,
          style: TextStyle(
            fontSize: radius * initialsScale,
            fontWeight: FontWeight.w600,
            color: textColor ?? Colors.white,
          ),
        ),
      );
    } else {
      return Icon(
        fallbackIcon,
        size: radius * iconScale,
        color: iconColor ?? Colors.grey.shade500,
      );
    }
  }

  Color _themeBg(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return isDark ? const Color(0xFF5B4A3E) : const Color(0xFFD1B7A7);
  }

  String _initials(String name) {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((s) => s.isNotEmpty)
        .toList(growable: false);
    if (parts.isEmpty) return '?';
    if (parts.length == 1) {
      final c = parts.first.characters;
      return c.isEmpty ? '?' : c.first.toUpperCase();
    }
    final a = parts[0].characters;
    final b = parts[1].characters;
    final ca = a.isEmpty ? '' : a.first.toUpperCase();
    final cb = b.isEmpty ? '' : b.first.toUpperCase();
    final res = (ca + cb).trim();
    return res.isEmpty ? '?' : res;
  }
}
