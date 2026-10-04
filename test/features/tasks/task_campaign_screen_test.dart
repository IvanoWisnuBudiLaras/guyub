import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guyub/features/auth/application/operator_profile.dart';
import 'package:guyub/features/tasks/application/task_campaign_boundary.dart';
import 'package:guyub/features/tasks/application/task_campaign_copy_boundary.dart';
import 'package:guyub/features/tasks/application/task_template.dart';
import 'package:guyub/features/tasks/presentation/screens/task_catalog_screen.dart';
import 'package:guyub/features/tasks/presentation/screens/task_campaign_confirmation_screen.dart';

final _template = TaskTemplate(
  id: 'household_ready',
  version: 1,
  title: 'Persiapan rumah tangga',
  category: 'HOUSEHOLD_PREPARATION',
  coreInstruction: 'Simpan dokumen penting di tempat aman.',
  safetyInstruction: 'Jangan mendekati air banjir atau kabel yang basah.',
  enabled: true,
  estimatedDurationMinutes: 30,
);

final _profile = OperatorProfile(
  uid: 'operator-a',
  communityId: 'rt-01',
  role: OperatorRole.ketuaRtRw,
  displayName: 'Operator RT',
);

final class _FakeTaskBoundary implements TaskCampaignBoundary {
  _FakeTaskBoundary({List<TaskTemplate>? templates})
    : templates = templates ?? [_template];

  final List<TaskTemplate> templates;
  int draftCalls = 0;
  int activationCalls = 0;
  String? lastRequestId;
  String? lastCommandId;

  @override
  Future<List<TaskTemplate>> listApprovedTemplates() async => templates;

  @override
  Future<TaskCampaignRecord> createDraft({
    required TaskTemplate template,
    required DateTime deadline,
    required String? locationReference,
    required String requestId,
  }) async {
    draftCalls += 1;
    lastRequestId = requestId;
    return _campaign(
      deadline: deadline,
      status: 'DRAFT',
      locationReference: locationReference,
    );
  }

  @override
  Future<TaskCampaignRecord> activateCampaign({
    required String campaignId,
    required String commandId,
  }) async {
    activationCalls += 1;
    lastCommandId = commandId;
    return _campaign(
      deadline: DateTime.now().add(const Duration(hours: 1)),
      status: 'ACTIVE',
    );
  }

  TaskCampaignRecord _campaign({
    required DateTime deadline,
    required String status,
    String? locationReference,
  }) => TaskCampaignRecord(
    campaignId: 'a' * 40,
    rtId: 'rt-01',
    templateSnapshot: _template.snapshot(),
    deadline: deadline,
    status: status,
    createdAt: DateTime.now(),
    locationReference: locationReference,
  );
}

final class _FakeCopyBoundary implements TaskCampaignCopyBoundary {
  String? copiedText;

  @override
  Future<void> copy(String text) async {
    copiedText = text;
  }
}

Future<void> _selectTemplateAndCreateDraft(
  WidgetTester tester,
  _FakeTaskBoundary boundary,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: TaskCatalogScreen(
        profile: _profile,
        controller: TaskCampaignController(boundary, idFactory: () => 'r' * 40),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(
    find.byKey(const Key('task-template-household_ready-select')),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('task-select-deadline')));
  await tester.pumpAndSettle();
  await tester.tap(find.text('OK').last);
  await tester.pumpAndSettle();
  await tester.tap(find.text('OK').last);
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(
    find.byKey(const Key('task-create-draft')),
    200,
    scrollable: find.byType(Scrollable).last,
  );
  await tester.tap(find.byKey(const Key('task-create-draft')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('empty catalog does not offer free-form task creation', (
    tester,
  ) async {
    final boundary = _FakeTaskBoundary(templates: const []);
    await tester.pumpWidget(
      MaterialApp(
        home: TaskCatalogScreen(
          profile: _profile,
          controller: TaskCampaignController(boundary),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Belum ada template yang disetujui'),
      findsOneWidget,
    );
    expect(find.text('Buat tugas bebas'), findsNothing);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets(
    'locked instructions stay visible and activation needs explicit action',
    (tester) async {
      final boundary = _FakeTaskBoundary();
      await _selectTemplateAndCreateDraft(tester, boundary);

      expect(boundary.draftCalls, 1);
      expect(boundary.activationCalls, 0);
      expect(find.text('Periksa sebelum mengaktifkan'), findsOneWidget);
      expect(find.text('Instruksi template terkunci'), findsOneWidget);
      expect(find.text(_template.safetyInstruction), findsOneWidget);
      await tester.scrollUntilVisible(
        find.byKey(const Key('task-campaign-draft')),
        200,
        scrollable: find.byType(Scrollable).last,
      );
      expect(find.byKey(const Key('task-campaign-draft')), findsOneWidget);
      expect(find.byKey(const Key('task-copy-whatsapp')), findsNothing);
      expect(
        find.textContaining('Pemberitahuan otomatis belum tersedia'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('task-additional-note')), findsNothing);
      expect(find.byType(TextField), findsNothing);
      await tester.scrollUntilVisible(
        find.byKey(const Key('task-confirm-activation')),
        200,
        scrollable: find.byType(Scrollable).last,
      );

      await tester.tap(find.byKey(const Key('task-confirm-activation')));
      await tester.pumpAndSettle();

      expect(boundary.activationCalls, 1);
      expect(boundary.lastCommandId, 'r' * 40);
      expect(find.byKey(const Key('task-campaign-active')), findsOneWidget);
      expect(find.byKey(const Key('task-copy-whatsapp')), findsOneWidget);
      expect(find.text(_template.safetyInstruction), findsOneWidget);
    },
  );

  testWidgets('backing out of confirmation leaves the campaign as a draft', (
    tester,
  ) async {
    final boundary = _FakeTaskBoundary();
    await _selectTemplateAndCreateDraft(tester, boundary);
    expect(boundary.activationCalls, 0);

    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(boundary.activationCalls, 0);
    expect(find.text('Siapkan Draf Tugas'), findsOneWidget);
  });
  testWidgets(
    'active campaign copies a reviewed summary for manual WhatsApp sharing',
    (tester) async {
      final campaignBoundary = _FakeTaskBoundary();
      final copyBoundary = _FakeCopyBoundary();
      final campaign = TaskCampaignRecord(
        campaignId: 'a' * 40,
        rtId: 'internal-rt-id',
        templateSnapshot: _template.snapshot(),
        deadline: DateTime(2026, 10, 5, 17),
        status: 'ACTIVE',
        createdAt: DateTime(2026, 10, 4),
        locationReference: 'COMMUNITY_GENERAL_AREA',
      );
      await tester.pumpWidget(
        MaterialApp(
          home: TaskCampaignConfirmationScreen(
            profile: _profile,
            campaign: campaign,
            controller: TaskCampaignController(campaignBoundary),
            copyBoundary: copyBoundary,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.byKey(const Key('task-copy-whatsapp')),
        200,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('task-copy-whatsapp')), findsOneWidget);
      expect(campaignBoundary.activationCalls, 0);
      await tester.tap(find.byKey(const Key('task-copy-whatsapp')));
      await tester.pumpAndSettle();

      expect(copyBoundary.copiedText, isNotNull);
      expect(copyBoundary.copiedText, contains(_template.title));
      expect(copyBoundary.copiedText, contains(_template.coreInstruction));
      expect(copyBoundary.copiedText, contains(_template.safetyInstruction));
      expect(
        copyBoundary.copiedText,
        contains('Keikutsertaan bersifat sukarela'),
      );
      expect(copyBoundary.copiedText, contains('bukan peringatan resmi'));
      expect(copyBoundary.copiedText, isNot(contains('internal-rt-id')));
      expect(campaignBoundary.activationCalls, 0);
      expect(
        find.textContaining('Teks disalin. Periksa kembali'),
        findsOneWidget,
      );
    },
  );
}
