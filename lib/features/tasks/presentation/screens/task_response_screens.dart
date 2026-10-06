import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../evidence/application/evidence_image_sanitizer.dart';

import '../../../auth/application/operator_profile.dart';
import '../../../auth/application/resident_session.dart';
import '../../application/task_response.dart';
import '../../application/task_response_boundary.dart';
import '../../application/task_location_reference.dart';
import '../widgets/locked_instructions_card.dart';

typedef PickEvidenceImage = Future<Uint8List?> Function();

/// Pull-based resident task list. No notification delivery is implied.
final class ResidentTaskListScreen extends StatefulWidget {
  const ResidentTaskListScreen({
    required this.session,
    required this.controller,
    this.connectivityChanges,
    super.key,
  });

  final ResidentSession session;
  final TaskResponseController controller;
  final Stream<bool>? connectivityChanges;

  @override
  State<ResidentTaskListScreen> createState() => _ResidentTaskListScreenState();
}

final class _ResidentTaskListScreenState extends State<ResidentTaskListScreen> {
  late Future<ResidentTaskList> _tasks;
  StreamSubscription<bool>? _connectivitySubscription;

  @override
  void initState() {
    super.initState();
    _tasks = widget.controller.listResidentActiveTasks(session: widget.session);
    _connectivitySubscription = widget.connectivityChanges?.listen((online) {
      if (online) unawaited(_reload());
    }, onError: (Object error, StackTrace stackTrace) {});
  }

  @override
  void dispose() {
    _connectivitySubscription?.cancel();
    super.dispose();
  }

  Future<void> _reload() async {
    final request = widget.controller.listResidentActiveTasks(
      session: widget.session,
    );
    setState(() {
      _tasks = request;
    });
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

  Future<void> _resolveSyncIssue(ResidentTaskSyncIssue issue) async {
    final confirmed = await _confirmSyncConflictResolution(context);
    if (confirmed != true || !mounted) return;
    try {
      if (issue.pendingChoice != null) {
        await widget.controller.discardPendingChoiceConflict(
          taskId: issue.taskId,
          session: widget.session,
        );
      } else {
        await widget.controller.discardPendingCompletionConflict(
          taskId: issue.taskId,
          session: widget.session,
        );
      }
      if (!mounted) return;
      await _reload();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Status terbaru dari server dimuat. Tindakan lokal tidak dikirim.',
            ),
          ),
        );
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Status server belum dapat diperiksa. Tindakan lokal tetap disimpan.',
          ),
        ),
      );
    }
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
                if (taskList.isCached) ...[
                  _ResidentTaskOfflineBanner(
                    lastSyncedAt: taskList.lastSyncedAt,
                  ),
                  const SizedBox(height: 12),
                ],
                for (final issue in taskList.syncIssues) ...[
                  _TaskSyncIssueCard(
                    issue: issue,
                    onResolve: _isSyncConflict(issue.kind)
                        ? () => _resolveSyncIssue(issue)
                        : null,
                  ),
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
                  'Periksa kembali aplikasi untuk tugas terbaru.',
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
              if (taskList.isCached) ...[
                _ResidentTaskOfflineBanner(lastSyncedAt: taskList.lastSyncedAt),
                const SizedBox(height: 12),
              ],
              for (final issue in taskList.syncIssues) ...[
                _TaskSyncIssueCard(
                  issue: issue,
                  onResolve: _isSyncConflict(issue.kind)
                      ? () => _resolveSyncIssue(issue)
                      : null,
                ),
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

bool _isSyncConflict(ResidentTaskSyncIssueKind kind) => switch (kind) {
  ResidentTaskSyncIssueKind.choiceConflict ||
  ResidentTaskSyncIssueKind.completionConflict ||
  ResidentTaskSyncIssueKind.taskUnavailable => true,
  _ => false,
};

Future<bool?> _confirmSyncConflictResolution(BuildContext context) =>
    showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Periksa status server?'),
        content: const Text(
          'Aplikasi akan membaca status tugas terbaru melalui server. Jika '
          'pembacaan berhasil, hanya tindakan offline yang bertentangan akan '
          'dihapus dari perangkat. Tidak ada perubahan yang dikirim ke server. '
          'Jika status tidak dapat dibaca, tindakan lokal tetap disimpan.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Batal'),
          ),
          FilledButton(
            key: const Key('resident-resolve-task-sync-conflict-confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Periksa dan hapus lokal'),
          ),
        ],
      ),
    );

final class _TaskSyncIssueCard extends StatelessWidget {
  const _TaskSyncIssueCard({required this.issue, this.onResolve});

  final ResidentTaskSyncIssue issue;
  final VoidCallback? onResolve;

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
            if (isConflict && onResolve != null) ...[
              const SizedBox(height: 8),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  key: const Key('resident-resolve-task-sync-conflict'),
                  onPressed: onResolve,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Periksa status & hapus tindakan lokal'),
                ),
              ),
            ],
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
    'Pilihan offline belum terkonfirmasi. Periksa status terbaru dari server '
        'sebelum memilih lagi.',
  ResidentTaskSyncIssueKind.completionPending =>
    'Penyelesaian menunggu sinkronisasi. Ini belum menjadi penyelesaian resmi; '
        'RT tetap harus memverifikasinya.',
  ResidentTaskSyncIssueKind.completionConflict =>
    'Penyelesaian offline bertentangan dengan status terakhir. Ini bukan '
        'penyelesaian resmi; periksa status terbaru dari server.',
  ResidentTaskSyncIssueKind.taskUnavailable =>
    issue.pendingChoice != null
        ? 'Tugas tidak lagi aktif di server. Pilihan offline belum dikonfirmasi.'
        : 'Tugas tidak lagi aktif di server. Penyelesaian offline belum '
              'dikonfirmasi dan bukan penyelesaian resmi.',
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
    this.pickEvidenceImage,
    super.key,
  });

  final ResidentSession session;
  final TaskResponseController controller;
  final ResidentTaskRecord task;
  final bool isCached;
  final DateTime? lastSyncedAt;
  final PickEvidenceImage? pickEvidenceImage;

  @override
  State<ResidentTaskDetailScreen> createState() =>
      _ResidentTaskDetailScreenState();
}

final class _ResidentTaskDetailScreenState
    extends State<ResidentTaskDetailScreen> {
  late ResidentTaskRecord _task;
  final TextEditingController _noteController = TextEditingController();
  Uint8List? _selectedEvidenceBytes;
  String? _uploadedEvidenceId;
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

  Future<void> _resolveTaskConflict() async {
    final confirmed = await _confirmSyncConflictResolution(context);
    if (confirmed != true || !mounted || _busy) return;
    setState(() => _busy = true);
    try {
      if (_task.hasPendingCompletionSync) {
        await widget.controller.discardPendingCompletionConflict(
          taskId: _task.taskId,
          session: widget.session,
        );
      } else {
        await widget.controller.discardPendingChoiceConflict(
          taskId: _task.taskId,
          session: widget.session,
        );
      }
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      _showMessage(
        'Status server belum dapat diperiksa. Tindakan lokal tetap disimpan.',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submitCompletion() async {
    var evidenceUploadFailed = false;
    await _runAction(() async {
      var evidenceId = _uploadedEvidenceId;
      final selectedBytes = _selectedEvidenceBytes;
      if (selectedBytes != null && evidenceId == null) {
        try {
          evidenceId = await widget.controller.uploadEvidence(
            taskId: _task.taskId,
            sanitizedJpegBytes: selectedBytes,
          );
          _uploadedEvidenceId = evidenceId;
        } catch (_) {
          evidenceUploadFailed = true;
        }
      }
      final result = await widget.controller.submitCompletion(
        taskId: _task.taskId,
        note: _noteController.text,
        evidenceId: evidenceId,
        session: widget.session,
      );
      _applyResponse(result);
      if (result.completion != CompletionState.notSubmitted ||
          result.isPendingCompletionSync) {
        setState(() {
          _selectedEvidenceBytes = null;
          _uploadedEvidenceId = result.evidenceId;
        });
      }
      if (evidenceUploadFailed) {
        _showMessage(
          'Foto tidak terkirim. Penyelesaian tetap dikirim tanpa foto.',
        );
      }
    });
  }

  Future<void> _chooseEvidence() async {
    if (_busy) return;
    if (_uploadedEvidenceId != null) {
      _showMessage('Hapus foto yang sudah diunggah sebelum memilih foto lain.');
      return;
    }
    try {
      final sourceBytes =
          await (widget.pickEvidenceImage ?? _pickEvidenceImage)();
      if (sourceBytes == null || !mounted) return;
      final sanitized = EvidenceImageSanitizer.sanitize(sourceBytes);
      setState(() => _selectedEvidenceBytes = sanitized.bytes);
    } on EvidenceImageSanitizationException {
      _showMessage('Pilih foto JPEG yang valid dan berukuran lebih kecil.');
    } catch (_) {
      _showMessage(
        'Foto belum dapat dipilih. Tugas tetap bisa dikirim tanpa foto.',
      );
    }
  }

  Future<void> _removeSelectedEvidence() async {
    if (_busy) return;
    final evidenceId = _uploadedEvidenceId;
    if (evidenceId == null) {
      setState(() => _selectedEvidenceBytes = null);
      return;
    }
    await _runAction(() async {
      await widget.controller.deleteEvidence(evidenceId: evidenceId);
      setState(() {
        _selectedEvidenceBytes = null;
        _uploadedEvidenceId = null;
      });
      _showMessage('Foto bukti dihapus.');
    });
  }

  Future<void> _deleteAttachedEvidence() async {
    final evidenceId = _task.evidenceId;
    if (evidenceId == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Hapus foto bukti?'),
        content: const Text(
          'Foto akan dihapus dari penyimpanan bukti. Status tugas tetap sama.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Kembali'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Hapus foto'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _runAction(() async {
      await widget.controller.deleteEvidence(evidenceId: evidenceId);
      setState(() => _task = _task.withoutEvidence());
      _showMessage('Foto bukti dihapus. Status tugas tidak berubah.');
    });
  }

  Future<Uint8List?> _pickEvidenceImage() async {
    final file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: EvidenceImageSanitizer.maxDimension.toDouble(),
      maxHeight: EvidenceImageSanitizer.maxDimension.toDouble(),
      imageQuality: 85,
      requestFullMetadata: false,
    );
    return file?.readAsBytes();
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
        if (widget.isCached) ...[
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

  Widget _evidencePicker() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Text(
        'Foto bukti JPEG bersifat opsional dan dijadwalkan untuk dihapus setelah '
        '30 hari. Lokasi metadata dihapus. Foto hanya '
        'diunggah saat Anda mengirim penyelesaian. Jangan sertakan wajah, '
        'alamat, atau data pribadi yang tidak diperlukan. Jika unggahan gagal, '
        'Anda tetap dapat mengirim tanpa foto.',
      ),
      const SizedBox(height: 8),
      OutlinedButton.icon(
        key: const Key('resident-choose-evidence'),
        onPressed: _busy ? null : _chooseEvidence,
        icon: const Icon(Icons.add_a_photo_outlined),
        label: Text(
          _selectedEvidenceBytes == null
              ? 'Pilih Foto (Opsional)'
              : 'Foto Dipilih',
        ),
      ),
      if (_selectedEvidenceBytes case final bytes?) ...[
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.memory(
            bytes,
            key: const Key('resident-evidence-preview'),
            height: 160,
            fit: BoxFit.contain,
          ),
        ),
        Text(
          _uploadedEvidenceId == null
              ? 'Foto telah diproses tanpa metadata lokasi.'
              : 'Foto terunggah secara privat; belum dilampirkan sampai penyelesaian terkirim.',
        ),
        TextButton.icon(
          key: const Key('resident-remove-evidence'),
          onPressed: _busy ? null : _removeSelectedEvidence,
          icon: const Icon(Icons.delete_outline),
          label: const Text('Hapus foto'),
        ),
      ],
    ],
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
        onResolve: _busy ? null : _resolveTaskConflict,
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
              if (_task.evidenceId != null) ...[
                const SizedBox(height: 8),
                const Text('Foto bukti tersedia untuk ditinjau RT.'),
                TextButton.icon(
                  key: const Key('resident-delete-attached-evidence'),
                  onPressed: _busy ? null : _deleteAttachedEvidence,
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Hapus foto bukti'),
                ),
              ],
            ],
          ),
        ),
      );
    }
    if (_task.completion == CompletionState.verifiedComplete) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Penyelesaian telah diverifikasi oleh RT.'),
              if (_task.evidenceId != null) ...[
                const SizedBox(height: 8),
                const Text('Foto bukti tersimpan sementara.'),
                TextButton.icon(
                  key: const Key('resident-delete-attached-evidence'),
                  onPressed: _busy ? null : _deleteAttachedEvidence,
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Hapus foto bukti'),
                ),
              ],
            ],
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Anda memilih ikut. Penyelesaian perlu diverifikasi RT.'),
        const SizedBox(height: 12),
        _evidencePicker(),
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
    this.initialTaskId,
    super.key,
  });

  final OperatorProfile profile;
  final TaskResponseController controller;
  final String? initialTaskId;

  @override
  State<TaskVerificationQueueScreen> createState() =>
      _TaskVerificationQueueScreenState();
}

final class _TaskVerificationQueueScreenState
    extends State<TaskVerificationQueueScreen> {
  late Future<TaskVerificationQueue> _pending;
  final Set<String> _busyResponses = {};
  final Set<String> _busyEvidence = {};

  @override
  void initState() {
    super.initState();
    _pending = widget.controller.listPendingVerifications();
  }

  void _reload() {
    setState(() => _pending = widget.controller.listPendingVerifications());
  }

  Future<void> _reviewEvidence(TaskVerificationRecord record) async {
    final evidenceId = record.evidenceId;
    if (evidenceId == null || _busyEvidence.contains(evidenceId)) return;
    setState(() => _busyEvidence.add(evidenceId));
    try {
      final bytes = await widget.controller.getEvidenceForVerification(
        evidenceId: evidenceId,
      );
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Foto bukti pribadi'),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480, maxHeight: 480),
            child: Image.memory(
              bytes,
              key: Key('task-evidence-review-${record.responseId}'),
              fit: BoxFit.contain,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Tutup'),
            ),
          ],
        ),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Foto bukti belum dapat dibuka.')),
        );
      }
    } finally {
      if (mounted) setState(() => _busyEvidence.remove(evidenceId));
    }
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
                  key: record.taskId == widget.initialTaskId
                      ? Key('verification-notification-${record.taskId}')
                      : null,
                  color: record.taskId == widget.initialTaskId
                      ? Theme.of(context).colorScheme.tertiaryContainer
                      : null,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (record.taskId == widget.initialTaskId) ...[
                          const Text('Dibuka dari notifikasi'),
                          const SizedBox(height: 6),
                        ],
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
                        if (record.evidenceId case final evidenceId?) ...[
                          const SizedBox(height: 8),
                          OutlinedButton.icon(
                            key: Key('review-evidence-${record.responseId}'),
                            onPressed: _busyEvidence.contains(evidenceId)
                                ? null
                                : () => _reviewEvidence(record),
                            icon: const Icon(Icons.image_outlined),
                            label: Text(
                              _busyEvidence.contains(evidenceId)
                                  ? 'Memuat foto…'
                                  : 'Lihat foto bukti',
                            ),
                          ),
                        ],
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
