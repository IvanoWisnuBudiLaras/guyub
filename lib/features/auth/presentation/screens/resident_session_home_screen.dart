import 'dart:async';

import 'package:flutter/material.dart';

import '../../application/resident_session.dart';
import '../../application/resident_session_controller.dart';
import '../../../assistance/application/assistance_volunteer_boundary.dart';
import '../../../tasks/application/task_response_boundary.dart';
import '../../../proposals/application/resident_proposal_boundary.dart';
import '../../../weather/application/weather_snapshot_store.dart';
import '../../../weather/application/weather_snapshot_boundary.dart';
import '../../../weather/presentation/weather_snapshot_card.dart';
import '../../../notifications/application/task_push_notifications.dart';
import '../../../notifications/presentation/task_push_opt_in_card.dart';

/// Initial resident destination after backend validation of the RT join code.
final class ResidentSessionHomeScreen extends StatefulWidget {
  const ResidentSessionHomeScreen({
    required this.session,
    required this.controller,
    this.taskResponseController,
    this.residentProposalController,
    this.weatherSnapshotStore,
    this.weatherSnapshotSyncController,
    this.assistanceVolunteerController,
    this.taskPushNotificationsController,
    this.connectivityChanges,
    super.key,
  });

  final ResidentSession session;
  final ResidentSessionController controller;
  final TaskResponseController? taskResponseController;
  final ResidentProposalController? residentProposalController;
  final WeatherSnapshotStore? weatherSnapshotStore;
  final WeatherSnapshotSyncController? weatherSnapshotSyncController;
  final AssistanceVolunteerController? assistanceVolunteerController;
  final TaskPushNotificationsController? taskPushNotificationsController;
  final Stream<bool>? connectivityChanges;

  @override
  State<ResidentSessionHomeScreen> createState() =>
      _ResidentSessionHomeScreenState();
}

final class _ResidentSessionHomeScreenState
    extends State<ResidentSessionHomeScreen> {
  late ResidentSession _session;
  StreamSubscription<bool>? _connectivitySubscription;
  late final Future<void> Function() _weatherRefresh;
  bool _syncing = false;
  bool _syncForCurrentConnection = false;
  bool _needsWeatherReload = false;
  int _weatherRevision = 0;

  ResidentSession get session => _session;
  ResidentSessionController get controller => widget.controller;
  TaskResponseController? get taskResponseController =>
      widget.taskResponseController;
  ResidentProposalController? get residentProposalController =>
      widget.residentProposalController;
  WeatherSnapshotStore? get weatherSnapshotStore => widget.weatherSnapshotStore;
  WeatherSnapshotSyncController? get weatherSnapshotSyncController =>
      widget.weatherSnapshotSyncController;
  AssistanceVolunteerController? get assistanceVolunteerController =>
      widget.assistanceVolunteerController;
  TaskPushNotificationsController? get taskPushNotificationsController =>
      widget.taskPushNotificationsController;

  @override
  void initState() {
    super.initState();
    _session = widget.session;
    _weatherRefresh = _refreshWeatherSnapshot;
    _connectivitySubscription = widget.connectivityChanges?.listen((online) {
      if (!online) {
        _syncForCurrentConnection = false;
        _needsWeatherReload = true;
      } else {
        _startReconnectSync();
      }
    }, onError: (Object error, StackTrace stackTrace) {});
  }

  void _startReconnectSync() {
    if (_syncForCurrentConnection) return;
    _syncForCurrentConnection = true;
    unawaited(_restoreAndSync());
  }

  @override
  void dispose() {
    _connectivitySubscription?.cancel();
    super.dispose();
  }

  Future<void> _restoreAndSync() async {
    if (_syncing) return;
    _syncing = true;
    try {
      final restored = await controller.restoreSession();
      if (!mounted) return;
      if (restored == null) {
        if (!_session.isOfflineSnapshot) {
          setState(() => _session = _session.asOfflineSnapshot());
        }
        return;
      }
      if (restored.isOfflineSnapshot) return;
      final reloadWeatherCard =
          _session.isOfflineSnapshot || _needsWeatherReload;
      if (_session != restored || reloadWeatherCard) {
        setState(() {
          _session = restored;
          if (reloadWeatherCard) _weatherRevision++;
        });
      }
      _needsWeatherReload = false;

      try {
        await taskResponseController?.listResidentActiveTasks(
          session: restored,
        );
      } catch (_) {
        // The callable remains the authorization boundary; keep local data.
      }
      if (weatherSnapshotStore == null) {
        try {
          await weatherSnapshotSyncController?.refreshForResident(
            communityId: restored.communityId,
          );
        } catch (_) {
          // Preserve the last valid weather snapshot if refresh fails.
        }
      }
      try {
        await taskPushNotificationsController?.syncResidentSession(restored);
      } catch (_) {
        // Push remains optional and does not block task/weather sync.
      }
    } catch (_) {
      // Reconnect is a trigger only; server calls decide whether data is current.
    } finally {
      _syncing = false;
    }
  }

  Future<void> _refreshWeatherSnapshot() async {
    if (session.isOfflineSnapshot) {
      await _restoreAndSync();
      return;
    }
    await weatherSnapshotSyncController?.refreshForResident(
      communityId: session.communityId,
    );
  }

  Future<void> _confirmAndDeleteOwnData(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Hapus data warga?'),
        content: const Text(
          'Profil, respons tugas, usulan, bantuan, bukti foto, dan token '
          'notifikasi Anda akan dihapus dari server. Cache tugas dan sesi pada '
          'perangkat ini juga akan dihapus. Riwayat tugas bersama RT tetap ada. '
          'Tindakan ini tidak dapat dibatalkan.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Batal'),
          ),
          FilledButton.tonal(
            key: const Key('resident-delete-data-confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Hapus Data Saya'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await controller.deleteOwnResidentData(session);
      await residentProposalController?.clearPendingForResident(
        residentId: session.residentId,
        communityId: session.communityId,
      );
      await taskResponseController?.clearLocalResidentData(session: session);
      await taskPushNotificationsController?.clearResidentStateAfterDeletion(
        session,
      );
      await controller.signOut();
      if (context.mounted) {
        Navigator.of(context).pushNamedAndRemoveUntil('/', (_) => false);
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(
              content: Text(
                'Penghapusan belum dapat dikonfirmasi. Periksa koneksi dan '
                'coba lagi dari perangkat ini.',
              ),
            ),
          );
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Ruang Warga'),
      actions: [
        IconButton(
          key: const Key('resident-sign-out'),
          tooltip: 'Keluar',
          onPressed: () async {
            await taskPushNotificationsController
                ?.unregisterResidentBeforeSignOut(session);
            taskPushNotificationsController?.clearActiveTarget();
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
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      children: [
                        const Text(
                          'Mode offline. Sesi dan informasi tugas tersimpan '
                          'belum diverifikasi ulang. Status tugas mungkin '
                          'sudah berubah.',
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          key: const Key('resident-reconnect-sync'),
                          onPressed: _syncing ? null : _restoreAndSync,
                          icon: const Icon(Icons.sync),
                          label: Text(
                            _syncing
                                ? 'Memeriksa status…'
                                : 'Periksa koneksi dan sinkronkan',
                          ),
                        ),
                      ],
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
                WeatherSnapshotCard(
                  key: ValueKey<int>(_weatherRevision),
                  store: weatherSnapshotStore!,
                  communityId: session.communityId,
                  onRefresh: weatherSnapshotSyncController == null
                      ? null
                      : _weatherRefresh,
                ),
              ],
              if (taskPushNotificationsController != null &&
                  taskResponseController != null &&
                  !session.isOfflineSnapshot) ...[
                const SizedBox(height: 12),
                TaskPushOptInCard.forResident(
                  controller: taskPushNotificationsController!,
                  session: session,
                ),
              ],
              const SizedBox(height: 24),
              Text(
                taskResponseController == null
                    ? 'Sesi warga Anda terverifikasi. Layanan tugas belum terhubung.'
                    : taskPushNotificationsController == null
                    ? 'Lihat tugas aktif yang telah disetujui operator RT. '
                          'Notifikasi push belum tersedia pada perangkat ini.'
                    : 'Lihat tugas aktif yang telah disetujui operator RT. '
                          'Notifikasi push hanya pemberitahuan tambahan.',
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
              if (assistanceVolunteerController != null &&
                  !session.isOfflineSnapshot) ...[
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  key: const Key('resident-assistance-volunteer'),
                  onPressed: () => Navigator.of(context)
                      .pushNamed('/resident/assistance', arguments: session),
                  icon: const Icon(Icons.volunteer_activism_outlined),
                  label: const Text('Kesediaan Membantu'),
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
              if (!session.isOfflineSnapshot) ...[
                const SizedBox(height: 32),
                TextButton.icon(
                  key: const Key('resident-delete-data'),
                  onPressed: () => _confirmAndDeleteOwnData(context),
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Hapus Data Saya'),
                ),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}
