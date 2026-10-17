import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/alert_banner.dart';
import '../../../../core/widgets/inline_action_button.dart';
import '../../../../core/widgets/metric_strip.dart';
import '../../../../core/widgets/section_card.dart';
import '../../../tasks/application/task_response.dart';
import '../../../tasks/application/task_response_boundary.dart';

/// Kartu ringkasan tugas di Beranda Warga
class TaskSummaryCard extends StatelessWidget {
  const TaskSummaryCard({
    required this.taskList,
    required this.loading,
    required this.error,
    required this.isCompact,
    required this.onViewAll,
    required this.onRetry,
    super.key,
  });

  final ResidentTaskList? taskList;
  final bool loading;
  final String? error;
  final bool isCompact;
  final VoidCallback onViewAll;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: 'Tugas Saya',
      icon: Icons.checklist,
      children: [
        if (loading)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: CircularProgressIndicator(),
            ),
          )
        else if (error != null)
          AlertBanner.danger(
            title: 'Gagal Memuat Tugas',
            message: error!,
            actionLabel: 'Coba Lagi',
            actionIcon: Icons.refresh,
            onAction: onRetry,
          )
        else if (taskList == null)
          Text(
            'Memuat tugas…',
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: context.appColors.textSecondary),
          )
        else
          _buildTaskSummary(context),
      ],
    );
  }

  Widget _buildTaskSummary(BuildContext context) {
    final colors = context.appColors;
    final tasks = taskList!.items;

    var joinedCount = 0;
    var pendingVerificationCount = 0;
    var verifiedCompleteCount = 0;

    for (final task in tasks) {
      if (task.participation == ParticipationState.joined) {
        joinedCount++;
        if (task.completion == CompletionState.pendingRtVerification) {
          pendingVerificationCount++;
        } else if (task.completion == CompletionState.verifiedComplete) {
          verifiedCompleteCount++;
        }
      }
    }

    if (tasks.isEmpty) {
      return Column(
        children: [
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                children: [
                  Icon(
                    Icons.check_circle_outline,
                    size: 36,
                    color: colors.textSecondary.withValues(alpha: 0.5),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Belum ada tugas aktif',
                    style: Theme.of(context).textTheme.bodyMedium
                        ?.copyWith(color: colors.textSecondary),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: InlineActionButton(
              onPressed: onViewAll,
              icon: Icons.arrow_forward,
              label: 'Lihat Tugas Kesiapsiagaan',
              variant: InlineActionButtonVariant.outlined,
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MetricStrip(
          items: [
            MetricItemData(
              icon: Icons.task_alt_outlined,
              value: joinedCount.toString(),
              label: 'Saya Ikut',
              accentColor: colors.primary,
              backgroundColor: colors.primary.withValues(alpha: 0.12),
            ),
            MetricItemData(
              icon: Icons.schedule_outlined,
              value: pendingVerificationCount.toString(),
              label: 'Verifikasi',
              accentColor: colors.warning,
              backgroundColor: colors.warning.withValues(alpha: 0.12),
            ),
            MetricItemData(
              icon: Icons.check_circle_outline,
              value: verifiedCompleteCount.toString(),
              label: 'Selesai',
              accentColor: colors.success,
              backgroundColor: colors.success.withValues(alpha: 0.12),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: InlineActionButton(
            onPressed: onViewAll,
            icon: Icons.arrow_forward,
            label: 'Lihat Tugas Kesiapsiagaan',
            variant: InlineActionButtonVariant.outlined,
          ),
        ),
      ],
    );
  }
}
