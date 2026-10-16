import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Badge prioritas tugas: tinggi (merah), sedang (kuning), rendah (abu)
final class PriorityBadge extends StatelessWidget {
  const PriorityBadge({required this.priority, super.key});

  final TaskPriority priority;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final String label;
    final Color bgColor;
    final Color textColor;

    switch (priority) {
      case TaskPriority.high:
        label = 'Prioritas Tinggi';
        bgColor = colors.dangerBg;
        textColor = colors.danger;
      case TaskPriority.medium:
        label = 'Prioritas Sedang';
        bgColor = colors.warningBg;
        textColor = colors.warning;
      case TaskPriority.low:
        label = 'Prioritas Rendah';
        bgColor = colors.background;
        textColor = colors.textSecondary;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ).copyWith(color: textColor),
      ),
    );
  }
}

enum TaskPriority { high, medium, low }
