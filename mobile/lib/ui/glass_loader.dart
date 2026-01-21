import 'package:shimmer/shimmer.dart';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'app_colors.dart';

class GlassLoader extends StatelessWidget {
  final bool show;
  final String message;

  const GlassLoader({
    super.key,
    required this.show,
    this.message = "Synchronizing…",
  });

  @override
  Widget build(BuildContext context) {
    if (!show) return const SizedBox.shrink();

    return Positioned.fill(
      child: AbsorbPointer(
        absorbing: true,
        child: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12), // Slightly reduced blur for performance
            child: Container(
              color: AppColors.bg.withOpacity(0.85), // Matches your premium background
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(color: AppColors.border),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.text.withOpacity(0.06),
                        blurRadius: 30,
                        offset: const Offset(0, 15),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 1. Brand-Themed Spinner
                      SizedBox(
                        width: 45,
                        height: 45,
                        child: CircularProgressIndicator(
                          strokeWidth: 5,
                          strokeCap: StrokeCap.round, // Modern rounded edges
                          valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
                          backgroundColor: AppColors.primarySoft,
                        ),
                      ),
                      const SizedBox(height: 24),

                      // 2. Themed Message
                      Text(
                        message.toUpperCase(),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 3.5, // Refined letter spacing
                          color: AppColors.text,
                        ),
                      ),
                      const SizedBox(height: 18),

                      // 3. Primary Shimmer Bar
                      Shimmer.fromColors(
                        baseColor: AppColors.primarySoft, // Blue tint base
                        highlightColor: AppColors.primary.withOpacity(0.4), // Primary blue highlight
                        child: Container(
                          width: 120,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                      ),
                    ],
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