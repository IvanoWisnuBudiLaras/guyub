import 'package:flutter_test/flutter_test.dart';
import 'package:guyub/features/tasks/application/task_campaign.dart';
import 'package:guyub/features/tasks/application/task_template.dart';
import 'package:guyub/features/tasks/application/task_response.dart';

void main() {
  final now = DateTime.utc(2026, 1, 1, 8);
  final deadline = now.add(const Duration(hours: 3));

  TaskTemplate template({
    bool enabled = true,
    String safety = 'Tetap di area aman.',
  }) => TaskTemplate(
    id: 'template-household-1',
    version: 3,
    title: 'Persiapan rumah tangga',
    category: 'household_preparation',
    coreInstruction: 'Amankan barang di dalam rumah.',
    safetyInstruction: safety,
    enabled: enabled,
    estimatedDurationMinutes: 30,
  );

  TaskCampaign draft({String communityId = 'rt-1'}) => TaskCampaign.createDraft(
    id: 'task-1',
    communityId: communityId,
    template: template(),
    createdByOperatorId: 'operator-1',
    createdAt: now,
    deadline: deadline,
    locationReference: 'HOUSEHOLD',
  );

  TaskCampaign activeCampaign() => draft().confirmAndActivate(
    operatorId: 'operator-1',
    operatorCommunityId: 'rt-1',
    confirmedAt: now,
    commandId: 'confirm-1',
  );

  group('TaskCampaign', () {
    test('draft snapshots controlled template content and safe parameters', () {
      final campaign = draft();

      expect(campaign.status, TaskCampaignStatus.draft);
      expect(campaign.templateSnapshot.templateId, 'template-household-1');
      expect(campaign.templateSnapshot.version, 3);
      expect(campaign.templateSnapshot.estimatedDurationMinutes, 30);
      expect(
        campaign.templateSnapshot.coreInstruction,
        'Amankan barang di dalam rumah.',
      );
      expect(
        campaign.templateSnapshot.safetyInstruction,
        'Tetap di area aman.',
      );
      expect(campaign.locationReference, 'HOUSEHOLD');
    });

    test('template edits cannot rewrite the campaign snapshot', () {
      final campaign = draft();
      final laterTemplate = TaskTemplate(
        id: 'template-household-1',
        version: 4,
        title: 'Revised title',
        category: 'household_preparation',
        coreInstruction: 'Revised instruction.',
        safetyInstruction: 'Revised safety text.',
        enabled: true,
      );

      expect(laterTemplate.version, 4);
      expect(campaign.templateSnapshot.version, 3);
      expect(
        campaign.templateSnapshot.coreInstruction,
        'Amankan barang di dalam rumah.',
      );
      expect(
        campaign.templateSnapshot.safetyInstruction,
        'Tetap di area aman.',
      );
    });

    test('estimated duration is optional but bounded when supplied', () {
      expect(
        () => TaskTemplate(
          id: 'template-household-1',
          version: 3,
          title: 'Persiapan rumah tangga',
          category: 'household_preparation',
          coreInstruction: 'Amankan barang di dalam rumah.',
          safetyInstruction: 'Tetap di area aman.',
          enabled: true,
          estimatedDurationMinutes: 481,
        ),
        throwsArgumentError,
      );
    });

    test('disabled or incomplete templates cannot produce a draft', () {
      expect(
        () => TaskCampaign.createDraft(
          id: 'task-1',
          communityId: 'rt-1',
          template: template(enabled: false),
          createdByOperatorId: 'operator-1',
          createdAt: now,
          deadline: deadline,
        ),
        throwsArgumentError,
      );
      expect(() => template(safety: '  '), throwsArgumentError);
    });

    test('only an explicit same-community operator confirmation activates', () {
      final pending = draft();
      expect(
        () => pending.confirmAndActivate(
          operatorId: 'operator-1',
          operatorCommunityId: 'rt-2',
          confirmedAt: now,
          commandId: 'confirm-1',
        ),
        throwsStateError,
      );

      final active = pending.confirmAndActivate(
        operatorId: 'operator-1',
        operatorCommunityId: 'rt-1',
        confirmedAt: now,
        commandId: 'confirm-1',
      );
      expect(active.status, TaskCampaignStatus.active);
      expect(active.approvedByOperatorId, 'operator-1');
      expect(
        identical(
          active.confirmAndActivate(
            operatorId: 'operator-1',
            operatorCommunityId: 'rt-1',
            confirmedAt: now,
            commandId: 'confirm-1',
          ),
          active,
        ),
        isTrue,
      );
      expect(
        () => active.confirmAndActivate(
          operatorId: 'operator-1',
          operatorCommunityId: 'rt-1',
          confirmedAt: now,
          commandId: 'confirm-2',
        ),
        throwsStateError,
      );
    });

    test('deadline and editable parameter bounds are validated', () {
      expect(
        () => TaskCampaign.createDraft(
          id: 'task-1',
          communityId: 'rt-1',
          template: template(),
          createdByOperatorId: 'operator-1',
          createdAt: now,
          deadline: now,
        ),
        throwsArgumentError,
      );
      expect(
        () => TaskCampaign.createDraft(
          id: 'task-1',
          communityId: 'rt-1',
          template: template(),
          createdByOperatorId: 'operator-1',
          createdAt: now,
          deadline: deadline,
          locationReference: 'Masuk ke saluran air untuk membersihkan sampah',
        ),
        throwsArgumentError,
      );
    });
  });

  group('TaskResponse', () {
    test('resident cannot respond to a draft campaign', () {
      final campaign = draft();
      final response = TaskResponse.unresponded(
        taskId: campaign.id,
        communityId: campaign.communityId,
        residentId: 'resident-1',
      );

      expect(
        () => response.chooseParticipation(
          ParticipationChoice.join,
          campaign: campaign,
        ),
        throwsStateError,
      );
    });

    test('resident can decline without creating a penalty state', () {
      final campaign = activeCampaign();
      final declined = TaskResponse.unresponded(
        taskId: campaign.id,
        communityId: campaign.communityId,
        residentId: 'resident-1',
      ).chooseParticipation(ParticipationChoice.decline, campaign: campaign);

      expect(declined.participation, ParticipationState.declined);
      expect(declined.completion, CompletionState.notSubmitted);
      expect(
        declined.chooseParticipation(
          ParticipationChoice.decline,
          campaign: campaign,
        ),
        same(declined),
      );
    });

    test('completion stays pending until same-community RT verification', () {
      final campaign = draft().confirmAndActivate(
        operatorId: 'operator-1',
        operatorCommunityId: 'rt-1',
        confirmedAt: now,
        commandId: 'confirm-1',
      );
      final response = TaskResponse.unresponded(
        taskId: campaign.id,
        communityId: campaign.communityId,
        residentId: 'resident-1',
      ).chooseParticipation(ParticipationChoice.join, campaign: campaign);
      final pending = response.submitCompletion(
        participantId: 'resident-1',
        campaign: campaign,
        submittedAt: now,
        note: 'Sudah dilakukan.',
      );

      expect(pending.completion, CompletionState.pendingRtVerification);
      expect(
        () => pending.verifyCompletion(
          operatorId: 'operator-1',
          operatorCommunityId: 'rt-2',
          verifiedAt: now,
        ),
        throwsStateError,
      );
      final verified = pending.verifyCompletion(
        operatorId: 'operator-1',
        operatorCommunityId: 'rt-1',
        verifiedAt: now,
      );
      expect(verified.completion, CompletionState.verifiedComplete);
      expect(verified.verifiedByOperatorId, 'operator-1');
      expect(
        identical(
          verified.verifyCompletion(
            operatorId: 'operator-2',
            operatorCommunityId: 'rt-1',
            verifiedAt: now,
          ),
          verified,
        ),
        isTrue,
      );
    });

    test(
      'completion submission rejects another resident and a declined task',
      () {
        final campaign = draft().confirmAndActivate(
          operatorId: 'operator-1',
          operatorCommunityId: 'rt-1',
          confirmedAt: now,
          commandId: 'confirm-1',
        );
        final joined = TaskResponse.unresponded(
          taskId: campaign.id,
          communityId: campaign.communityId,
          residentId: 'resident-1',
        ).chooseParticipation(ParticipationChoice.join, campaign: campaign);
        expect(
          () => joined.submitCompletion(
            participantId: 'resident-2',
            campaign: campaign,
            submittedAt: now,
          ),
          throwsStateError,
        );

        final declined = TaskResponse.unresponded(
          taskId: campaign.id,
          communityId: campaign.communityId,
          residentId: 'resident-2',
        ).chooseParticipation(ParticipationChoice.decline, campaign: campaign);
        expect(
          () => declined.submitCompletion(
            participantId: 'resident-2',
            campaign: campaign,
            submittedAt: now,
          ),
          throwsStateError,
        );
      },
    );
  });
}
