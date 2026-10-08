import 'package:flutter/material.dart';

import '../../../auth/application/operator_profile.dart';
import '../../application/task_campaign_boundary.dart';
import '../../application/task_location_reference.dart';
import '../widgets/locked_instructions_card.dart';

/// Lists the authenticated operator's RT-scoped active campaigns and allows
/// explicit, audited cancellation through the trusted callable boundary.
final class TaskActiveCampaignsScreen extends StatefulWidget {
  const TaskActiveCampaignsScreen({
    required this.profile,
    required this.controller,
    this.initialTaskId,
    super.key,
  });

  final OperatorProfile profile;
  final TaskCampaignController controller;
  final String? initialTaskId;

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

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Tugas Aktif RT'),
      actions: [
        IconButton(
          key: const Key('active-task-reload'),
          tooltip: 'Muat ulang tugas aktif',
          onPressed: _isActing ? null : () => _reload(),
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
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
              Text(
                '${widget.profile.role.label} · RT ${widget.profile.communityId}',
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const SizedBox(height: 8),
              Text(
                'Daftar ini berasal dari server untuk RT operator yang masuk. '
                'Rincian template di bawah merupakan snapshot terkunci.',
                style: Theme.of(context).textTheme.bodyLarge,
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
  });

  final ActiveTaskCampaignRecord task;
  final bool isHighlighted;
  final bool cancelling;
  final bool closing;
  final bool actionsDisabled;
  final VoidCallback onCancel;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => Card(
    key: isHighlighted ? Key('notification-task-${task.taskId}') : null,
    color: isHighlighted
        ? Theme.of(context).colorScheme.primaryContainer
        : null,
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            task.templateSnapshot.title,
            style: Theme.of(context).textTheme.titleLarge,
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
            value: _formatDeadline(context, task.deadline),
          ),
          _TaskDetailRow(
            label: 'Lokasi umum',
            value: task.locationReference == null
                ? 'Belum ditentukan'
                : TaskLocationReferences.label(task.locationReference!),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            key: Key('task-campaign-cancel-${task.taskId}'),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: actionsDisabled ? null : onCancel,
            icon: cancelling
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.cancel_outlined),
            label: Text(cancelling ? 'Memproses…' : 'Batalkan tugas'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            key: Key('task-campaign-close-${task.taskId}'),
            onPressed: actionsDisabled ? null : onClose,
            icon: closing
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.archive_outlined),
            label: Text(closing ? 'Memproses…' : 'Tutup tugas aktif'),
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
  Widget build(BuildContext context) => Card(
    color: Theme.of(context).colorScheme.tertiaryContainer,
    child: const Padding(
      padding: EdgeInsets.all(16),
      child: Text(
        'Pembatalan dan penutupan adalah tindakan operator yang dicatat dalam '
        'riwayat audit. Penutupan tidak menandai tanggapan warga selesai; '
        'verifikasi RT tetap menjadi acuan. Pilihan warga yang masih antre '
        'secara offline dapat berkonflik saat disinkronkan; status server tetap '
        'menjadi acuan.',
      ),
    ),
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
            OutlinedButton(
              key: const Key('active-task-retry'),
              onPressed: onRetry,
              child: const Text('Coba lagi'),
            ),
          ],
        ],
      ),
    ),
  );
}

String _formatDeadline(BuildContext context, DateTime value) {
  final local = value.toLocal();
  final date = MaterialLocalizations.of(context).formatMediumDate(local);
  final time = MaterialLocalizations.of(context)
      .formatTimeOfDay(TimeOfDay.fromDateTime(local));
  return '$date · $time';
}
