import 'package:flutter/material.dart';

import '../ui/app_loader.dart';

class PrimaryButton extends StatelessWidget {
  final String? text;
  final String? label;
  final String? title;

  final VoidCallback? onPressed;
  final VoidCallback? onTap;

  final bool loading;
  final bool? isLoading;

  final bool disabled;
  final IconData? icon;
  final bool fullWidth;

  const PrimaryButton({
    super.key,
    this.text,
    this.label,
    this.title,
    this.onPressed,
    this.onTap,
    this.loading = false,
    this.isLoading,
    this.disabled = false,
    this.icon,
    this.fullWidth = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final btnText = (text ?? label ?? title ?? "Continue").trim();
    final effectiveLoading = isLoading ?? loading;

    final callback =
        (disabled || effectiveLoading) ? null : (onPressed ?? onTap);

    final child = Row(
      mainAxisSize: fullWidth ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (effectiveLoading) ...[
          SizedBox(
            width: 18,
            height: 18,
            child: AppLoader.inline(size: 18),
          ),
          const SizedBox(width: 10),
        ] else if (icon != null) ...[
          Icon(icon, size: 18),
          const SizedBox(width: 8),
        ],
        Text(
          btnText,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ],
    );

    return SizedBox(
      width: fullWidth ? double.infinity : null,
      height: 48,
      child: ElevatedButton(
        onPressed: callback,
        style: ElevatedButton.styleFrom(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          backgroundColor: theme.colorScheme.primary,
          foregroundColor: theme.colorScheme.onPrimary,
          elevation: 0,
        ),
        child: child,
      ),
    );
  }
}
