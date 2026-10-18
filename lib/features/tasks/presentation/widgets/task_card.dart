import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/guyub_tokens.dart';
import '../../../../core/utils/indonesian_date_formatter.dart';
import '../../application/task_response.dart';
import '../../application/task_response_boundary.dart';

/// Kartu tugas pada Daftar Tugas sesuai desain proposal.
///
/// Menampilkan badge prioritas ("tinggi" merah / "Sedang" abu-abu),
/// sisa waktu, judul tugas, batas waktu, dan dua tombol aksi:
/// "Lihat Detail" dan "Ikut" / "Saya Ikut".
final class TaskCard extends StatelessWidget {
  const TaskCard({
    required this.task,
    required this.onTap,
    this.onJoin,
    super.key,
  });

  final ResidentTaskRecord task;
  final VoidCallback onTap;
  final VoidCallback? onJoin;

  String _formatTime(Duration diff) {
    if (diff.isNegative) return 'Terlewat';
    if (diff.inDays > 0) return '${diff.inDays} hari';
    if (diff.inHours > 0) return '${diff.inHours} jam';
    return '${diff.inMinutes} mnt';
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final template = task.templateSnapshot;
    final now = DateTime.now();
    final timeRemaining = task.deadline.difference(now);
    final isUrgent = timeRemaining.inHours < 48 && !timeRemaining.isNegative;

    final isJoined = task.participation == ParticipationState.joined;
    final isVerified = task.completion == CompletionState.verifiedComplete;
    final isPendingVerification =
        task.completion == CompletionState.pendingRtVerification;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(GuyubTokens.cardRadius),
        border: Border.all(color: GuyubTokens.greyBorder),
        boxShadow: GuyubTokens.softShadow,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(GuyubTokens.cardRadius),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  alignment: WrapAlignment.spaceBetween,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: isUrgent
                                ? const Color(0xFFFEE2E2)
                                : GuyubTokens.greyFill,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: isUrgent
                                  ? const Color(0xFFEF4444)
                                  : GuyubTokens.greyBorder,
                            ),
                          ),
                          child: Text(
                            isUrgent ? 'tinggi' : 'Sedang',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: isUrgent
                                  ? const Color(0xFFEF4444)
                                  : colors.textSecondary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _formatTime(timeRemaining),
                          style: TextStyle(
                            fontSize: 11,
                            color: colors.textSecondary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                    if (isVerified)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: GuyubTokens.greenSoft,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Text(
                          'Selesai',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: GuyubTokens.green,
                          ),
                        ),
                      )
                    else if (isPendingVerification)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: GuyubTokens.yellowFill,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Text(
                          'Menunggu Verifikasi',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF92400E),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),

                // Title
                Text(
                  template.title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1E293B),
                  ),
                ),
                const SizedBox(height: 4),

                // Deadline
                Text(
                  'Batas: ${IndonesianDateFormatter.formatDateOnly(task.deadline)}, '
                  '${task.deadline.hour.toString().padLeft(2, '0')}:${task.deadline.minute.toString().padLeft(2, '0')}',
                  style: TextStyle(fontSize: 11, color: colors.textSecondary),
                ),
                const SizedBox(height: 14),

                // Action buttons row
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 36),
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          side: const BorderSide(color: GuyubTokens.greyBorder),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        onPressed: onTap,
                        child: Text(
                          'Lihat Detail',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: colors.textPrimary,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: isJoined
                          ? OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size(0, 36),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 8,
                                ),
                                side: const BorderSide(
                                  color: GuyubTokens.green,
                                  width: 1.5,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              onPressed: onTap,
                              child: const Text(
                                'Saya Ikut',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: GuyubTokens.green,
                                ),
                              ),
                            )
                          : FilledButton(
                              style: FilledButton.styleFrom(
                                backgroundColor: GuyubTokens.green,
                                minimumSize: const Size(0, 36),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 8,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              onPressed: onJoin ?? onTap,
                              child: const Text(
                                'Ikut',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
