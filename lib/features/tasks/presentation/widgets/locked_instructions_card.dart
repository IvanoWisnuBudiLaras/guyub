import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/tinted_info_box.dart';
import '../../application/task_template.dart';

/// Prominent display of reviewed instructions; this widget has no edit inputs.
/// Adheres to Guyub.id design guidelines:
/// - Info tint with lock icon for the locked template header
/// - Warning tint with warning icon for the KESELAMATAN block
final class LockedTaskInstructionsCard extends StatelessWidget {
  const LockedTaskInstructionsCard({required this.snapshot, super.key});

  final TaskTemplateSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    final hasCustom =
        snapshot.customInstruction != null &&
        snapshot.customInstruction!.trim().isNotEmpty;
    final rawInstruction = hasCustom
        ? snapshot.customInstruction!.trim()
        : snapshot.coreInstruction.trim();
    final steps = rawInstruction
        .split(RegExp(r'\r?\n+'))
        .where((s) => s.trim().isNotEmpty)
        .toList();

    return Container(
      decoration: BoxDecoration(
        color: colors.primarySoft,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.primary.withValues(alpha: 0.3)),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.lock_outline,
                  size: 20,
                  color: colors.primaryDark,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Instruksi template terkunci',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: colors.primaryDark,
                      ),
                    ),
                    if (hasCustom) ...[
                      const SizedBox(height: 2),
                      Text(
                        'Instruksi disesuaikan oleh RT untuk lingkungan ini',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: colors.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Core instruction list/steps
          if (steps.length > 1) ...[
            ...steps.asMap().entries.map((entry) {
              final idx = entry.key + 1;
              final text = entry.value.replaceFirst(
                RegExp(r'^\d+[\.\)]\s*'),
                '',
              );
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 22,
                      height: 22,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: colors.primary.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        '$idx',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: colors.primaryDark,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        text,
                        style: TextStyle(
                          fontSize: 14,
                          color: colors.textPrimary,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ] else ...[
            Text(
              rawInstruction,
              style: TextStyle(
                fontSize: 14,
                color: colors.textPrimary,
                height: 1.4,
              ),
            ),
          ],

          const SizedBox(height: 14),

          // KESELAMATAN warning block
          TintedInfoBox.warning(
            icon: Icons.warning_amber_rounded,
            title: 'KESELAMATAN',
            text: snapshot.safetyInstruction,
          ),
        ],
      ),
    );
  }
}
