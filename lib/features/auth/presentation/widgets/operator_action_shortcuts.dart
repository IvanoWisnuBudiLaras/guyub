import 'package:flutter/material.dart';

import '../../../../core/widgets/action_tile_grid.dart';

/// Grid kartu pintasan aksi operasional 2 kolom untuk dashboard RT.
/// Mendelegasikan ke shared [ActionTileGrid].
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
    return ActionTileGrid(
      items: [
        ActionTileData(
          key: const Key('operator-task-catalog'),
          icon: Icons.checklist,
          label: 'Katalog Tugas',
          description: 'Pilih template aman',
          onTap: onOpenCatalog,
        ),
        if (onWeatherSuggestions != null)
          ActionTileData(
            key: const Key('operator-weather-suggestions'),
            icon: Icons.cloud_outlined,
            label: 'Saran Cuaca',
            description: 'Rekomendasi BMKG',
            onTap: onWeatherSuggestions,
          ),
        if (onActiveTasks != null)
          ActionTileData(
            key: const Key('operator-active-task-campaigns'),
            icon: Icons.task_alt_outlined,
            label: 'Tugas Aktif',
            description: 'Pantau tugas berjalan',
            onTap: onActiveTasks,
          ),
        if (onVerification != null)
          ActionTileData(
            key: const Key('operator-task-verification'),
            icon: Icons.fact_check_outlined,
            label: 'Verifikasi',
            description: 'Laporan tugas warga',
            onTap: onVerification,
          ),
        if (onProposalReview != null)
          ActionTileData(
            key: const Key('operator-proposal-review'),
            icon: Icons.rate_review_outlined,
            label: 'Usulan Warga',
            description: 'Tinjau ide persiapan',
            onTap: onProposalReview,
          ),
        if (onProxyAssistance != null)
          ActionTileData(
            key: const Key('operator-proxy-resident-assistance'),
            icon: Icons.support_outlined,
            label: 'Dukungan Warga',
            description: 'Bantuan & status proxy',
            onTap: onProxyAssistance,
          ),
        if (onTaskHistory != null)
          ActionTileData(
            key: const Key('operator-task-history'),
            icon: Icons.history,
            label: 'Riwayat Tugas',
            description: 'Catatan tugas lampau',
            onTap: onTaskHistory,
          ),
      ],
    );
  }
}
