import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/indonesian_date_formatter.dart';
import '../../../../core/widgets/action_tile_grid.dart';
import '../../../../core/widgets/alert_banner.dart';
import '../../../../core/widgets/guyub_bottom_nav_bar.dart';
import '../../../../core/widgets/guyub_top_bar.dart';
import '../../../../core/widgets/hero_header_card.dart';
import '../../../../core/widgets/section_card.dart';
import '../../application/resident_session.dart';
import '../../application/resident_session_controller.dart';
import '../../../assistance/application/assistance_volunteer_boundary.dart';
import '../../../tasks/application/task_response_boundary.dart';
import '../../../tasks/application/task_response.dart';
import '../../../tasks/presentation/screens/task_response_screens.dart';
import '../../../proposals/application/resident_proposal_boundary.dart';
import '../../../weather/application/weather_snapshot_store.dart';
import '../../../weather/application/weather_snapshot_boundary.dart';
import '../../../weather/presentation/weather_snapshot_card.dart';
import '../../../notifications/application/task_push_notifications.dart';
import '../../../notifications/presentation/task_push_opt_in_card.dart';
import '../widgets/task_summary_card.dart';
import '../../../tasks/presentation/widgets/task_list_tab.dart';
import '../../../emergency/application/emergency_directory_controller.dart';
import '../../../emergency/presentation/emergency_directory_screen.dart';
import '../../../trees/presentation/controllers/tree_point_controller.dart';

/// Initial resident destination after backend validation of the RT join code.
final class ResidentSessionHomeScreen extends StatefulWidget {
  const ResidentSessionHomeScreen({
    required this.session,
    required this.controller,
    this.taskResponseController,
    this.residentProposalController,
    this.emergencyDirectoryController,
    this.weatherSnapshotStore,
    this.weatherSnapshotSyncController,
    this.assistanceVolunteerController,
    this.taskPushNotificationsController,
    this.treePointController,
    this.connectivityChanges,
    super.key,
  });

  final ResidentSession session;
  final ResidentSessionController controller;
  final TaskResponseController? taskResponseController;
  final ResidentProposalController? residentProposalController;
  final EmergencyDirectoryController? emergencyDirectoryController;
  final WeatherSnapshotStore? weatherSnapshotStore;
  final WeatherSnapshotSyncController? weatherSnapshotSyncController;
  final AssistanceVolunteerController? assistanceVolunteerController;
  final TaskPushNotificationsController? taskPushNotificationsController;
  final TreePointController? treePointController;
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
  EmergencyDirectoryController? get emergencyDirectoryController =>
      widget.emergencyDirectoryController;
  WeatherSnapshotStore? get weatherSnapshotStore => widget.weatherSnapshotStore;
  WeatherSnapshotSyncController? get weatherSnapshotSyncController =>
      widget.weatherSnapshotSyncController;
  AssistanceVolunteerController? get assistanceVolunteerController =>
      widget.assistanceVolunteerController;
  TaskPushNotificationsController? get taskPushNotificationsController =>
      widget.taskPushNotificationsController;
  TreePointController? get treePointController => widget.treePointController;

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
    // Load tasks if controller is available and session is online
    if (taskResponseController != null && !_session.isOfflineSnapshot) {
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
      appBar: AppBar(
        titleSpacing: 16,
        title: _selectedTabIndex == 0
            ? const Row(
                children: [
                  GuyubWordmark(),
                  SizedBox(width: 8),
                  Text(
                    'Guyub.id',
                    style: TextStyle(fontSize: 0, height: 0),
                  ),
                ],
              )
            : Text(
                _selectedTabIndex == 1 ? 'Daftar Tugas' : 'Informasi Darurat',
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
        key: const Key('resident-switch-role-appbar'),
        tooltip: 'Ganti Peran',
        onPressed: () => _switchRole(context),
        icon: const Icon(Icons.swap_horiz),
      ),
      IconButton(
        key: const Key('resident-sign-out'),
        tooltip: 'Keluar',
        onPressed: () => _confirmAndSignOut(context),
        icon: const Icon(Icons.logout),
      ),
    ];
  }

  void _switchRole(BuildContext context) {
    Navigator.of(context).pushNamedAndRemoveUntil('/', (_) => false);
  }

  Future<void> _confirmAndSignOut(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Keluar dari sesi ini?'),
        content: const Text(
          'Jika keluar lalu masuk lagi, kamu dianggap warga baru dan '
          'riwayat tugas di perangkat ini tidak terbawa. '
          'Pakai Ganti Peran bila hanya ingin pindah peran.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Batal'),
          ),
          FilledButton(
            key: const Key('resident-sign-out-confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Keluar'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    await taskPushNotificationsController?.unregisterResidentBeforeSignOut(
      session,
    );
    taskPushNotificationsController?.clearActiveTarget();
    await controller.signOut();
    if (context.mounted) {
      Navigator.of(context).pushNamedAndRemoveUntil('/', (_) => false);
    }
  }

  Widget _buildBerandaTab(BuildContext context, bool isCompact) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      children: [
        // 1. Header Hero Warga
        _buildBerandaHeader(context, isCompact),
        const SizedBox(height: 10),

        // 2. Offline warning (jika offline)
        if (session.isOfflineSnapshot) ...[
          _buildOfflineWarning(context),
          const SizedBox(height: 10),
        ],

        // 3. Weather card
        if (weatherSnapshotStore != null) ...[
          WeatherSnapshotCard(
            key: ValueKey<int>(_weatherRevision),
            store: weatherSnapshotStore!,
            communityId: session.communityId,
            onRefresh: weatherSnapshotSyncController == null
                ? null
                : _weatherRefresh,
          ),
          const SizedBox(height: 10),
        ],

        // 4. Ringkasan Tugas Saya
        _buildTaskSummaryPlaceholder(context, isCompact),
        const SizedBox(height: 10),

        // 5. Push notification opt-in
        if (taskPushNotificationsController != null &&
            taskResponseController != null &&
            !session.isOfflineSnapshot) ...[
          TaskPushOptInCard.forResident(
            controller: taskPushNotificationsController!,
            session: session,
          ),
          const SizedBox(height: 10),
        ],

        // 6. Shortcuts (Aksi Cepat Warga: Kesediaan Membantu & Usulkan Persiapan)
        _buildShortcuts(context, isCompact),
        const SizedBox(height: 16),

        // 7. Ganti Peran
        OutlinedButton.icon(
          key: const Key('resident-switch-role'),
          onPressed: () => _switchRole(context),
          icon: const Icon(Icons.swap_horiz),
          label: const Text('Ganti Peran'),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(44),
          ),
        ),
        const SizedBox(height: 10),

        // 8. Keluar dari sesi ini
        OutlinedButton.icon(
          key: const Key('resident-sign-out-button'),
          onPressed: () => _confirmAndSignOut(context),
          icon: const Icon(Icons.logout),
          label: const Text('Keluar dari sesi ini'),
          style: OutlinedButton.styleFrom(
            foregroundColor: context.appColors.textSecondary,
            side: BorderSide(color: context.appColors.border),
            minimumSize: const Size.fromHeight(44),
          ),
        ),
        const SizedBox(height: 16),

        // 9. Hapus Data Saya (paling bawah, paling jauh, gaya destruktif)
        if (!session.isOfflineSnapshot) ...[
          TextButton.icon(
            key: const Key('resident-delete-data'),
            onPressed: () => _confirmAndDeleteOwnData(context),
            icon: Icon(
              Icons.delete_forever_outlined,
              color: context.appColors.danger,
            ),
            label: Text(
              'Hapus Data Saya',
              style: TextStyle(
                color: context.appColors.danger,
                fontWeight: FontWeight.w600,
              ),
            ),
            style: TextButton.styleFrom(
              foregroundColor: context.appColors.danger,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildBerandaHeader(BuildContext context, bool isCompact) {
    return HeroHeaderCard(
      variant: HeroVariant.resident,
      roleLabel: 'Warga • ${session.rtLabel}',
      roleIcon: Icons.person_outline,
      title: 'Halo, ${session.nickname}',
      subtitle: session.communityName,
      dateText: _formatTodayDate(),
    );
  }

  Widget _buildOfflineWarning(BuildContext context) {
    return AlertBanner.warning(
      key: const Key('resident-offline-warning'),
      title: 'Mode offline',
      message:
          'Sesi dan informasi tugas tersimpan belum diverifikasi ulang. '
          'Status tugas mungkin sudah berubah.',
      icon: Icons.cloud_off_outlined,
      actionLabel: _syncing ? 'Memeriksa status…' : 'Sinkronkan sekarang',
      actionIcon: Icons.sync,
      actionKey: const Key('resident-reconnect-sync'),
      onAction: _syncing ? null : _restoreAndSync,
    );
  }

  Widget _buildTaskSummaryPlaceholder(BuildContext context, bool isCompact) {
    if (taskResponseController == null) {
      return SectionCard(
        title: 'Tugas Saya',
        icon: Icons.checklist,
        children: [
          Text(
            'Layanan tugas belum terhubung.',
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: context.appColors.textSecondary),
          ),
        ],
      );
    }

    return TaskSummaryCard(
      taskList: _taskList,
      loading: _loadingTasks,
      error: _taskLoadError,
      isCompact: isCompact,
      onViewAll: () => setState(() => _selectedTabIndex = 1),
      onRetry: _loadTasks,
      onProposeTask: residentProposalController != null
          ? () => Navigator.of(context).pushNamed(
              '/resident/proposals',
              arguments: session,
            )
          : null,
    );
  }

  Widget _buildShortcuts(BuildContext context, bool isCompact) {
    if (session.isOfflineSnapshot) return const SizedBox.shrink();

    final items = <ActionTileData>[];
    if (assistanceVolunteerController != null) {
      items.add(
        ActionTileData(
          key: const Key('resident-assistance-volunteer'),
          icon: Icons.volunteer_activism_outlined,
          label: 'Kesediaan Membantu',
          description: 'Daftar kesiapan membantu',
          onTap: () =>
              Navigator.of(context)
                  .pushNamed('/resident/assistance', arguments: session),
        ),
      );
    }
    if (residentProposalController != null) {
      items.add(
        ActionTileData(
          key: const Key('resident-propose-task'),
          icon: Icons.lightbulb_outline,
          label: 'Usulkan Persiapan Warga',
          description: 'Kirim usulan ke RT',
          onTap: () =>
              Navigator.of(context)
                  .pushNamed('/resident/proposals', arguments: session),
        ),
      );
    }
    if (treePointController != null) {
      items.add(
        ActionTileData(
          key: const Key('resident-trees-shortcut'),
          icon: Icons.park_outlined,
          label: 'Pohon Guyub RT',
          description: 'Peta pohon & resapan',
          onTap: () {
            Navigator.of(context).pushNamed('/community/trees');
          },
        ),
      );
    }

    if (items.isEmpty) return const SizedBox.shrink();

    return ActionTileGrid(items: items);
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
      onTaskTap: (task) => _openTaskDetail(task),
      onTaskJoin: (task) => _joinTask(task),
    );
  }

  Future<void> _openTaskDetail(ResidentTaskRecord task) async {
    final controller = taskResponseController;
    if (controller == null) return;

    // Navigate directly with MaterialPageRoute instead of named route
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ResidentTaskDetailScreen(
          session: _session,
          controller: controller,
          task: task,
          isCached: _taskList?.isCached ?? false,
          lastSyncedAt: _taskList?.lastSyncedAt,
          treePointController: widget.treePointController,
        ),
      ),
    );

    // Reload tasks after returning from detail
    await _loadTasks();
  }

  Future<void> _joinTask(ResidentTaskRecord task) async {
    final controller = taskResponseController;
    if (controller == null) return;

    try {
      await controller.recordParticipation(
        taskId: task.taskId,
        choice: ParticipationChoice.join,
        session: _session,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Anda telah memilih ikut dalam tugas ini'),
            duration: Duration(seconds: 2),
          ),
        );
        await _loadTasks();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Gagal menyimpan pilihan. Coba lagi nanti.'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

  Widget _buildDaruratTab(BuildContext context) {
    final directoryController = emergencyDirectoryController;
    if (directoryController == null) {
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
                'Direktori darurat belum tersedia pada sesi ini.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return EmergencyDirectoryScreen(
      controller: directoryController,
      session: session,
      showAppBar: false,
    );
  }

  Widget _buildBottomNavigation(BuildContext context) {
    return GuyubBottomNavBar(
      currentIndex: _selectedTabIndex,
      onTap: (index) => setState(() => _selectedTabIndex = index),
    );
  }

  String _formatTodayDate() =>
      IndonesianDateFormatter.formatDateOnly(DateTime.now());
}
