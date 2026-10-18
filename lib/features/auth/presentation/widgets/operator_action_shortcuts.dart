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
    this.onTreeMap,
    super.key,
  });

  final VoidCallback onOpenCatalog;
  final VoidCallback? onWeatherSuggestions;
  final VoidCallback? onActiveTasks;
  final VoidCallback? onVerification;
  final VoidCallback? onProposalReview;
  final VoidCallback? onProxyAssistance;
  final VoidCallback? onTaskHistory;
  final VoidCallback? onTreeMap;

  @override
  Widget build(BuildContext context) {
    return ActionTileGrid(
      items: [
        ActionTileData(
          key: const Key('operator-task-catalog'),
          icon: Icons.checklist,
          label: 'Katalog Tugas',
          description: 'Buka Katalog Tugas Aman',
          semanticsLabel: 'Buka Katalog Tugas Aman',
          onTap: onOpenCatalog,
        ),
        if (onWeatherSuggestions != null)
          ActionTileData(
            key: const Key('operator-weather-suggestions'),
            icon: Icons.cloud_outlined,
            label: 'Saran Cuaca',
            description: 'Rekomendasi BMKG',
            semanticsLabel: 'Saran Cuaca: Rekomendasi BMKG',
            onTap: onWeatherSuggestions,
          ),
        if (onActiveTasks != null)
          ActionTileData(
            key: const Key('operator-active-task-campaigns'),
            icon: Icons.task_alt_outlined,
            label: 'Tugas Aktif',
            description: 'Tinjau Tugas Aktif',
            semanticsLabel: 'Tinjau Tugas Aktif',
            onTap: onActiveTasks,
          ),
        if (onVerification != null)
          ActionTileData(
            key: const Key('operator-task-verification'),
            icon: Icons.fact_check_outlined,
            label: 'Verifikasi',
            description: 'Tinjau Penyelesaian Warga',
            semanticsLabel: 'Tinjau Penyelesaian Warga',
            onTap: onVerification,
          ),
        if (onProposalReview != null)
          ActionTileData(
            key: const Key('operator-proposal-review'),
            icon: Icons.rate_review_outlined,
            label: 'Usulan Warga',
            description: 'Tinjau Usulan Warga',
            semanticsLabel: 'Tinjau Usulan Warga',
            onTap: onProposalReview,
          ),
        if (onProxyAssistance != null)
          ActionTileData(
            key: const Key('operator-proxy-resident-assistance'),
            icon: Icons.support_outlined,
            label: 'Dukungan Warga',
            description: 'Bantuan & status proxy',
            semanticsLabel: 'Dukungan Warga: Bantuan & status proxy',
            onTap: onProxyAssistance,
          ),
        if (onTaskHistory != null)
          ActionTileData(
            key: const Key('operator-task-history'),
            icon: Icons.history,
            label: 'Riwayat Tugas',
            description: 'Lihat Riwayat Tugas RT',
            semanticsLabel: 'Lihat Riwayat Tugas RT',
            onTap: onTaskHistory,
          ),
        if (onTreeMap != null)
          ActionTileData(
            key: const Key('operator-tree-map'),
            icon: Icons.park_outlined,
            label: 'Peta Pohon RT',
            description: 'Sebaran pohon resapan',
            semanticsLabel: 'Peta Pohon RT: Sebaran pohon resapan',
            onTap: onTreeMap,
          ),
      ],
    );
  }
}
