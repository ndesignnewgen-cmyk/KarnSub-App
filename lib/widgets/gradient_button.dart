import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Shared primary call-to-action button: gradient fill + soft shadow, with an
/// optional leading icon and a loading state. Used across the app so every main
/// action looks identical (Export, Save, dialog confirm, …).
class GradientButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final double height;
  final bool loading;
  final bool expand;
  final Gradient? gradient;
  final Color? solidColor; // overrides the gradient (e.g. success/danger state)

  const GradientButton({
    super.key,
    required this.label,
    this.icon,
    this.onTap,
    this.height = 54,
    this.loading = false,
    this.expand = true,
    this.gradient,
    this.solidColor,
  });

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null || loading;
    final g = solidColor == null ? (gradient ?? AppGradients.primary) : null;
    return GestureDetector(
      onTap: disabled ? null : onTap,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 150),
        opacity: disabled && !loading ? 0.55 : 1,
        child: Container(
          height: height,
          width: expand ? double.infinity : null,
          padding: expand ? null : const EdgeInsets.symmetric(horizontal: 22),
          decoration: BoxDecoration(
            gradient: g,
            color: solidColor,
            borderRadius: BorderRadius.circular(AppRadius.md),
            boxShadow: [
              BoxShadow(
                color: (solidColor ?? AppColors.primary).withOpacity(0.38),
                blurRadius: 14,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (loading)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    color: Colors.white,
                  ),
                )
              else if (icon != null)
                Icon(icon, color: Colors.white, size: 21),
              if ((icon != null || loading)) const SizedBox(width: 9),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15.5,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
