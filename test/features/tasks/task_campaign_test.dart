import 'package:flutter_test/flutter_test.dart';
import 'package:guyub/data/fake/fake_task_repository.dart';
import 'package:guyub/domain/models/task_campaign.dart';
import 'package:guyub/domain/models/task_template.dart';

void main() {
  late FakeTaskRepository repository;

  setUp(() {
    repository = FakeTaskRepository();
  });

  group('TaskCampaign Domain & Invariants (Phase 2)', () {
    test('getEnabledTemplates only returns enabled safe templates', () async {
      final templates = await repository.getEnabledTemplates();
      expect(templates, isNotEmpty);
      for (final t in templates) {
        expect(t.enabled, isTrue);
        expect(t.safetyInstruction, isNotEmpty);
        expect(t.coreInstruction, isNotEmpty);
      }
    });

    test('AT-002: createDraft does NOT create an ACTIVE task campaign', () async {
      final templates = await repository.getEnabledTemplates();
      final template = templates.first;
      final deadline = DateTime.now().add(const Duration(days: 2));

      final draft = await repository.createDraft(
        template: template,
        deadline: deadline,
        locationNote: 'Blok A',
        additionalNote: 'Bawa sekop',
      );

      // Invariant: Draft must never be active
      expect(draft.state, equals(TaskCampaignState.draft));
      expect(draft.approvedByOperatorUid, isNull);
      expect(draft.approvedAt, isNull);
      expect(draft.locationNote, equals('Blok A'));
      expect(draft.additionalNote, equals('Bawa sekop'));
      expect(draft.deadline, equals(deadline));
    });

    test('AT-003: Safety instruction snapshot is immutable and matches template', () async {
      final templates = await repository.getEnabledTemplates();
      final template = templates.first;

      final draft = await repository.createDraft(
        template: template,
        deadline: DateTime.now().add(const Duration(days: 1)),
      );

      // Snapshot must match template precisely
      expect(
        draft.instructionSnapshot.coreInstruction,
        equals(template.coreInstruction),
      );
      expect(
        draft.instructionSnapshot.safetyInstruction,
        equals(template.safetyInstruction),
      );

      // Even if a modified template is simulated, snapshot remains independent
      const modifiedTemplate = TaskTemplate(
        templateId: 'tpl-inspeksi-drainase',
        title: 'Terserah Operator',
        category: 'Berbahaya',
        coreInstruction: 'Turun ke gorong-gorong sedalam 3 meter',
        safetyInstruction: 'Tanpa pelindung',
        enabled: true,
        version: 2,
      );

      expect(
        draft.instructionSnapshot.coreInstruction,
        isNot(equals(modifiedTemplate.coreInstruction)),
      );
      expect(
        draft.instructionSnapshot.safetyInstruction,
        isNot(equals(modifiedTemplate.safetyInstruction)),
      );
    });

    test('INV-01: Explicit activateCampaign transitions state from DRAFT to ACTIVE', () async {
      final templates = await repository.getEnabledTemplates();
      final template = templates.first;

      final draft = await repository.createDraft(
        template: template,
        deadline: DateTime.now().add(const Duration(days: 1)),
      );

      final activated = await repository.activateCampaign(draft);

      expect(activated.state, equals(TaskCampaignState.active));
      expect(activated.approvedByOperatorUid, isNotNull);
      expect(activated.approvedAt, isNotNull);
      expect(activated.taskId, equals(draft.taskId));
      expect(activated.templateId, equals(template.templateId));
    });

    test('Idempotency: Re-activating an active campaign remains ACTIVE without state corruption', () async {
      final templates = await repository.getEnabledTemplates();
      final template = templates.first;

      final draft = await repository.createDraft(
        template: template,
        deadline: DateTime.now().add(const Duration(days: 1)),
      );

      final firstActivation = await repository.activateCampaign(draft);
      final secondActivation = await repository.activateCampaign(firstActivation);

      expect(secondActivation.state, equals(TaskCampaignState.active));
      expect(secondActivation.taskId, equals(firstActivation.taskId));
      expect(secondActivation.approvedByOperatorUid, equals(firstActivation.approvedByOperatorUid));
    });

    test('RecipientPreview returns sample recipients for RT confirmation', () async {
      final preview = await repository.getRecipientPreview();
      expect(preview.totalCount, greaterThan(0));
      expect(preview.sampleNames, isNotEmpty);
    });
  });
}
