import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

enum TintType { info, success, warning, danger, neutral }

/// Reusable container with soft tint background, colored icon, and dark high-contrast text.
/// Adheres to Guyub.id color and accessibility rules (contrast >= 4.5:1).
final class TintedInfoBox extends StatelessWidget {
  const TintedInfoBox({
    required this.child,
    this.tint = TintType.info,
    this.icon,
    this.title,
    this.action,
    this.padding = const EdgeInsets.all(12),
    this.margin,
    super.key,
  });

  factory TintedInfoBox.info({
    required String text,
    IconData icon = Icons.info_outline,
    String? title,
    Widget? action,
    Key? key,
  }) => TintedInfoBox(
    key: key,
    tint: TintType.info,
    icon: icon,
    title: title,
    action: action,
    child: Text(text),
  );

  factory TintedInfoBox.warning({
    required String text,
    IconData icon = Icons.warning_amber_rounded,
    String? title,
    Widget? action,
    Key? key,
  }) => TintedInfoBox(
    key: key,
    tint: TintType.warning,
    icon: icon,
    title: title,
    action: action,
    child: Text(text),
  );

  factory TintedInfoBox.danger({
    required String text,
    IconData icon = Icons.error_outline,
    String? title,
    Widget? action,
    Key? key,
  }) => TintedInfoBox(
    key: key,
    tint: TintType.danger,
    icon: icon,
    title: title,
    action: action,
    child: Text(text),
  );

  factory TintedInfoBox.success({
    required String text,
    IconData icon = Icons.check_circle_outline,
    String? title,
    Widget? action,
    Key? key,
  }) => TintedInfoBox(
    key: key,
    tint: TintType.success,
    icon: icon,
    title: title,
    action: action,
    child: Text(text),
  );

  final Widget child;
  final TintType tint;
  final IconData? icon;
  final String? title;
  final Widget? action;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    final Color bgColor;
    final Color borderColor;
    final Color iconColor;
    final Color titleColor;

    switch (tint) {
      case TintType.info:
        bgColor = colors.primarySoft;
        borderColor = colors.primary.withValues(alpha: 0.3);
        iconColor = colors.primaryDark;
        titleColor = colors.primaryDark;
      case TintType.success:
        bgColor = colors.successBg;
        borderColor = colors.success.withValues(alpha: 0.3);
        iconColor = colors.success;
        titleColor = colors.textPrimary;
      case TintType.warning:
        bgColor = colors.warningBg;
        borderColor = colors.warning.withValues(alpha: 0.4);
        iconColor = const Color(
          0xFFB45309,
        ); // Dark amber for high contrast >= 4.5:1
        titleColor = const Color(0xFF92400E);
      case TintType.danger:
        bgColor = colors.dangerBg;
        borderColor = colors.danger.withValues(alpha: 0.3);
        iconColor = colors.danger;
        titleColor = colors.danger;
      case TintType.neutral:
        bgColor = colors.background;
        borderColor = colors.border;
        iconColor = colors.textSecondary;
        titleColor = colors.textPrimary;
    }

    return Container(
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (icon != null) ...[
                Icon(icon, color: iconColor, size: 20),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (title != null) ...[
                      Text(
                        title!,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                          color: titleColor,
                        ),
                      ),
                      const SizedBox(height: 4),
                    ],
                    DefaultTextStyle(
                      style: TextStyle(
                        fontSize: 13,
                        color: colors.textPrimary,
                        height: 1.4,
                      ),
                      child: child,
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (action != null) ...[const SizedBox(height: 10), action!],
        ],
      ),
    );
  }
}
