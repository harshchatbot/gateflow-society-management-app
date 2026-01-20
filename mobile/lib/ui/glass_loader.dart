import 'dart:ui';
import 'package:flutter/material.dart';
import 'app_colors.dart';

class GlassLoader extends StatelessWidget {
  final bool show;
  final String message;

  /// Optional: show the "progress shimmer bar" + message block
  final bool showMessage;

  /// Optional sizes (keep default for consistency)
  final double size;

  const GlassLoader({
    super.key,
    required this.show,
    this.message = "Synchronizing…",
    this.showMessage = true,
    this.size = 56,
  });

  @override
  Widget build(BuildContext context) {
    if (!show) return const SizedBox.shrink();

    return Positioned.fill(
      child: AbsorbPointer(
        absorbing: true,
        child: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
            child: Container(
              color: AppColors.bg.withOpacity(0.90),
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(18.0),
                  child: _LoaderContent(
                    size: size,
                    message: message,
                    showMessage: showMessage,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LoaderContent extends StatelessWidget {
  final double size;
  final String message;
  final bool showMessage;

  const _LoaderContent({
    required this.size,
    required this.message,
    required this.showMessage,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      decoration: BoxDecoration(
        color: AppColors.surface.withOpacity(0.78),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.border.withOpacity(0.9)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 28,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          OrbitalSpinner(size: size),
          if (showMessage) ...[
            const SizedBox(height: 18),
            _AnimatedMessage(message: message),
            const SizedBox(height: 14),
            const _ShimmerBar(),
          ],
        ],
      ),
    );
  }
}

/// 3-layer spinner:
/// - Outer ring (clockwise)
/// - Middle ring (counter-clockwise)
/// - Core jewel (pulse)
class OrbitalSpinner extends StatefulWidget {
  final double size;
  const OrbitalSpinner({super.key, this.size = 56});

  @override
  State<OrbitalSpinner> createState() => _OrbitalSpinnerState();
}

class _OrbitalSpinnerState extends State<OrbitalSpinner>
    with TickerProviderStateMixin {
  late final AnimationController _outer;
  late final AnimationController _middle;
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();

    _outer = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();

    _middle = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();

    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _outer.dispose();
    _middle.dispose();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final container = widget.size;
    final inner = widget.size * 0.72;
    final core = widget.size * 0.30;

    return SizedBox(
      width: container,
      height: container,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Outer orbital (clockwise)
          AnimatedBuilder(
            animation: _outer,
            builder: (_, __) {
              return Transform.rotate(
                angle: _outer.value * 6.283185307179586, // 2*pi
                child: CustomPaint(
                  size: Size(container, container),
                  painter: _RingPainter(
                    thickness: 3,
                    baseColor: AppColors.border.withOpacity(0.9),
                    highlightColor: AppColors.text, // dark top stroke like your React
                    highlightStartAtTop: true,
                  ),
                ),
              );
            },
          ),

          // Middle ring (counter clockwise)
          AnimatedBuilder(
            animation: _middle,
            builder: (_, __) {
              return Transform.rotate(
                angle: -_middle.value * 6.283185307179586,
                child: CustomPaint(
                  size: Size(inner, inner),
                  painter: _RingPainter(
                    thickness: 2,
                    baseColor: AppColors.border.withOpacity(0.9),
                    highlightColor: AppColors.success, // emerald accent
                    highlightStartAtTop: false,
                  ),
                ),
              );
            },
          ),

          // Core jewel pulse
          AnimatedBuilder(
            animation: _pulse,
            builder: (_, __) {
              final scale = 1 + (_pulse.value * 0.35);
              final opacity = 0.70 + (_pulse.value * 0.30);
              return Opacity(
                opacity: opacity,
                child: Transform.scale(
                  scale: scale,
                  child: Container(
                    width: core,
                    height: core,
                    decoration: BoxDecoration(
                      color: AppColors.text,
                      borderRadius: BorderRadius.circular(core),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primary.withOpacity(0.18),
                          blurRadius: 22,
                          spreadRadius: 8,
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

/// Ring painter that mimics:
/// border-stone-100 + border-t-stone-950 (or border-b-emerald)
class _RingPainter extends CustomPainter {
  final double thickness;
  final Color baseColor;
  final Color highlightColor;
  final bool highlightStartAtTop;

  _RingPainter({
    required this.thickness,
    required this.baseColor,
    required this.highlightColor,
    required this.highlightStartAtTop,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final center = rect.center;
    final radius = (size.shortestSide / 2) - (thickness / 2);

    // Base ring
    final basePaint = Paint()
      ..color = baseColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = thickness
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(center, radius, basePaint);

    // Highlight arc (small segment)
    final arcPaint = Paint()
      ..color = highlightColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = thickness
      ..strokeCap = StrokeCap.round;

    // 60 degrees arc
    const sweep = 1.05; // radians ~ 60deg
    final start = highlightStartAtTop ? -1.5707963267948966 : 1.5707963267948966;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      start,
      sweep,
      false,
      arcPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _RingPainter oldDelegate) {
    return oldDelegate.thickness != thickness ||
        oldDelegate.baseColor != baseColor ||
        oldDelegate.highlightColor != highlightColor ||
        oldDelegate.highlightStartAtTop != highlightStartAtTop;
  }
}

class _AnimatedMessage extends StatefulWidget {
  final String message;
  const _AnimatedMessage({required this.message});

  @override
  State<_AnimatedMessage> createState() => _AnimatedMessageState();
}

class _AnimatedMessageState extends State<_AnimatedMessage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fade;

  @override
  void initState() {
    super.initState();
    _fade = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    )..forward();
  }

  @override
  void dispose() {
    _fade.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: Text(
        widget.message.toUpperCase(),
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w900,
          letterSpacing: 6.0, // like your 0.4em tracking
          color: AppColors.text,
          height: 1.4,
        ),
      ),
    );
  }
}

class _ShimmerBar extends StatefulWidget {
  const _ShimmerBar();

  @override
  State<_ShimmerBar> createState() => _ShimmerBarState();
}

class _ShimmerBarState extends State<_ShimmerBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 140,
      height: 6,
      decoration: BoxDecoration(
        color: AppColors.border.withOpacity(0.9),
        borderRadius: BorderRadius.circular(999),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 10,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(999),
        child: AnimatedBuilder(
          animation: _ctrl,
          builder: (_, __) {
            // Move a dark bar left -> right
            final x = lerpDouble(-160, 160, _ctrl.value)!;
            return Transform.translate(
              offset: Offset(x, 0),
              child: Container(
                width: 60,
                height: 6,
                decoration: BoxDecoration(
                  color: AppColors.text,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
