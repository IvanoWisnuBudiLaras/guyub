import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../application/task_response.dart';
import '../../application/task_response_boundary.dart';

/// Kartu tugas di list
class TaskCard extends StatelessWidget {
  const TaskCard({
    required this.task,
    required this.onTap,
    this.onJoin,
    super.key,
  });

  final ResidentTaskRecord task;
  final VoidCallback onTap;
  final VoidCallback? onJoin;

  @override
  Widget build(BuildContext context) {
    final template = task.templateSnapshot;
    final now = DateTime.now();
    final timeRemaining = task.deadline.difference(now);
    final isUrgent = timeRemaining.inHours < 24 && timeRemaining.inHours >= 0;
    final isPastDeadline = timeRemaining.isNegative;

    // Tentukan warna border berdasarkan urgency
    Color borderColor;
    Color urgencyColor;
    String urgencyLabel;

    if (isPastDeadline) {
      borderColor = context.appColors.danger;
      urgencyColor = context.appColors.danger;
      urgencyLabel = 'Terlewat';
    } else if (isUrgent) {
      borderColor = context.appColors.warning;
      urgencyColor = context.appColors.warning;
      urgencyLabel = 'Mendesak';
    } else {
      borderColor = context.appColors.border;
      urgencyColor = context.appColors.primary;
      urgencyLabel = 'Normal';
    }

    // Status badge
    String statusLabel;
    Color statusColor;
    IconData statusIcon;

    if (task.participation == ParticipationState.joined) {
      if (task.completion == CompletionState.verifiedComplete) {
        statusLabel = 'Selesai';
        statusColor = context.appColors.success;
        statusIcon = Icons.check_circle;
      } else if (task.completion == CompletionState.pendingRtVerification) {
        statusLabel = 'Menunggu Verifikasi';
        statusColor = context.appColors.warning;
        statusIcon = Icons.schedule;
      } else {
        statusLabel = 'Saya Ikut';
        statusColor = context.appColors.primary;
        statusIcon = Icons.task_alt;
      }
    } else if (task.participation == ParticipationState.declined) {
      statusLabel = 'Tidak Ikut';
      statusColor = context.appColors.textSecondary;
      statusIcon = Icons.cancel_outlined;
    } else {
      statusLabel = 'Belum Dijawab';
      statusColor = context.appColors.textSecondary;
      statusIcon = Icons.help_outline;
    }

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: borderColor, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: onTap,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header: urgency + deadline
                  Row(
                    children: [
                      // Urgency badge
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: urgencyColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          urgencyLabel,
                          style: TextStyle(
                            color: urgencyColor,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Deadline
                      Expanded(
                        child: Text(
                          _formatDeadline(timeRemaining),
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: context.appColors.textSecondary,
                              ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Title
                  Text(
                    template.title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (template.coreInstruction.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      template.coreInstruction,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: context.appColors.textSecondary,
                          ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const SizedBox(height: 12),
                  // Status badge
                  Row(
                    children: [
                      Icon(statusIcon, size: 16, color: statusColor),
                      const SizedBox(width: 4),
                      Text(
                        statusLabel,
                        style: TextStyle(
                          color: statusColor,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          // Action buttons
          Container(
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(
                  color: context.appColors.border.withOpacity(0.5),
                ),
              ),
            ),
            child: Row(
              children: [
                // Button sesuai status
                if (task.participation == ParticipationState.unresponded &&
                    onJoin != null) ...[
                  Expanded(
                    child: InkWell(
                      onTap: onJoin,
                      borderRadius: const BorderRadius.only(
                        bottomLeft: Radius.circular(12),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.check_circle_outline,
                              size: 18,
                              color: context.appColors.success,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Ikut',
                              style: Theme.of(context)
                                  .textTheme
                                  .labelLarge
                                  ?.copyWith(
                                    color: context.appColors.success,
                                    fontWeight: FontWeight.w600,
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Container(
                    width: 1,
                    height: 44,
                    color: context.appColors.border.withOpacity(0.5),
                  ),
                ],
                // Tombol Detail selalu ada
                Expanded(
                  child: InkWell(
                    onTap: onTap,
                    borderRadius: BorderRadius.only(
                      bottomRight: const Radius.circular(12),
                      bottomLeft: task.participation ==
                              ParticipationState.unresponded
                          ? Radius.zero
                          : const Radius.circular(12),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.article_outlined,
                            size: 18,
                            color: context.appColors.primary,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Detail',
                            style: Theme.of(context)
                                .textTheme
                                .labelLarge
                                ?.copyWith(
                                  color: context.appColors.primary,
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatDeadline(Duration timeRemaining) {
    if (timeRemaining.isNegative) {
      return 'Batas waktu terlewat';
    }
    if (timeRemaining.inDays > 0) {
      return '${timeRemaining.inDays} hari lagi';
    }
    if (timeRemaining.inHours > 0) {
      return '${timeRemaining.inHours} jam lagi';
    }
    return '${timeRemaining.inMinutes} menit lagi';
  }
}
