import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:guyub/features/auth/application/resident_session_vault.dart';
import 'package:guyub/features/evidence/application/task_evidence_boundary.dart';
import 'package:guyub/features/tasks/application/task_response.dart';
import 'package:guyub/features/tasks/application/task_response_boundary.dart';

void main() {
  test(
    'resident controller reads the bearer token from the secure vault',
    () async {
      final boundary = _FakeBoundary();
      final controller = TaskResponseController(
        boundary: boundary,
        vault: _FakeVault('secret-session-token'),
      );

      await controller.listResidentActiveTasks();

      expect(boundary.lastSessionToken, 'secret-session-token');
    },
  );

  test('resident choice retries reuse one opaque command ID', () async {
    final boundary = _FakeBoundary()..failNextChoice = true;
    var generated = 0;
    final controller = TaskResponseController(
      boundary: boundary,
      vault: _FakeVault('secret-session-token'),
      commandIdFactory: () => 'c${generated++}'.padRight(40, 'x'),
    );

    await expectLater(
      controller.recordParticipation(
        taskId: 'task-a',
        choice: ParticipationChoice.join,
      ),
      throwsStateError,
    );
    await controller.recordParticipation(
      taskId: 'task-a',
      choice: ParticipationChoice.join,
    );

    expect(boundary.choiceCommandIds, hasLength(2));
    expect(boundary.choiceCommandIds[0], boundary.choiceCommandIds[1]);
    expect(generated, 1);
  });

  test(
    'completion retries preserve the command ID for an unchanged note',
    () async {
      final boundary = _FakeBoundary()..failNextCompletion = true;
      var generated = 0;
      final controller = TaskResponseController(
        boundary: boundary,
        vault: _FakeVault('secret-session-token'),
        commandIdFactory: () => 'n${generated++}'.padRight(40, 'x'),
      );
      await expectLater(
        controller.submitCompletion(taskId: 'task-a', note: 'Sudah siap'),
        throwsStateError,
      );
      await controller.submitCompletion(taskId: 'task-a', note: 'Sudah siap');

      expect(
        boundary.completionCommandIds[0],
        boundary.completionCommandIds[1],
      );
      expect(generated, 1);
    },
  );

  test(
    'evidence upload uses the secure session and never persists photo bytes',
    () async {
      final responseBoundary = _FakeBoundary();
      final evidenceBoundary = _FakeEvidenceBoundary();
      final controller = TaskResponseController(
        boundary: responseBoundary,
        evidenceBoundary: evidenceBoundary,
        vault: _FakeVault('secret-session-token'),
        commandIdFactory: () => 'upload-request-id'.padRight(40, 'x'),
      );
      final bytes = Uint8List.fromList([1, 2, 3, 4]);

      final evidenceId = await controller.uploadEvidence(
        taskId: 'task-a',
        sanitizedJpegBytes: bytes,
      );

      expect(evidenceId, 'a' * 40);
      expect(evidenceBoundary.sessionToken, 'secret-session-token');
      expect(evidenceBoundary.uploadedBytes, bytes);
      expect(evidenceBoundary.requestId, 'upload-request-id'.padRight(40, 'x'));
    },
  );

  test('evidence deletion retries reuse the same command ID', () async {
    final evidenceBoundary = _FakeEvidenceBoundary()..failNextDelete = true;
    var generated = 0;
    final controller = TaskResponseController(
      boundary: _FakeBoundary(),
      evidenceBoundary: evidenceBoundary,
      vault: _FakeVault('secret-session-token'),
      commandIdFactory: () => 'delete${generated++}'.padRight(40, 'x'),
    );
    await expectLater(
      controller.deleteEvidence(evidenceId: 'b' * 40),
      throwsStateError,
    );
    await controller.deleteEvidence(evidenceId: 'b' * 40);

    expect(evidenceBoundary.deleteCommandIds, hasLength(2));
    expect(
      evidenceBoundary.deleteCommandIds.first,
      evidenceBoundary.deleteCommandIds.last,
    );
    expect(generated, 1);
  });

  test('wire parsing accepts only opaque hexadecimal evidence IDs', () {
    expect(
      () => TaskResponseRecord.fromWire({
        'taskId': 'task-a',
        'participationState': 'JOINED',
        'completionState': 'PENDING_RT_VERIFICATION',
        'evidenceId': 'public-url',
      }),
      throwsFormatException,
    );
    expect(
      () => TaskVerificationRecord.fromWire({
        'responseId': 'response-a',
        'taskId': 'task-a',
        'taskTitle': 'Tugas',
        'nickname': 'Warga',
        'submittedAt': '2026-10-05T12:00:00.000Z',
        'evidenceId': 'public-url',
      }),
      throwsFormatException,
    );
  });

  test('missing secure session fails before a resident call', () async {
    final boundary = _FakeBoundary();
    final controller = TaskResponseController(
      boundary: boundary,
      vault: _FakeVault(null),
    );

    await expectLater(controller.listResidentActiveTasks(), throwsStateError);
    expect(boundary.lastSessionToken, isNull);
  });

  test(
    'wire models preserve state and recap exposes no non-response count',
    () {
      final task = ResidentTaskRecord.fromWire({
        'taskId': 'task-a',
        'rtId': 'rt-a',
        'status': 'ACTIVE',
        'deadline': '2026-10-05T12:00:00.000Z',
        'locationReference': 'COMMUNITY_GENERAL_AREA',
        'participationState': 'UNRESPONDED',
        'completionState': 'NOT_SUBMITTED',
        'completionNote': null,
        'completionSubmittedAt': null,
        'verifiedAt': null,
        'templateSnapshot': {
          'templateId': 'safe-prep',
          'version': 1,
          'title': 'Siapkan keluarga',
          'category': 'HOUSEHOLD_PREPARATION',
          'coreInstruction': 'Simpan dokumen penting.',
          'safetyInstruction': 'Jangan mendekati air banjir.',
        },
      });
      final recap = TaskResponseRecap.fromWire({
        'taskId': 'task-a',
        'rtId': 'rt-a',
        'recordedResponseCount': 2,
        'joinedCount': 1,
        'declinedCount': 1,
        'pendingVerificationCount': 0,
        'verifiedCompleteCount': 1,
        'isPartial': false,
        'taskTitle': 'Siapkan keluarga',
      });

      expect(task.participation, ParticipationState.unresponded);
      expect(
        task.templateSnapshot.safetyInstruction,
        'Jangan mendekati air banjir.',
      );
      expect(recap.recordedResponseCount, 2);
      expect(recap.isPartial, isFalse);
      expect(recap.toString().contains('nonResponseCount'), isFalse);
    },
  );
}

final class _FakeVault implements ResidentSessionVault {
  _FakeVault(this.token);

  final String? token;

  @override
  Future<String?> read() async => token;

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
  String? lastSessionToken;
  bool failNextChoice = false;
  bool failNextCompletion = false;
  final List<String> choiceCommandIds = [];
  final List<String> completionCommandIds = [];

  @override
  Future<ResidentTaskList> listResidentActiveTasks({
    required String sessionToken,
  }) async {
    lastSessionToken = sessionToken;
    return const ResidentTaskList(items: [], isPartial: false);
  }

  @override
  Future<TaskResponseRecord> recordResidentTaskResponse({
    required String sessionToken,
    required String taskId,
    required ParticipationChoice choice,
    required String commandId,
  }) async {
    lastSessionToken = sessionToken;
    choiceCommandIds.add(commandId);
    if (failNextChoice) {
      failNextChoice = false;
      throw StateError('temporary network failure');
    }
    return TaskResponseRecord(
      taskId: taskId,
      participation: choice == ParticipationChoice.join
          ? ParticipationState.joined
          : ParticipationState.declined,
      completion: CompletionState.notSubmitted,
    );
  }

  @override
  Future<TaskResponseRecord> submitTaskCompletion({
    required String sessionToken,
    required String taskId,
    required String? note,
    required String commandId,
    String? evidenceId,
  }) async {
    lastSessionToken = sessionToken;
    completionCommandIds.add(commandId);
    if (failNextCompletion) {
      failNextCompletion = false;
      throw StateError('temporary network failure');
    }
    return TaskResponseRecord(
      taskId: taskId,
      participation: ParticipationState.joined,
      completion: CompletionState.pendingRtVerification,
      completionNote: note,
    );
  }

  @override
  Future<TaskVerificationQueue> listPendingVerifications() async =>
      const TaskVerificationQueue(items: [], isPartial: false);

  @override
  Future<TaskResponseRecord> verifyTaskCompletion({
    required String responseId,
    required String commandId,
  }) async => TaskResponseRecord(
    taskId: 'task-a',
    participation: ParticipationState.joined,
    completion: CompletionState.verifiedComplete,
  );

  @override
  Future<TaskResponseRecap> getResponseRecap({required String taskId}) async =>
      const TaskResponseRecap(
        taskId: 'task-a',
        rtId: 'rt-a',
        recordedResponseCount: 0,
        joinedCount: 0,
        declinedCount: 0,
        pendingVerificationCount: 0,
        verifiedCompleteCount: 0,
        isPartial: false,
        taskTitle: 'Task',
      );
}

final class _FakeEvidenceBoundary implements TaskEvidenceBoundary {
  String? sessionToken;
  String? requestId;
  Uint8List? uploadedBytes;
  final List<String> deleteCommandIds = [];
  bool failNextDelete = false;

  @override
  Future<String> uploadResidentTaskEvidence({
    required String sessionToken,
    required String taskId,
    required String requestId,
    required Uint8List sanitizedJpegBytes,
  }) async {
    this.sessionToken = sessionToken;
    this.requestId = requestId;
    uploadedBytes = sanitizedJpegBytes;
    return 'a' * 40;
  }

  @override
  Future<void> deleteResidentTaskEvidence({
    required String sessionToken,
    required String evidenceId,
    required String commandId,
  }) async {
    this.sessionToken = sessionToken;
    deleteCommandIds.add(commandId);
    if (failNextDelete) {
      failNextDelete = false;
      throw StateError('offline');
    }
  }

  @override
  Future<Uint8List> getTaskEvidenceForVerification({
    required String evidenceId,
  }) async => Uint8List.fromList([1, 2, 3]);
}
