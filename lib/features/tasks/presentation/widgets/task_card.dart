import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/task_category_presentation.dart';
import '../../application/task_response.dart';
import '../../application/task_response_boundary.dart';

/// Kartu tugas di list dengan ikon kategori di sisi kiri dalam kotak tint,
/// chip estimasi waktu, status badge, dan tombol aksi berjarak.
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
    final colors = context.appColors;
    final template = task.templateSnapshot;
    final now = DateTime.now();
    final timeRemaining = task.deadline.difference(now);
    final isUrgent = timeRemaining.inHours < 24 && timeRemaining.inHours >= 0;
    final isPastDeadline = timeRemaining.isNegative;

    final categoryInfo = TaskCategoryPresentation.fromRaw(
      template.category,
      context,
    );

    // Deadline and urgency presentation
    final Color deadlineColor;
    if (isPastDeadline) {
      deadlineColor = colors.danger;
    } else if (isUrgent) {
      deadlineColor = const Color(0xFFB45309); // Dark amber for high contrast
    } else {
      deadlineColor = colors.textSecondary;
    }

    // Status badge mapping
    final String statusLabel;
    final Color statusColor;
    final Color statusBg;
    final IconData statusIcon;

    if (task.participation == ParticipationState.joined) {
      if (task.completion == CompletionState.verifiedComplete) {
        statusLabel = 'Selesai';
        statusColor = colors.success;
        statusBg = colors.successBg;
        statusIcon = Icons.check_circle;
      } else if (task.completion == CompletionState.pendingRtVerification) {
        statusLabel = 'Menunggu Verifikasi';
        statusColor = const Color(0xFFB45309);
        statusBg = colors.warningBg;
        statusIcon = Icons.schedule;
      } else {
        statusLabel = 'Saya Ikut';
        statusColor = colors.primary;
        statusBg = colors.primarySoft;
        statusIcon = Icons.task_alt;
      }
    } else if (task.participation == ParticipationState.declined) {
      statusLabel = 'Tidak Ikut';
      statusColor = colors.textSecondary;
      statusBg = colors.background;
      statusIcon = Icons.cancel_outlined;
    } else {
      statusLabel = 'Belum Dijawab';
      statusColor = colors.textSecondary;
      statusBg = colors.background;
      statusIcon = Icons.help_outline;
    }

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: onTap,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Left side: category icon in tinted container
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: categoryInfo.tintColor,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: categoryInfo.iconColor.withValues(alpha: 0.2),
                      ),
                    ),
                    child: Icon(
                      categoryInfo.icon,
                      color: categoryInfo.iconColor,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 14),

                  // Middle & right: Task info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Top row: Chips (Category + Duration) & Status badge
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          alignment: WrapAlignment.spaceBetween,
                          children: [
                            Wrap(
                              spacing: 6,
                              runSpacing: 4,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                TaskCategoryChip(
                                  category: template.category,
                                  compact: true,
                                ),
                                if (template.estimatedDurationMinutes != null)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: colors.background,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: colors.border),
                                    ),
                                    child: Text(
                                      '~${template.estimatedDurationMinutes} mnt',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: colors.textSecondary,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: statusBg,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: statusColor.withValues(alpha: 0.25),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    statusIcon,
                                    size: 12,
                                    color: statusColor,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    statusLabel,
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: statusColor,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),

                        // Title
                        Text(
                          template.title,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: colors.textPrimary,
                              ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 6),

                        // Core instruction preview
                        if (template.coreInstruction.isNotEmpty) ...[
                          Text(
                            template.coreInstruction,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: colors.textSecondary,
                                  height: 1.3,
                                ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 8),
                        ],

                        // Deadline with high-contrast color
                        Row(
                          children: [
                            Icon(
                              Icons.schedule,
                              size: 14,
                              color: deadlineColor,
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                'Batas: ${_formatDeadline(timeRemaining)}',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: deadlineColor,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Bottom action buttons with ripple
          Container(
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(color: colors.border.withValues(alpha: 0.6)),
              ),
            ),
            child: Row(
              children: [
                if (task.participation == ParticipationState.unresponded &&
                    onJoin != null) ...[
                  Expanded(
                    child: InkWell(
                      onTap: onJoin,
                      borderRadius: const BorderRadius.only(
                        bottomLeft: Radius.circular(16),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.check_circle_outline,
                              size: 18,
                              color: colors.success,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Ikut',
                              style: Theme.of(context).textTheme.labelLarge
                                  ?.copyWith(
                                    color: colors.success,
                                    fontWeight: FontWeight.w700,
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
                    color: colors.border.withValues(alpha: 0.6),
                  ),
                ],
                Expanded(
                  child: InkWell(
                    onTap: onTap,
                    borderRadius: BorderRadius.only(
                      bottomRight: const Radius.circular(16),
                      bottomLeft:
                          task.participation ==
                                  ParticipationState.unresponded &&
                              onJoin != null
                          ? Radius.zero
                          : const Radius.circular(16),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.article_outlined,
                            size: 18,
                            color: colors.primary,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Detail',
                            style: Theme.of(context).textTheme.labelLarge
                                ?.copyWith(
                                  color: colors.primary,
                                  fontWeight: FontWeight.w700,
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
      return 'Terlewat';
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
