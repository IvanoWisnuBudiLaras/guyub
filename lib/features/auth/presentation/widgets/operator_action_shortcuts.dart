import 'package:flutter/material.dart';

/// Standardized action shortcut buttons for the RT operator dashboard.
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton.icon(
          key: const Key('operator-task-catalog'),
          onPressed: onOpenCatalog,
          icon: const Icon(Icons.checklist),
          label: const Text('Buka Katalog Tugas Aman'),
        ),
        if (onWeatherSuggestions != null) ...[
          const SizedBox(height: 12),
          OutlinedButton.icon(
            key: const Key('operator-weather-suggestions'),
            onPressed: onWeatherSuggestions,
            icon: const Icon(Icons.cloud_outlined),
            label: const Text('Tinjau Saran Cuaca'),
          ),
        ],
        if (onActiveTasks != null) ...[
          const SizedBox(height: 12),
          OutlinedButton.icon(
            key: const Key('operator-active-task-campaigns'),
            onPressed: onActiveTasks,
            icon: const Icon(Icons.task_alt_outlined),
            label: const Text('Tinjau Tugas Aktif'),
          ),
        ],
        if (onVerification != null) ...[
          const SizedBox(height: 12),
          OutlinedButton.icon(
            key: const Key('operator-task-verification'),
            onPressed: onVerification,
            icon: const Icon(Icons.fact_check_outlined),
            label: const Text('Tinjau Penyelesaian Warga'),
          ),
        ],
        if (onProposalReview != null) ...[
          const SizedBox(height: 12),
          OutlinedButton.icon(
            key: const Key('operator-proposal-review'),
            onPressed: onProposalReview,
            icon: const Icon(Icons.rate_review_outlined),
            label: const Text('Tinjau Usulan Warga'),
          ),
        ],
        if (onProxyAssistance != null) ...[
          const SizedBox(height: 12),
          OutlinedButton.icon(
            key: const Key('operator-proxy-resident-assistance'),
            onPressed: onProxyAssistance,
            icon: const Icon(Icons.support_outlined),
            label: const Text('Dukungan Warga & Status Proxy'),
          ),
        ],
        if (onTaskHistory != null) ...[
          const SizedBox(height: 12),
          OutlinedButton.icon(
            key: const Key('operator-task-history'),
            onPressed: onTaskHistory,
            icon: const Icon(Icons.history),
            label: const Text('Lihat Riwayat Tugas RT'),
          ),
        ],
      ],
    );
  }
}
