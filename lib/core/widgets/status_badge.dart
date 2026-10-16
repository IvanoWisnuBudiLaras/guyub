import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Badge status: success (hijau), warning (kuning), danger (merah), default (abu)
final class StatusBadge extends StatelessWidget {
  const StatusBadge({
    required this.label,
    this.type = StatusBadgeType.neutral,
    super.key,
  });

  final String label;
  final StatusBadgeType type;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final Color bgColor;
    final Color textColor;

    switch (type) {
      case StatusBadgeType.success:
        bgColor = colors.successBg;
        textColor = colors.success;
      case StatusBadgeType.warning:
        bgColor = colors.warningBg;
        textColor = colors.warning;
      case StatusBadgeType.danger:
        bgColor = colors.dangerBg;
        textColor = colors.danger;
      case StatusBadgeType.neutral:
        bgColor = colors.background;
        textColor = colors.textSecondary;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: textColor.withValues(alpha: 0.2)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ).copyWith(color: textColor),
      ),
    );
  }
}

enum StatusBadgeType { success, warning, danger, neutral }
