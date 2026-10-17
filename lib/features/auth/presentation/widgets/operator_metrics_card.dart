import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/metric_strip.dart';

/// Clean 3-column metric cards showing RT operational readiness at a glance.
/// Diangkat dari implementasi acuan dan mendelegasikan ke shared [MetricStrip].
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

    return MetricStrip(
      items: [
        MetricItemData(
          label: 'Tugas Aktif',
          value: activeTasksCount != null ? '$activeTasksCount' : '-',
          icon: Icons.task_alt,
          accentColor: colors.primary,
          backgroundColor: colors.primarySoft,
          onTap: onActiveTasksTap,
        ),
        MetricItemData(
          label: 'Verifikasi',
          value: pendingVerificationsCount != null
              ? '$pendingVerificationsCount'
              : '-',
          icon: Icons.fact_check_outlined,
          accentColor: colors.warning,
          backgroundColor: colors.warningBg,
          onTap: onVerificationsTap,
        ),
        MetricItemData(
          label: 'Warga Rentan',
          value: vulnerableResidentsCount != null
              ? '$vulnerableResidentsCount'
              : '-',
          icon: Icons.support_outlined,
          accentColor: colors.success,
          backgroundColor: colors.successBg,
          onTap: onVulnerableResidentsTap,
        ),
      ],
    );
  }
}
