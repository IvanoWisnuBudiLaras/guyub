import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../auth/application/operator_profile.dart';
import '../../../../core/utils/indonesian_date_formatter.dart';
import '../../../../core/widgets/inline_action_button.dart';
import '../../../../core/widgets/task_category_presentation.dart';
import '../../../../core/widgets/tinted_info_box.dart';
import '../../application/task_campaign_boundary.dart';
import '../../application/task_campaign_copy_boundary.dart';
import '../../application/task_campaign_share_text.dart';
import '../../application/task_location_reference.dart';
import '../widgets/locked_instructions_card.dart';

/// Lists the authenticated operator's RT-scoped active campaigns and allows
/// explicit, audited cancellation through the trusted callable boundary.
final class TaskActiveCampaignsScreen extends StatefulWidget {
  const TaskActiveCampaignsScreen({
    required this.profile,
    required this.controller,
    this.initialTaskId,
    this.showAppBar = true,
    this.copyBoundary,
    super.key,
  });

  final OperatorProfile profile;
  final TaskCampaignController controller;
  final String? initialTaskId;
  final bool showAppBar;
  final TaskCampaignCopyBoundary? copyBoundary;

  @override
  State<TaskActiveCampaignsScreen> createState() =>
      _TaskActiveCampaignsScreenState();
}

final class _TaskActiveCampaignsScreenState
    extends State<TaskActiveCampaignsScreen> {
  late Future<List<ActiveTaskCampaignRecord>> _campaignsFuture;
  final Set<String> _cancellingTaskIds = {};
  final Set<String> _closingTaskIds = {};
  String? _actionError;

  bool get _isActing =>
      _cancellingTaskIds.isNotEmpty || _closingTaskIds.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _campaignsFuture = widget.controller.listActiveTaskCampaigns();
  }

  void _reload({bool clearActionError = true}) {
    final future = widget.controller.listActiveTaskCampaigns();
    setState(() {
      _campaignsFuture = future;
      if (clearActionError) _actionError = null;
    });
  }

  Future<void> _refresh() async {
    final future = widget.controller.listActiveTaskCampaigns();
    setState(() {
      _campaignsFuture = future;
      _actionError = null;
    });
    try {
      await future;
    } catch (_) {
      // FutureBuilder shows the generic fail-closed state.
    }
  }

  Future<void> _cancel(ActiveTaskCampaignRecord task) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Batalkan tugas aktif?'),
        content: Text(
          '“${task.templateSnapshot.title}” akan dibatalkan dan dicatat dalam '
          'riwayat audit. Anggota yang mengaktifkan push dapat menerima '
          'pemberitahuan status; pemberitahuan tidak menjamin semua warga '
          'melihat perubahan. Pilihan offline diselaraskan dengan status server.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Kembali'),
          ),
          FilledButton(
            key: const Key('task-campaign-cancel-confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Batalkan tugas'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _cancellingTaskIds.add(task.taskId);
      _actionError = null;
    });
    try {
      final result = await widget.controller.cancelTaskCampaign(
        taskId: task.taskId,
      );
      if (result.taskId != task.taskId || result.status != 'CANCELLED') {
        throw const FormatException('Invalid cancellation response.');
      }
      if (mounted) _reload();
    } catch (_) {
      if (mounted) {
        setState(() {
          _actionError =
              'Pembatalan belum dapat dipastikan. Status tugas sedang '
              'dimuat ulang dari server; jangan menganggap tugas sudah batal.';
          _campaignsFuture = widget.controller.listActiveTaskCampaigns();
        });
      }
    } finally {
      if (mounted) {
        setState(() => _cancellingTaskIds.remove(task.taskId));
      }
    }
  }

  Future<void> _close(ActiveTaskCampaignRecord task) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Tutup tugas aktif?'),
        content: Text(
          '“${task.templateSnapshot.title}” akan dikeluarkan dari daftar tugas '
          'aktif warga. Penutupan tidak menandai tanggapan sebagai selesai; '
          'verifikasi RT tetap menjadi acuan. Perubahan dicatat dalam riwayat.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Kembali'),
          ),
          FilledButton(
            key: const Key('task-campaign-close-confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Tutup tugas'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _closingTaskIds.add(task.taskId);
      _actionError = null;
    });
    try {
      final result = await widget.controller.closeTaskCampaign(
        taskId: task.taskId,
      );
      if (result.taskId != task.taskId || result.status != 'CLOSED') {
        throw const FormatException('Invalid closure response.');
      }
      if (mounted) _reload();
    } catch (_) {
      if (mounted) {
        setState(() {
          _actionError =
              'Penutupan belum dapat dipastikan. Status tugas sedang dimuat '
              'ulang dari server; jangan menganggap tugas sudah ditutup.';
          _campaignsFuture = widget.controller.listActiveTaskCampaigns();
        });
      }
    } finally {
      if (mounted) {
        setState(() => _closingTaskIds.remove(task.taskId));
      }
    }
  }

  Future<void> _copyWhatsApp(ActiveTaskCampaignRecord task) async {
    final campaign = TaskCampaignRecord(
      campaignId: task.taskId,
      rtId: widget.profile.communityId,
      templateSnapshot: task.templateSnapshot,
      deadline: task.deadline,
      status: 'ACTIVE',
      createdAt: null,
      locationReference: task.locationReference,
    );
    final text = buildTaskCampaignWhatsAppText(
      campaign: campaign,
      formattedDeadline: _formatDeadline(task.deadline),
    );
    try {
      await (widget.copyBoundary ?? const _ClipboardTaskCampaignCopyBoundary())
          .copy(text);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Teks disalin. Periksa kembali sebelum membagikannya ke grup RT.',
            ),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Teks tidak dapat disalin. Tidak ada pesan yang dikirim.',
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: widget.showAppBar
        ? AppBar(
            title: const Text('Tugas Aktif RT'),
            actions: [
              IconButton(
                key: const Key('active-task-to-history'),
                tooltip: 'Riwayat Tugas',
                onPressed: () => Navigator.of(context).pushNamed(
                  '/operator/tasks/history',
                  arguments: widget.profile,
                ),
                icon: const Icon(Icons.history),
              ),
              IconButton(
                key: const Key('active-task-reload'),
                tooltip: 'Muat ulang tugas aktif',
                onPressed: _isActing ? null : () => _reload(),
                icon: const Icon(Icons.refresh),
              ),
            ],
          )
        : null,
    body: FutureBuilder<List<ActiveTaskCampaignRecord>>(
      future: _campaignsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError || snapshot.data == null) {
          return _LoadFailure(
            actionError: _actionError,
            onRetry: _isActing ? null : () => _reload(),
          );
        }
        final tasks = snapshot.data!;
        return RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      '${widget.profile.role.label} · RT ${widget.profile.communityId}',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                  ),
                  OutlinedButton.icon(
                    key: const Key('active-task-history-btn'),
                    onPressed: () => Navigator.of(context).pushNamed(
                      '/operator/tasks/history',
                      arguments: widget.profile,
                    ),
                    icon: const Icon(Icons.history, size: 18),
                    label: const Text('Riwayat'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      minimumSize: const Size(0, 36),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Daftar tugas gotong royong yang sedang aktif di RT ini.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 12),
              const _CancellationNotice(),
              if (_actionError != null) ...[
                const SizedBox(height: 12),
                _ActionError(message: _actionError!),
              ],
              if (widget.initialTaskId != null &&
                  !tasks.any(
                    (task) => task.taskId == widget.initialTaskId,
                  )) ...[
                const SizedBox(height: 12),
                const Card(
                  key: Key('notification-task-unavailable'),
                  child: Padding(
                    padding: EdgeInsets.all(12),
                    child: Text(
                      'Tugas dari notifikasi tidak lagi aktif atau tidak dapat dibuka untuk RT ini.',
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              if (tasks.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 32),
                  child: Text(
                    'Tidak ada tugas aktif untuk RT ini.',
                    key: Key('active-task-empty'),
                    textAlign: TextAlign.center,
                  ),
                )
              else
                for (final task in tasks) ...[
                  _ActiveTaskCard(
                    task: task,
                    isHighlighted: task.taskId == widget.initialTaskId,
                    cancelling: _cancellingTaskIds.contains(task.taskId),
                    actionsDisabled: _isActing,
                    onCancel: () => _cancel(task),
                    closing: _closingTaskIds.contains(task.taskId),
                    onClose: () => _close(task),
                    onCopyWhatsApp: () => _copyWhatsApp(task),
                  ),
                  const SizedBox(height: 12),
                ],
            ],
          ),
        );
      },
    ),
  );
}

final class _ActiveTaskCard extends StatelessWidget {
  const _ActiveTaskCard({
    required this.task,
    required this.isHighlighted,
    required this.cancelling,
    required this.closing,
    required this.actionsDisabled,
    required this.onCancel,
    required this.onClose,
    required this.onCopyWhatsApp,
  });

  final ActiveTaskCampaignRecord task;
  final bool isHighlighted;
  final bool cancelling;
  final bool closing;
  final bool actionsDisabled;
  final VoidCallback onCancel;
  final VoidCallback onClose;
  final VoidCallback onCopyWhatsApp;

  static String _sisaWaktu(DateTime deadline) {
    final now = DateTime.now();
    final difference = deadline.difference(now);
    if (difference.isNegative) return 'Batas waktu lewat';
    if (difference.inDays > 0) return 'Sisa ${difference.inDays} hari';
    if (difference.inHours > 0) return 'Sisa ${difference.inHours} jam';
    return 'Sisa ${difference.inMinutes} menit';
  }

  @override
  Widget build(BuildContext context) => Card(
    key: isHighlighted ? Key('notification-task-${task.taskId}') : null,
    elevation: 0,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side: BorderSide(
        color: isHighlighted
            ? Theme.of(context).colorScheme.primary
            : Theme.of(context).colorScheme.outlineVariant,
      ),
    ),
    color: isHighlighted
        ? Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3)
        : null,
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              TaskCategoryChip(category: task.templateSnapshot.category),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF3C7),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.timer_outlined,
                      size: 14,
                      color: Color(0xFFB45309),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _sisaWaktu(task.deadline),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFFB45309),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            task.templateSnapshot.title,
            style: Theme.of(context).textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            'Snapshot terkunci · Versi ${task.templateSnapshot.version}',
            style: Theme.of(context).textTheme.labelMedium,
          ),
          const SizedBox(height: 12),
          LockedTaskInstructionsCard(snapshot: task.templateSnapshot),
          const SizedBox(height: 8),
          _TaskDetailRow(
            label: 'Batas waktu',
            value: _formatDeadline(task.deadline),
          ),
          _TaskDetailRow(
            label: 'Lokasi umum',
            value: task.locationReference == null
                ? 'Belum ditentukan'
                : TaskLocationReferences.label(task.locationReference!),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 48,
            child: OutlinedButton.icon(
              key: Key('task-copy-whatsapp-${task.taskId}'),
              onPressed: actionsDisabled ? null : onCopyWhatsApp,
              icon: const Icon(Icons.copy, size: 18),
              label: const Text('Salin teks untuk WhatsApp'),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 48,
            child: OutlinedButton.icon(
              key: Key('task-campaign-close-${task.taskId}'),
              onPressed: actionsDisabled ? null : onClose,
              icon: closing
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.archive_outlined, size: 18),
              label: Text(closing ? 'Memproses…' : 'Tutup tugas aktif'),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 48,
            child: FilledButton.icon(
              key: Key('task-campaign-cancel-${task.taskId}'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFFEE2E2),
                foregroundColor: const Color(0xFF991B1B),
              ),
              onPressed: actionsDisabled ? null : onCancel,
              icon: cancelling
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.cancel_outlined, size: 18),
              label: Text(cancelling ? 'Memproses…' : 'Batalkan tugas'),
            ),
          ),
        ],
      ),
    ),
  );
}

final class _TaskDetailRow extends StatelessWidget {
  const _TaskDetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 108,
          child: Text(label, style: Theme.of(context).textTheme.labelLarge),
        ),
        const SizedBox(width: 8),
        Expanded(child: Text(value)),
      ],
    ),
  );
}

final class _CancellationNotice extends StatelessWidget {
  const _CancellationNotice();

  @override
  Widget build(BuildContext context) => TintedInfoBox.info(
    text:
        'Pembatalan dan penutupan adalah tindakan operator yang dicatat dalam '
        'riwayat audit. Penutupan tidak menandai tanggapan warga selesai; '
        'verifikasi RT tetap menjadi acuan. Pilihan warga yang masih antre '
        'secara offline dapat berkonflik saat disinkronkan; status server tetap '
        'menjadi acuan.',
    icon: Icons.info_outline,
  );
}

final class _ActionError extends StatelessWidget {
  const _ActionError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Text(
      message,
      style: TextStyle(color: Theme.of(context).colorScheme.error),
    ),
  );
}

final class _LoadFailure extends StatelessWidget {
  const _LoadFailure({required this.actionError, required this.onRetry});

  final String? actionError;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off_outlined, size: 40),
          const SizedBox(height: 12),
          if (actionError != null) ...[
            _ActionError(message: actionError!),
            const SizedBox(height: 8),
          ],
          const Text(
            'Tugas aktif belum dapat dimuat. Periksa koneksi dan akses RT, '
            'lalu coba lagi.',
            textAlign: TextAlign.center,
          ),
          if (onRetry != null) ...[
            const SizedBox(height: 16),
            InlineActionButton(
              key: const Key('active-task-retry'),
              variant: InlineActionButtonVariant.outlined,
              icon: Icons.refresh,
              label: 'Coba lagi',
              onPressed: onRetry,
            ),
          ],
        ],
      ),
    ),
  );
}

String _formatDeadline(DateTime value) =>
    IndonesianDateFormatter.formatFull(value);

final class _ClipboardTaskCampaignCopyBoundary
    implements TaskCampaignCopyBoundary {
  const _ClipboardTaskCampaignCopyBoundary();

  @override
  Future<void> copy(String text) =>
      Clipboard.setData(ClipboardData(text: text));
}
