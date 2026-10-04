import 'package:flutter/material.dart';

import '../../application/operator_auth_boundary.dart';
import '../../application/operator_profile.dart';

/// Minimal authenticated operator landing page until task features are wired.
final class OperatorHomeScreen extends StatelessWidget {
  const OperatorHomeScreen({
    required this.profile,
    required this.authBoundary,
    super.key,
  });

  final OperatorProfile profile;
  final OperatorAuthBoundary? authBoundary;

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
            const Text(
              'Akses operator terverifikasi. Alur tugas dan data komunitas '
              'belum tersedia pada build ini.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    ),
  );
}
