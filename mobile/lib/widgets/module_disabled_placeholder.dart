import 'package:flutter/material.dart';
import '../ui/app_colors.dart';

/// Shown when user opens a module screen but the module is disabled for the society.
/// Use from DB-only; no UI toggles.
class ModuleDisabledPlaceholder extends StatelessWidget {
  final VoidCallback? onBack;

  const ModuleDisabledPlaceholder({super.key, this.onBack});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: AppColors.text),
          onPressed: () {
            if (onBack != null) {
              onBack!();
            } else if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            }
          },
        ),
        title: const Text(
          'Feature unavailable',
          style: TextStyle(
              color: AppColors.text, fontWeight: FontWeight.w800, fontSize: 18),
        ),
        centerTitle: true,
      ),
      body: const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.lock_outline_rounded,
                  size: 64, color: AppColors.textMuted),
              SizedBox(height: 20),
              Text(
                'This feature is not enabled for your society.',
                style: TextStyle(
                  fontSize: 16,
                  color: AppColors.text2,
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
