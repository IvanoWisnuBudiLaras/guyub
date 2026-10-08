import 'package:flutter/material.dart';

import '../../application/operator_auth_boundary.dart';
import '../../application/operator_profile.dart';
import '../../../tasks/application/task_campaign_boundary.dart';
import '../../../tasks/application/task_response_boundary.dart';
import '../../../proposals/application/resident_proposal_boundary.dart';

/// Authenticated operator landing page with access to server-reviewed tasks.
final class OperatorHomeScreen extends StatelessWidget {
  const OperatorHomeScreen({
    required this.profile,
    required this.authBoundary,
    this.taskCampaignBoundary,
    this.taskResponseController,
    this.proposalReviewController,
    super.key,
  });

  final OperatorProfile profile;
  final OperatorAuthBoundary? authBoundary;
  final TaskCampaignBoundary? taskCampaignBoundary;
  final TaskResponseController? taskResponseController;
  final ResidentProposalReviewController? proposalReviewController;

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
          ],
        ),
      ),
    ),
  );
}
