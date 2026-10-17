import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

/// Clean 3-column metric cards showing RT operational readiness at a glance.
final class OperatorMetricsCard extends StatelessWidget {
  const OperatorMetricsCard({
    this.activeTasksCount,
    this.pendingVerificationsCount,
    this.vulnerableResidentsCount,
    this.onActiveTasksTap,
    this.onVerificationsTap,
    this.onVulnerableResidentsTap,
    super.key,
  });

  final int? activeTasksCount;
  final int? pendingVerificationsCount;
  final int? vulnerableResidentsCount;
  final VoidCallback? onActiveTasksTap;
  final VoidCallback? onVerificationsTap;
  final VoidCallback? onVulnerableResidentsTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.border),
      ),
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
      child: Row(
        children: [
          Expanded(
            child: _MetricItem(
              label: 'Tugas Aktif',
              value: activeTasksCount != null ? '$activeTasksCount' : '-',
              icon: Icons.task_alt,
              accentColor: colors.primary,
              backgroundColor: colors.primarySoft,
              onTap: onActiveTasksTap,
            ),
          ),
          Container(height: 36, width: 1, color: colors.border),
          Expanded(
            child: _MetricItem(
              label: 'Verifikasi',
              value: pendingVerificationsCount != null
                  ? '$pendingVerificationsCount'
                  : '-',
              icon: Icons.fact_check_outlined,
              accentColor: colors.warning,
              backgroundColor: colors.warningBg,
              onTap: onVerificationsTap,
            ),
          ),
          Container(height: 36, width: 1, color: colors.border),
          Expanded(
            child: _MetricItem(
              label: 'Warga Rentan',
              value: vulnerableResidentsCount != null
                  ? '$vulnerableResidentsCount'
                  : '-',
              icon: Icons.support_outlined,
              accentColor: colors.success,
              backgroundColor: colors.successBg,
              onTap: onVulnerableResidentsTap,
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricItem extends StatelessWidget {
  const _MetricItem({
    required this.label,
    required this.value,
    required this.icon,
    required this.accentColor,
    required this.backgroundColor,
    this.onTap,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color accentColor;
  final Color backgroundColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: backgroundColor,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: accentColor, size: 14),
            ),
            const SizedBox(width: 6),
            Text(
              value,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: colors.textPrimary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          label,
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 11,
            color: colors.textSecondary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );

    if (onTap == null) return content;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: content,
      ),
    );
  }
}
