import 'package:flutter/material.dart';

import '../../application/operator_auth_boundary.dart';
import '../../application/operator_profile.dart';
import '../../../tasks/application/task_campaign_boundary.dart';
import '../../../tasks/application/task_response_boundary.dart';
import '../../../proposals/application/resident_proposal_boundary.dart';
import '../../../assistance/application/proxy_resident_boundary.dart';

/// Authenticated operator landing page with access to server-reviewed tasks.
final class OperatorHomeScreen extends StatelessWidget {
  const OperatorHomeScreen({
    required this.profile,
    required this.authBoundary,
    this.taskCampaignBoundary,
    this.taskResponseController,
    this.proposalReviewController,
    this.proxyResidentController,
    super.key,
  });

  final OperatorProfile profile;
  final OperatorAuthBoundary? authBoundary;
  final TaskCampaignBoundary? taskCampaignBoundary;
  final TaskResponseController? taskResponseController;
  final ResidentProposalReviewController? proposalReviewController;
  final ProxyResidentController? proxyResidentController;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Ruang Operator'),
      actions: [
        IconButton(
          key: const Key('operator-sign-out'),
          tooltip: 'Keluar',
          onPressed: () async {
            await authBoundary?.signOut();
            if (context.mounted) {
              Navigator.of(context).pushNamedAndRemoveUntil('/', (_) => false);
            }
          },
          icon: const Icon(Icons.logout),
        ),
      ],
    ),
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              profile.role.label,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text('RT ${profile.communityId}'),
            const SizedBox(height: 24),
            if (taskCampaignBoundary == null)
              const Text(
                'Akses operator terverifikasi. Katalog tugas belum terhubung.',
                textAlign: TextAlign.center,
              )
            else ...[
              const Text(
                'Gunakan template yang ditinjau. Aktivasi tugas tetap memerlukan '
                'konfirmasi operator.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                key: const Key('operator-task-catalog'),
                onPressed: () => Navigator.of(context)
                    .pushNamed('/operator/tasks/catalog', arguments: profile),
                icon: const Icon(Icons.checklist),
                label: const Text('Buka Katalog Tugas Aman'),
              ),
              if (taskCampaignBoundary is TaskCampaignManagementBoundary) ...[
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  key: const Key('operator-active-task-campaigns'),
                  onPressed: () => Navigator.of(context)
                      .pushNamed('/operator/tasks/active', arguments: profile),
                  icon: const Icon(Icons.task_alt_outlined),
                  label: const Text('Tinjau Tugas Aktif'),
                ),
                if (taskCampaignBoundary is TaskCampaignHistoryBoundary) ...[
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    key: const Key('operator-task-history'),
                    onPressed: () => Navigator.of(
                      context,
                    ).pushNamed('/operator/tasks/history', arguments: profile),
                    icon: const Icon(Icons.history),
                    label: const Text('Lihat Riwayat Tugas RT'),
                  ),
                ],
              ],
              if (taskResponseController != null) ...[
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  key: const Key('operator-task-verification'),
                  onPressed: () => Navigator.of(context).pushNamed(
                    '/operator/tasks/verification',
                    arguments: profile,
                  ),
                  icon: const Icon(Icons.fact_check_outlined),
                  label: const Text('Tinjau Penyelesaian Warga'),
                ),
              ],
            ],
            if (proposalReviewController != null) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                key: const Key('operator-proposal-review'),
                onPressed: () =>
                    Navigator.of(context)
                        .pushNamed('/operator/proposals', arguments: profile),
                icon: const Icon(Icons.rate_review_outlined),
                label: const Text('Tinjau Usulan Warga'),
              ),
            ],
            if (proxyResidentController != null) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                key: const Key('operator-proxy-resident-assistance'),
                onPressed: () =>
                    Navigator.of(context)
                        .pushNamed('/operator/assistance', arguments: profile),
                icon: const Icon(Icons.support_outlined),
                label: const Text('Dukungan Warga & Status Proxy'),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}
