import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../tasks/application/task_response.dart';
import '../../../tasks/application/task_response_boundary.dart';

/// Kartu ringkasan tugas di Beranda
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
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: context.appColors.border),
      ),
      child: Padding(
        padding: EdgeInsets.all(isCompact ? 12 : 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Icon(
                  Icons.checklist,
                  size: 20,
                  color: context.appColors.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Tugas Saya',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Content
            if (loading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (error != null)
              Column(
                children: [
                  Text(
                    error!,
                    style: TextStyle(color: context.appColors.danger),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('Coba Lagi'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                    ),
                  ),
                ],
              )
            else if (taskList == null)
              Text(
                'Memuat tugas…',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: context.appColors.textSecondary,
                    ),
              )
            else
              _buildTaskSummary(context),
          ],
        ),
      ),
    );
  }

  Widget _buildTaskSummary(BuildContext context) {
    final tasks = taskList!.items;
    
    // Hitung jumlah per status
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
          Icon(
            Icons.check_circle_outline,
            size: 48,
            color: context.appColors.textSecondary.withOpacity(0.5),
          ),
          const SizedBox(height: 8),
          Text(
            'Belum ada tugas aktif',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: context.appColors.textSecondary,
                ),
          ),
        ],
      );
    }

    return Column(
      children: [
        // Statistik
        Row(
          children: [
            Expanded(
              child: StatItem(
                icon: Icons.task_outlined,
                label: 'Saya Ikut',
                value: joinedCount.toString(),
                color: context.appColors.primary,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: StatItem(
                icon: Icons.schedule_outlined,
                label: 'Verifikasi',
                value: pendingVerificationCount.toString(),
                color: context.appColors.warning,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: StatItem(
                icon: Icons.check_circle_outlined,
                label: 'Selesai',
                value: verifiedCompleteCount.toString(),
                color: context.appColors.success,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // Tombol Lihat Semua
        OutlinedButton.icon(
          onPressed: onViewAll,
          icon: const Icon(Icons.arrow_forward, size: 18),
          label: const Text('Lihat Semua Tugas'),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(40),
          ),
        ),
      ],
    );
  }
}

/// Item statistik kecil
class StatItem extends StatelessWidget {
  const StatItem({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    super.key,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(height: 4),
          Text(
            value,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: context.appColors.textSecondary,
                  fontSize: 11,
                ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
