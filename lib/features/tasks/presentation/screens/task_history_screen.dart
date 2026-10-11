import 'package:flutter/material.dart';

import '../../../auth/application/operator_profile.dart';
import '../../application/task_campaign_boundary.dart';
import '../../application/task_location_reference.dart';
import '../../application/task_response_boundary.dart';
import 'task_response_screens.dart';

/// Read-only, server-paginated history for the authenticated operator's RT.
/// No resident response records are requested or stored by this screen.
final class TaskHistoryScreen extends StatefulWidget {
  const TaskHistoryScreen({
    required this.profile,
    required this.controller,
    this.taskResponseController,
    super.key,
  });

  final OperatorProfile profile;
  final TaskCampaignController controller;
  final TaskResponseController? taskResponseController;

  @override
  State<TaskHistoryScreen> createState() => _TaskHistoryScreenState();
}

final class _TaskHistoryScreenState extends State<TaskHistoryScreen> {
  List<RtTaskHistoryRecord> _tasks = const [];
  String? _nextCursor;
  bool _loadingFirstPage = true;
  bool _loadingMore = false;
  bool _firstPageFailed = false;
  String? _loadMoreFailure;

  @override
  void initState() {
    super.initState();
    _loadFirstPage();
  }

  Future<void> _loadFirstPage() async {
    try {
      final page = await widget.controller.listRtTaskHistory();
      if (!mounted) return;
      setState(() {
        _tasks = page.tasks;
        _nextCursor = page.nextCursor;
        _loadingFirstPage = false;
        _firstPageFailed = false;
        _loadMoreFailure = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _tasks = const [];
        _nextCursor = null;
        _loadingFirstPage = false;
        _firstPageFailed = true;
        _loadMoreFailure = null;
      });
    }
  }

  Future<void> _refresh() async {
    setState(() {
      _loadingFirstPage = true;
      _firstPageFailed = false;
      _tasks = const [];
      _nextCursor = null;
      _loadMoreFailure = null;
    });
    await _loadFirstPage();
  }

  Future<void> _loadMore() async {
    final cursor = _nextCursor;
    if (cursor == null || _loadingMore || _loadingFirstPage) return;
    setState(() {
      _loadingMore = true;
      _loadMoreFailure = null;
    });
    try {
      final page = await widget.controller.listRtTaskHistory(cursor: cursor);
      if (!mounted) return;
      final existingIds = _tasks.map((task) => task.taskId).toSet();
      setState(() {
        _tasks = [
          ..._tasks,
          ...page.tasks.where((task) => existingIds.add(task.taskId)),
        ];
        _nextCursor = page.nextCursor;
        _loadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingMore = false;
        _loadMoreFailure = 'Halaman berikutnya belum berhasil dimuat. Riwayat yang tampil belum lengkap.';
      });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Riwayat Tugas RT')),
    body: _loadingFirstPage
        ? const Center(child: CircularProgressIndicator())
        : _firstPageFailed
        ? Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Riwayat tugas belum dapat dimuat dari server. '
                    'Periksa koneksi dan coba lagi.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    key: const Key('task-history-retry'),
                    onPressed: _refresh,
                    child: const Text('Coba Lagi'),
                  ),
                ],
              ),
            ),
          )
        : RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  '${widget.profile.role.label} • RT ${widget.profile.communityId}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Riwayat dibaca dari server RT. Data tanggapan warga '
                  'tidak ditampilkan di daftar ini.',
                ),
                const SizedBox(height: 12),
                if (_tasks.isEmpty) ...[
                  const SizedBox(height: 48),
                  const Icon(Icons.history, size: 48),
                  const SizedBox(height: 12),
                  const Text(
                    'Belum ada riwayat tugas untuk RT ini.',
                    key: Key('task-history-empty'),
                    textAlign: TextAlign.center,
                  ),
                ],
                for (final task in _tasks)
                  _HistoryTaskCard(
                    profile: widget.profile,
                    controller: widget.controller,
                    task: task,
                    taskResponseController: widget.taskResponseController,
                  ),
                if (_loadMoreFailure case final failure?) ...[
                  const SizedBox(height: 8),
                  Text(failure, textAlign: TextAlign.center),
                  const SizedBox(height: 8),
                  OutlinedButton(
                    key: const Key('task-history-load-more-retry'),
                    onPressed: _loadMore,
                    child: const Text('Coba Muat Lagi'),
                  ),
                ] else if (_loadingMore) ...[
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                ] else if (_nextCursor != null) ...[
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    key: const Key('task-history-load-more'),
                    onPressed: _loadMore,
                    icon: const Icon(Icons.expand_more),
                    label: const Text('Muat Riwayat Berikutnya'),
                  ),
                ],
              ],
            ),
          ),
  );
}

final class _HistoryTaskCard extends StatefulWidget {
  const _HistoryTaskCard({
    required this.profile,
    required this.controller,
    required this.task,
    required this.taskResponseController,
  });

  final OperatorProfile profile;
  final TaskCampaignController controller;
  final RtTaskHistoryRecord task;
  final TaskResponseController? taskResponseController;

  @override
  State<_HistoryTaskCard> createState() => _HistoryTaskCardState();
}

final class _HistoryTaskCardState extends State<_HistoryTaskCard> {
  bool _showEvents = false;
  Future<List<RtTaskLifecycleEvent>>? _eventsFuture;

  void _toggleEvents() {
    setState(() {
      _showEvents = !_showEvents;
      if (_showEvents) _eventsFuture ??= _loadEvents();
    });
  }

  Future<List<RtTaskLifecycleEvent>> _loadEvents() =>
      widget.controller.listTaskLifecycleEvents(taskId: widget.task.taskId);

  void _retryEvents() => setState(() => _eventsFuture = _loadEvents());

  String get _statusLabel => switch (widget.task.status) {
    'CANCELLED' => 'Dibatalkan',
    'CLOSED' => 'Ditutup',
    _ => 'Aktif',
  };

  @override
  Widget build(BuildContext context) {
    final task = widget.task;
    return Card(
      key: Key('history-task-${task.taskId}'),
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              task.templateSnapshot.title,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text('Status: $_statusLabel'),
            Text('Versi template: ${task.templateSnapshot.version}'),
            Text('Batas waktu: ${_formatDate(task.deadline)}'),
            Text('Diaktifkan: ${_formatDate(task.activatedAt)}'),
            if (task.cancelledAt case final cancelledAt?)
              Text('Dibatalkan: ${_formatDate(cancelledAt)}'),
            if (task.closedAt case final closedAt?)
              Text('Ditutup: ${_formatDate(closedAt)}'),
            if (task.locationReference case final location?)
              Text('Lokasi umum: ${TaskLocationReferences.label(location)}'),
            const SizedBox(height: 12),
            Text(
              task.templateSnapshot.coreInstruction,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Keselamatan: ${task.templateSnapshot.safetyInstruction}',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              key: Key('history-events-toggle-${task.taskId}'),
              onPressed: _toggleEvents,
              icon: Icon(_showEvents ? Icons.expand_less : Icons.history),
              label: Text(
                _showEvents
                    ? 'Sembunyikan riwayat perubahan'
                    : 'Lihat riwayat perubahan',
              ),
            ),
            if (_showEvents) _lifecycleEvents(context),
            const SizedBox(height: 8),
            if (widget.taskResponseController case final controller?)
              OutlinedButton.icon(
                key: Key('history-recap-${task.taskId}'),
                onPressed: () => Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    builder: (_) => TaskResponseRecapScreen(
                      profile: widget.profile,
                      taskId: task.taskId,
                      controller: controller,
                    ),
                  ),
                ),
                icon: const Icon(Icons.analytics_outlined),
                label: const Text('Lihat rekap tanggapan agregat'),
              )
            else
              OutlinedButton.icon(
                onPressed: null,
                icon: Icon(Icons.analytics_outlined),
                label: Text('Rekap tanggapan tidak tersedia'),
              ),
          ],
        ),
      ),
    );
  }

  Widget _lifecycleEvents(BuildContext context) => Semantics(
    container: true,
    explicitChildNodes: true,
    label: 'Riwayat perubahan tugas',
    child: FutureBuilder<List<RtTaskLifecycleEvent>>(
      future: _eventsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: LinearProgressIndicator(),
          );
        }
        if (snapshot.hasError || snapshot.data == null) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Riwayat perubahan belum dapat dimuat.'),
              OutlinedButton(
                key: Key('history-events-retry-${widget.task.taskId}'),
                onPressed: _retryEvents,
                child: const Text('Coba muat perubahan lagi'),
              ),
            ],
          );
        }
        final events = snapshot.data!;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Perubahan yang dicatat server:'),
            for (final event in events)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  '${_eventLabel(event.eventType)}: ${_formatDate(event.occurredAt)}',
                ),
              ),
          ],
        );
      },
    ),
  );

  String _eventLabel(String eventType) => switch (eventType) {
    'ACTIVATED' => 'Diaktifkan',
    'CLOSED' => 'Ditutup',
    'CANCELLED' => 'Dibatalkan',
    _ => 'Perubahan',
  };
}

String _formatDate(DateTime value) {
  final local = value.toLocal();
  final day = local.day.toString().padLeft(2, '0');
  final month = local.month.toString().padLeft(2, '0');
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '$day/$month/${local.year} $hour:$minute';
}
