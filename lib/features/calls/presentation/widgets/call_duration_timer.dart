// lib/features/calls/presentation/widgets/call_duration_timer.dart

import 'dart:async';
import 'package:flutter/material.dart';

/// Reactive timer displaying formatted elapsed call duration (MM:SS or HH:MM:SS).
class CallDurationTimer extends StatefulWidget {
  final bool isRunning;
  final int initialElapsedSeconds;
  final TextStyle? style;
  final Widget? placeholder;

  const CallDurationTimer({
    super.key,
    required this.isRunning,
    this.initialElapsedSeconds = 0,
    this.style,
    this.placeholder,
  });

  @override
  State<CallDurationTimer> createState() => _CallDurationTimerState();
}

class _CallDurationTimerState extends State<CallDurationTimer> {
  Timer? _ticker;
  late int _elapsedSeconds;

  @override
  void initState() {
    super.initState();
    _elapsedSeconds = widget.initialElapsedSeconds;
    if (widget.isRunning) {
      _startTicker();
    }
  }

  @override
  void didUpdateWidget(CallDurationTimer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isRunning && !oldWidget.isRunning) {
      _startTicker();
    } else if (!widget.isRunning && oldWidget.isRunning) {
      _stopTicker();
    }
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {
          _elapsedSeconds++;
        });
      }
    });
  }

  void _stopTicker() {
    _ticker?.cancel();
    _ticker = null;
  }

  @override
  void dispose() {
    _stopTicker();
    super.dispose();
  }

  String _formatDuration(int totalSeconds) {
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;

    final minStr = minutes.toString().padLeft(2, '0');
    final secStr = seconds.toString().padLeft(2, '0');

    if (hours > 0) {
      final hrStr = hours.toString().padLeft(2, '0');
      return '$hrStr:$minStr:$secStr';
    }
    return '$minStr:$secStr';
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isRunning && _elapsedSeconds == 0) {
      return widget.placeholder ?? const SizedBox.shrink();
    }

    final defaultStyle = const TextStyle(
      color: Colors.white70,
      fontSize: 14,
      fontWeight: FontWeight.w500,
      letterSpacing: 0.5,
    );

    return Text(
      _formatDuration(_elapsedSeconds),
      style: widget.style ?? defaultStyle,
    );
  }
}
