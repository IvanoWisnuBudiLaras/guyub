import 'package:flutter_test/flutter_test.dart';
import 'package:guyub/features/tasks/application/task_campaign_boundary.dart';
import 'package:guyub/features/tasks/application/task_template.dart';

final _template = TaskTemplate(
  id: 'household_ready',
  version: 1,
  title: 'Persiapan rumah tangga',
  category: 'HOUSEHOLD_PREPARATION',
  coreInstruction: 'Simpan dokumen penting.',
  safetyInstruction: 'Jangan mendekati air banjir.',
  enabled: true,
);

final class _RetryBoundary implements TaskCampaignBoundary {
  String? draftRequestId;
  String? activationCommandId;
  bool failDraftOnce = true;
  bool failActivationOnce = true;

  @override
  Future<List<TaskTemplate>> listApprovedTemplates() async => [_template];

  @override
  Future<TaskCampaignRecord> createDraft({
    required TaskTemplate template,
    required DateTime deadline,
    required String? locationReference,
    required String? additionalNote,
    required String requestId,
  }) async {
    draftRequestId = requestId;
    if (failDraftOnce) {
      failDraftOnce = false;
      throw StateError('simulated lost response');
    }
    return _record(status: 'DRAFT', deadline: deadline);
  }

  @override
  Future<TaskCampaignRecord> activateCampaign({
    required String campaignId,
    required String commandId,
  }) async {
    activationCommandId = commandId;
    if (failActivationOnce) {
      failActivationOnce = false;
      throw StateError('simulated lost response');
    }
    return _record(status: 'ACTIVE', deadline: DateTime.utc(2026, 10, 5));
  }

  TaskCampaignRecord _record({
    required String status,
    required DateTime deadline,
  }) => TaskCampaignRecord(
    campaignId: 'a' * 40,
    rtId: 'rt-01',
    templateSnapshot: _template.snapshot(),
    deadline: deadline,
    status: status,
    createdAt: DateTime.utc(2026, 10, 4),
  );
}

void main() {
  test(
    'draft retries reuse one idempotency key after a lost response',
    () async {
      final boundary = _RetryBoundary();
      final controller = TaskCampaignController(
        boundary,
        idFactory: () => 'r' * 40,
      );
      final deadline = DateTime.utc(2026, 10, 5);

      await expectLater(
        controller.createDraft(
          template: _template,
          deadline: deadline,
          locationReference: null,
          additionalNote: null,
        ),
        throwsStateError,
      );
      final record = await controller.createDraft(
        template: _template,
        deadline: deadline,
        locationReference: null,
        additionalNote: null,
      );

      expect(record.status, 'DRAFT');
      expect(boundary.draftRequestId, 'r' * 40);
    },
  );

  test(
    'activation retries reuse one command key after a lost response',
    () async {
      final boundary = _RetryBoundary();
      final controller = TaskCampaignController(
        boundary,
        idFactory: () => 'c' * 40,
      );

      await expectLater(
        controller.activateCampaign(campaignId: 'a' * 40),
        throwsStateError,
      );
      final record = await controller.activateCampaign(campaignId: 'a' * 40);

      expect(record.status, 'ACTIVE');
      expect(boundary.activationCommandId, 'c' * 40);
    },
  );

  test('malformed callable campaign data fails closed', () {
    expect(
      () => TaskCampaignRecord.fromWire({
        'campaignId': 'a' * 40,
        'rtId': 'rt-01',
        'templateSnapshot': {
          'templateId': 'household_ready',
          'version': 1,
          'title': 'Tugas',
          'category': 'HOUSEHOLD_PREPARATION',
          'coreInstruction': 'Petunjuk',
          'safetyInstruction': '',
        },
        'deadline': '2026-10-05T00:00:00.000Z',
        'status': 'DRAFT',
      }),
      throwsFormatException,
    );
  });
}
