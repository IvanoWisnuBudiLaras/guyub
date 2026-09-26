import 'package:flutter/material.dart';
import '../../app/theme/app_colors.dart';

/// Card dasar dengan radius & border konsisten sesuai mockup.
/// [filled] = true untuk versi solid warna (mis. card role "Ketua RT/RW"),
/// false untuk versi outline (mis. card role "Warga").
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.onTap,
    this.filled = false,
    this.fillColor,
    this.padding = const EdgeInsets.all(16),
  });

  final Widget child;
  final VoidCallback? onTap;
  final bool filled;
  final Color? fillColor;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: filled ? (fillColor ?? AppColors.primaryBlue) : Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: filled
                ? null
                : Border.all(color: AppColors.borderGray),
          ),
          child: child,
        ),
      ),
    );
  }
}
