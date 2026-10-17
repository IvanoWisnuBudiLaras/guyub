import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guyub/core/theme/app_theme.dart';
import 'package:guyub/core/widgets/info_row.dart';
import 'package:guyub/core/widgets/section_card.dart';
import 'package:guyub/features/auth/application/resident_session.dart';
import 'package:guyub/features/auth/application/resident_session_vault.dart';
import 'package:guyub/features/tasks/application/task_response.dart';
import 'package:guyub/features/tasks/application/task_response_boundary.dart';
import 'package:guyub/features/tasks/application/task_template.dart';
import 'package:guyub/features/tasks/presentation/screens/task_response_screens.dart';
import 'package:guyub/features/tasks/presentation/widgets/locked_instructions_card.dart';

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
  @override
  Future<ResidentTaskList> listResidentActiveTasks({
    required String sessionToken,
  }) async => const ResidentTaskList(items: [], isPartial: false);

  @override
  Future<TaskResponseRecord> recordResidentTaskResponse({
    required String sessionToken,
    required String taskId,
    required ParticipationChoice choice,
    required String commandId,
  }) async => TaskResponseRecord(
    taskId: taskId,
    participation: choice == ParticipationChoice.join
        ? ParticipationState.joined
        : ParticipationState.declined,
    completion: CompletionState.notSubmitted,
  );

  @override
  Future<TaskResponseRecord> submitTaskCompletion({
    required String sessionToken,
    required String taskId,
    required String? note,
    required String commandId,
    String? evidenceId,
  }) async => TaskResponseRecord(
    taskId: taskId,
    participation: ParticipationState.joined,
    completion: CompletionState.pendingRtVerification,
  );

  @override
  Future<TaskVerificationQueue> listPendingVerifications() async =>
      const TaskVerificationQueue(items: [], isPartial: false);

  @override
  Future<TaskResponseRecord> verifyTaskCompletion({
    required String responseId,
    required String commandId,
  }) async => const TaskResponseRecord(
    taskId: 'task-1',
    participation: ParticipationState.joined,
    completion: CompletionState.verifiedComplete,
  );

  @override
  Future<TaskResponseRecap> getResponseRecap({required String taskId}) async =>
      const TaskResponseRecap(
        taskId: 'task-1',
        rtId: 'rt-01',
        recordedResponseCount: 0,
        joinedCount: 0,
        declinedCount: 0,
        pendingVerificationCount: 0,
        verifiedCompleteCount: 0,
        isPartial: false,
        taskTitle: 'Bersihkan Selokan Depan Rumah',
      );
}

void main() {
  testWidgets(
    'Tahap B3.c: Detail Tugas Warga memiliki AppBar, chip RT kecil, SectionCards (Header, Waktu, Lokasi), LockedInstructions, dan sticky bottom bar',
    (tester) async {
      final session = ResidentSession(
        residentId: 'resident-1',
        communityId: 'rt-01',
        communityName: 'Kedungwaru',
        rtLabel: 'RT 01',
        nickname: 'Budi',
        expiresAt: DateTime.utc(2026, 12, 31),
      );

      final task = ResidentTaskRecord(
        taskId: 'task-1',
        rtId: 'rt-01',
        templateSnapshot: const TaskTemplateSnapshot(
          templateId: 'tpl-1',
          version: 1,
          category: 'GOTONG_ROYONG',
          title: 'Bersihkan Selokan Depan Rumah',
          coreInstruction: 'Bersihkan sampah yang menyumbat saluran air.',
          safetyInstruction: 'Gunakan sarung tangan karet dan sepatu bot.',
          estimatedDurationMinutes: 45,
        ),
        deadline: DateTime.now().add(const Duration(hours: 12)),
        status: 'ACTIVE',
        participation: ParticipationState.unresponded,
        completion: CompletionState.notSubmitted,
        locationReference: 'COMMUNITY_GENERAL_AREA',
      );

      final controller = TaskResponseController(
        boundary: _FakeBoundary(),
        vault: _FakeVault(),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: ResidentTaskDetailScreen(
            session: session,
            task: task,
            controller: controller,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 1. AppBar dengan title "Detail Tugas" dan back button
      expect(find.text('Detail Tugas'), findsOneWidget);
      expect(find.byType(BackButton), findsOneWidget);

      // 2. Chip RT kecil
      expect(find.text('Warga • RT 01 Kedungwaru'), findsOneWidget);

      // 3. Kartu Header: judul + status badge
      expect(find.text('Bersihkan Selokan Depan Rumah'), findsOneWidget);
      expect(find.text('Belum Direspons'), findsOneWidget);

      // 4. Kartu Waktu
      expect(find.text('Waktu Pelaksanaan'), findsOneWidget);
      expect(find.text('Estimasi'), findsOneWidget);
      expect(find.text('45 menit'), findsOneWidget);
      expect(find.text('Batas Waktu'), findsOneWidget);
      expect(find.text('Sisa Waktu'), findsOneWidget);

      // 5. Kartu Lokasi
      expect(find.text('Lokasi Tugas'), findsOneWidget);
      expect(find.text('Titik Lokasi'), findsOneWidget);
      expect(
        find.text('Area umum RT yang ditentukan operator'),
        findsOneWidget,
      );

      // 6. SectionCard dan InfoRow digunakan
      expect(find.byType(SectionCard), findsNWidgets(3));
      expect(find.byType(InfoRow), findsNWidgets(4));

      // 7. Instruksi & Keselamatan
      expect(find.byType(LockedTaskInstructionsCard), findsOneWidget);
      expect(find.text('Instruksi template terkunci'), findsOneWidget);
      expect(
        find.text('Gunakan sarung tangan karet dan sepatu bot.'),
        findsOneWidget,
      );

      // 8. Sticky bottom bar dengan tombol Tidak Ikut & Ikut
      expect(find.byKey(const Key('resident-decline-task')), findsOneWidget);
      expect(find.byKey(const Key('resident-join-task')), findsOneWidget);
    },
  );
}
