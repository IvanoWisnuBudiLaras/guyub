import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_logo.dart';
import '../../application/resident_session.dart';
import '../../application/resident_session_controller.dart';
import '../../../assistance/application/assistance_volunteer_boundary.dart';
import '../../../tasks/application/task_response_boundary.dart';
import '../../../tasks/application/task_response.dart';
import '../../../proposals/application/resident_proposal_boundary.dart';
import '../../../weather/application/weather_snapshot_store.dart';
import '../../../weather/application/weather_snapshot_boundary.dart';
import '../../../weather/presentation/weather_snapshot_card.dart';
import '../../../notifications/application/task_push_notifications.dart';
import '../../../notifications/presentation/task_push_opt_in_card.dart';
import '../widgets/task_summary_card.dart';
import '../../../tasks/presentation/widgets/task_list_tab.dart';

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
  int _selectedTabIndex = 0; // Bottom navigation state
  ResidentTaskList? _taskList;
  bool _loadingTasks = false;
  String? _taskLoadError;

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
    // Load tasks if controller is available
    if (taskResponseController != null) {
      _loadTasks();
    }
  }

  Future<void> _loadTasks() async {
    if (_loadingTasks) return;
    setState(() {
      _loadingTasks = true;
      _taskLoadError = null;
    });
    try {
      final taskList = await taskResponseController!.listResidentActiveTasks(
        session: _session,
      );
      if (mounted) {
        setState(() {
          _taskList = taskList;
          _loadingTasks = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _taskLoadError = 'Tidak dapat memuat tugas. Coba lagi nanti.';
          _loadingTasks = false;
        });
      }
    }
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
        final taskList = await taskResponseController?.listResidentActiveTasks(
          session: restored,
        );
        if (mounted && taskList != null) {
          setState(() => _taskList = taskList);
        }
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
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final isCompact = screenHeight < 700;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: _selectedTabIndex == 0
          ? null
          : AppBar(
              backgroundColor: Colors.white,
              elevation: 0,
              title: Text(
                _selectedTabIndex == 1
                    ? 'Daftar Tugas'
                    : 'Informasi Darurat',
              ),
              actions: _buildAppBarActions(context),
            ),
      body: IndexedStack(
        index: _selectedTabIndex,
        children: [
          // Tab 0: Beranda
          _buildBerandaTab(context, isCompact),
          // Tab 1: Tugas (placeholder untuk sekarang)
          _buildTugasTab(context),
          // Tab 2: Darurat (placeholder untuk sekarang)
          _buildDaruratTab(context),
        ],
      ),
      bottomNavigationBar: _buildBottomNavigation(context),
    );
  }

  List<Widget> _buildAppBarActions(BuildContext context) {
    return [
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
    ];
  }

  Widget _buildBerandaTab(BuildContext context, bool isCompact) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header dengan sapaan + badge RT
          _buildBerandaHeader(context, isCompact),
          Padding(
            padding: EdgeInsets.all(isCompact ? 16 : 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Offline warning (jika offline)
                if (session.isOfflineSnapshot) ...[
                  _buildOfflineWarning(context),
                  SizedBox(height: isCompact ? 12 : 16),
                ],
                // Weather card
                if (weatherSnapshotStore != null) ...[
                  WeatherSnapshotCard(
                    key: ValueKey<int>(_weatherRevision),
                    store: weatherSnapshotStore!,
                    communityId: session.communityId,
                    onRefresh: weatherSnapshotSyncController == null
                        ? null
                        : _weatherRefresh,
                  ),
                  SizedBox(height: isCompact ? 12 : 16),
                ],
                // Ringkasan Tugas Saya (placeholder untuk sekarang)
                _buildTaskSummaryPlaceholder(context, isCompact),
                SizedBox(height: isCompact ? 12 : 16),
                // Push notification opt-in
                if (taskPushNotificationsController != null &&
                    taskResponseController != null &&
                    !session.isOfflineSnapshot) ...[
                  TaskPushOptInCard.forResident(
                    controller: taskPushNotificationsController!,
                    session: session,
                  ),
                  SizedBox(height: isCompact ? 12 : 16),
                ],
                // Shortcuts
                _buildShortcuts(context, isCompact),
                SizedBox(height: isCompact ? 12 : 16),
                // Hapus data (hanya jika online)
                if (!session.isOfflineSnapshot) ...[
                  TextButton.icon(
                    key: const Key('resident-delete-data'),
                    onPressed: () => _confirmAndDeleteOwnData(context),
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Hapus Data Saya'),
                    style: TextButton.styleFrom(
                      foregroundColor: context.appColors.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBerandaHeader(BuildContext context, bool isCompact) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        isCompact ? 16 : 20,
        isCompact ? 48 : 56,
        isCompact ? 16 : 20,
        isCompact ? 16 : 20,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            context.appColors.primary,
            context.appColors.primary.withOpacity(0.85),
          ],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Badge RT
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withOpacity(0.3)),
              ),
              child: Text(
                session.rtLabel,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ),
            const SizedBox(height: 12),
            // Sapaan
            Text(
              'Halo, ${session.nickname}',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 4),
            // Community name
            Text(
              session.communityName,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.white.withOpacity(0.9),
                  ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOfflineWarning(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.appColors.warning.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.appColors.warning.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.cloud_off_outlined,
                color: context.appColors.warning,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Mode offline',
                  style: TextStyle(
                    color: context.appColors.warning,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Sesi dan informasi tugas tersimpan belum diverifikasi ulang. '
            'Status tugas mungkin sudah berubah.',
            style: TextStyle(fontSize: 13),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            key: const Key('resident-reconnect-sync'),
            onPressed: _syncing ? null : _restoreAndSync,
            icon: const Icon(Icons.sync, size: 18),
            label: Text(
              _syncing ? 'Memeriksa status…' : 'Sinkronkan sekarang',
              style: const TextStyle(fontSize: 13),
            ),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTaskSummaryPlaceholder(BuildContext context, bool isCompact) {
    if (taskResponseController == null) {
      return Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: context.appColors.border),
        ),
        child: Padding(
          padding: EdgeInsets.all(isCompact ? 12 : 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Tugas Saya',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                'Layanan tugas belum terhubung.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: context.appColors.textSecondary,
                    ),
              ),
            ],
          ),
        ),
      );
    }

    return TaskSummaryCard(
      taskList: _taskList,
      loading: _loadingTasks,
      error: _taskLoadError,
      isCompact: isCompact,
      onViewAll: () => setState(() => _selectedTabIndex = 1),
      onRetry: _loadTasks,
    );
  }

  Widget _buildShortcuts(BuildContext context, bool isCompact) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Kesediaan Membantu
        if (assistanceVolunteerController != null &&
            !session.isOfflineSnapshot) ...[
          OutlinedButton.icon(
            key: const Key('resident-assistance-volunteer'),
            onPressed: () => Navigator.of(context)
                .pushNamed('/resident/assistance', arguments: session),
            icon: const Icon(Icons.volunteer_activism_outlined),
            label: const Text('Kesediaan Membantu'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
            ),
          ),
          SizedBox(height: isCompact ? 8 : 12),
        ],
        // Usulkan Persiapan
        if (residentProposalController != null &&
            !session.isOfflineSnapshot) ...[
          OutlinedButton.icon(
            key: const Key('resident-propose-task'),
            onPressed: () => Navigator.of(context)
                .pushNamed('/resident/proposals', arguments: session),
            icon: const Icon(Icons.lightbulb_outline),
            label: const Text('Usulkan Persiapan Warga'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildTugasTab(BuildContext context) {
    if (taskResponseController == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.checklist,
                size: 64,
                color: context.appColors.textSecondary,
              ),
              const SizedBox(height: 16),
              Text(
                'Layanan Tugas Belum Terhubung',
                style: Theme.of(context).textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return TaskListTab(
      taskList: _taskList,
      loading: _loadingTasks,
      error: _taskLoadError,
      onRetry: _loadTasks,
      onTaskTap: (task) {
        // Navigate ke detail tugas (akan diimplementasikan di commit berikutnya)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Detail tugas: ${task.templateSnapshot.title}'),
            duration: const Duration(seconds: 1),
          ),
        );
      },
    );
  }

  Widget _buildDaruratTab(BuildContext context) {
    // Placeholder untuk tab Darurat
    // Akan diimplementasikan di commit berikutnya
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.health_and_safety_outlined,
              size: 64,
              color: context.appColors.danger,
            ),
            const SizedBox(height: 16),
            Text(
              'Informasi Darurat',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            const Text(
              'Implementasi informasi darurat akan ditambahkan.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () => Navigator.of(context)
                  .pushNamed('/emergency', arguments: session),
              icon: const Icon(Icons.arrow_forward),
              label: const Text('Buka Halaman Darurat Lengkap'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomNavigation(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: context.appColors.border),
        ),
      ),
      child: BottomNavigationBar(
        currentIndex: _selectedTabIndex,
        onTap: (index) => setState(() => _selectedTabIndex = index),
        selectedItemColor: context.appColors.primary,
        unselectedItemColor: context.appColors.textSecondary,
        selectedFontSize: 12,
        unselectedFontSize: 12,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home_outlined),
            activeIcon: Icon(Icons.home),
            label: 'Beranda',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.checklist_outlined),
            activeIcon: Icon(Icons.checklist),
            label: 'Tugas',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.health_and_safety_outlined),
            activeIcon: Icon(Icons.health_and_safety),
            label: 'Darurat',
          ),
        ],
      ),
    );
  }
}
