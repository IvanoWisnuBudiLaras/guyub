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
    super.key,
  });

  final OperatorProfile profile;
  final TaskCampaignController controller;

  @override
  State<TaskActiveCampaignsScreen> createState() =>
      _TaskActiveCampaignsScreenState();
}

final class _TaskActiveCampaignsScreenState
    extends State<TaskActiveCampaignsScreen> {
  late Future<List<ActiveTaskCampaignRecord>> _campaignsFuture;
  final Set<String> _cancellingTaskIds = {};
  String? _actionError;

  bool get _isCancelling => _cancellingTaskIds.isNotEmpty;

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
          '“${task.templateSnapshot.title}” akan dibatalkan. Pembatalan '
          'dicatat dalam riwayat audit. Tidak ada notifikasi yang dikirim. '
          'Pilihan warga yang masih antre secara offline dapat mengalami '
          'konflik saat tersambung kembali dan perlu diselaraskan dengan '
          'status server.',
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

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Tugas Aktif RT'),
      actions: [
        IconButton(
          key: const Key('active-task-reload'),
          tooltip: 'Muat ulang tugas aktif',
          onPressed: _isCancelling ? null : () => _reload(),
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
            onRetry: _isCancelling ? null : () => _reload(),
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
                    cancelling: _cancellingTaskIds.contains(task.taskId),
                    actionsDisabled: _isCancelling,
                    onCancel: () => _cancel(task),
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
    required this.cancelling,
    required this.actionsDisabled,
    required this.onCancel,
  });

  final ActiveTaskCampaignRecord task;
  final bool cancelling;
  final bool actionsDisabled;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) => Card(
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
        'Pembatalan dicatat dalam riwayat audit dan tidak mengirim '
        'notifikasi. Pilihan warga yang masih antre secara offline dapat '
        'berkonflik saat disinkronkan; status server tetap menjadi acuan.',
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
