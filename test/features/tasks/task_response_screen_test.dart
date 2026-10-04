import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guyub/features/auth/application/operator_profile.dart';
import 'package:guyub/features/auth/application/resident_session.dart';
import 'package:guyub/features/auth/application/resident_session_vault.dart';
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
      expect(
        find.textContaining('Cache offline belum tersedia'),
        findsOneWidget,
      );
      expect(find.text('Coba Lagi'), findsOneWidget);
    },
  );
}

TaskResponseController _controller(_FakeBoundary boundary) =>
    TaskResponseController(boundary: boundary, vault: _FakeVault());

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
  bool pendingPartial = false;
  ParticipationChoice? lastChoice;
  String? lastNote;
  final List<String> verifiedResponses = [];

  @override
  Future<ResidentTaskList> listResidentActiveTasks({
    required String sessionToken,
  }) async {
    if (failTaskList) throw StateError('offline');
    return ResidentTaskList(items: tasks, isPartial: taskListPartial);
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
  }) async {
    lastNote = note;
    final response = TaskResponseRecord(
      taskId: taskId,
      participation: ParticipationState.joined,
      completion: CompletionState.pendingRtVerification,
      completionNote: note,
      completionSubmittedAt: DateTime.utc(2026, 10, 4),
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
