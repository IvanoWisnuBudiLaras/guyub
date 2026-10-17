import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/guyub_tokens.dart';
import '../../../../core/widgets/alert_banner.dart';
import '../../../../core/widgets/mockup_widgets.dart';
import '../../../../core/widgets/section_card.dart';
import '../../../tasks/application/task_response.dart';
import '../../../tasks/application/task_response_boundary.dart';

/// Kartu ringkasan tugas di Beranda Warga sesuai desain proposal
final class TaskSummaryCard extends StatelessWidget {
  const TaskSummaryCard({
    required this.taskList,
    required this.loading,
    required this.error,
    required this.isCompact,
    required this.onViewAll,
    required this.onRetry,
    this.onProposeTask,
    super.key,
  });

  final ResidentTaskList? taskList;
  final bool loading;
  final String? error;
  final bool isCompact;
  final VoidCallback onViewAll;
  final VoidCallback onRetry;
  final VoidCallback? onProposeTask;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return SectionCard(
        title: 'Tugas Saya',
        icon: Icons.checklist,
        children: const [
          Center(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: CircularProgressIndicator(),
            ),
          ),
        ],
      );
    }

    if (error != null) {
      return SectionCard(
        title: 'Tugas Saya',
        icon: Icons.checklist,
        children: [
          AlertBanner.danger(
            title: 'Gagal Memuat Tugas',
            message: error!,
            actionLabel: 'Coba Lagi',
            actionIcon: Icons.refresh,
            onAction: onRetry,
          ),
        ],
      );
    }

    if (taskList == null) {
      return SectionCard(
        title: 'Tugas Saya',
        icon: Icons.checklist,
        children: [
          Text(
            'Memuat tugas…',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: context.appColors.textSecondary,
            ),
          ),
        ],
      );
    }

    final tasks = taskList!.items;
    var inProgressCount = 0;
    var verifiedCompleteCount = 0;
    var notStartedCount = 0;
    ResidentTaskRecord? priorityTask;

    for (final task in tasks) {
      if (task.completion == CompletionState.verifiedComplete) {
        verifiedCompleteCount++;
      } else if (task.participation == ParticipationState.joined) {
        inProgressCount++;
        priorityTask ??= task;
      } else {
        notStartedCount++;
        priorityTask ??= task;
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1. TUGAS SAYA Header & 3 Stat Tiles
        const GuyubSmallLabel('TUGAS SAYA'),
        GuyubStatRow(
          tiles: [
            GuyubStatTile(
              value: '$inProgressCount',
              label: 'Dalam proses',
              color: GuyubTokens.green,
              onTap: onViewAll,
            ),
            GuyubStatTile(
              value: '$verifiedCompleteCount',
              label: 'Selesai',
              color: const Color(0xFF1E293B),
              onTap: onViewAll,
            ),
            GuyubStatTile(
              value: '$notStartedCount',
              label: 'Belum mulai',
              color: GuyubTokens.orange,
              onTap: onViewAll,
            ),
          ],
        ),
        const SizedBox(height: 12),

        // 2. PRIORITAS — segera diselesaikan
        if (priorityTask != null) ...[
          _buildPriorityCard(context, priorityTask),
          const SizedBox(height: 12),
        ],

        // 3. Lainnya (Baris Navigasi)
        const GuyubSmallLabel('Lainnya'),
        GuyubNavRow(
          icon: Icons.assignment_outlined,
          title: 'Semua Tugas',
          subtitle: '${tasks.length} Tugas tersedia',
          onTap: onViewAll,
        ),
        if (onProposeTask != null)
          GuyubNavRow(
            icon: Icons.outlined_flag,
            title: 'Usulkan Tugas baru',
            subtitle: 'Ditinjau Ketua RT sebelum disetujui',
            onTap: onProposeTask!,
          ),
      ],
    );
  }

  Widget _buildPriorityCard(BuildContext context, ResidentTaskRecord task) {
    final colors = context.appColors;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(GuyubTokens.cardRadius),
        border: Border.all(color: GuyubTokens.yellowBorder, width: 1.2),
        boxShadow: GuyubTokens.softShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Yellow bar header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: const BoxDecoration(
              color: GuyubTokens.yellowFill,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(GuyubTokens.cardRadius - 1),
                topRight: Radius.circular(GuyubTokens.cardRadius - 1),
              ),
            ),
            child: const Row(
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  size: 15,
                  color: Color(0xFFB45309),
                ),
                SizedBox(width: 6),
                Text(
                  'PRIORITAS — segera diselesaikan',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF92400E),
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  task.templateSnapshot.title,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1E293B),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Batas: ${task.deadline.difference(DateTime.now()).inHours <= 24 ? "Besok" : "${task.deadline.day}/${task.deadline.month}"}',
                  style: TextStyle(fontSize: 11, color: colors.textSecondary),
                ),
                if (task.locationReference != null) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(
                        Icons.location_on_outlined,
                        size: 13,
                        color: colors.textSecondary,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          task.locationReference!,
                          style: TextStyle(
                            fontSize: 11,
                            color: colors.textSecondary,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
