// lib/features/calls/presentation/widgets/call_avatar.dart

import 'package:flutter/material.dart';

/// Clean animated avatar component for voice calls and ringing screens.
class CallAvatar extends StatelessWidget {
  final String name;
  final String? avatarUrl;
  final String statusText;
  final double radius;
  final Widget? trailingSubtitle;

  const CallAvatar({
    super.key,
    required this.name,
    this.avatarUrl,
    required this.statusText,
    this.radius = 64,
    this.trailingSubtitle,
  });

  String _getInitials(String input) {
    final clean = input.trim();
    if (clean.isEmpty) return '?';
    final parts = clean.split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      return (parts[0][0] + parts[1][0]).toUpperCase();
    }
    return clean[0].toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Pulsing / glowing outer halo
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white.withOpacity(0.08),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.2),
                blurRadius: 16,
                spreadRadius: 4,
              ),
            ],
          ),
          child: CircleAvatar(
            radius: radius,
            backgroundColor: Colors.blueGrey.shade800,
            backgroundImage: (avatarUrl != null && avatarUrl!.trim().isNotEmpty)
                ? NetworkImage(avatarUrl!)
                : null,
            child: (avatarUrl == null || avatarUrl!.trim().isEmpty)
                ? Text(
                    _getInitials(name),
                    style: TextStyle(
                      fontSize: radius * 0.7,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  )
                : null,
          ),
        ),
        const SizedBox(height: 20),

        // Participant Name
        Text(
          name.isNotEmpty ? name : 'Instant Messenger User',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 24,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.3,
          ),
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 8),

        // Status Text (e.g. "Ringing...", "Connected", "01:23")
        Text(
          statusText,
          style: TextStyle(
            color: Colors.white.withOpacity(0.75),
            fontSize: 16,
            fontWeight: FontWeight.normal,
          ),
          textAlign: TextAlign.center,
        ),

        if (trailingSubtitle != null) ...[
          const SizedBox(height: 8),
          trailingSubtitle!,
        ],
      ],
    );
  }
}
