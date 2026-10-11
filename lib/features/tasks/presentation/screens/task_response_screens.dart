import 'package:flutter/material.dart';

import '../../../auth/application/operator_profile.dart';
import '../../../auth/application/resident_session.dart';
import '../../application/task_response.dart';
import '../../application/task_response_boundary.dart';
import '../../application/task_location_reference.dart';
import '../widgets/locked_instructions_card.dart';

/// Pull-based resident task list. No notification delivery is implied.
final class ResidentTaskListScreen extends StatefulWidget {
  const ResidentTaskListScreen({
    required this.session,
    required this.controller,
    super.key,
  });

  final ResidentSession session;
  final TaskResponseController controller;

  @override
  State<ResidentTaskListScreen> createState() => _ResidentTaskListScreenState();
}

final class _ResidentTaskListScreenState extends State<ResidentTaskListScreen> {
  late Future<ResidentTaskList> _tasks;

  @override
  void initState() {
    super.initState();
    _tasks = widget.controller.listResidentActiveTasks(session: widget.session);
  }

  Future<void> _reload() async {
    final request = widget.controller.listResidentActiveTasks(
      session: widget.session,
    );
    setState(() => _tasks = request);
    try {
      await request;
    } catch (_) {
      // The FutureBuilder displays a safe retry state.
    }
  }

  Future<void> _openTask(
    ResidentTaskRecord task,
    ResidentTaskList taskList,
  ) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => ResidentTaskDetailScreen(
          session: widget.session,
          controller: widget.controller,
          task: task,
          isCached: taskList.isCached,
          lastSyncedAt: taskList.lastSyncedAt,
        ),
      ),
    );
    if (mounted) await _reload();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Tugas Kesiapsiagaan')),
    body: FutureBuilder<ResidentTaskList>(
      future: _tasks,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return _LoadError(
            message: 'Tugas belum tersedia. Periksa koneksi atau sinkronkan saat online.',
            onRetry: () => _reload(),
          );
        }
        final taskList = snapshot.data!;
        final tasks = taskList.items;
        if (tasks.isEmpty) {
          return RefreshIndicator(
            onRefresh: _reload,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(24),
              children: [
                if (taskList.isCached || widget.session.isOfflineSnapshot) ...[
                  _ResidentTaskOfflineBanner(
                    lastSyncedAt: taskList.lastSyncedAt,
                  ),
                  const SizedBox(height: 12),
                ],
                for (final issue in taskList.syncIssues) ...[
                  _TaskSyncIssueCard(issue: issue),
                  const SizedBox(height: 8),
                ],
                const SizedBox(height: 64),
                const Icon(Icons.checklist_outlined, size: 52),
                const SizedBox(height: 16),
                const Text(
                  'Belum ada tugas aktif untuk RT ini.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Tugas tampil setelah diaktifkan oleh operator RT. '
                  'Notifikasi belum tersedia.',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          );
        }
        return RefreshIndicator(
          onRefresh: _reload,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (taskList.isCached || widget.session.isOfflineSnapshot) ...[
                _ResidentTaskOfflineBanner(lastSyncedAt: taskList.lastSyncedAt),
                const SizedBox(height: 12),
              ],
              for (final issue in taskList.syncIssues) ...[
                _TaskSyncIssueCard(issue: issue),
                const SizedBox(height: 8),
              ],
              Text(
                'Warga • ${widget.session.rtLabel}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              const Text(
                'Partisipasi bersifat sukarela. Tidak ada peringkat atau penalti.',
              ),
              if (taskList.isPartial) ...[
                const SizedBox(height: 8),
                const Text('Daftar tugas dibatasi. Tarik untuk memuat ulang.'),
              ],
              const SizedBox(height: 12),
              for (final task in tasks)
                Card(
                  child: ListTile(
                    key: Key('resident-task-${task.taskId}'),
                    title: Text(task.templateSnapshot.title),
                    subtitle: Text(
                      _taskListSubtitle(task),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _openTask(task, taskList),
                  ),
                ),
            ],
          ),
        );
      },
    ),
  );
}

String _taskListSubtitle(ResidentTaskRecord task) {
  final lines = <String>[
    '${_participationLabel(task.participation)} • Batas ${_formatDate(task.deadline)}',
  ];
  if (task.pendingChoice != null) {
    lines.add(
      'Pilihan ${_choiceLabel(task.pendingChoice!)} menunggu sinkronisasi.',
    );
  }
  if (task.hasPendingCompletionSync) {
    lines.add('Penyelesaian menunggu sinkronisasi.');
  }
  if (task.hasSyncConflict) {
    lines.add(
      'Perlu pemeriksaan status; pilihan belum dipastikan oleh server.',
    );
  }
  return lines.join('\n');
}

final class _ResidentTaskOfflineBanner extends StatelessWidget {
  const _ResidentTaskOfflineBanner({this.lastSyncedAt});

  final DateTime? lastSyncedAt;

  @override
  Widget build(BuildContext context) => Card(
    key: const Key('resident-task-offline-banner'),
    color: Theme.of(context).colorScheme.tertiaryContainer,
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Mode offline • data tugas tersimpan, belum diperbarui.',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          if (lastSyncedAt != null) ...[
            const SizedBox(height: 4),
            Text('Terakhir tersinkron: ${_formatDate(lastSyncedAt!)}'),
          ],
          const SizedBox(height: 4),
          const Text(
            'Status server dapat berubah. Pilihan offline belum dihitung '
            'sampai diterima server RT.',
          ),
        ],
      ),
    ),
  );
}

final class _TaskSyncIssueCard extends StatelessWidget {
  const _TaskSyncIssueCard({required this.issue});

  final ResidentTaskSyncIssue issue;

  @override
  Widget build(BuildContext context) {
    final isConflict = switch (issue.kind) {
      ResidentTaskSyncIssueKind.choiceConflict ||
      ResidentTaskSyncIssueKind.completionConflict ||
      ResidentTaskSyncIssueKind.taskUnavailable => true,
      _ => false,
    };
    return Card(
      color: isConflict
          ? Theme.of(context).colorScheme.errorContainer
          : Theme.of(context).colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (issue.taskTitle case final title?) ...[
              Text(title, style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 4),
            ],
            Text(_syncIssueMessage(issue)),
          ],
        ),
      ),
    );
  }
}

String _syncIssueMessage(ResidentTaskSyncIssue issue) => switch (issue.kind) {
  ResidentTaskSyncIssueKind.choicePending =>
    'Pilihan ${issue.pendingChoice == null ? '' : _choiceLabel(issue.pendingChoice!)} '
        'belum tersinkron. Server RT belum mengonfirmasinya.',
  ResidentTaskSyncIssueKind.choiceConflict =>
    'Pilihan offline belum disimpan. Status server: '
        '${issue.authoritativeParticipation == null ? 'perlu diperiksa' : _participationLabel(issue.authoritativeParticipation!)}.',
  ResidentTaskSyncIssueKind.completionPending =>
    'Penyelesaian menunggu sinkronisasi. Ini belum menjadi penyelesaian resmi; '
        'RT tetap harus memverifikasinya.',
  ResidentTaskSyncIssueKind.completionConflict => 'Penyelesaian offline belum disimpan karena tugas tidak lagi aktif di server.',
  ResidentTaskSyncIssueKind.taskUnavailable =>
    'Tugas tidak lagi aktif di server. Pilihan offline belum dikonfirmasi.',
};

String _choiceLabel(ParticipationChoice choice) => switch (choice) {
  ParticipationChoice.join => 'ikut',
  ParticipationChoice.decline => 'tidak ikut',
};

/// Safety instructions appear before any resident action.
final class ResidentTaskDetailScreen extends StatefulWidget {
  const ResidentTaskDetailScreen({
    required this.session,
    required this.controller,
    required this.task,
    this.isCached = false,
    this.lastSyncedAt,
    super.key,
  });

  final ResidentSession session;
  final TaskResponseController controller;
  final ResidentTaskRecord task;
  final bool isCached;
  final DateTime? lastSyncedAt;

  @override
  State<ResidentTaskDetailScreen> createState() =>
      _ResidentTaskDetailScreenState();
}

final class _ResidentTaskDetailScreenState
    extends State<ResidentTaskDetailScreen> {
  late ResidentTaskRecord _task;
  final TextEditingController _noteController = TextEditingController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _task = widget.task;
    _noteController.text = _task.completionNote ?? '';
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _choose(ParticipationChoice choice) async {
    await _runAction(() async {
      final result = await widget.controller.recordParticipation(
        taskId: _task.taskId,
        choice: choice,
        session: widget.session,
      );
      _applyResponse(result);
    });
  }

  Future<void> _submitCompletion() async {
    await _runAction(() async {
      final result = await widget.controller.submitCompletion(
        taskId: _task.taskId,
        note: _noteController.text,
        session: widget.session,
      );
      _applyResponse(result);
    });
  }

  Future<void> _runAction(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } on OfflineCompletionNoteException {
      if (mounted) {
        _showMessage(
          'Catatan tidak disimpan. Hubungkan internet untuk mengirim catatan; '
          'tidak ada penyelesaian yang tercatat.',
        );
      }
    } on TaskResponseRejectedException {
      if (mounted) {
        _showMessage(
          'Server RT menolak perubahan ini. Status tugas belum diubah.',
        );
      }
    } catch (_) {
      if (mounted) {
        _showMessage(
          'Permintaan belum tersimpan. Periksa koneksi dan coba lagi.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _applyResponse(TaskResponseRecord response) {
    if (!mounted) return;
    setState(() => _task = _task.withResponse(response));
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Detail Tugas')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          'Warga • ${widget.session.rtLabel}',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        if (widget.isCached || widget.session.isOfflineSnapshot) ...[
          const SizedBox(height: 12),
          _ResidentTaskOfflineBanner(lastSyncedAt: widget.lastSyncedAt),
        ],
        const SizedBox(height: 8),
        Text(
          _task.templateSnapshot.title,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        Text('Batas waktu: ${_formatDate(_task.deadline)}'),
        if (_task.locationReference case final location?) ...[
          const SizedBox(height: 8),
          Text('Jenis lokasi umum: ${TaskLocationReferences.label(location)}'),
        ],
        const SizedBox(height: 16),
        LockedTaskInstructionsCard(snapshot: _task.templateSnapshot),
        const SizedBox(height: 16),
        _responseActions(),
      ],
    ),
  );

  Widget _responseActions() {
    if (_task.hasSyncConflict) {
      final kind = _task.hasPendingCompletionSync
          ? ResidentTaskSyncIssueKind.completionConflict
          : _task.pendingChoice != null
          ? ResidentTaskSyncIssueKind.choiceConflict
          : ResidentTaskSyncIssueKind.taskUnavailable;
      return _TaskSyncIssueCard(
        issue: ResidentTaskSyncIssue(
          taskId: _task.taskId,
          kind: kind,
          pendingChoice: _task.pendingChoice,
        ),
      );
    }
    if (_task.pendingChoice != null) {
      return _TaskSyncIssueCard(
        issue: ResidentTaskSyncIssue(
          taskId: _task.taskId,
          kind: ResidentTaskSyncIssueKind.choicePending,
          pendingChoice: _task.pendingChoice,
        ),
      );
    }
    if (_task.hasPendingCompletionSync) {
      return _TaskSyncIssueCard(
        issue: ResidentTaskSyncIssue(
          taskId: _task.taskId,
          kind: ResidentTaskSyncIssueKind.completionPending,
        ),
      );
    }
    if (_task.participation == ParticipationState.unresponded) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Ikut atau tidak ikut adalah pilihan Anda. Menolak tidak mengurangi '
            'hak atau layanan.',
          ),
          const SizedBox(height: 12),
          FilledButton(
            key: const Key('resident-join-task'),
            onPressed: _busy ? null : () => _choose(ParticipationChoice.join),
            child: const Text('Saya Ikut'),
          ),
          OutlinedButton(
            key: const Key('resident-decline-task'),
            onPressed: _busy
                ? null
                : () => _choose(ParticipationChoice.decline),
            child: const Text('Tidak Ikut'),
          ),
          if (_busy) const Center(child: CircularProgressIndicator()),
        ],
      );
    }
    if (_task.participation == ParticipationState.declined) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text('Anda memilih tidak ikut. Tidak ada penalti.'),
        ),
      );
    }
    if (_task.completion == CompletionState.pendingRtVerification) {
      return Card(
        color: Theme.of(context).colorScheme.secondaryContainer,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Menunggu Verifikasi RT',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              if (_task.completionNote case final note?) ...[
                const SizedBox(height: 8),
                Text('Catatan: $note'),
              ],
            ],
          ),
        ),
      );
    }
    if (_task.completion == CompletionState.verifiedComplete) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text('Penyelesaian telah diverifikasi oleh RT.'),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Anda memilih ikut. Penyelesaian perlu diverifikasi RT.'),
        const SizedBox(height: 12),
        TextField(
          key: const Key('resident-completion-note'),
          controller: _noteController,
          maxLength: TaskResponse.maxCompletionNoteLength,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'Catatan singkat (opsional)',
            hintText: 'Jangan masukkan alamat, NIK, nomor telepon, atau koordinat lokasi.',
            border: OutlineInputBorder(),
          ),
        ),
        FilledButton(
          key: const Key('resident-submit-completion'),
          onPressed: _busy ? null : _submitCompletion,
          child: const Text('Kirim untuk Verifikasi RT'),
        ),
        if (_busy) const Center(child: CircularProgressIndicator()),
      ],
    );
  }
}

/// RT-only queue of resident-submitted completion requests.
final class TaskVerificationQueueScreen extends StatefulWidget {
  const TaskVerificationQueueScreen({
    required this.profile,
    required this.controller,
    super.key,
  });

  final OperatorProfile profile;
  final TaskResponseController controller;

  @override
  State<TaskVerificationQueueScreen> createState() =>
      _TaskVerificationQueueScreenState();
}

final class _TaskVerificationQueueScreenState
    extends State<TaskVerificationQueueScreen> {
  late Future<TaskVerificationQueue> _pending;
  final Set<String> _busyResponses = {};

  @override
  void initState() {
    super.initState();
    _pending = widget.controller.listPendingVerifications();
  }

  void _reload() {
    setState(() => _pending = widget.controller.listPendingVerifications());
  }

  Future<void> _verify(TaskVerificationRecord record) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Verifikasi penyelesaian?'),
        content: Text(
          'Pastikan tugas “${record.taskTitle}” oleh ${record.nickname} '
          'sudah ditinjau. Verifikasi akan dicatat untuk RT ini.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Kembali'),
          ),
          FilledButton(
            key: const Key('confirm-task-verification'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Verifikasi'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busyResponses.add(record.responseId));
    try {
      await widget.controller.verifyCompletion(responseId: record.responseId);
      _reload();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Penyelesaian diverifikasi RT.')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Verifikasi gagal. Coba lagi.')),
        );
      }
    } finally {
      if (mounted) setState(() => _busyResponses.remove(record.responseId));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Verifikasi Tugas')),
    body: FutureBuilder<TaskVerificationQueue>(
      future: _pending,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return _LoadError(
            message: 'Daftar verifikasi tidak tersedia. Coba lagi.',
            onRetry: _reload,
          );
        }
        final queue = snapshot.data!;
        final pending = queue.items;
        if (pending.isEmpty) {
          return RefreshIndicator(
            onRefresh: () async => _reload(),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(24),
              children: const [
                SizedBox(height: 120),
                Icon(Icons.fact_check_outlined, size: 48),
                SizedBox(height: 16),
                Text(
                  'Belum ada penyelesaian yang menunggu verifikasi RT.',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          );
        }
        return RefreshIndicator(
          onRefresh: () async => _reload(),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                '${widget.profile.role.label} • RT ${widget.profile.communityId}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              if (queue.isPartial) ...[
                const SizedBox(height: 8),
                const Text(
                  'Daftar verifikasi dibatasi. Muat ulang untuk memeriksa lagi.',
                ),
              ],
              const SizedBox(height: 12),
              for (final record in pending)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          record.taskTitle,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 4),
                        Text('Dikirim oleh ${record.nickname}'),
                        Text('Waktu kirim: ${_formatDate(record.submittedAt)}'),
                        if (record.completionNote case final note?) ...[
                          const SizedBox(height: 8),
                          Text('Catatan: $note'),
                        ],
                        const SizedBox(height: 8),
                        const Text('Status: Menunggu Verifikasi RT'),
                        Wrap(
                          spacing: 8,
                          children: [
                            FilledButton.tonal(
                              key: Key('verify-${record.responseId}'),
                              onPressed:
                                  _busyResponses.contains(record.responseId)
                                  ? null
                                  : () => _verify(record),
                              child: const Text('Tinjau dan Verifikasi'),
                            ),
                            TextButton(
                              key: Key('recap-${record.taskId}'),
                              onPressed: () => Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => TaskResponseRecapScreen(
                                    profile: widget.profile,
                                    taskId: record.taskId,
                                    controller: widget.controller,
                                  ),
                                ),
                              ),
                              child: const Text('Lihat Rekap'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    ),
  );
}

/// Aggregate-only RT recap. It deliberately has no non-response denominator.
final class TaskResponseRecapScreen extends StatelessWidget {
  const TaskResponseRecapScreen({
    required this.profile,
    required this.taskId,
    required this.controller,
    super.key,
  });

  final OperatorProfile profile;
  final String taskId;
  final TaskResponseController controller;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Rekap Tugas')),
    body: FutureBuilder<TaskResponseRecap>(
      future: controller.getResponseRecap(taskId: taskId),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError || snapshot.data == null) {
          return const Center(child: Text('Rekap belum tersedia.'));
        }
        final recap = snapshot.data!;
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              '${profile.role.label} • RT ${recap.rtId}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            Text(
              recap.taskTitle,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            _CountRow(
              label: 'Tanggapan tercatat',
              count: recap.recordedResponseCount,
            ),
            _CountRow(label: 'Memilih ikut', count: recap.joinedCount),
            _CountRow(label: 'Memilih tidak ikut', count: recap.declinedCount),
            _CountRow(
              label: 'Menunggu verifikasi',
              count: recap.pendingVerificationCount,
            ),
            _CountRow(
              label: 'Terverifikasi selesai',
              count: recap.verifiedCompleteCount,
            ),
            if (recap.isPartial) ...[
              const SizedBox(height: 12),
              const Text(
                'Rekap dibatasi. Angka ini mungkin belum mencakup semua tanggapan.',
              ),
            ],
            const SizedBox(height: 16),
            const Text(
              'Rekap menghitung tanggapan yang tersimpan saja. Warga yang belum '
              'menjawab tidak dihitung. Ini bukan peringkat.',
            ),
          ],
        );
      },
    ),
  );
}

final class _CountRow extends StatelessWidget {
  const _CountRow({required this.label, required this.count});

  final String label;
  final int count;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [Text(label), Text('$count')],
    ),
  );
}

final class _LoadError extends StatelessWidget {
  const _LoadError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: onRetry, child: const Text('Coba Lagi')),
        ],
      ),
    ),
  );
}

String _participationLabel(ParticipationState state) => switch (state) {
  ParticipationState.unresponded => 'Belum memilih',
  ParticipationState.joined => 'Memilih ikut',
  ParticipationState.declined => 'Memilih tidak ikut',
};

String _formatDate(DateTime value) {
  final local = value.toLocal();
  final day = local.day.toString().padLeft(2, '0');
  final month = local.month.toString().padLeft(2, '0');
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '$day/$month/${local.year} $hour:$minute';
}
