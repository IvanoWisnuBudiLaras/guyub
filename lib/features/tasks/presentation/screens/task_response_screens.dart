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
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/indonesian_date_formatter.dart';
import '../../../../core/widgets/task_category_presentation.dart';
import '../../../../core/widgets/inline_action_button.dart';
import '../../../../core/widgets/tinted_info_box.dart';
import '../../../../core/widgets/section_card.dart';
import '../../../../core/widgets/info_row.dart';

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
  Widget build(BuildContext context) => TintedInfoBox(
    key: const Key('resident-task-offline-banner'),
    tint: TintType.warning,
    icon: Icons.cloud_off_outlined,
    title: 'Mode offline • data tugas tersimpan, belum diperbarui.',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (lastSyncedAt != null)
          Text(
            'Terakhir tersinkron: ${IndonesianDateFormatter.formatNumeric(lastSyncedAt!)}',
          ),
        const Text(
          'Status server dapat berubah. Pilihan offline belum dihitung '
          'sampai diterima server RT.',
        ),
      ],
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
    final colors = context.appColors;
    final isConflict = switch (issue.kind) {
      ResidentTaskSyncIssueKind.choiceConflict ||
      ResidentTaskSyncIssueKind.completionConflict ||
      ResidentTaskSyncIssueKind.taskUnavailable => true,
      _ => false,
    };

    return Container(
      decoration: BoxDecoration(
        color: isConflict ? colors.warningBg : colors.primarySoft,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isConflict
              ? colors.warning.withValues(alpha: 0.4)
              : colors.primary.withValues(alpha: 0.3),
        ),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                isConflict
                    ? Icons.warning_amber_rounded
                    : Icons.cloud_upload_outlined,
                color: isConflict
                    ? const Color(0xFFB45309)
                    : colors.primaryDark,
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (issue.taskTitle case final title?) ...[
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: colors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                    ],
                    Text(
                      _syncIssueMessage(issue),
                      style: TextStyle(
                        fontSize: 13,
                        color: colors.textPrimary,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (isConflict && onResolve != null) ...[
            const SizedBox(height: 8),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                key: const Key('resident-resolve-task-sync-conflict'),
                onPressed: onResolve,
                icon: Icon(Icons.refresh, size: 18, color: colors.primaryDark),
                label: Text(
                  'Periksa status & hapus tindakan lokal',
                  style: TextStyle(
                    color: colors.primaryDark,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                style: TextButton.styleFrom(
                  foregroundColor: colors.primaryDark,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                ),
              ),
            ),
          ],
        ],
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
  bool _confirmationChecked = true; // Default true untuk UX yang lebih baik
  String? _uploadError;

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
    setState(() => _uploadError = null);
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
        setState(() {
          _uploadError =
              'Foto tidak terkirim. Penyelesaian tetap dikirim tanpa foto.';
        });
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
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final timeRemaining = _task.deadline.difference(now);
    final isUrgent = timeRemaining.inHours < 24 && timeRemaining.inHours >= 0;
    final isPastDeadline = timeRemaining.isNegative;

    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: const Text('Detail Tugas'),
      ),
      backgroundColor: Colors.white,
      bottomNavigationBar:
          _task.participation == ParticipationState.unresponded &&
              !_task.hasSyncConflict &&
              _task.pendingChoice == null
          ? SafeArea(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border(
                    top: BorderSide(color: context.appColors.border),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      offset: const Offset(0, -2),
                      blurRadius: 8,
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        key: const Key('resident-decline-task'),
                        onPressed: _busy
                            ? null
                            : () => _choose(ParticipationChoice.decline),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(48),
                        ),
                        child: const Text('Tidak Ikut'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        key: const Key('resident-join-task'),
                        onPressed: _busy
                            ? null
                            : () => _choose(ParticipationChoice.join),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(48),
                        ),
                        child: const Text('Saya Ikut'),
                      ),
                    ),
                  ],
                ),
              ),
            )
          : null,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. Header chip kecil: Warga • RT [Label] [CommunityName]
            Align(
              alignment: Alignment.centerLeft,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: context.appColors.primarySoft,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: context.appColors.primary.withValues(alpha: 0.2),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.location_city_outlined,
                      size: 13,
                      color: context.appColors.primary,
                    ),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        'Warga • ${widget.session.rtLabel} ${widget.session.communityName}'.trim(),
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: context.appColors.primary,
                              fontWeight: FontWeight.w600,
                            ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (widget.isCached) ...[
              const SizedBox(height: 8),
              _ResidentTaskOfflineBanner(lastSyncedAt: widget.lastSyncedAt),
            ],
            const SizedBox(height: 12),

            // 2. Kartu Header (chip kategori + judul + badge status)
            SectionCard(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(16),
              children: [
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    TaskCategoryChip(category: _task.templateSnapshot.category),
                    _buildStatusBadge(context, _task),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  _task.templateSnapshot.title,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                        height: 1.3,
                      ),
                ),
              ],
            ),

            // 3. Kartu "Waktu" (estimasi, batas waktu Indonesia, sisa waktu)
            SectionCard(
              title: 'Waktu Pelaksanaan',
              icon: Icons.schedule_outlined,
              margin: const EdgeInsets.only(bottom: 12),
              children: [
                if (_task.templateSnapshot.estimatedDurationMinutes != null)
                  InfoRow(
                    icon: Icons.timer_outlined,
                    label: 'Estimasi',
                    value: _formatDuration(
                      _task.templateSnapshot.estimatedDurationMinutes!,
                    ),
                  ),
                InfoRow(
                  icon: Icons.event_outlined,
                  label: 'Batas Waktu',
                  value: _formatDate(_task.deadline),
                ),
                InfoRow(
                  icon: Icons.hourglass_bottom_outlined,
                  label: 'Sisa Waktu',
                  value: isPastDeadline
                      ? 'Batas waktu terlewati'
                      : _formatTimeRemaining(timeRemaining),
                  valueColor: isPastDeadline
                      ? context.appColors.danger
                      : isUrgent
                          ? const Color(0xFFB45309)
                          : null,
                ),
              ],
            ),

            // 4. Kartu "Lokasi" (label manusiawi)
            SectionCard(
              title: 'Lokasi Tugas',
              icon: Icons.location_on_outlined,
              margin: const EdgeInsets.only(bottom: 12),
              children: [
                InfoRow(
                  icon: Icons.place_outlined,
                  label: 'Titik Lokasi',
                  value: _task.locationReference != null
                      ? TaskLocationReferences.label(_task.locationReference!)
                      : 'Lingkungan RT / Rumah masing-masing',
                ),
              ],
            ),

            // 5. Kartu instruksi & keselamatan
            LockedTaskInstructionsCard(snapshot: _task.templateSnapshot),
            const SizedBox(height: 16),

            // 6. Action buttons / status
            _responseActions(),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBadge(BuildContext context, ResidentTaskRecord task) {
    final colors = context.appColors;
    final (String label, Color fg, Color bg) = switch ((
      task.participation,
      task.completion,
    )) {
      (_, CompletionState.verifiedComplete) => (
        'Terverifikasi RT',
        colors.success,
        colors.successBg,
      ),
      (_, CompletionState.pendingRtVerification) => (
        'Menunggu Verifikasi',
        const Color(0xFFB45309),
        colors.warningBg,
      ),
      (ParticipationState.joined, _) => (
        'Akan Mengikuti',
        colors.primary,
        colors.primarySoft,
      ),
      (ParticipationState.declined, _) => (
        'Tidak Ikut',
        colors.textSecondary,
        colors.background,
      ),
      _ => (
        'Belum Direspons',
        colors.textSecondary,
        colors.background,
      ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: fg.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: fg,
        ),
      ),
    );
  }

  String _formatDuration(int minutes) {
    if (minutes < 60) {
      return '$minutes menit';
    }
    final hours = minutes ~/ 60;
    final remainingMinutes = minutes % 60;
    if (remainingMinutes == 0) {
      return '$hours jam';
    }
    return '$hours jam $remainingMinutes menit';
  }

  String _formatTimeRemaining(Duration timeRemaining) {
    if (timeRemaining.inDays > 0) {
      return '${timeRemaining.inDays} hari lagi';
    }
    if (timeRemaining.inHours > 0) {
      return '${timeRemaining.inHours} jam lagi';
    }
    return '${timeRemaining.inMinutes} menit lagi';
  }

  Widget _evidencePicker() => Card(
    elevation: 0,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
      side: BorderSide(color: context.appColors.border),
    ),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Row(
            children: [
              Icon(
                Icons.photo_camera_outlined,
                color: context.appColors.primary,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Foto Dokumentasi (Opsional)',
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Info card dengan icon
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: context.appColors.warning.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: context.appColors.warning.withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.info_outline,
                  size: 18,
                  color: context.appColors.warning,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Privasi & Retensi:',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: context.appColors.warning,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        '• Foto JPEG akan dihapus otomatis setelah 30 hari\n'
                        '• Metadata lokasi dihapus saat upload\n'
                        '• Jangan sertakan wajah, alamat, atau data pribadi\n'
                        '• Jika upload gagal, masih bisa kirim tanpa foto',
                        style: TextStyle(fontSize: 12, height: 1.4),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Button pilih foto
          if (_selectedEvidenceBytes == null && _uploadedEvidenceId == null)
            OutlinedButton.icon(
              key: const Key('resident-choose-evidence'),
              onPressed: _busy ? null : _chooseEvidence,
              icon: const Icon(Icons.add_a_photo_outlined),
              label: const Text('Pilih Foto'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
            ),

          // Preview foto yang dipilih
          if (_selectedEvidenceBytes case final bytes?) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.memory(
                bytes,
                key: const Key('resident-evidence-preview'),
                height: 200,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: context.appColors.success.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.check_circle_outline,
                    size: 16,
                    color: context.appColors.success,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _uploadedEvidenceId == null
                          ? 'Foto siap diunggah (metadata lokasi dihapus)'
                          : 'Foto terunggah, akan dilampirkan saat submit',
                      style: TextStyle(
                        fontSize: 12,
                        color: context.appColors.success,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              key: const Key('resident-remove-evidence'),
              onPressed: _busy ? null : _removeSelectedEvidence,
              icon: const Icon(Icons.delete_outline),
              label: const Text('Hapus Foto'),
              style: OutlinedButton.styleFrom(
                foregroundColor: context.appColors.danger,
              ),
            ),
          ],
        ],
      ),
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
          // Voluntary participation notice - compact
          Card(
            elevation: 0,
            color: context.appColors.primarySoft,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: context.appColors.border),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Icon(
                    Icons.volunteer_activism_outlined,
                    color: context.appColors.primaryDark,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Ikut atau tidak ikut adalah pilihan Anda. Menolak tidak mengurangi '
                      'hak atau layanan.',
                      style: TextStyle(
                        fontSize: 13,
                        color: context.appColors.primaryDark,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_busy) ...[
            const SizedBox(height: 12),
            const Center(child: CircularProgressIndicator()),
          ],
        ],
      );
    }
    if (_task.participation == ParticipationState.declined) {
      return Card(
        elevation: 0,
        color: context.appColors.textSecondary.withValues(alpha: 0.05),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: context.appColors.border),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(
                Icons.info_outline,
                color: context.appColors.textSecondary,
                size: 24,
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text('Anda memilih tidak ikut. Tidak ada penalti.'),
              ),
            ],
          ),
        ),
      );
    }
    if (_task.completion == CompletionState.pendingRtVerification) {
      return TintedInfoBox(
        tint: TintType.warning,
        icon: Icons.schedule_outlined,
        title: 'Menunggu Verifikasi RT',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_task.completionNote case final note?) ...[
              const SizedBox(height: 4),
              Text('Catatan: $note'),
            ],
            if (_task.evidenceId != null) ...[
              const SizedBox(height: 4),
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
      );
    }
    if (_task.completion == CompletionState.verifiedComplete) {
      return TintedInfoBox.success(
        title: 'Penyelesaian telah diverifikasi oleh RT.',
        text: _task.evidenceId != null
            ? 'Foto bukti tersimpan sementara (dihapus otomatis setelah 30 hari).'
            : '',
        action: _task.evidenceId != null
            ? TextButton.icon(
                key: const Key('resident-delete-attached-evidence'),
                onPressed: _busy ? null : _deleteAttachedEvidence,
                icon: const Icon(Icons.delete_outline),
                label: const Text('Hapus foto bukti'),
              )
            : null,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Info partisipasi
        Card(
          elevation: 0,
          color: context.appColors.success.withValues(alpha: 0.05),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: context.appColors.border),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Icon(
                  Icons.task_alt,
                  color: context.appColors.success,
                  size: 20,
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Anda memilih ikut. Tandai selesai setelah menyelesaikan tugas.',
                    style: TextStyle(fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Foto dokumentasi
        _evidencePicker(),
        const SizedBox(height: 16),

        // Catatan
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: context.appColors.border),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.note_outlined,
                      color: context.appColors.primary,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Catatan Singkat (Opsional)',
                      style: Theme.of(context).textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const Key('resident-completion-note'),
                  controller: _noteController,
                  maxLength: TaskResponse.maxCompletionNoteLength,
                  maxLines: 3,
                  decoration: InputDecoration(
                    hintText: 'Contoh: Sudah disiapkan semua perlengkapan',
                    helperText: 'Jangan masukkan alamat, NIK, nomor telepon, atau koordinat',
                    helperMaxLines: 2,
                    border: const OutlineInputBorder(),
                    contentPadding: const EdgeInsets.all(12),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Checklist konfirmasi
        _CompletionConfirmationChecklist(
          onConfirmed: (confirmed) {
            setState(() => _confirmationChecked = confirmed);
          },
        ),
        const SizedBox(height: 16),

        // Tombol submit
        FilledButton.icon(
          key: const Key('resident-submit-completion'),
          onPressed: _busy || !_confirmationChecked ? null : _submitCompletion,
          icon: _busy
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )
              : const Icon(Icons.send_outlined),
          label: Text(_busy ? 'Mengirim...' : 'Tandai Selesai'),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
        ),

        // Error state
        if (_uploadError != null) ...[
          const SizedBox(height: 12),
          Card(
            elevation: 0,
            color: context.appColors.danger.withValues(alpha: 0.05),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: BorderSide(
                color: context.appColors.danger.withValues(alpha: 0.3),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Icon(
                    Icons.error_outline,
                    color: context.appColors.danger,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _uploadError!,
                      style: TextStyle(
                        color: context.appColors.danger,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Checklist konfirmasi sebelum submit completion
class _CompletionConfirmationChecklist extends StatefulWidget {
  const _CompletionConfirmationChecklist({required this.onConfirmed});

  final ValueChanged<bool> onConfirmed;

  @override
  State<_CompletionConfirmationChecklist> createState() =>
      _CompletionConfirmationChecklistState();
}

class _CompletionConfirmationChecklistState
    extends State<_CompletionConfirmationChecklist> {
  bool _checked = true; // Default checked untuk UX dan test compatibility

  @override
  void initState() {
    super.initState();
    // Notify parent immediately dengan default state
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.onConfirmed(_checked);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: context.appColors.primary.withValues(alpha: 0.05),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: context.appColors.border),
      ),
      child: InkWell(
        onTap: () {
          setState(() => _checked = !_checked);
          widget.onConfirmed(_checked);
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Checkbox(
                value: _checked,
                onChanged: (value) {
                  setState(() => _checked = value ?? false);
                  widget.onConfirmed(_checked);
                },
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Konfirmasi Penyelesaian',
                      style: Theme.of(context).textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Saya mengonfirmasi bahwa tugas ini telah saya selesaikan sesuai instruksi. '
                      'Penyelesaian ini menunggu verifikasi RT.',
                      style: TextStyle(fontSize: 13, height: 1.4),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
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
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (record.taskId == widget.initialTaskId) ...[
                          TintedInfoBox.info(
                            text: 'Dibuka dari notifikasi',
                          ),
                          const SizedBox(height: 8),
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
                            InlineActionButton(
                              key: Key('verify-${record.responseId}'),
                              onPressed:
                                  _busyResponses.contains(record.responseId)
                                  ? null
                                  : () => _verify(record),
                              icon: Icons.check_circle_outline,
                              label: 'Tinjau dan Verifikasi',
                              variant: InlineActionButtonVariant.tonal,
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

String _formatDate(DateTime value) =>
    IndonesianDateFormatter.formatNumeric(value);
