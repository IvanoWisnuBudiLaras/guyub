import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/indonesian_date_formatter.dart';
import '../../../../core/widgets/guyub_bottom_nav_bar.dart';
import '../../../../core/widgets/inline_action_button.dart';
import '../../../../core/widgets/section_card.dart';
import '../../../../core/widgets/task_category_presentation.dart';
import '../../../../core/widgets/tinted_info_box.dart';
import '../../application/operator_auth_boundary.dart';
import '../../application/operator_profile.dart';
import '../../../assistance/application/proxy_resident_boundary.dart';
import '../../../emergency/application/emergency_directory_controller.dart';
import '../../../emergency/presentation/emergency_directory_screen.dart';
import '../../../notifications/application/task_push_notifications.dart';
import '../../../notifications/presentation/task_push_opt_in_card.dart';
import '../../../proposals/application/resident_proposal_boundary.dart';
import '../../../tasks/application/task_campaign_boundary.dart';
import '../../../tasks/application/task_response_boundary.dart';
import '../../../tasks/presentation/screens/task_active_campaigns_screen.dart';
import '../../../weather/application/weather_snapshot_boundary.dart';
import '../../../weather/application/weather_snapshot_store.dart';
import '../../../weather/application/weather_suggestion.dart';
import '../../../weather/application/weather_suggestion_boundary.dart';
import '../../../weather/presentation/weather_snapshot_card.dart';
import '../widgets/operator_action_shortcuts.dart';
import '../widgets/operator_metrics_card.dart';

/// Authenticated operator landing page and operational dashboard.
final class OperatorHomeScreen extends StatefulWidget {
  const OperatorHomeScreen({
    required this.profile,
    required this.authBoundary,
    this.taskCampaignBoundary,
    this.taskResponseController,
    this.proposalReviewController,
    this.proxyResidentController,
    this.taskPushNotificationsController,
    this.weatherSuggestionBoundary,
    this.weatherSnapshotStore,
    this.weatherSnapshotSyncController,
    this.emergencyDirectoryController,
    super.key,
  });

  final OperatorProfile profile;
  final OperatorAuthBoundary? authBoundary;
  final TaskCampaignBoundary? taskCampaignBoundary;
  final TaskResponseController? taskResponseController;
  final ResidentProposalReviewController? proposalReviewController;
  final ProxyResidentController? proxyResidentController;
  final TaskPushNotificationsController? taskPushNotificationsController;
  final WeatherSuggestionBoundary? weatherSuggestionBoundary;
  final WeatherSnapshotStore? weatherSnapshotStore;
  final WeatherSnapshotSyncController? weatherSnapshotSyncController;
  final EmergencyDirectoryController? emergencyDirectoryController;

  @override
  State<OperatorHomeScreen> createState() => _OperatorHomeScreenState();
}

final class _OperatorHomeScreenState extends State<OperatorHomeScreen> {
  int _selectedTabIndex = 0;
  List<ActiveTaskCampaignRecord> _activeTasks = const [];
  bool _activeTasksLoadFailed = false;
  int? _pendingVerificationsCount;
  int? _vulnerableResidentsCount;
  List<WeatherSuggestion> _weatherSuggestions = const [];
  int _weatherRevision = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_loadDashboardData());
  }

  Future<void> _loadDashboardData() async {
    // 1. Active tasks count
    final campaignBoundary = widget.taskCampaignBoundary;
    if (campaignBoundary is TaskCampaignManagementBoundary) {
      try {
        final tasks = await (campaignBoundary as TaskCampaignManagementBoundary)
            .listActiveTaskCampaigns();
        if (mounted) {
          setState(() {
            _activeTasks = tasks;
            _activeTasksLoadFailed = false;
          });
        }
      } catch (_) {
        if (mounted) {
          setState(() {
            _activeTasksLoadFailed = true;
          });
        }
      }
    }

    // 2. Pending verifications
    final responseController = widget.taskResponseController;
    if (responseController != null) {
      try {
        final queue = await responseController.listPendingVerifications();
        if (mounted) {
          setState(() => _pendingVerificationsCount = queue.items.length);
        }
      } catch (_) {
        // Safe fail-closed
      }
    }

    // 3. Vulnerable residents
    final proxyController = widget.proxyResidentController;
    if (proxyController != null) {
      try {
        final list = await proxyController.listProxyResidents();
        final count = list.residents.where((r) => r.needsAssistance).length;
        if (mounted) setState(() => _vulnerableResidentsCount = count);
      } catch (_) {
        // Safe fail-closed
      }
    }

    // 4. Weather suggestions
    final weatherBoundary = widget.weatherSuggestionBoundary;
    if (weatherBoundary != null && campaignBoundary != null) {
      try {
        final suggestions = await weatherBoundary.listWeatherSuggestions();
        if (mounted) setState(() => _weatherSuggestions = suggestions);
      } catch (_) {
        // Safe fail-closed
      }
    }
  }

  Future<void> _refreshWeather() async {
    final sync = widget.weatherSnapshotSyncController;
    if (sync == null) return;
    try {
      await sync.refreshForResident(communityId: widget.profile.communityId);
      if (mounted) setState(() => _weatherRevision++);
    } catch (_) {
      // Preserve last valid weather data
    }
  }

  String _formatTodayDate() =>
      IndonesianDateFormatter.formatDateOnly(DateTime.now());

  @override
  Widget build(BuildContext context) {
    final profile = widget.profile;

    final String appBarTitle = switch (_selectedTabIndex) {
      1 => 'Tugas Aktif RT',
      2 => 'Informasi Darurat',
      _ => 'Ruang Operator',
    };

    return Scaffold(
      appBar: AppBar(
        title: Text(appBarTitle),
        actions: [
          if (_selectedTabIndex == 1)
            IconButton(
              key: const Key('operator-appbar-history'),
              tooltip: 'Riwayat Tugas',
              onPressed: () =>
                  Navigator.of(context)
                      .pushNamed('/operator/tasks/history', arguments: profile),
              icon: const Icon(Icons.history),
            ),
          IconButton(
            key: const Key('operator-sign-out'),
            tooltip: 'Keluar',
            onPressed: () async {
              await widget.taskPushNotificationsController
                  ?.unregisterPendampingBeforeSignOut(profile);
              widget.taskPushNotificationsController?.clearActiveTarget();
              await widget.authBoundary?.signOut();
              if (context.mounted) {
                Navigator.of(context)
                    .pushNamedAndRemoveUntil('/', (_) => false);
              }
            },
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: IndexedStack(
        index: _selectedTabIndex,
        children: [
          _buildBerandaTab(context),
          _buildTugasTab(context),
          _buildDaruratTab(context),
        ],
      ),
      bottomNavigationBar: GuyubBottomNavBar(
        currentIndex: _selectedTabIndex,
        onTap: (index) => setState(() => _selectedTabIndex = index),
      ),
    );
  }

  Widget _buildBerandaTab(BuildContext context) {
    final colors = context.appColors;
    final profile = widget.profile;
    final hasCampaignBoundary = widget.taskCampaignBoundary != null;
    final isManagement =
        widget.taskCampaignBoundary is TaskCampaignManagementBoundary;
    final isHistory =
        widget.taskCampaignBoundary is TaskCampaignHistoryBoundary;

    return RefreshIndicator(
      onRefresh: () async {
        await _loadDashboardData();
        await _refreshWeather();
      },
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: [
          // 1. Header Operator
          _buildOperatorHeader(context),
          const SizedBox(height: 10),

          // 2. Pendamping Push Opt-in (if applicable)
          if (profile.role == OperatorRole.pendampingRt &&
              widget.taskPushNotificationsController != null) ...[
            TaskPushOptInCard.forPendamping(
              controller: widget.taskPushNotificationsController!,
              profile: profile,
            ),
            const SizedBox(height: 10),
          ],

          // 3. Status koneksi katalog tugas
          if (!hasCampaignBoundary) ...[
            const TintedInfoBox(
              tint: TintType.warning,
              icon: Icons.cloud_off_outlined,
              title: 'Katalog Belum Terhubung',
              child: Text(
                'Akses operator terverifikasi. Katalog tugas belum terhubung.',
              ),
            ),
            const SizedBox(height: 10),
          ],

          // 4. Kartu Cuaca BMKG
          if (widget.weatherSnapshotStore != null) ...[
            WeatherSnapshotCard(
              key: ValueKey<int>(_weatherRevision),
              store: widget.weatherSnapshotStore!,
              communityId: profile.communityId,
              onRefresh: widget.weatherSnapshotSyncController == null
                  ? null
                  : _refreshWeather,
            ),
            const SizedBox(height: 10),
          ],

          // 5. Banner Rekomendasi Cuaca (jika ada saran BMKG)
          if (_weatherSuggestions.isNotEmpty &&
              widget.weatherSuggestionBoundary != null &&
              hasCampaignBoundary) ...[
            TintedInfoBox(
              tint: TintType.info,
              icon: Icons.wb_cloudy_outlined,
              title: 'Rekomendasi Tindakan dari Cuaca',
              action: InlineActionButton(
                variant: InlineActionButtonVariant.filled,
                onPressed: () => Navigator.of(context).pushNamed(
                  '/operator/weather-suggestions',
                  arguments: profile,
                ),
                label: 'Tinjau',
              ),
              child: Text(
                'BMKG mendeteksi potensi cuaca yang memerlukan persiapan. '
                'Tersedia ${_weatherSuggestions.length} saran persiapan aman.',
              ),
            ),
            const SizedBox(height: 10),
          ],

          // 6. Kartu Metrik Kesiapan RT
          if (hasCampaignBoundary) ...[
            OperatorMetricsCard(
              activeTasksCount: _activeTasksLoadFailed
                  ? null
                  : (isManagement ? _activeTasks.length : null),
              pendingVerificationsCount: _pendingVerificationsCount,
              vulnerableResidentsCount: _vulnerableResidentsCount,
              onActiveTasksTap: isManagement
                  ? () => Navigator.of(context)
                        .pushNamed('/operator/tasks/active', arguments: profile)
                  : null,
              onVerificationsTap: widget.taskResponseController != null
                  ? () => Navigator.of(context).pushNamed(
                      '/operator/tasks/verification',
                      arguments: profile,
                    )
                  : null,
              onVulnerableResidentsTap: widget.proxyResidentController != null
                  ? () => Navigator.of(context)
                        .pushNamed('/operator/assistance', arguments: profile)
                  : null,
            ),
            const SizedBox(height: 10),
          ],

          // 7. Banner Peringatan Warga Rentan
          if ((_vulnerableResidentsCount ?? 0) > 0 &&
              widget.proxyResidentController != null) ...[
            TintedInfoBox.warning(
              title: 'Perhatian Warga Rentan',
              text:
                  '$_vulnerableResidentsCount warga rentan tercatat memerlukan '
                  'pendampingan evakuasi / persiapan.',
              action: InlineActionButton(
                variant: InlineActionButtonVariant.outlined,
                onPressed: () =>
                    Navigator.of(context)
                        .pushNamed('/operator/assistance', arguments: profile),
                label: 'Lihat Warga',
              ),
            ),
            const SizedBox(height: 10),
          ],

          // 8. Banner Verifikasi Tertunda (hanya jumlah + link ke antrean)
          if ((_pendingVerificationsCount ?? 0) > 0 &&
              widget.taskResponseController != null) ...[
            TintedInfoBox.info(
              title: 'Antrean Verifikasi',
              text:
                  '$_pendingVerificationsCount laporan tugas warga menunggu verifikasi.',
              action: InlineActionButton(
                variant: InlineActionButtonVariant.outlined,
                onPressed: () => Navigator.of(
                  context,
                ).pushNamed('/operator/tasks/verification', arguments: profile),
                label: 'Buka Antrean',
              ),
            ),
            const SizedBox(height: 10),
          ],

          // 9. Error Card atau Pratinjau Tugas Aktif
          if (isManagement && _activeTasksLoadFailed) ...[
            Container(
              key: const Key('operator-active-tasks-error-card'),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: colors.danger.withValues(alpha: 0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.error_outline, color: colors.danger, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Gagal Memuat Tugas Aktif',
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: colors.danger,
                              ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Daftar tugas aktif RT belum dapat dimuat dari server. '
                    'Periksa koneksi internet Anda.',
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: colors.textSecondary),
                  ),
                  const SizedBox(height: 10),
                  InlineActionButton(
                    key: const Key('operator-active-tasks-retry-button'),
                    variant: InlineActionButtonVariant.outlined,
                    icon: Icons.refresh,
                    label: 'Coba Lagi',
                    onPressed: () => _loadDashboardData(),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
          ] else if (isManagement && _activeTasks.isNotEmpty) ...[
            _buildActiveTasksPreview(context),
            const SizedBox(height: 10),
          ],

          // 10. Menu Operasional & Aksi Cepat
          if (hasCampaignBoundary) ...[
            SectionCard(
              title: 'Menu Operasional RT',
              icon: Icons.dashboard_outlined,
              padding: const EdgeInsets.all(14),
              margin: const EdgeInsets.only(bottom: 8),
              children: [
                Text(
                  'Gunakan template yang ditinjau. Aktivasi tugas tetap memerlukan '
                  'konfirmasi operator.',
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: colors.textSecondary),
                ),
                const SizedBox(height: 12),
                OperatorActionShortcuts(
                  onOpenCatalog: () => Navigator.of(context)
                      .pushNamed('/operator/tasks/catalog', arguments: profile),
                  onWeatherSuggestions: widget.weatherSuggestionBoundary != null
                      ? () => Navigator.of(context).pushNamed(
                          '/operator/weather-suggestions',
                          arguments: profile,
                        )
                      : null,
                  onActiveTasks: isManagement
                      ? () => Navigator.of(context).pushNamed(
                          '/operator/tasks/active',
                          arguments: profile,
                        )
                      : null,
                  onVerification: widget.taskResponseController != null
                      ? () => Navigator.of(context).pushNamed(
                          '/operator/tasks/verification',
                          arguments: profile,
                        )
                      : null,
                  onProposalReview: widget.proposalReviewController != null
                      ? () => Navigator.of(
                          context,
                        ).pushNamed('/operator/proposals', arguments: profile)
                      : null,
                  onProxyAssistance: widget.proxyResidentController != null
                      ? () => Navigator.of(
                          context,
                        ).pushNamed('/operator/assistance', arguments: profile)
                      : null,
                  onTaskHistory: isHistory
                      ? () => Navigator.of(context).pushNamed(
                          '/operator/tasks/history',
                          arguments: profile,
                        )
                      : null,
                ),
              ],
            ),
          ],
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Widget _buildOperatorHeader(BuildContext context) {
    final colors = context.appColors;
    final profile = widget.profile;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [colors.primary, colors.primaryDark],
        ),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: colors.primary.withValues(alpha: 0.15),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Badges row — use Wrap to prevent overflow
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.shield_outlined,
                      size: 13,
                      color: Colors.white,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      profile.role.label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  profile.humanizedCommunityName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 11,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.calendar_today_outlined,
                      size: 11,
                      color: Colors.white.withValues(alpha: 0.85),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _formatTodayDate(),
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.85),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Greeting & Name
          Text(
            'Selamat Bertugas, ${profile.displayName.isNotEmpty ? profile.displayName : profile.role.label}',
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(color: Colors.white, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  Widget _buildActiveTasksPreview(BuildContext context) {
    final colors = context.appColors;

    return SectionCard(
      title: 'Tugas Aktif Berjalan',
      icon: Icons.task_alt,
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(bottom: 8),
      trailing: TextButton(
        onPressed: () =>
            Navigator.of(context)
                .pushNamed('/operator/tasks/active', arguments: widget.profile),
        child: const Text('Lihat Semua'),
      ),
      children: [
        for (final task in _activeTasks.take(2)) ...[
          Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: colors.background,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: colors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  task.templateSnapshot.title,
                  style: Theme.of(context).textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    TaskCategoryChip(
                      category: task.templateSnapshot.category,
                      compact: true,
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.schedule,
                            size: 11,
                            color: colors.textSecondary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${task.deadline.difference(DateTime.now()).inHours.clamp(0, 999)} jam lagi',
                            style: TextStyle(
                              fontSize: 10,
                              color: colors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildTugasTab(BuildContext context) {
    final campaignBoundary = widget.taskCampaignBoundary;
    if (campaignBoundary is! TaskCampaignManagementBoundary) {
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
    return TaskActiveCampaignsScreen(
      profile: widget.profile,
      controller: TaskCampaignController(campaignBoundary!),
      showAppBar: false,
    );
  }

  Widget _buildDaruratTab(BuildContext context) {
    final directoryController = widget.emergencyDirectoryController;
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
                color: context.appColors.textSecondary,
              ),
              const SizedBox(height: 16),
              Text(
                'Layanan Darurat Belum Terhubung',
                style: Theme.of(context).textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }
    return EmergencyDirectoryScreen(
      controller: directoryController,
      showAppBar: false,
    );
  }
}
