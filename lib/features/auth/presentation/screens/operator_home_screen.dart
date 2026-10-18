import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/guyub_tokens.dart';
import '../../../../core/utils/indonesian_date_formatter.dart';
import '../../../../core/widgets/alert_banner.dart';
import '../../../../core/widgets/guyub_bottom_nav_bar.dart';
import '../../../../core/widgets/guyub_top_bar.dart';
import '../../../../core/widgets/hero_header_card.dart';
import '../../../../core/widgets/mockup_widgets.dart';
import '../../../../core/widgets/section_card.dart';
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
import '../../../trees/presentation/controllers/tree_point_controller.dart';

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
    this.treePointController,
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
  final TreePointController? treePointController;

  @override
  State<OperatorHomeScreen> createState() => _OperatorHomeScreenState();
}

final class _OperatorHomeScreenState extends State<OperatorHomeScreen> {
  int _selectedTabIndex = 0;
  List<ActiveTaskCampaignRecord> _activeTasks = const [];
  bool _activeTasksLoadFailed = false;
  int? _pendingVerificationsCount;
  TaskVerificationRecord? _firstPendingRecord;
  int? _completedTasksCount;
  int? _totalHouseholdsCount;
  int? _readyHouseholdsCount;
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
          setState(() {
            _pendingVerificationsCount = queue.items.length;
            _firstPendingRecord = queue.items.isNotEmpty
                ? queue.items.first
                : null;
          });
        }
      } catch (_) {
        // Safe fail-closed
      }
    }

    // 3. Completed task history
    if (campaignBoundary is TaskCampaignHistoryBoundary) {
      try {
        final history = await (campaignBoundary as TaskCampaignHistoryBoundary)
            .listRtTaskHistory(pageSize: 50);
        if (mounted) {
          setState(() => _completedTasksCount = history.tasks.length);
        }
      } catch (_) {
        // Safe fail-closed
      }
    }

    // 4. Vulnerable & Total households
    final proxyController = widget.proxyResidentController;
    if (proxyController != null) {
      try {
        final list = await proxyController.listProxyResidents();
        final count = list.residents.where((r) => r.needsAssistance).length;
        if (mounted) {
          setState(() {
            _vulnerableResidentsCount = count;
            _totalHouseholdsCount = list.residents.isNotEmpty
                ? list.residents.length
                : null;
          });
        }
      } catch (_) {
        // Safe fail-closed
      }
    }

    // 5. Active task recaps for readiness
    if (responseController != null && _activeTasks.isNotEmpty) {
      try {
        int totalVerified = 0;
        for (final task in _activeTasks) {
          final recap = await responseController.getResponseRecap(
            taskId: task.taskId,
          );
          totalVerified += recap.verifiedCompleteCount;
        }
        if (mounted) {
          setState(() => _readyHouseholdsCount = totalVerified);
        }
      } catch (_) {
        // Safe fail-closed
      }
    }

    // 6. Weather suggestions
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

  Future<void> _navigateAndRefresh(
    String routeName, {
    Object? arguments,
  }) async {
    await Navigator.of(context).pushNamed(routeName, arguments: arguments);
    if (mounted) {
      await _loadDashboardData();
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

  Future<void> _signOut() async {
    await widget.taskPushNotificationsController
        ?.unregisterPendampingBeforeSignOut(widget.profile);
    widget.taskPushNotificationsController?.clearActiveTarget();
    await widget.authBoundary?.signOut();
    if (mounted) {
      Navigator.of(context).pushNamedAndRemoveUntil('/', (_) => false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = widget.profile;

    final String semanticTitle = switch (_selectedTabIndex) {
      1 => 'Tugas Aktif RT',
      2 => 'Informasi Darurat',
      _ => 'Ruang Operator',
    };

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        titleSpacing: 16,
        title: _selectedTabIndex == 0
            ? const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  GuyubWordmark(),
                  SizedBox(width: 8),
                  Text(
                    'Ruang Operator',
                    style: TextStyle(fontSize: 0, height: 0),
                  ),
                ],
              )
            : Text(semanticTitle),
        actions: [
          if (_selectedTabIndex == 1)
            IconButton(
              key: const Key('operator-appbar-history'),
              tooltip: 'Riwayat Tugas',
              onPressed: () => _navigateAndRefresh(
                '/operator/tasks/history',
                arguments: profile,
              ),
              icon: const Icon(Icons.history),
            ),
          IconButton(
            tooltip: 'Notifikasi',
            icon: const Icon(Icons.notifications_none, size: 22),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Belum ada notifikasi baru untuk operator.'),
                  duration: Duration(seconds: 2),
                ),
              );
            },
          ),
          IconButton(
            key: const Key('operator-sign-out'),
            tooltip: 'Keluar',
            onPressed: _signOut,
            icon: const Icon(Icons.logout, size: 22),
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
        onTap: (index) {
          setState(() => _selectedTabIndex = index);
          if (index == 0) {
            unawaited(_loadDashboardData());
          }
        },
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
          // 1. Header Operator (Solid Blue)
          _buildOperatorHeader(context),
          const SizedBox(height: 12),

          // 2. Pendamping Push Opt-in (if applicable)
          if (profile.role == OperatorRole.pendampingRt &&
              widget.taskPushNotificationsController != null) ...[
            TaskPushOptInCard.forPendamping(
              controller: widget.taskPushNotificationsController!,
              profile: profile,
            ),
            const SizedBox(height: 10),
          ],

          // 3. Status koneksi katalog tugas (jika belum terhubung)
          if (!hasCampaignBoundary) ...[
            const AlertBanner.warning(
              title: 'Katalog Belum Terhubung',
              message: 'Akses operator terverifikasi. Katalog tugas belum terhubung.',
              icon: Icons.cloud_off_outlined,
            ),
            const SizedBox(height: 10),
          ],

          // 4. Kartu Cuaca BMKG (Format CUACA SEKARANG proposal)
          if (widget.weatherSnapshotStore != null) ...[
            WeatherSnapshotCard(
              key: ValueKey<int>(_weatherRevision),
              store: widget.weatherSnapshotStore!,
              communityId: profile.communityId,
              onRefresh: widget.weatherSnapshotSyncController == null
                  ? null
                  : _refreshWeather,
            ),
            if (_weatherSuggestions.isNotEmpty &&
                widget.weatherSuggestionBoundary != null &&
                hasCampaignBoundary) ...[
              const SizedBox(height: 8),
              TintedInfoBox(
                tint: TintType.info,
                icon: Icons.wb_cloudy_outlined,
                child: Text(
                  'BMKG mendeteksi potensi cuaca yang memerlukan persiapan. '
                  'Tersedia ${_weatherSuggestions.length} saran persiapan aman.',
                ),
              ),
            ],
            const SizedBox(height: 10),
          ],

          // 5. Error Card aktif jika gagal memuat
          if (isManagement && _activeTasksLoadFailed) ...[
            AlertBanner.danger(
              key: const Key('operator-active-tasks-error-card'),
              title: 'Gagal Memuat Tugas Aktif',
              message:
                  'Daftar tugas aktif RT belum dapat dimuat dari server. '
                  'Periksa koneksi internet Anda.',
              actionLabel: 'Coba Lagi',
              actionIcon: Icons.refresh,
              actionKey: const Key('operator-active-tasks-retry-button'),
              onAction: () => _loadDashboardData(),
            ),
            const SizedBox(height: 10),
          ],

          // 6. Banner "Warga perlu dibantu" (Hanya jika ada warga rentan)
          if ((_vulnerableResidentsCount ?? 0) > 0 &&
              widget.proxyResidentController != null) ...[
            _buildVulnerableBanner(context),
            const SizedBox(height: 10),
          ],

          // 7. Card "Menunggu Verifikasi" (Hanya jika ada verifikasi tertunda)
          if ((_pendingVerificationsCount ?? 0) > 0 &&
              widget.taskResponseController != null) ...[
            _buildPendingVerificationCard(context),
            const SizedBox(height: 10),
          ],

          // 8. Menu Operasional RT (Aksi cepat lengkap)
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
                  onOpenCatalog: () => _navigateAndRefresh(
                    '/operator/tasks/catalog',
                    arguments: profile,
                  ),
                  onWeatherSuggestions: widget.weatherSuggestionBoundary != null
                      ? () => _navigateAndRefresh(
                          '/operator/weather-suggestions',
                          arguments: profile,
                        )
                      : null,
                  onActiveTasks: isManagement
                      ? () => _navigateAndRefresh(
                          '/operator/tasks/active',
                          arguments: profile,
                        )
                      : null,
                  onVerification: widget.taskResponseController != null
                      ? () => _navigateAndRefresh(
                          '/operator/tasks/verification',
                          arguments: profile,
                        )
                      : null,
                  onProposalReview: widget.proposalReviewController != null
                      ? () => _navigateAndRefresh(
                          '/operator/proposals',
                          arguments: profile,
                        )
                      : null,
                  onProxyAssistance: widget.proxyResidentController != null
                      ? () => _navigateAndRefresh(
                          '/operator/assistance',
                          arguments: profile,
                        )
                      : null,
                  onTaskHistory: isHistory
                      ? () => _navigateAndRefresh(
                          '/operator/tasks/history',
                          arguments: profile,
                        )
                      : null,
                  onTreeMap: widget.treePointController != null
                      ? () => _navigateAndRefresh('/community/trees')
                      : null,
                ),
              ],
            ),
            const SizedBox(height: 10),
          ],

          // 9. TUGAS WARGA (Stat Row: 3 Boxes)
          if (hasCampaignBoundary) ...[
            const GuyubSmallLabel('TUGAS WARGA'),
            GuyubStatRow(
              tiles: [
                GuyubStatTile(
                  value: _activeTasksLoadFailed
                      ? '-'
                      : '${isManagement ? _activeTasks.length : 0}',
                  label: 'Tugas Aktif',
                  color: GuyubTokens.green,
                  onTap: isManagement
                      ? () => _navigateAndRefresh(
                          '/operator/tasks/active',
                          arguments: profile,
                        )
                      : null,
                ),
                GuyubStatTile(
                  value: _completedTasksCount != null
                      ? '$_completedTasksCount'
                      : '0',
                  label: 'Selesai',
                  color: const Color(0xFF1E293B),
                  onTap: isHistory
                      ? () => _navigateAndRefresh(
                          '/operator/tasks/history',
                          arguments: profile,
                        )
                      : null,
                ),
                GuyubStatTile(
                  value: '${_pendingVerificationsCount ?? 0}',
                  label: 'Tertunda',
                  color: GuyubTokens.orange,
                  onTap: widget.taskResponseController != null
                      ? () => _navigateAndRefresh(
                          '/operator/tasks/verification',
                          arguments: profile,
                        )
                      : null,
                ),
              ],
            ),
            const SizedBox(height: 10),
          ],

          // 10. TUGAS TERKINI
          if (isManagement && _activeTasks.isNotEmpty) ...[
            const GuyubSmallLabel('TUGAS TERKINI'),
            for (final task in _activeTasks.take(3))
              _buildTaskTerkiniRow(context, task),
            const SizedBox(height: 10),
          ],

          // 11. KESIAPAN RUMAH TANGGA
          if (hasCampaignBoundary) ...[
            _buildHouseholdReadinessCard(context),
            const SizedBox(height: 12),
          ],
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildOperatorHeader(BuildContext context) {
    final profile = widget.profile;
    final greeting = guyubGreetingFor(DateTime.now());
    final displayName = profile.displayName.isNotEmpty
        ? profile.displayName
        : profile.role.label;
    final hasCommunityName =
        profile.communityName != null &&
        profile.communityName!.trim().isNotEmpty;

    return HeroHeaderCard(
      variant: HeroVariant.operator,
      roleLabel: profile.role.label,
      roleIcon: Icons.shield_outlined,
      communityLabel: hasCommunityName
          ? 'RT ${profile.communityId}'
          : profile.humanizedCommunityName,
      secondaryCommunityLabel: hasCommunityName ? profile.communityName : null,
      title: '$greeting, $displayName',
      dateText: _formatTodayDate(),
    );
  }

  Widget _buildHouseholdReadinessCard(BuildContext context) {
    final colors = context.appColors;
    final total = _totalHouseholdsCount ?? 32;
    final ready = _readyHouseholdsCount ?? (_completedTasksCount ?? 0);
    final percent = total > 0 ? (ready / total).clamp(0.0, 1.0) : 0.0;
    final percentInt = (percent * 100).round();
    final belumSiap = (total - ready).clamp(0, 9999);

    String targetText = 'Tidak ada target aktif';
    if (_activeTasks.isNotEmpty) {
      final nearest = _activeTasks
          .map((t) => t.deadline)
          .reduce((a, b) => a.isBefore(b) ? a : b);
      targetText = 'Target: ${IndonesianDateFormatter.formatDateOnly(nearest)}';
    }

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(GuyubTokens.cardRadius),
        boxShadow: GuyubTokens.softShadow,
      ),
      child: Material(
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(GuyubTokens.cardRadius),
          side: const BorderSide(color: GuyubTokens.greyBorder),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'KESIAPAN RUMAH TANGGA',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: colors.textSecondary,
                      letterSpacing: 0.6,
                    ),
                  ),
                  Text(
                    '$percentInt%',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: colors.primary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              RichText(
                text: TextSpan(
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF1E293B),
                  ),
                  children: [
                    TextSpan(text: '$ready '),
                    TextSpan(
                      text: 'dari $total Rumah Tangga siap',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.normal,
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: percent,
                  backgroundColor: const Color(0xFFE2E8F0),
                  valueColor: AlwaysStoppedAnimation<Color>(colors.primary),
                  minHeight: 6,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '$belumSiap belum siap',
                    style: TextStyle(fontSize: 11, color: colors.textSecondary),
                  ),
                  Text(
                    targetText,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFFE11D48),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildVulnerableBanner(BuildContext context) {
    final count = _vulnerableResidentsCount ?? 0;
    return Container(
      decoration: BoxDecoration(
        color: GuyubTokens.yellowFill,
        borderRadius: BorderRadius.circular(GuyubTokens.cardRadius),
        border: Border.all(color: GuyubTokens.yellowBorder, width: 1.2),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(GuyubTokens.cardRadius),
          onTap: () => _navigateAndRefresh(
            '/operator/assistance',
            arguments: widget.profile,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                const Icon(
                  Icons.favorite_border,
                  size: 20,
                  color: Color(0xFFB45309),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$count Warga perlu dibantu',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF92400E),
                        ),
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        'Lansia, disabilitas dan ibu hamil belum ditandai relawan',
                        style: TextStyle(
                          fontSize: 11,
                          color: Color(0xFFB45309),
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.chevron_right,
                  size: 20,
                  color: Color(0xFFB45309),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPendingVerificationCard(BuildContext context) {
    final pending = _firstPendingRecord;
    final nickname = pending?.nickname ?? 'Warga RT';
    final taskTitle = pending?.taskTitle ?? 'Penyelesaian Tugas';
    final timeStr = pending != null
        ? IndonesianDateFormatter.formatCompact(pending.submittedAt)
        : '';
    final hasEvidence = pending?.evidenceId != null;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(GuyubTokens.cardRadius),
        border: Border.all(color: GuyubTokens.greyBorder),
        boxShadow: GuyubTokens.softShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Yellow header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: const BoxDecoration(
              color: GuyubTokens.yellowFill,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(GuyubTokens.cardRadius - 1),
                topRight: Radius.circular(GuyubTokens.cardRadius - 1),
              ),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.warning_amber_rounded,
                  size: 15,
                  color: Color(0xFFB45309),
                ),
                const SizedBox(width: 6),
                Text(
                  'Menunggu Verifikasi (${_pendingVerificationsCount ?? 1})',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF92400E),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        nickname,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        taskTitle,
                        style: TextStyle(
                          fontSize: 12,
                          color: context.appColors.textSecondary,
                        ),
                      ),
                      if (timeStr.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          timeStr,
                          style: TextStyle(
                            fontSize: 10,
                            color: context.appColors.textSecondary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE2E8F0),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    hasEvidence ? Icons.image_outlined : Icons.task_alt,
                    color: hasEvidence
                        ? const Color(0xFF0F766E)
                        : const Color(0xFF94A3B8),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      minimumSize: const Size(0, 36),
                      side: const BorderSide(color: GuyubTokens.greyBorder),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    onPressed: () => _navigateAndRefresh(
                      '/operator/tasks/verification',
                      arguments: widget.profile,
                    ),
                    child: const Text(
                      'Buka Antrean',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: GuyubTokens.green,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      minimumSize: const Size(0, 36),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    onPressed: () => _navigateAndRefresh(
                      '/operator/tasks/verification',
                      arguments: widget.profile,
                    ),
                    child: const Text(
                      'Tinjau & Verifikasi',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTaskTerkiniRow(
    BuildContext context,
    ActiveTaskCampaignRecord task,
  ) {
    final colors = context.appColors;
    final hoursLeft = task.deadline
        .difference(DateTime.now())
        .inHours
        .clamp(0, 999);
    final daysLeft = task.deadline.difference(DateTime.now()).inDays;
    final timeRemaining = daysLeft > 1
        ? '$daysLeft hari lagi'
        : (hoursLeft > 0 ? '$hoursLeft jam lagi' : 'Batas waktu terlewat');

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: GuyubTokens.greyBorder),
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              color: GuyubTokens.green,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  task.templateSnapshot.title,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$timeRemaining • Batas: ${IndonesianDateFormatter.formatDateOnly(task.deadline)}',
                  style: TextStyle(fontSize: 10, color: colors.textSecondary),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: GuyubTokens.greenSoft,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Text(
              'Aktif',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: GuyubTokens.green,
              ),
            ),
          ),
        ],
      ),
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
