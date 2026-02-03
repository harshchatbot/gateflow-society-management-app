import 'dart:async';
import 'package:flutter/material.dart';
import '../ui/sentinel_theme.dart';

/// Mascot illustration (Senti) with optional subtle eye-blink for calm states.
/// Use [kind] to identify the illustration (e.g. 'otp', 'pending', 'idle', 'cab', 'delivery', 'visitor').
/// Blink runs only for 'otp', 'pending', 'idle'; not for 'warning', 'alert', or error states.
class SentinelIllustration extends StatefulWidget {
  final String kind;
  final double? height;

  const SentinelIllustration({
    super.key,
    required this.kind,
    this.height,
  });

  @override
  State<SentinelIllustration> createState() => _SentinelIllustrationState();
}

class _SentinelIllustrationState extends State<SentinelIllustration> {
  static const Set<String> _blinkKinds = {'otp', 'pending', 'idle'};
  static const String _closedEyesAsset = 'assets/mascot/senti_eyes_closed.png';

  static const Duration _blinkInterval = Duration(seconds: 5);
  static const Duration _eyesClosedDuration = Duration(milliseconds: 170);

  bool _eyesOpen = true;
  Timer? _intervalTimer;
  Timer? _openTimer;

  static String _openEyesAssetFor(String kind) {
    switch (kind) {
      case 'warning':
        return 'assets/mascot/senti_warning.png';
      case 'alert':
        return 'assets/mascot/senti_alert.png';
      case 'idle':
      case 'otp':
      case 'pending':
        return 'assets/mascot/senti_idle.png';
      case 'happy':
        return 'assets/mascot/senti_happy.png';
      case 'namaste':
        return 'assets/mascot/senti_namaste.png';
      case 'cab':
      case 'delivery':
      case 'visitor':
      case 'empty_visitors':
        return 'assets/mascot/senti_idle.png';
      default:
        return 'assets/mascot/senti_idle.png';
    }
  }

  void _cancelTimers() {
    _intervalTimer?.cancel();
    _intervalTimer = null;
    _openTimer?.cancel();
    _openTimer = null;
  }

  void _scheduleBlink() {
    if (!_blinkKinds.contains(widget.kind)) return;
    _cancelTimers();
    _intervalTimer = Timer.periodic(_blinkInterval, (_) {
      if (!mounted) return;
      setState(() => _eyesOpen = false);
      _openTimer?.cancel();
      _openTimer = Timer(_eyesClosedDuration, () {
        if (!mounted) return;
        setState(() => _eyesOpen = true);
      });
    });
  }

  @override
  void initState() {
    super.initState();
    _scheduleBlink();
  }

  @override
  void didUpdateWidget(SentinelIllustration oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.kind != widget.kind) {
      if (!_blinkKinds.contains(widget.kind)) {
        _cancelTimers();
        if (mounted) setState(() => _eyesOpen = true);
      } else {
        _scheduleBlink();
      }
    }
  }

  @override
  void dispose() {
    _cancelTimers();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final String asset = _eyesOpen
        ? _openEyesAssetFor(widget.kind)
        : _closedEyesAsset;

    final h = widget.height ?? 140;
    return Container(
      height: h,
      width: double.infinity,
      decoration: BoxDecoration(
        color: SentinelColors.card,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: SentinelColors.border),
      ),
      child: Center(
        child: Image.asset(
          asset,
          fit: BoxFit.contain,
          height: (h * 120 / 140).clamp(40.0, 120.0),
          width: 160,
          errorBuilder: (_, __, ___) => _buildFallback(),
        ),
      ),
    );
  }

  Widget _buildFallback() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          Icons.shield_rounded,
          size: 48,
          color: SentinelColors.primary.withOpacity(0.6),
        ),
        const SizedBox(height: 8),
        Text(
          'Illustration: ${widget.kind}',
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: SentinelColors.textSecondary,
          ),
        ),
      ],
    );
  }
}
