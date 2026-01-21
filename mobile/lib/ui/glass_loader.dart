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
            filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
            child: Container(
              color: AppColors.bg.withOpacity(0.92),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
                  decoration: BoxDecoration(
                    color: AppColors.surface.withOpacity(0.80),
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
                      // Netflix-ish shimmer orb
                      Shimmer.fromColors(
                        baseColor: AppColors.border.withOpacity(0.65),
                        highlightColor: AppColors.text.withOpacity(0.9),
                        child: Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),

                      Text(
                        message.toUpperCase(),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 6.0,
                          color: AppColors.text,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 14),

                      // Shimmer bar
                      Shimmer.fromColors(
                        baseColor: AppColors.border.withOpacity(0.7),
                        highlightColor: AppColors.text.withOpacity(0.95),
                        child: Container(
                          width: 160,
                          height: 6,
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
