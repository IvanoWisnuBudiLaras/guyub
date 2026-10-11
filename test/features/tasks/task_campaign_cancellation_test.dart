import 'package:flutter_test/flutter_test.dart';
import 'package:guyub/features/tasks/application/task_campaign_boundary.dart';
import 'package:guyub/features/tasks/application/task_template.dart';
import 'package:guyub/features/tasks/data/firebase_task_campaign_boundary.dart';

final _taskId = 'a' * 40;
const _templateId = 'household_ready';
final _deadline = DateTime.utc(2026, 10, 5, 12);

Map<String, Object?> _taskWire({
  String? taskId,
  String? locationReference = 'COMMUNITY_GENERAL_AREA',
}) => {
  'taskId': taskId ?? _taskId,
  'templateSnapshot': {
    'templateId': _templateId,
    'version': 2,
    'title': 'Persiapan rumah tangga',
    'category': 'HOUSEHOLD_PREPARATION',
    'coreInstruction': 'Simpan dokumen penting di tempat aman.',
    'safetyInstruction': 'Jangan mendekati air banjir.',
    'estimatedDurationMinutes': 30,
  },
  'deadline': _deadline.toIso8601String(),
  'locationReference': locationReference,
};

final class _CancelRetryBoundary
    implements TaskCampaignBoundary, TaskCampaignManagementBoundary {
  int failCount = 1;
  final List<String> taskIds = [];
  final List<String> commandIds = [];

  @override
  Future<List<ActiveTaskCampaignRecord>> listActiveTaskCampaigns() async =>
      ActiveTaskCampaignRecord.listFromWire({
        'tasks': [_taskWire()],
      });

  @override
  Future<TaskCampaignCancellationRecord> cancelTaskCampaign({
    required String taskId,
    required String commandId,
  }) async {
    taskIds.add(taskId);
    commandIds.add(commandId);
    if (failCount > 0) {
      failCount--;
      throw StateError('lost response');
    }
    return TaskCampaignCancellationRecord(taskId: taskId, status: 'CANCELLED');
  }

  @override
  Future<List<TaskTemplate>> listApprovedTemplates() async => const [];

  @override
  Future<TaskCampaignRecord> createDraft({
    required TaskTemplate template,
    required DateTime deadline,
    required String? locationReference,
    required String requestId,
  }) => throw UnimplementedError();

  @override
  Future<TaskCampaignRecord> activateCampaign({
    required String campaignId,
    required String commandId,
  }) => throw UnimplementedError();
}

void main() {
  test('strictly parses the active-task callable response', () {
    final tasks = ActiveTaskCampaignRecord.listFromWire({
      'tasks': [_taskWire()],
    });

    expect(tasks, hasLength(1));
    expect(tasks.single.taskId, _taskId);
    expect(tasks.single.templateSnapshot.title, 'Persiapan rumah tangga');
    expect(
      tasks.single.templateSnapshot.safetyInstruction,
      'Jangan mendekati air banjir.',
    );
    expect(tasks.single.deadline, _deadline);
    expect(tasks.single.locationReference, 'COMMUNITY_GENERAL_AREA');
  });

  test(
    'rejects extra response fields, malformed snapshots, and unsafe locations',
    () {
      expect(
        () => ActiveTaskCampaignRecord.listFromWire({
          'tasks': [_taskWire()],
          'residents': ['must never be exposed'],
        }),
        throwsFormatException,
      );

      final withResidentData = _taskWire()..['residentResponses'] = [];
      expect(
        () => ActiveTaskCampaignRecord.listFromWire({
          'tasks': [withResidentData],
        }),
        throwsFormatException,
      );

      final withUnknownLocation = _taskWire()
        ..['locationReference'] = 'Jalan Mawar No. 12';
      expect(
        () => ActiveTaskCampaignRecord.fromWire(withUnknownLocation),
        throwsFormatException,
      );

      final missingSafety = _taskWire();
      (missingSafety['templateSnapshot']! as Map<String, Object?>).remove(
        'safetyInstruction',
      );
      expect(
        () => ActiveTaskCampaignRecord.fromWire(missingSafety),
        throwsFormatException,
      );

      final unreviewedCategory = _taskWire();
      (unreviewedCategory['templateSnapshot']!
              as Map<String, Object?>)['category'] =
          'UNREVIEWED';
      expect(
        () => ActiveTaskCampaignRecord.fromWire(unreviewedCategory),
        throwsFormatException,
      );

      final malformedDeadline = _taskWire()..['deadline'] = '2026-10-05';
      expect(
        () => ActiveTaskCampaignRecord.fromWire(malformedDeadline),
        throwsFormatException,
      );
    },
  );

  test('validates cancellation status and returned task ID', () {
    expect(
      () => TaskCampaignCancellationRecord.fromWire({
        'taskId': _taskId,
        'status': 'ACTIVE',
      }, expectedTaskId: _taskId),
      throwsFormatException,
    );
    expect(
      () => TaskCampaignCancellationRecord.fromWire({
        'taskId': 'b' * 40,
        'status': 'CANCELLED',
      }, expectedTaskId: _taskId),
      throwsFormatException,
    );
  });

  test(
    'cancellation retries reuse a stable command ID for each task',
    () async {
      final boundary = _CancelRetryBoundary();
      var nextId = 0;
      final controller = TaskCampaignController(
        boundary,
        idFactory: () => (++nextId == 1 ? 'c' : 'd') * 40,
      );

      await expectLater(
        controller.cancelTaskCampaign(taskId: _taskId),
        throwsStateError,
      );
      final result = await controller.cancelTaskCampaign(taskId: _taskId);

      expect(result.status, 'CANCELLED');
      expect(boundary.commandIds, ['c' * 40, 'c' * 40]);
      expect(boundary.taskIds, [_taskId, _taskId]);
    },
  );

  test('Firebase adapter uses the exact active and cancellation callable contracts', () async {
    final calls = <(String, Map<String, Object?>)>[];
    final boundary = FirebaseTaskCampaignBoundary.withInvoker((
      name,
      data,
    ) async {
      calls.add((name, data));
      if (name == 'listActiveTaskCampaigns') {
        return {
          'tasks': [_taskWire()],
        };
      }
      return {'taskId': _taskId, 'status': 'CANCELLED'};
    });

    await boundary.listActiveTaskCampaigns();
    final cancelled = await boundary.cancelTaskCampaign(
      taskId: _taskId,
      commandId: 'c' * 40,
    );

    expect(cancelled.status, 'CANCELLED');
    expect(calls.map((call) => call.$1).toList(), [
      'listActiveTaskCampaigns',
      'cancelTaskCampaign',
    ]);
    expect(calls[0].$2, isEmpty);
    expect(calls[1].$2, {'taskId': _taskId, 'commandId': 'c' * 40});
  });
}
