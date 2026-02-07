import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Premium, calm, security-themed loader. Uses theme colors.
/// - [AppLoader.inline] for buttons / inline areas
/// - [AppLoader.overlay] for page-level (semi-transparent overlay + message)
/// - [AppLoader.fullscreen] for full-screen branded loading
class AppLoader extends StatelessWidget {
  final bool show;
  final double size;
  final String? message;
  final _AppLoaderKind kind;

  const AppLoader._({
    super.key,
    this.show = true,
    this.size = 24,
    this.message,
    required this.kind,
  });

  /// Small spinner for buttons / inline areas. Use inside a button or row.
  static Widget inline({Key? key, double size = 20}) {
    return AppLoader._(key: key, size: size, kind: _AppLoaderKind.inline);
  }

  /// Semi-transparent overlay + centered loader + optional one-line message.
  /// Use for page-level loading (e.g. in a Stack). When [show] is false, returns [SizedBox.shrink].
  static Widget overlay({
    Key? key,
    bool show = true,
    String? message,
  }) {
    return AppLoader._(
      key: key,
      show: show,
      message: message,
      kind: _AppLoaderKind.overlay,
    );
  }

  /// Full-screen branded loading: full screen + loader + optional message.
  /// When [show] is false, returns [SizedBox.shrink].
  static Widget fullscreen({
    Key? key,
    bool show = true,
    String? message,
  }) {
    return AppLoader._(
      key: key,
      show: show,
      message: message,
      kind: _AppLoaderKind.fullscreen,
    );
  }

  @override
  Widget build(BuildContext context) {
    switch (kind) {
      case _AppLoaderKind.inline:
        return SizedBox(
          width: size,
          height: size,
          child: _LoaderRing(size: size),
        );
      case _AppLoaderKind.overlay:
        if (!show) return const SizedBox.shrink();
        return Positioned.fill(
          child: Container(
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.08),
            child: Center(
              child: _OverlayCard(message: message),
            ),
          ),
        );
      case _AppLoaderKind.fullscreen:
        if (!show) return const SizedBox.shrink();
        return Container(
          width: double.infinity,
          height: double.infinity,
          color: Theme.of(context).scaffoldBackgroundColor,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const _LoaderRing(size: 44),
                if (message != null && message!.trim().isNotEmpty) ...[
                  const SizedBox(height: 20),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Text(
                      message!.trim(),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
    }
  }
}

enum _AppLoaderKind { inline, overlay, fullscreen }

/// Centered card with ring + optional message (for overlay).
class _OverlayCard extends StatelessWidget {
  final String? message;

  const _OverlayCard({this.message});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = (message ?? "").trim();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.dividerColor),
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.onSurface.withOpacity(0.06),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 28,
            height: 28,
            child: _LoaderRing(size: 28),
          ),
          if (text.isNotEmpty) ...[
            const SizedBox(width: 14),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 220),
              child: Text(
                text,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurface,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Calm rotating ring (security-themed). Pure Flutter animation.
class _LoaderRing extends StatefulWidget {
  final double size;

  const _LoaderRing({required this.size});

  @override
  State<_LoaderRing> createState() => _LoaderRingState();
}

class _LoaderRingState extends State<_LoaderRing>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return CustomPaint(
          size: Size(widget.size, widget.size),
          painter: _RingPainter(
            progress: _controller.value,
            color: Theme.of(context).colorScheme.primary,
            strokeWidth: (widget.size * 0.12).clamp(2.0, 3.0),
          ),
        );
      },
    );
  }
}

/// Draws a single arc that rotates (calm, minimal ring).
class _RingPainter extends CustomPainter {
  final double progress;
  final Color color;
  final double strokeWidth;

  _RingPainter({
    required this.progress,
    required this.color,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.shortestSide / 2) - strokeWidth;
    const sweepAngle = 0.65 * 2 * math.pi; // ~65% of circle
    final startAngle = -math.pi / 2 + (progress * 2 * math.pi);

    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepAngle,
      false,
      paint,
    );
  }

  @override
  bool shouldRepaint(_RingPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.color != color ||
      oldDelegate.strokeWidth != strokeWidth;
}
