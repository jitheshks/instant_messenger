import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A WhatsApp-style right-swipe gesture wrapper for message bubbles.
///
/// Swiping right past the activation threshold reveals an animated reply icon
/// and triggers [onSwipeReply] on gesture completion.
///
/// Both incoming and outgoing messages swipe to the right to reply.
class SwipeToReply extends StatefulWidget {
  final Widget child;
  final VoidCallback onSwipeReply;
  final bool isMe;
  final bool enabled;

  const SwipeToReply({
    super.key,
    required this.child,
    required this.onSwipeReply,
    this.isMe = false,
    this.enabled = true,
  });

  @override
  State<SwipeToReply> createState() => _SwipeToReplyState();
}

class _SwipeToReplyState extends State<SwipeToReply>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late Animation<double> _animation;
  double _dragOffset = 0.0;
  bool _triggered = false;

  static const double _triggerThreshold = 30.0;
  static const double _maxDragOffset = 48.0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    )..addListener(() {
        setState(() {
          _dragOffset = _animation.value;
        });
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onHorizontalDragStart(DragStartDetails details) {
    if (!widget.enabled) return;
    _controller.stop();
    _triggered = false;
  }

  void _onHorizontalDragUpdate(DragUpdateDetails details) {
    if (!widget.enabled) return;

    final delta = details.primaryDelta ?? details.delta.dx;
    // Only allow rightward drag (dx > 0)
    if (delta <= 0 && _dragOffset <= 0) {
      return;
    }

    setState(() {
      final effectiveDelta =
          _dragOffset >= _triggerThreshold ? delta * 0.3 : delta;
      _dragOffset = (_dragOffset + effectiveDelta).clamp(0.0, _maxDragOffset);
      if (_dragOffset >= _triggerThreshold && !_triggered) {
        _triggered = true;
        HapticFeedback.lightImpact();
      }
    });
  }

  void _onHorizontalDragEnd(DragEndDetails details) {
    if (!widget.enabled) return;
    if (_triggered) {
      widget.onSwipeReply();
    }
    _animateBack();
  }

  void _onHorizontalDragCancel() {
    if (!widget.enabled) return;
    _animateBack();
  }

  void _animateBack() {
    _animation = Tween<double>(
      begin: _dragOffset,
      end: 0.0,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    ));
    _controller.forward(from: 0.0);
    _triggered = false;
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) {
      return widget.child;
    }

    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final progress = (_dragOffset / _triggerThreshold).clamp(0.0, 1.0);

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragStart: _onHorizontalDragStart,
      onHorizontalDragUpdate: _onHorizontalDragUpdate,
      onHorizontalDragEnd: _onHorizontalDragEnd,
      onHorizontalDragCancel: _onHorizontalDragCancel,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          if (_dragOffset > 0)
            Positioned(
              left: widget.isMe ? -38.0 : 6.0,
              top: 0,
              bottom: 0,
              child: Center(
                child: Opacity(
                  opacity: progress,
                  child: Transform.scale(
                    scale: 0.6 + 0.4 * progress,
                    child: Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        color: cs.primaryContainer,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.reply,
                        size: 18,
                        color: cs.onPrimaryContainer,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          Transform.translate(
            offset: Offset(_dragOffset, 0),
            child: widget.child,
          ),
        ],
      ),
    );
  }
}
