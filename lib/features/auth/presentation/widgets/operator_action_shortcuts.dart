import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

/// Grid kartu pintasan aksi operasional 2 kolom untuk dashboard RT.
final class OperatorActionShortcuts extends StatelessWidget {
  const OperatorActionShortcuts({
    required this.onOpenCatalog,
    this.onWeatherSuggestions,
    this.onActiveTasks,
    this.onVerification,
    this.onProposalReview,
    this.onProxyAssistance,
    this.onTaskHistory,
    super.key,
  });

  final VoidCallback onOpenCatalog;
  final VoidCallback? onWeatherSuggestions;
  final VoidCallback? onActiveTasks;
  final VoidCallback? onVerification;
  final VoidCallback? onProposalReview;
  final VoidCallback? onProxyAssistance;
  final VoidCallback? onTaskHistory;

  @override
  Widget build(BuildContext context) {
    final items = <Widget>[
      _ShortcutCard(
        key: const Key('operator-task-catalog'),
        icon: Icons.checklist,
        label: 'Katalog Tugas',
        description: 'Pilih template aman',
        onTap: onOpenCatalog,
      ),
      if (onWeatherSuggestions != null)
        _ShortcutCard(
          key: const Key('operator-weather-suggestions'),
          icon: Icons.cloud_outlined,
          label: 'Saran Cuaca',
          description: 'Rekomendasi BMKG',
          onTap: onWeatherSuggestions!,
        ),
      if (onActiveTasks != null)
        _ShortcutCard(
          key: const Key('operator-active-task-campaigns'),
          icon: Icons.task_alt_outlined,
          label: 'Tugas Aktif',
          description: 'Pantau tugas berjalan',
          onTap: onActiveTasks!,
        ),
      if (onVerification != null)
        _ShortcutCard(
          key: const Key('operator-task-verification'),
          icon: Icons.fact_check_outlined,
          label: 'Verifikasi',
          description: 'Laporan tugas warga',
          onTap: onVerification!,
        ),
      if (onProposalReview != null)
        _ShortcutCard(
          key: const Key('operator-proposal-review'),
          icon: Icons.rate_review_outlined,
          label: 'Usulan Warga',
          description: 'Tinjau ide persiapan',
          onTap: onProposalReview!,
        ),
      if (onProxyAssistance != null)
        _ShortcutCard(
          key: const Key('operator-proxy-resident-assistance'),
          icon: Icons.support_outlined,
          label: 'Dukungan Warga',
          description: 'Bantuan & status proxy',
          onTap: onProxyAssistance!,
        ),
      if (onTaskHistory != null)
        _ShortcutCard(
          key: const Key('operator-task-history'),
          icon: Icons.history,
          label: 'Riwayat Tugas',
          description: 'Catatan tugas lampau',
          onTap: onTaskHistory!,
        ),
    ];

    // Grid 2-kolom responsif menggunakan LayoutBuilder / GridView
    return LayoutBuilder(
      builder: (context, constraints) {
        final itemWidth = (constraints.maxWidth - 10) / 2;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: items
              .map((w) => SizedBox(width: itemWidth, child: w))
              .toList(),
        );
      },
    );
  }
}

final class _ShortcutCard extends StatelessWidget {
  const _ShortcutCard({
    required this.icon,
    required this.label,
    required this.description,
    required this.onTap,
    super.key,
  });

  final IconData icon;
  final String label;
  final String description;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: colors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: colors.primarySoft,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: colors.primary, size: 20),
              ),
              const SizedBox(height: 10),
              Text(
                label,
                style: Theme.of(context).textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w600),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                description,
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: colors.textSecondary, fontSize: 11),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
