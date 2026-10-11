import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guyub/features/auth/application/operator_profile.dart';
import 'package:guyub/features/auth/application/resident_session.dart';
import 'package:guyub/features/auth/application/resident_session_vault.dart';
import 'package:guyub/features/proposals/application/resident_proposal_boundary.dart';
import 'package:guyub/features/proposals/presentation/resident_proposal_review_screen.dart';
import 'package:guyub/features/proposals/presentation/resident_proposal_screen.dart';
import 'package:guyub/features/tasks/application/task_campaign_boundary.dart';
import 'package:guyub/features/tasks/application/task_template.dart';

void main() {
  testWidgets('resident submission stays a proposal, not an active task', (
    tester,
  ) async {
    final boundary = _FakeProposalBoundary();
    final controller = ResidentProposalController(
      boundary: boundary,
      vault: _FakeVault('opaque-resident-session-token'),
      requestIdFactory: () => 'r' * 40,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: ResidentProposalScreen(
          session: _residentSession,
          controller: controller,
        ),
      ),
    );

    await tester.enterText(
      find.byKey(const Key('proposal-title')),
      'Bersihkan drainase',
    );
    await tester.enterText(
      find.byKey(const Key('proposal-description')),
      'Masuk ke saluran air untuk membersihkan sampah',
    );
    await tester.drag(find.byType(ListView).first, const Offset(0, -700));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('proposal-submit')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('proposal-submit')));
    await tester.pumpAndSettle();

    expect(boundary.submissionCalls, 1);
    expect(boundary.lastSessionToken, 'opaque-resident-session-token');
    expect(boundary.lastState, 'SUBMITTED');
    expect(boundary.lastRequestId, 'r' * 40);
    expect(find.byKey(const Key('proposal-submitted')), findsOneWidget);
    expect(find.text('Menunggu Tinjauan RT'), findsOneWidget);
    expect(find.textContaining('belum menjadi tugas'), findsOneWidget);
    expect(find.textContaining('tugas aktif'), findsOneWidget);
  });

  testWidgets(
    'proposal retry can show an already reviewed result without activation',
    (tester) async {
      final boundary = _FakeProposalBoundary(submissionState: 'DISMISSED');
      final controller = ResidentProposalController(
        boundary: boundary,
        vault: _FakeVault('opaque-resident-session-token'),
        requestIdFactory: () => 'r' * 40,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: ResidentProposalScreen(
            session: _residentSession,
            controller: controller,
          ),
        ),
      );
      await tester.enterText(find.byKey(const Key('proposal-title')), 'Usulan');
      await tester.enterText(
        find.byKey(const Key('proposal-description')),
        'Teks usulan yang sama.',
      );
      await tester.drag(find.byType(ListView).first, const Offset(0, -700));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('proposal-submit')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('proposal-submit')));
      await tester.pumpAndSettle();

      expect(find.text('Usulan telah ditinjau RT'), findsOneWidget);
      expect(find.textContaining('belum menjadi tugas'), findsOneWidget);
    },
  );

  testWidgets(
    'same-RT operator can close a submitted proposal without activation',
    (tester) async {
      final boundary = _FakeProposalBoundary(withQueueItem: true);
      final controller = ResidentProposalReviewController(
        boundary: boundary,
        commandIdFactory: () => 'c' * 40,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: ResidentProposalReviewScreen(
            profile: _operatorProfile,
            controller: controller,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Usulan bukan tugas aktif.'), findsOneWidget);
      expect(find.text('Tutup usulan'), findsOneWidget);
      expect(find.textContaining('Masuk ke saluran air'), findsOneWidget);
      await tester.tap(find.byKey(Key('proposal-dismiss-${'a' * 40}')));
      await tester.pumpAndSettle();

      expect(boundary.lastDecision, 'DISMISSED');
      expect(boundary.lastCommandId, 'c' * 40);
      expect(boundary.activationCalls, 0);
    },
  );

  testWidgets(
    'same-RT operator can mark a submitted proposal as needing official report without activation',
    (tester) async {
      final boundary = _FakeProposalBoundary(withQueueItem: true);
      final controller = ResidentProposalReviewController(
        boundary: boundary,
        commandIdFactory: () => 'off-${'c' * 36}',
      );
      await tester.pumpWidget(
        MaterialApp(
          home: ResidentProposalReviewScreen(
            profile: _operatorProfile,
            controller: controller,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Arahkan ke kanal resmi'), findsOneWidget);
      await tester.tap(find.byKey(Key('proposal-official-${'a' * 40}')));
      await tester.pumpAndSettle();

      expect(boundary.lastDecision, 'NEEDS_OFFICIAL_REPORT');
      expect(boundary.activationCalls, 0);
    },
  );

  testWidgets('proposal mapping creates DRAFT; separate action activates it', (
    tester,
  ) async {
    final proposalBoundary = _FakeProposalBoundary(withQueueItem: true);
    final taskBoundary = _FakeTaskCampaignBoundary();
    await tester.pumpWidget(
      MaterialApp(
        home: ResidentProposalReviewScreen(
          profile: _operatorProfile,
          controller: ResidentProposalReviewController(
            boundary: proposalBoundary,
          ),
          campaignController: TaskCampaignController(
            taskBoundary,
            idFactory: () => 'c' * 40,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key('proposal-map-${'a' * 40}')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.textContaining('Konteks usulan warga'), findsOneWidget);
    expect(find.textContaining('Isi usulan tidak disalin'), findsOneWidget);
    expect(
      find.textContaining('Masuk ke saluran air untuk membersihkan sampah'),
      findsNWidgets(2),
    );
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const Key('proposal-map-create-draft')),
          )
          .onPressed,
      isNull,
    );
    await tester.tap(find.byKey(const Key('proposal-map-template')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Persiapan rumah tangga').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byKey(const Key('proposal-map-location')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Tanpa lokasi khusus').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byKey(const Key('proposal-map-deadline')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('OK').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('OK').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const Key('proposal-map-create-draft')),
          )
          .onPressed,
      isNotNull,
    );
    await tester.tap(find.byKey(const Key('proposal-map-create-draft')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(proposalBoundary.mappingCalls, 1);
    expect(proposalBoundary.lastMappedTemplateId, 'safe_household_prep');
    expect(proposalBoundary.lastMappedLocation, isNull);
    expect(taskBoundary.activationCalls, 0);
    expect(find.text('Konfirmasi Aktivasi Tugas'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const Key('task-campaign-draft')),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.byKey(const Key('task-campaign-draft')), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const Key('task-confirm-activation')),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.byKey(const Key('task-confirm-activation')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(taskBoundary.activationCalls, 1);
    expect(find.byKey(const Key('task-campaign-active')), findsOneWidget);
  });
}

final _residentSession = ResidentSession(
  residentId: 'resident-1',
  communityId: 'rt-1',
  communityName: 'RT uji',
  rtLabel: '01',
  nickname: 'Warga Uji',
  expiresAt: DateTime.utc(2026, 10, 5),
);

final _operatorProfile = OperatorProfile(
  uid: 'operator-1',
  communityId: 'rt-1',
  role: OperatorRole.ketuaRtRw,
  displayName: 'Ketua RT',
);

final class _FakeVault implements ResidentSessionVault {
  _FakeVault(this.sessionToken);

  final String sessionToken;

  @override
  Future<String?> read() async => sessionToken;

  @override
  Future<void> write(String sessionToken) async {}

  @override
  Future<void> clear() async {}

  @override
  Future<void> writePendingEnrollmentId(String requestId) async {}

  @override
  Future<String?> readPendingEnrollmentId() async => null;

  @override
  Future<void> clearPendingEnrollmentId() async {}
}

final class _FakeProposalBoundary implements ResidentProposalBoundary {
  _FakeProposalBoundary({
    this.withQueueItem = false,
    this.submissionState = 'SUBMITTED',
  });

  final bool withQueueItem;
  final String submissionState;
  int submissionCalls = 0;
  int activationCalls = 0;
  int mappingCalls = 0;
  String? lastMappedTemplateId;
  String? lastMappedLocation;
  String? lastSessionToken;
  String? lastRequestId;
  String? lastDecision;
  String? lastCommandId;
  String lastState = 'SUBMITTED';

  ResidentProposalRecord _record({String state = 'SUBMITTED'}) =>
      ResidentProposalRecord(
        proposalId: 'a' * 40,
        title: 'Bersihkan drainase',
        description: 'Masuk ke saluran air untuk membersihkan sampah',
        category: ResidentProposalCategory.environmentalCleanup,
        state: state,
        submittedAt: DateTime.utc(2026, 10, 4),
        locationReference: 'COMMUNITY_GENERAL_AREA',
        submitterNickname: 'Warga Uji',
      );

  @override
  Future<ResidentProposalRecord> submitResidentProposal({
    required String sessionToken,
    required String title,
    required String description,
    required ResidentProposalCategory category,
    required String? locationReference,
    required String requestId,
  }) async {
    submissionCalls += 1;
    lastSessionToken = sessionToken;
    lastRequestId = requestId;
    lastState = submissionState;
    return _record(state: submissionState);
  }

  @override
  Future<ResidentProposalQueue> listResidentProposals() async =>
      ResidentProposalQueue(
        items: withQueueItem ? [_record()] : const [],
        isPartial: false,
      );

  @override
  Future<ResidentProposalRecord> reviewResidentProposal({
    required String proposalId,
    required String decision,
    required String commandId,
  }) async {
    lastDecision = decision;
    lastCommandId = commandId;
    return _record(state: decision);
  }

  @override
  Future<ResidentProposalDraftMapping> mapResidentProposalToDraft({
    required String proposalId,
    required String templateId,
    required int version,
    required DateTime deadline,
    required String? locationReference,
    required String commandId,
  }) async {
    mappingCalls++;
    lastMappedTemplateId = templateId;
    lastMappedLocation = locationReference;
    final template = TaskTemplate(
      id: templateId,
      version: version,
      title: 'Persiapan rumah tangga',
      category: 'HOUSEHOLD_PREPARATION',
      coreInstruction: 'Simpan dokumen penting.',
      safetyInstruction: 'Jangan dekati air banjir.',
      enabled: true,
    );
    final campaign = TaskCampaignRecord(
      campaignId: 'b' * 40,
      rtId: 'rt-1',
      templateSnapshot: template.snapshot(),
      deadline: deadline,
      status: 'DRAFT',
      createdAt: DateTime.now(),
      locationReference: locationReference,
    );
    return ResidentProposalDraftMapping(
      proposalId: proposalId,
      state: 'MAPPED_TO_SAFE_TEMPLATE',
      reviewedAt: DateTime.now(),
      campaign: campaign,
    );
  }
}

final class _FakeTaskCampaignBoundary implements TaskCampaignBoundary {
  int activationCalls = 0;
  final TaskTemplate template = TaskTemplate(
    id: 'safe_household_prep',
    version: 1,
    title: 'Persiapan rumah tangga',
    category: 'HOUSEHOLD_PREPARATION',
    coreInstruction: 'Simpan dokumen penting.',
    safetyInstruction: 'Jangan dekati air banjir.',
    enabled: true,
  );

  @override
  Future<List<TaskTemplate>> listApprovedTemplates() async => [template];

  TaskCampaignRecord _record({required String status}) => TaskCampaignRecord(
    campaignId: 'b' * 40,
    rtId: 'rt-1',
    templateSnapshot: template.snapshot(),
    deadline: DateTime.now().add(const Duration(days: 1)),
    status: status,
    createdAt: DateTime.now(),
    activatedAt: status == 'ACTIVE' ? DateTime.now() : null,
  );

  @override
  Future<TaskCampaignRecord> createDraft({
    required TaskTemplate template,
    required DateTime deadline,
    required String? locationReference,
    required String requestId,
  }) async => _record(status: 'DRAFT');

  @override
  Future<TaskCampaignRecord> activateCampaign({
    required String campaignId,
    required String commandId,
  }) async {
    activationCalls++;
    return _record(status: 'ACTIVE');
  }
}
