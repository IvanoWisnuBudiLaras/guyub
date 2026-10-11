import 'package:flutter/material.dart';

import '../../application/resident_session.dart';
import '../../application/resident_session_controller.dart';
import '../../../tasks/application/task_response_boundary.dart';
import '../../../proposals/application/resident_proposal_boundary.dart';
import '../../../weather/application/weather_snapshot_store.dart';
import '../../../weather/presentation/weather_snapshot_card.dart';

/// Initial resident destination after backend validation of the RT join code.
final class ResidentSessionHomeScreen extends StatelessWidget {
  const ResidentSessionHomeScreen({
    required this.session,
    required this.controller,
    this.taskResponseController,
    this.residentProposalController,
    this.weatherSnapshotStore,
    super.key,
  });

  final ResidentSession session;
  final ResidentSessionController controller;
  final TaskResponseController? taskResponseController;
  final ResidentProposalController? residentProposalController;
  final WeatherSnapshotStore? weatherSnapshotStore;

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
    body: SingleChildScrollView(
      child: Center(
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
              if (session.isOfflineSnapshot) ...[
                const SizedBox(height: 16),
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(12),
                    child: Text(
                      'Mode offline. Sesi dan informasi tugas tersimpan belum '
                      'diverifikasi ulang. Status tugas mungkin sudah berubah.',
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              OutlinedButton.icon(
                key: const Key('resident-emergency-directory'),
                onPressed: () =>
                    Navigator.of(context)
                        .pushNamed('/emergency', arguments: session),
                icon: const Icon(Icons.health_and_safety_outlined),
                label: const Text('Informasi Darurat'),
              ),
              if (weatherSnapshotStore != null) ...[
                const SizedBox(height: 12),
                WeatherSnapshotCard(store: weatherSnapshotStore!),
              ],
              const SizedBox(height: 24),
              Text(
                taskResponseController == null
                    ? 'Sesi warga Anda terverifikasi. Layanan tugas belum terhubung.'
                    : 'Lihat tugas aktif yang telah disetujui operator RT. '
                          'Notifikasi tugas belum tersedia.',
                textAlign: TextAlign.center,
              ),
              if (taskResponseController != null) ...[
                const SizedBox(height: 20),
                FilledButton.icon(
                  key: const Key('resident-task-list'),
                  onPressed: () =>
                      Navigator.of(context)
                          .pushNamed('/resident/tasks', arguments: session),
                  icon: const Icon(Icons.checklist),
                  label: const Text('Lihat Tugas Kesiapsiagaan'),
                ),
              ],
              if (residentProposalController != null &&
                  !session.isOfflineSnapshot) ...[
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  key: const Key('resident-propose-task'),
                  onPressed: () =>
                      Navigator.of(context)
                          .pushNamed('/resident/proposals', arguments: session),
                  icon: const Icon(Icons.lightbulb_outline),
                  label: const Text('Usulkan Persiapan Warga'),
                ),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}
