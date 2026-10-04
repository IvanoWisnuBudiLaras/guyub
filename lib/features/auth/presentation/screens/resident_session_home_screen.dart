import 'package:flutter/material.dart';

import '../../application/resident_session.dart';
import '../../application/resident_session_controller.dart';

/// Initial resident destination after backend validation of the RT join code.
final class ResidentSessionHomeScreen extends StatelessWidget {
  const ResidentSessionHomeScreen({
    required this.session,
    required this.controller,
    super.key,
  });

  final ResidentSession session;
  final ResidentSessionController controller;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Ruang Warga'),
      actions: [
        IconButton(
          key: const Key('resident-sign-out'),
          tooltip: 'Keluar',
          onPressed: () async {
            await controller.signOut();
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
            const Icon(Icons.home_outlined, size: 48),
            const SizedBox(height: 12),
            Text(
              'Warga • ${session.rtLabel}',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(session.communityName),
            const SizedBox(height: 8),
            Text('Halo, ${session.nickname}'),
            const SizedBox(height: 24),
            const Text(
              'Sesi warga Anda terverifikasi. Tugas komunitas akan tampil di sini.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    ),
  );
}
