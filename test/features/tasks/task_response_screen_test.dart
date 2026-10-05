import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as image;
import 'package:flutter_test/flutter_test.dart';
import 'package:guyub/features/auth/application/operator_profile.dart';
import 'package:guyub/features/auth/application/resident_session.dart';
import 'package:guyub/features/auth/application/resident_session_vault.dart';
import 'package:guyub/features/evidence/application/task_evidence_boundary.dart';
import 'package:guyub/features/tasks/application/task_response.dart';
import 'package:guyub/features/tasks/application/task_response_boundary.dart';
import 'package:guyub/features/tasks/application/task_template.dart';
import 'package:guyub/features/tasks/presentation/screens/task_response_screens.dart';

void main() {
  testWidgets(
    'resident sees locked safety text and can decline without penalty',
    (tester) async {
      final boundary = _FakeBoundary()..tasks = [_task()];
      final controller = _controller(boundary);
      await tester.pumpWidget(
        MaterialApp(
          home: ResidentTaskListScreen(
            session: _session(),
            controller: controller,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Siapkan perlengkapan keluarga'), findsOneWidget);
      await tester.tap(find.byKey(const Key('resident-task-task-a')));
      await tester.pumpAndSettle();

      expect(
        find.text('Jangan mendekati air banjir atau instalasi listrik basah.'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('resident-join-task')), findsOneWidget);
      expect(find.byKey(const Key('resident-decline-task')), findsOneWidget);
      expect(
        find.textContaining('Menolak tidak mengurangi hak'),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('resident-decline-task')));
      await tester.pumpAndSettle();
      expect(
        find.text('Anda memilih tidak ikut. Tidak ada penalti.'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('resident-submit-completion')), findsNothing);
      expect(boundary.lastChoice, ParticipationChoice.decline);
    },
  );

  testWidgets(
    'joined resident submits completion and sees RT verification pending',
    (tester) async {
      final boundary = _FakeBoundary()..tasks = [_task()];
      final controller = _controller(boundary);
      await tester.pumpWidget(
        MaterialApp(
          home: ResidentTaskDetailScreen(
            session: _session(),
            controller: controller,
            task: _task(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('resident-join-task')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('resident-completion-note')), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('resident-completion-note')),
        'Perlengkapan sudah disiapkan.',
      );
      await tester.ensureVisible(
        find.byKey(const Key('resident-submit-completion')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('resident-submit-completion')));
      await tester.pumpAndSettle();

      expect(find.text('Menunggu Verifikasi RT'), findsOneWidget);
      expect(
        find.textContaining('Catatan: Perlengkapan sudah disiapkan.'),
        findsOneWidget,
      );
      expect(boundary.lastNote, 'Perlengkapan sudah disiapkan.');
    },
  );

  testWidgets('photo upload failure never blocks resident completion', (
    tester,
  ) async {
    final boundary = _FakeBoundary()
      ..tasks = [_task(participation: ParticipationState.joined)];
    final evidenceBoundary = _FakeEvidenceBoundary(failUpload: true);
    final controller = _controller(
      boundary,
      evidenceBoundary: evidenceBoundary,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: ResidentTaskDetailScreen(
          session: _session(),
          controller: controller,
          task: _task(participation: ParticipationState.joined),
          pickEvidenceImage: () async => _testJpeg(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('resident-choose-evidence')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('resident-evidence-preview')), findsOneWidget);
    await tester.ensureVisible(
      find.byKey(const Key('resident-submit-completion')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('resident-submit-completion')));
    await tester.pumpAndSettle();

    expect(find.text('Menunggu Verifikasi RT'), findsOneWidget);
    expect(boundary.lastEvidenceId, isNull);
    expect(
      find.textContaining('Penyelesaian tetap dikirim tanpa foto'),
      findsOneWidget,
    );
  });

  testWidgets('resident attaches sanitized optional photo to completion', (
    tester,
  ) async {
    final boundary = _FakeBoundary()
      ..tasks = [_task(participation: ParticipationState.joined)];
    final evidenceBoundary = _FakeEvidenceBoundary();
    await tester.pumpWidget(
      MaterialApp(
        home: ResidentTaskDetailScreen(
          session: _session(),
          controller: _controller(boundary, evidenceBoundary: evidenceBoundary),
          task: _task(participation: ParticipationState.joined),
          pickEvidenceImage: () async => _testJpeg(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('resident-choose-evidence')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const Key('resident-submit-completion')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('resident-submit-completion')));
    await tester.pumpAndSettle();

    expect(boundary.lastEvidenceId, 'a' * 40);
    expect(evidenceBoundary.uploadedBytes, isNotNull);
    expect(find.text('Foto bukti tersedia untuk ditinjau RT.'), findsOneWidget);
    expect(
      find.byKey(const Key('resident-delete-attached-evidence')),
      findsOneWidget,
    );
  });

  testWidgets(
    'resident can explicitly delete attached evidence without changing task state',
    (tester) async {
      final boundary = _FakeBoundary();
      final evidenceBoundary = _FakeEvidenceBoundary();
      await tester.pumpWidget(
        MaterialApp(
          home: ResidentTaskDetailScreen(
            session: _session(),
            controller: _controller(
              boundary,
              evidenceBoundary: evidenceBoundary,
            ),
            task: _task(
              participation: ParticipationState.joined,
              completion: CompletionState.pendingRtVerification,
              evidenceId: 'b' * 40,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('resident-delete-attached-evidence')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Hapus foto bukti?'), findsOneWidget);
      await tester.tap(find.text('Hapus foto'));
      await tester.pumpAndSettle();

      expect(evidenceBoundary.deletedEvidenceIds, ['b' * 40]);
      expect(
        find.byKey(const Key('resident-delete-attached-evidence')),
        findsNothing,
      );
      expect(find.text('Menunggu Verifikasi RT'), findsOneWidget);
    },
  );

  testWidgets('operator opens evidence only after an explicit review tap', (
    tester,
  ) async {
    final bytes = _testJpeg();
    final boundary = _FakeBoundary()
      ..pending = [
        TaskVerificationRecord(
          responseId: 'response-photo',
          taskId: 'task-a',
          taskTitle: 'Tugas foto',
          nickname: 'Warga A',
          submittedAt: DateTime.utc(2026, 10, 4),
          evidenceId: 'a' * 40,
        ),
      ];
    final evidenceBoundary = _FakeEvidenceBoundary(imageBytes: bytes);
    await tester.pumpWidget(
      MaterialApp(
        home: TaskVerificationQueueScreen(
          profile: _operator(),
          controller: _controller(boundary, evidenceBoundary: evidenceBoundary),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('review-evidence-response-photo')),
      findsOneWidget,
    );
    expect(evidenceBoundary.requestedEvidenceId, isNull);
    await tester.tap(find.byKey(const Key('review-evidence-response-photo')));
    await tester.pumpAndSettle();
    expect(evidenceBoundary.requestedEvidenceId, 'a' * 40);
    expect(find.text('Foto bukti pribadi'), findsOneWidget);
    await tester.tap(find.text('Tutup'));
    await tester.pumpAndSettle();
  });

  testWidgets(
    'operator verifies a resident submission only after confirmation',
    (tester) async {
      final boundary = _FakeBoundary()
        ..pending = [
          TaskVerificationRecord(
            responseId: 'response-a',
            taskId: 'task-a',
            taskTitle: 'Siapkan perlengkapan keluarga',
            nickname: 'Warga A',
            submittedAt: DateTime.utc(2026, 10, 4),
            completionNote: 'Sudah disiapkan.',
          ),
        ];
      final controller = _controller(boundary);
      await tester.pumpWidget(
        MaterialApp(
          home: TaskVerificationQueueScreen(
            profile: _operator(),
            controller: controller,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Ketua RT/RW • RT rt-a'), findsOneWidget);
      expect(find.textContaining('Menunggu Verifikasi RT'), findsOneWidget);
      expect(find.textContaining('Warga A'), findsOneWidget);
      await tester.ensureVisible(find.byKey(const Key('verify-response-a')));
      await tester.tap(find.byKey(const Key('verify-response-a')));
      await tester.pumpAndSettle();
      expect(find.text('Verifikasi penyelesaian?'), findsOneWidget);
      expect(boundary.verifiedResponses, isEmpty);
      await tester.tap(find.byKey(const Key('confirm-task-verification')));
      await tester.pumpAndSettle();

      expect(boundary.verifiedResponses, ['response-a']);
      expect(
        find.text('Belum ada penyelesaian yang menunggu verifikasi RT.'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'RT recap counts recorded responses without a non-response total',
    (tester) async {
      final boundary = _FakeBoundary();
      await tester.pumpWidget(
        MaterialApp(
          home: TaskResponseRecapScreen(
            profile: _operator(),
            taskId: 'task-a',
            controller: _controller(boundary),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Tanggapan tercatat'), findsOneWidget);
      expect(find.text('Memilih ikut'), findsOneWidget);
      expect(find.text('Memilih tidak ikut'), findsOneWidget);
      expect(
        find.textContaining('Warga yang belum menjawab tidak dihitung'),
        findsOneWidget,
      );
      expect(find.textContaining('bukan peringkat'), findsOneWidget);
      expect(find.text('Belum menjawab'), findsNothing);
    },
  );

  testWidgets('bounded lists disclose truncation', (tester) async {
    final residentBoundary = _FakeBoundary()
      ..tasks = [_task()]
      ..taskListPartial = true;
    await tester.pumpWidget(
      MaterialApp(
        home: ResidentTaskListScreen(
          session: _session(),
          controller: _controller(residentBoundary),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Daftar tugas dibatasi'), findsOneWidget);

    final operatorBoundary = _FakeBoundary()
      ..pendingPartial = true
      ..pending = [
        TaskVerificationRecord(
          responseId: 'response-a',
          taskId: 'task-a',
          taskTitle: 'Tugas',
          nickname: 'Warga A',
          submittedAt: DateTime.utc(2026, 10, 4),
        ),
      ];
    await tester.pumpWidget(
      MaterialApp(
        home: TaskVerificationQueueScreen(
          profile: _operator(),
          controller: _controller(operatorBoundary),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Daftar verifikasi dibatasi'), findsOneWidget);
  });

  testWidgets('cached task list and detail show stale timestamps', (
    tester,
  ) async {
    final boundary = _FakeBoundary()
      ..tasks = [_task()]
      ..taskListCached = true
      ..lastSyncedAt = DateTime.utc(2026, 10, 4, 10);
    final controller = _controller(boundary);
    await tester.pumpWidget(
      MaterialApp(
        home: ResidentTaskListScreen(
          session: _session(),
          controller: controller,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('resident-task-offline-banner')),
      findsOneWidget,
    );
    expect(find.textContaining('Mode offline'), findsOneWidget);
    expect(find.textContaining('Terakhir tersinkron:'), findsOneWidget);
    await tester.tap(find.byKey(const Key('resident-task-task-a')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('resident-task-offline-banner')),
      findsOneWidget,
    );
    expect(
      find.text('Jangan mendekati air banjir atau instalasi listrik basah.'),
      findsOneWidget,
    );
  });

  testWidgets('pending offline choice is not shown as server accepted', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ResidentTaskDetailScreen(
          session: _session(),
          controller: _controller(_FakeBoundary()),
          task: _task(
            pendingChoice: ParticipationChoice.join,
            hasSyncConflict: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Pilihan offline belum disimpan'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('resident-join-task')), findsNothing);
    expect(find.byKey(const Key('resident-decline-task')), findsNothing);
  });

  testWidgets('offline completion stays pending RT verification', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ResidentTaskDetailScreen(
          session: _session(),
          controller: _controller(_FakeBoundary()),
          task: _task(
            participation: ParticipationState.joined,
            hasPendingCompletionSync: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Penyelesaian menunggu sinkronisasi'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('resident-submit-completion')), findsNothing);
    expect(
      find.textContaining('RT tetap harus memverifikasinya'),
      findsOneWidget,
    );
  });

  testWidgets(
    'resident sees an honest online-only error when task fetch fails',
    (tester) async {
      final boundary = _FakeBoundary()..failTaskList = true;
      await tester.pumpWidget(
        MaterialApp(
          home: ResidentTaskListScreen(
            session: _session(),
            controller: _controller(boundary),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Tugas belum tersedia'), findsOneWidget);
      expect(find.text('Coba Lagi'), findsOneWidget);
    },
  );
}

TaskResponseController _controller(
  _FakeBoundary boundary, {
  TaskEvidenceBoundary? evidenceBoundary,
}) => TaskResponseController(
  boundary: boundary,
  evidenceBoundary: evidenceBoundary,
  vault: _FakeVault(),
);

ResidentSession _session() => ResidentSession(
  residentId: 'resident-a',
  communityId: 'rt-a',
  communityName: 'Komunitas A',
  rtLabel: 'RT 01',
  nickname: 'Warga A',
  expiresAt: DateTime.utc(2026, 10, 11),
);

OperatorProfile _operator() => OperatorProfile(
  uid: 'operator-a',
  communityId: 'rt-a',
  role: OperatorRole.ketuaRtRw,
  displayName: 'Ketua RT',
);

ResidentTaskRecord _task({
  ParticipationState participation = ParticipationState.unresponded,
  CompletionState completion = CompletionState.notSubmitted,
  String? completionNote,
  String? evidenceId,
  ParticipationChoice? pendingChoice,
  bool hasSyncConflict = false,
  bool hasPendingCompletionSync = false,
}) => ResidentTaskRecord(
  taskId: 'task-a',
  rtId: 'rt-a',
  templateSnapshot: const TaskTemplateSnapshot(
    templateId: 'safe-prep',
    version: 1,
    title: 'Siapkan perlengkapan keluarga',
    category: 'HOUSEHOLD_PREPARATION',
    coreInstruction: 'Simpan dokumen penting di tempat aman.',
    safetyInstruction:
        'Jangan mendekati air banjir atau instalasi listrik basah.',
  ),
  deadline: DateTime.utc(2026, 10, 5, 12),
  status: 'ACTIVE',
  participation: participation,
  completion: completion,
  completionNote: completionNote,
  evidenceId: evidenceId,
  pendingChoice: pendingChoice,
  hasSyncConflict: hasSyncConflict,
  hasPendingCompletionSync: hasPendingCompletionSync,
);

final class _FakeVault implements ResidentSessionVault {
  @override
  Future<String?> read() async => 'opaque-session-token';

  @override
  Future<void> write(String sessionToken) async {}

  @override
  Future<void> clear() async {}

  @override
  Future<String?> readPendingEnrollmentId() async => null;

  @override
  Future<void> writePendingEnrollmentId(String requestId) async {}

  @override
  Future<void> clearPendingEnrollmentId() async {}
}

final class _FakeBoundary implements TaskResponseBoundary {
  List<ResidentTaskRecord> tasks = [];
  List<TaskVerificationRecord> pending = [];
  bool failTaskList = false;
  bool taskListPartial = false;
  bool taskListCached = false;
  DateTime? lastSyncedAt;
  List<ResidentTaskSyncIssue> syncIssues = [];
  bool pendingPartial = false;
  ParticipationChoice? lastChoice;
  String? lastNote;
  String? lastEvidenceId;
  final List<String> verifiedResponses = [];

  @override
  Future<ResidentTaskList> listResidentActiveTasks({
    required String sessionToken,
  }) async {
    if (failTaskList) throw StateError('offline');
    return ResidentTaskList(
      items: tasks,
      isPartial: taskListPartial,
      isCached: taskListCached,
      lastSyncedAt: lastSyncedAt,
      syncIssues: syncIssues,
    );
  }

  @override
  Future<TaskResponseRecord> recordResidentTaskResponse({
    required String sessionToken,
    required String taskId,
    required ParticipationChoice choice,
    required String commandId,
  }) async {
    lastChoice = choice;
    final response = TaskResponseRecord(
      taskId: taskId,
      participation: choice == ParticipationChoice.join
          ? ParticipationState.joined
          : ParticipationState.declined,
      completion: CompletionState.notSubmitted,
    );
    tasks = tasks.map((task) => task.withResponse(response)).toList();
    return response;
  }

  @override
  Future<TaskResponseRecord> submitTaskCompletion({
    required String sessionToken,
    required String taskId,
    required String? note,
    required String commandId,
    String? evidenceId,
  }) async {
    lastNote = note;
    lastEvidenceId = evidenceId;
    final response = TaskResponseRecord(
      taskId: taskId,
      participation: ParticipationState.joined,
      completion: CompletionState.pendingRtVerification,
      completionNote: note,
      completionSubmittedAt: DateTime.utc(2026, 10, 4),
      evidenceId: evidenceId,
    );
    tasks = tasks.map((task) => task.withResponse(response)).toList();
    return response;
  }

  @override
  Future<TaskVerificationQueue> listPendingVerifications() async =>
      TaskVerificationQueue(items: pending, isPartial: pendingPartial);

  @override
  Future<TaskResponseRecord> verifyTaskCompletion({
    required String responseId,
    required String commandId,
  }) async {
    verifiedResponses.add(responseId);
    pending = [];
    return TaskResponseRecord(
      taskId: 'task-a',
      participation: ParticipationState.joined,
      completion: CompletionState.verifiedComplete,
      verifiedAt: DateTime.utc(2026, 10, 4),
    );
  }

  @override
  Future<TaskResponseRecap> getResponseRecap({required String taskId}) async =>
      const TaskResponseRecap(
        taskId: 'task-a',
        rtId: 'rt-a',
        recordedResponseCount: 2,
        joinedCount: 1,
        declinedCount: 1,
        pendingVerificationCount: 0,
        verifiedCompleteCount: 1,
        isPartial: false,
        taskTitle: 'Siapkan perlengkapan keluarga',
      );
}

final class _FakeEvidenceBoundary implements TaskEvidenceBoundary {
  _FakeEvidenceBoundary({this.failUpload = false, this.imageBytes});

  final bool failUpload;
  final Uint8List? imageBytes;
  final List<String> deletedEvidenceIds = [];
  Uint8List? uploadedBytes;
  String? requestedEvidenceId;

  @override
  Future<String> uploadResidentTaskEvidence({
    required String sessionToken,
    required String taskId,
    required String requestId,
    required Uint8List sanitizedJpegBytes,
  }) async {
    if (failUpload) throw StateError('optional upload failed');
    uploadedBytes = sanitizedJpegBytes;
    return 'a' * 40;
  }

  @override
  Future<void> deleteResidentTaskEvidence({
    required String sessionToken,
    required String evidenceId,
    required String commandId,
  }) async {
    deletedEvidenceIds.add(evidenceId);
  }

  @override
  Future<Uint8List> getTaskEvidenceForVerification({
    required String evidenceId,
  }) async {
    requestedEvidenceId = evidenceId;
    return imageBytes ?? _testJpeg();
  }
}

Uint8List _testJpeg() => Uint8List.fromList(
  image.encodeJpg(image.Image(width: 8, height: 8, numChannels: 3)),
);
