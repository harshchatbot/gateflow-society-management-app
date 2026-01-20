import 'dart:ui';
import 'package:flutter/material.dart';
import 'app_colors.dart';

class GlassLoader extends StatelessWidget {
  final bool show;
  final String? message;

  const GlassLoader({
    super.key,
    required this.show,
    this.message,
  });

  @override
  Widget build(BuildContext context) {
    if (!show) return const SizedBox.shrink();

    return Stack(
      children: [
        // Dim + blur background
        Positioned.fill(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(
              color: Colors.black.withOpacity(0.10),
            ),
          ),
        ),

        // Center glass card
        Center(
          child: Container(
            width: 220,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.72),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppColors.border.withOpacity(0.9)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.06),
                  blurRadius: 24,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  height: 34,
                  width: 34,
                  child: CircularProgressIndicator(strokeWidth: 3),
                ),
                if ((message ?? "").trim().isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    message!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.text,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}
