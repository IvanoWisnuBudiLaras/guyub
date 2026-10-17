import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Single source of truth for task category presentation (Indonesian label, icon, colors).
/// Never displays raw enums like HOUSEHOLD_PREPARATION to users.
final class TaskCategoryPresentation {
  const TaskCategoryPresentation({
    required this.label,
    required this.icon,
    required this.tintColor,
    required this.iconColor,
  });

  final String label;
  final IconData icon;
  final Color tintColor;
  final Color iconColor;

  static TaskCategoryPresentation fromRaw(String? raw, BuildContext context) {
    final colors = context.appColors;
    final normalized = (raw ?? '').trim().toUpperCase();

    switch (normalized) {
      case 'HOUSEHOLD_PREPARATION':
      case 'PERSIAPAN_RUMAH_TANGGA':
        return TaskCategoryPresentation(
          label: 'Persiapan Rumah Tangga',
          icon: Icons.home_work_outlined,
          tintColor: colors.primarySoft,
          iconColor: colors.primaryDark,
        );
      case 'INFRASTRUCTURE':
      case 'INFRASTRUKTUR':
        return TaskCategoryPresentation(
          label: 'Infrastruktur',
          icon: Icons.construction_outlined,
          tintColor: const Color(0xFFE0F2FE),
          iconColor: const Color(0xFF0369A1),
        );
      case 'LOGISTICS':
      case 'LOGISTIK':
        return TaskCategoryPresentation(
          label: 'Logistik',
          icon: Icons.inventory_2_outlined,
          tintColor: const Color(0xFFFEF3C7),
          iconColor: const Color(0xFFB45309),
        );
      case 'DRAINAGE':
      case 'DRAINASE':
        return TaskCategoryPresentation(
          label: 'Drainase',
          icon: Icons.water_damage_outlined,
          tintColor: const Color(0xFFE0F7FA),
          iconColor: const Color(0xFF00838F),
        );
      case 'ENVIRONMENTAL_CLEANUP':
      case 'KEBERSIHAN_LINGKUNGAN':
        return TaskCategoryPresentation(
          label: 'Kebersihan Lingkungan',
          icon: Icons.cleaning_services_outlined,
          tintColor: const Color(0xFFDCFCE7),
          iconColor: const Color(0xFF15803D),
        );
      case 'SAFE_VISUAL_INSPECTION':
      case 'PENGAMATAN_AMAN':
        return TaskCategoryPresentation(
          label: 'Pengamatan Tempat Aman',
          icon: Icons.visibility_outlined,
          tintColor: const Color(0xFFF3E8FF),
          iconColor: const Color(0xFF7E22CE),
        );
      case 'EVACUATION':
      case 'EVAKUASI':
        return TaskCategoryPresentation(
          label: 'Evakuasi',
          icon: Icons.directions_run_outlined,
          tintColor: const Color(0xFFFEE2E2),
          iconColor: const Color(0xFFB91C1C),
        );
      default:
        // Format SCREAMING_SNAKE_CASE to Title Case
        final friendly = normalized.isEmpty
            ? 'Umum'
            : normalized
                  .split('_')
                  .map(
                    (word) => word.isEmpty
                        ? ''
                        : '${word[0]}${word.substring(1).toLowerCase()}',
                  )
                  .join(' ');
        return TaskCategoryPresentation(
          label: friendly,
          icon: Icons.assignment_outlined,
          tintColor: colors.background,
          iconColor: colors.primary,
        );
    }
  }
}

/// Category chip displaying the human-friendly Indonesian label.
final class TaskCategoryChip extends StatelessWidget {
  const TaskCategoryChip({
    required this.category,
    this.showIcon = true,
    this.compact = false,
    super.key,
  });

  final String? category;
  final bool showIcon;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final info = TaskCategoryPresentation.fromRaw(category, context);

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical: compact ? 3 : 5,
      ),
      decoration: BoxDecoration(
        color: info.tintColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: info.iconColor.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showIcon) ...[
            Icon(info.icon, size: compact ? 12 : 14, color: info.iconColor),
            SizedBox(width: compact ? 4 : 6),
          ],
          Flexible(
            child: Text(
              info.label,
              style: TextStyle(
                fontSize: compact ? 11 : 12,
                fontWeight: FontWeight.w600,
                color: info.iconColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
