import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../ui/app_colors.dart';

/// Mood states for the reusable SENTI mascot.
enum AliveMascotMood {
  idle,
  happy,
  alert,
  warning,
  namaste,
}

/// Reusable Duolingo-style mascot widget:
/// - Idle life loop (float + gentle tilt)
/// - Blink loop
/// - Reaction pulse when mood changes
/// - Optional delayed nudge bubble
class SentinelAliveMascot extends StatefulWidget {
  final AliveMascotMood mood;
  final double size;
  final bool showNudge;
  final List<String> nudgeMessages;
  final Duration nudgeDelay;
  final Duration nudgeRotateEvery;
  final TextStyle? nudgeTextStyle;

  const SentinelAliveMascot({
    super.key,
    this.mood = AliveMascotMood.idle,
    this.size = 124,
    this.showNudge = false,
    this.nudgeMessages = const <String>[],
    this.nudgeDelay = const Duration(seconds: 8),
    this.nudgeRotateEvery = const Duration(seconds: 6),
    this.nudgeTextStyle,
  });

  @override
  State<SentinelAliveMascot> createState() => _SentinelAliveMascotState();
}

class _SentinelAliveMascotState extends State<SentinelAliveMascot>
    with TickerProviderStateMixin {
  static const String _genericClosedEyesAsset =
      'assets/mascot/senti_eyes_closed.png';
  static const String _namasteClosedEyesAsset =
      'assets/mascot/senti_namaste_eyez_closed.png';

  late final AnimationController _lifeController;
  late final AnimationController _reactionController;
  late final Animation<double> _reactionScale;

  Timer? _nextBlinkTimer;
  Timer? _openEyesTimer;
  Timer? _nudgeDelayTimer;
  Timer? _nudgeRotateTimer;

  bool _eyesClosed = false;
  bool _showNudgeBubble = false;
  int _nudgeIndex = 0;

  @override
  void initState() {
    super.initState();
    _lifeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    )..repeat(reverse: true);

    _reactionController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    );
    _reactionScale = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 0.0, end: 0.08)
            .chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 45,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 0.08, end: 0.0)
            .chain(CurveTween(curve: Curves.easeInOutCubic)),
        weight: 55,
      ),
    ]).animate(_reactionController);

    _scheduleNextBlink();
    _setupNudges();
  }

  @override
  void didUpdateWidget(covariant SentinelAliveMascot oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.mood != widget.mood) {
      _reactionController.forward(from: 0);
    }

    if (oldWidget.showNudge != widget.showNudge ||
        oldWidget.nudgeDelay != widget.nudgeDelay ||
        oldWidget.nudgeRotateEvery != widget.nudgeRotateEvery ||
        oldWidget.nudgeMessages != widget.nudgeMessages) {
      _resetNudges();
    }
  }

  void _resetNudges() {
    _nudgeDelayTimer?.cancel();
    _nudgeRotateTimer?.cancel();
    if (mounted) {
      setState(() {
        _showNudgeBubble = false;
        _nudgeIndex = 0;
      });
    }
    _setupNudges();
  }

  void _setupNudges() {
    if (!widget.showNudge || widget.nudgeMessages.isEmpty) return;

    _nudgeDelayTimer = Timer(widget.nudgeDelay, () {
      if (!mounted) return;
      setState(() => _showNudgeBubble = true);

      _nudgeRotateTimer?.cancel();
      _nudgeRotateTimer = Timer.periodic(widget.nudgeRotateEvery, (_) {
        if (!mounted) return;
        if (widget.nudgeMessages.isEmpty) return;
        setState(() {
          _nudgeIndex = (_nudgeIndex + 1) % widget.nudgeMessages.length;
        });
      });
    });
  }

  void _scheduleNextBlink() {
    final millis = 2600 + math.Random().nextInt(2400);
    _nextBlinkTimer?.cancel();
    _nextBlinkTimer = Timer(Duration(milliseconds: millis), () {
      if (!mounted) return;
      setState(() => _eyesClosed = true);

      _openEyesTimer?.cancel();
      _openEyesTimer = Timer(const Duration(milliseconds: 130), () {
        if (!mounted) return;
        setState(() => _eyesClosed = false);
        _scheduleNextBlink();
      });
    });
  }

  String _assetForMood(AliveMascotMood mood) {
    switch (mood) {
      case AliveMascotMood.idle:
        return 'assets/mascot/senti_idle.png';
      case AliveMascotMood.happy:
        return 'assets/mascot/senti_happy.png';
      case AliveMascotMood.alert:
        return 'assets/mascot/senti_alert.png';
      case AliveMascotMood.warning:
        return 'assets/mascot/senti_warning.png';
      case AliveMascotMood.namaste:
        return 'assets/mascot/senti_namaste.png';
    }
  }

  String _closedEyesAssetForMood(AliveMascotMood mood) {
    if (mood == AliveMascotMood.namaste) return _namasteClosedEyesAsset;
    return _genericClosedEyesAsset;
  }

  @override
  void dispose() {
    _nextBlinkTimer?.cancel();
    _openEyesTimer?.cancel();
    _nudgeDelayTimer?.cancel();
    _nudgeRotateTimer?.cancel();
    _lifeController.dispose();
    _reactionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final nudgeText = widget.nudgeMessages.isEmpty
        ? ''
        : widget.nudgeMessages[_nudgeIndex % widget.nudgeMessages.length];

    return SizedBox(
      width: widget.size + 20,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.showNudge && _showNudgeBubble && nudgeText.isNotEmpty) ...[
            _NudgeBubble(
              text: nudgeText,
              textStyle: widget.nudgeTextStyle,
            ),
            const SizedBox(height: 8),
          ],
          AnimatedBuilder(
            animation: Listenable.merge([_lifeController, _reactionController]),
            builder: (context, child) {
              final lifeT = Curves.easeInOut.transform(_lifeController.value);
              final yOffset = -4.0 + (lifeT * 8.0);
              final tilt = ((lifeT - 0.5) * 0.05);
              final scale = 1.0 + _reactionScale.value;

              return Transform.translate(
                offset: Offset(0, yOffset),
                child: Transform.rotate(
                  angle: tilt,
                  child: Transform.scale(scale: scale, child: child),
                ),
              );
            },
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 120),
              switchInCurve: Curves.easeOut,
              switchOutCurve: Curves.easeIn,
              child: Image.asset(
                _eyesClosed
                    ? _closedEyesAssetForMood(widget.mood)
                    : _assetForMood(widget.mood),
                key: ValueKey<String>(
                  '${widget.mood.name}_${_eyesClosed ? 'closed' : 'open'}',
                ),
                width: widget.size,
                height: widget.size,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => Container(
                  width: widget.size,
                  height: widget.size,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Icon(
                    Icons.pets_rounded,
                    size: widget.size * 0.45,
                    color: AppColors.primary.withValues(alpha: 0.75),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NudgeBubble extends StatelessWidget {
  final String text;
  final TextStyle? textStyle;

  const _NudgeBubble({
    required this.text,
    this.textStyle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.18)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: textStyle ??
            theme.textTheme.bodySmall?.copyWith(
              color: AppColors.text,
              fontWeight: FontWeight.w600,
              height: 1.25,
            ),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
