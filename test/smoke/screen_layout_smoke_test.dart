/// Smoke tests: setiap screen utama dibuka di bawah [AppTheme.light] dan
/// tidak boleh ada layout exception (khususnya dari tema global
/// minimumSize = double.infinity pada button di konteks unconstrained).
///
/// Tes ini TIDAK menguji logika bisnis. Hanya memastikan widget tree bisa
/// di-render tanpa error.
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:guyub/core/database/local_store.dart';
import 'package:guyub/core/result/result.dart';
import 'package:guyub/features/assistance/application/assistance_volunteer_boundary.dart';
import 'package:guyub/features/assistance/application/proxy_resident_boundary.dart';
import 'package:guyub/features/assistance/presentation/assistance_volunteer_screen.dart';
import 'package:guyub/features/assistance/presentation/proxy_resident_screen.dart';
import 'package:guyub/features/auth/application/operator_auth_boundary.dart';
import 'package:guyub/features/auth/application/operator_profile.dart';
import 'package:guyub/features/auth/application/resident_session.dart';
import 'package:guyub/features/auth/application/resident_session_boundary.dart';
import 'package:guyub/features/auth/application/resident_session_vault.dart';
import 'package:guyub/features/auth/application/resident_session_controller.dart';
import 'package:guyub/features/auth/presentation/screens/operator_home_screen.dart';
import 'package:guyub/features/auth/presentation/screens/operator_login_screen.dart';
import 'package:guyub/features/auth/presentation/screens/resident_entry_screen.dart';
import 'package:guyub/features/auth/presentation/screens/resident_session_home_screen.dart';
import 'package:guyub/features/auth/presentation/screens/role_selection_screen.dart';
import 'package:guyub/features/emergency/application/emergency_directory.dart';
import 'package:guyub/features/emergency/application/emergency_directory_boundary.dart';
import 'package:guyub/features/emergency/application/emergency_directory_controller.dart';
import 'package:guyub/features/emergency/data/emergency_directory_cache.dart';
import 'package:guyub/features/emergency/presentation/emergency_directory_screen.dart';
import 'package:guyub/features/evidence/application/task_evidence_boundary.dart';
import 'package:guyub/features/proposals/application/resident_proposal_boundary.dart';
import 'package:guyub/features/proposals/presentation/resident_proposal_review_screen.dart';
import 'package:guyub/features/proposals/presentation/resident_proposal_screen.dart';
import 'package:guyub/features/tasks/application/task_campaign_boundary.dart';
import 'package:guyub/features/tasks/application/task_response.dart';
import 'package:guyub/features/tasks/application/task_response_boundary.dart';
import 'package:guyub/features/tasks/application/task_template.dart';
import 'package:guyub/features/tasks/presentation/screens/task_active_campaigns_screen.dart';
import 'package:guyub/features/tasks/presentation/screens/task_campaign_confirmation_screen.dart';
import 'package:guyub/features/tasks/presentation/screens/task_catalog_screen.dart';
import 'package:guyub/features/tasks/presentation/screens/task_history_screen.dart';
import 'package:guyub/features/tasks/presentation/screens/task_response_screens.dart';
import 'package:guyub/features/weather/application/weather_suggestion.dart';
import 'package:guyub/features/weather/application/weather_suggestion_boundary.dart';
import 'package:guyub/features/weather/presentation/weather_suggestion_review_screen.dart';

import '../helpers/pump_app.dart';

// ---------------------------------------------------------------------------
// Shared Fixtures & Fakes
// ---------------------------------------------------------------------------

final _session = ResidentSession(
  residentId: 'r-1',
  communityId: 'c-1',
  communityName: 'Kel. Smoke',
  rtLabel: 'RT 99 / RW 01',
  nickname: 'Tester',
  expiresAt: DateTime.now().toUtc().add(const Duration(days: 1)),
);

final _profile = OperatorProfile(
  uid: 'op-1',
  communityId: 'c-1',
  displayName: 'Op Test',
  role: OperatorRole.ketuaRtRw,
);

final _template = TaskTemplate(
  id: 'household_ready',
  version: 1,
  title: 'Persiapan rumah tangga',
  category: 'HOUSEHOLD_PREPARATION',
  coreInstruction: 'Simpan dokumen penting di tempat aman.',
  safetyInstruction: 'Jangan mendekati air banjir atau kabel basah.',
  enabled: true,
  estimatedDurationMinutes: 30,
);

final _snapshot = TaskTemplateSnapshot(
  templateId: 'household_ready',
  version: 1,
  title: 'Persiapan rumah tangga',
  category: 'HOUSEHOLD_PREPARATION',
  coreInstruction: 'Simpan dokumen penting di tempat aman.',
  safetyInstruction: 'Jangan mendekati air banjir atau kabel basah.',
  estimatedDurationMinutes: 30,
);

final _campaignRecord = TaskCampaignRecord(
  campaignId: 'd' * 40,
  rtId: 'c-1',
  templateSnapshot: _snapshot,
  deadline: DateTime.now().add(const Duration(hours: 24)),
  status: 'DRAFT',
  createdAt: DateTime.now(),
  locationReference: 'HOUSEHOLD',
);

final _residentTask = ResidentTaskRecord(
  taskId: 'a' * 40,
  rtId: 'c-1',
  templateSnapshot: _snapshot,
  locationReference: 'HOUSEHOLD',
  deadline: DateTime.now().add(const Duration(hours: 12)),
  status: 'ACTIVE',
  participation: ParticipationState.joined,
  completion: CompletionState.pendingRtVerification,
);

final class _FakeLocalStore implements LocalStore {
  final _v = <String, String>{};
  @override
  Future<void> clear() async => _v.clear();
  @override
  Future<void> close() async {}
  @override
  Future<bool> containsKey(String k) async => _v.containsKey(k);
  @override
  Future<void> delete(String k) async => _v.remove(k);
  @override
  Future<String?> read(String k) async => _v[k];
  @override
  Future<void> write(String k, String v) async => _v[k] = v;
}

final class _FakeVault implements ResidentSessionVault {
  String? _token = 'smoke-test-token';
  @override
  Future<void> clear() async => _token = null;
  @override
  Future<void> clearPendingEnrollmentId() async {}
  @override
  Future<String?> read() async => _token;
  @override
  Future<String?> readPendingEnrollmentId() async => null;
  @override
  Future<void> write(String t) async => _token = t;
  @override
  Future<void> writePendingEnrollmentId(String id) async {}
}

final class _FakeEmergencyBoundary implements EmergencyDirectoryBoundary {
  @override
  Future<EmergencyDirectoryResponse> getEmergencyDirectory({
    required String sessionToken,
  }) async => EmergencyDirectoryResponse.fromWire(const {
    'state': 'CONFIGURED',
    'version': 1,
    'emergencyContacts': [
      {'label': 'BPBD Tulungagung', 'phoneNumber': '0355321199', 'order': 1},
    ],
    'assemblyPoints': [
      {
        'label': 'Balai Desa',
        'publicLocation': 'Jl. Pahlawan No. 1',
        'order': 1,
      },
    ],
    'officialReportChannels': [
      {
        'label': 'Website Pemkab',
        'uri': 'https://tulungagung.go.id',
        'channelType': 'WEBSITE',
        'order': 1,
      },
    ],
    'lastVerifiedAt': '2026-10-17T00:00:00.000Z',
  });
}

final class _FakeSessionBoundary implements ResidentSessionBoundary {
  @override
  Future<ResidentSessionGrant> createSession({
    required String joinCode,
    required String nickname,
    required String requestId,
  }) async => ResidentSessionGrant(session: _session, sessionToken: 't');
  @override
  Future<void> deleteOwnResidentData({
    required String sessionToken,
    required String residentId,
    required String communityId,
  }) async {}
  @override
  Future<void> revokeSession(String sessionToken) async {}
  @override
  Future<ResidentSession> validateSession(String sessionToken) async =>
      _session;
}

final class _FakeTaskBoundary
    implements
        TaskCampaignBoundary,
        TaskCampaignManagementBoundary,
        TaskCampaignHistoryBoundary,
        TaskCampaignLifecycleBoundary {
  @override
  Future<List<TaskTemplate>> listApprovedTemplates() async => [_template];
  @override
  Future<TaskCampaignRecord> createDraft({
    required TaskTemplate template,
    required DateTime deadline,
    required String? locationReference,
    required String requestId,
    String? customInstruction,
  }) async => _campaignRecord;
  @override
  Future<TaskCampaignRecord> activateCampaign({
    required String campaignId,
    required String commandId,
  }) async => _campaignRecord;
  @override
  Future<List<ActiveTaskCampaignRecord>> listActiveTaskCampaigns() async => [
    ActiveTaskCampaignRecord(
      taskId: 'a' * 40,
      templateSnapshot: _snapshot,
      deadline: DateTime.now().add(const Duration(hours: 6)),
      locationReference: 'HOUSEHOLD',
    ),
  ];
  @override
  Future<TaskCampaignCancellationRecord> cancelTaskCampaign({
    required String taskId,
    required String commandId,
  }) async =>
      TaskCampaignCancellationRecord(taskId: taskId, status: 'CANCELLED');
  @override
  Future<RtTaskHistoryPage> listRtTaskHistory({
    int pageSize = 25,
    String? cursor,
  }) async => const RtTaskHistoryPage(tasks: [], nextCursor: null);
  @override
  Future<List<RtTaskLifecycleEvent>> listTaskLifecycleEvents({
    required String taskId,
  }) async => const [];
  @override
  Future<TaskCampaignClosureRecord> closeTaskCampaign({
    required String taskId,
    required String commandId,
  }) async => TaskCampaignClosureRecord(taskId: taskId, status: 'CLOSED');
}

final class _FakeTaskResponseBoundary implements TaskResponseBoundary {
  @override
  Future<ResidentTaskList> listResidentActiveTasks({
    required String sessionToken,
  }) async => ResidentTaskList(items: [_residentTask], isPartial: false);
  @override
  Future<TaskResponseRecord> recordResidentTaskResponse({
    required String sessionToken,
    required String taskId,
    required ParticipationChoice choice,
    required String commandId,
  }) async => TaskResponseRecord(
    taskId: taskId,
    participation: ParticipationState.joined,
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
    completionNote: note,
    evidenceId: evidenceId,
  );
  @override
  Future<TaskVerificationQueue> listPendingVerifications() async =>
      TaskVerificationQueue(
        items: [
          TaskVerificationRecord(
            responseId: 'r-1',
            taskId: 'a' * 40,
            taskTitle: 'Persiapan keluarga',
            nickname: 'Pak Budi',
            submittedAt: DateTime.now(),
            completionNote: 'Selesai',
          ),
        ],
        isPartial: false,
      );
  @override
  Future<TaskResponseRecord> verifyTaskCompletion({
    required String responseId,
    required String commandId,
  }) async => TaskResponseRecord(
    taskId: 'a' * 40,
    participation: ParticipationState.joined,
    completion: CompletionState.verifiedComplete,
  );
  @override
  Future<TaskResponseRecap> getResponseRecap({required String taskId}) async =>
      TaskResponseRecap(
        taskId: taskId,
        rtId: 'c-1',
        recordedResponseCount: 10,
        joinedCount: 8,
        declinedCount: 2,
        pendingVerificationCount: 1,
        verifiedCompleteCount: 5,
        isPartial: false,
        taskTitle: 'Persiapan rumah tangga',
      );
}

final class _FakeEvidenceBoundary implements TaskEvidenceBoundary {
  @override
  Future<void> deleteResidentTaskEvidence({
    required String sessionToken,
    required String evidenceId,
    required String commandId,
  }) async {}
  @override
  Future<String> uploadResidentTaskEvidence({
    required String sessionToken,
    required String taskId,
    required String requestId,
    required Uint8List sanitizedJpegBytes,
  }) async => 'evidence-1';
  @override
  Future<Uint8List> getTaskEvidenceForVerification({
    required String evidenceId,
  }) async => Uint8List(0);
}

final class _FakeProposalBoundary implements ResidentProposalBoundary {
  @override
  Future<ResidentProposalRecord> submitResidentProposal({
    required String sessionToken,
    required String title,
    required String description,
    required ResidentProposalCategory category,
    required String? locationReference,
    required String requestId,
  }) async => ResidentProposalRecord(
    proposalId: 'p-1',
    title: title,
    description: description,
    category: category,
    locationReference: locationReference,
    state: 'SUBMITTED',
    submittedAt: DateTime.now(),
  );
  @override
  Future<ResidentProposalQueue> listResidentProposals() async =>
      const ResidentProposalQueue(items: [], isPartial: false);
  @override
  Future<ResidentProposalRecord> reviewResidentProposal({
    required String proposalId,
    required String decision,
    required String commandId,
  }) async => ResidentProposalRecord(
    proposalId: proposalId,
    title: 'Usulan',
    description: 'Penjelasan',
    category: ResidentProposalCategory.householdPreparation,
    state: decision,
    submittedAt: DateTime.now(),
  );
  @override
  Future<ResidentProposalDraftMapping> mapResidentProposalToDraft({
    required String proposalId,
    required String templateId,
    required int version,
    required DateTime deadline,
    required String? locationReference,
    required String commandId,
  }) async => ResidentProposalDraftMapping(
    proposalId: proposalId,
    state: 'DRAFTED',
    reviewedAt: DateTime.now(),
    campaign: _campaignRecord,
  );
  @override
  Future<List<ResidentProposalRecord>> listMyProposals({
    required String sessionToken,
  }) async => const [];
}

final class _FakeVolunteerBoundary implements AssistanceVolunteerBoundary {
  @override
  Future<ResidentVolunteerData> getVolunteerData({
    required String sessionToken,
  }) async => ResidentVolunteerData(
    willingToHelp: false,
    assignments: const [],
    isPartial: false,
  );
  @override
  Future<bool> updateVolunteerConsent({
    required String sessionToken,
    required bool willingToHelp,
    required bool residentConsentConfirmed,
    required String commandId,
  }) async => willingToHelp;
  @override
  Future<HelperAssignmentResult> respondToHelperAssignment({
    required String sessionToken,
    required String assignmentId,
    required String decision,
    required bool residentConsentConfirmed,
    required String commandId,
  }) async =>
      HelperAssignmentResult(assignmentId: assignmentId, state: decision);
}

final class _FakeProxyBoundary implements ProxyResidentBoundary {
  @override
  Future<String> cancelPendingProxyResidentCreate({
    required String requestId,
  }) async => 'CANCELLED';
  @override
  Future<ProxyResidentRecord> createProxyResident({
    required String nickname,
    required String? houseNumber,
    required bool needsAssistance,
    required bool residentConsentConfirmed,
    required String requestId,
  }) async => ProxyResidentRecord(
    residentId: 'p-1',
    nickname: nickname,
    houseNumber: houseNumber,
    needsAssistance: needsAssistance,
    createdAt: DateTime.now(),
  );
  @override
  Future<ProxyResidentList> listProxyResidents() async =>
      ProxyResidentList(residents: const [], isPartial: false);
  @override
  Future<VolunteerHelperList> listVolunteerHelpers() async =>
      VolunteerHelperList(items: const [], isPartial: false);
  @override
  Future<HelperAssignmentResult> createHelperAssignment({
    required String residentId,
    required String helperResidentId,
    required String commandId,
  }) async =>
      const HelperAssignmentResult(assignmentId: 'a-1', state: 'OFFERED');
  @override
  Future<ProxyTaskStatusRecord> getProxyTaskStatus({
    required String residentId,
    required String taskId,
  }) async => ProxyTaskStatusRecord(
    taskId: taskId,
    participationState: 'UNRESPONDED',
    completionState: 'NOT_SUBMITTED',
  );
  @override
  Future<ProxyTaskStatusRecord> updateProxyTaskStatus({
    required String residentId,
    required String taskId,
    required String participationState,
    required bool completionReported,
    required bool residentConsentConfirmed,
    required String commandId,
  }) async => ProxyTaskStatusRecord(
    taskId: taskId,
    participationState: participationState,
    completionState: 'NOT_SUBMITTED',
  );
  @override
  Future<ProxyAssistanceUpdate> updateProxyAssistance({
    required String residentId,
    required bool needsAssistance,
    required bool residentConsentConfirmed,
    required String commandId,
  }) async => ProxyAssistanceUpdate(
    residentId: residentId,
    needsAssistance: needsAssistance,
  );
  @override
  Future<void> deleteResidentData({
    required String residentId,
    required bool residentRequestConfirmed,
    required bool identityVerificationConfirmed,
    required String commandId,
  }) async {}
}

final class _FakeSuggestionBoundary implements WeatherSuggestionBoundary {
  @override
  Future<List<WeatherSuggestion>> listWeatherSuggestions() async => [
    WeatherSuggestion(
      id: 's-1',
      sourceSnapshotId: 'snap-1',
      ruleId: 'RULE_RAIN',
      recommendedTemplateIds: ['household_ready'],
      createdAt: DateTime.now(),
      explanation: 'Hujan lebat diprediksi terjadi.',
    ),
  ];
  @override
  Future<void> ignoreWeatherSuggestion({required String suggestionId}) async {}
}

final class _FakeAuthBoundary implements OperatorAuthBoundary {
  @override
  Future<Result<OperatorProfile>> signIn({
    required String email,
    required String password,
  }) async => Result.ok(_profile);
  @override
  Future<void> signOut() async {}
  @override
  Future<Result<OperatorProfile>> restoreCurrentSession() async =>
      Result.ok(_profile);
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('Smoke: Warga screens render under AppTheme without layout error', () {
    testWidgets('RoleSelectionScreen', (tester) async {
      await tester.pumpApp(const RoleSelectionScreen());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('ResidentEntryScreen', (tester) async {
      final controller = ResidentSessionController(
        boundary: _FakeSessionBoundary(),
        vault: _FakeVault(),
      );
      await tester.pumpApp(
        ResidentEntryScreen(controller: controller, onAuthenticated: (_) {}),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('EmergencyDirectoryScreen (authenticated)', (tester) async {
      final controller = EmergencyDirectoryController(
        boundary: _FakeEmergencyBoundary(),
        cache: EmergencyDirectoryCache(_FakeLocalStore()),
        vault: _FakeVault(),
      );
      await tester.pumpApp(
        EmergencyDirectoryScreen(controller: controller, session: _session),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      controller.dispose();
    });

    testWidgets('EmergencyDirectoryScreen (unauthenticated)', (tester) async {
      final controller = EmergencyDirectoryController(
        boundary: _FakeEmergencyBoundary(),
        cache: EmergencyDirectoryCache(_FakeLocalStore()),
        vault: _FakeVault(),
      );
      await tester.pumpApp(EmergencyDirectoryScreen(controller: controller));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      controller.dispose();
    });

    testWidgets('ResidentSessionHomeScreen (3 tabs: Beranda, Tugas, Darurat)', (
      tester,
    ) async {
      final vault = _FakeVault();
      final controller = ResidentSessionController(
        boundary: _FakeSessionBoundary(),
        vault: vault,
      );
      final emergencyController = EmergencyDirectoryController(
        boundary: _FakeEmergencyBoundary(),
        cache: EmergencyDirectoryCache(_FakeLocalStore()),
        vault: vault,
      );
      await tester.pumpApp(
        ResidentSessionHomeScreen(
          session: _session,
          controller: controller,
          emergencyDirectoryController: emergencyController,
        ),
      );
      await tester.pumpAndSettle();

      // Tab Beranda
      expect(tester.takeException(), isNull);

      // Tab Tugas
      await tester.tap(find.text('Tugas'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      // Tab Darurat
      await tester.tap(find.text('Darurat'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      emergencyController.dispose();
    });

    testWidgets('ResidentTaskListScreen', (tester) async {
      final controller = TaskResponseController(
        boundary: _FakeTaskResponseBoundary(),
        evidenceBoundary: _FakeEvidenceBoundary(),
        vault: _FakeVault(),
      );
      await tester.pumpApp(
        ResidentTaskListScreen(session: _session, controller: controller),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('ResidentTaskDetailScreen', (tester) async {
      final controller = TaskResponseController(
        boundary: _FakeTaskResponseBoundary(),
        evidenceBoundary: _FakeEvidenceBoundary(),
        vault: _FakeVault(),
      );
      await tester.pumpApp(
        ResidentTaskDetailScreen(
          session: _session,
          controller: controller,
          task: _residentTask,
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('ResidentProposalScreen', (tester) async {
      final controller = ResidentProposalController(
        boundary: _FakeProposalBoundary(),
        vault: _FakeVault(),
        requestStore: InMemoryResidentProposalRequestStore(),
      );
      await tester.pumpApp(
        ResidentProposalScreen(session: _session, controller: controller),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('AssistanceVolunteerScreen', (tester) async {
      final controller = AssistanceVolunteerController(
        boundary: _FakeVolunteerBoundary(),
        readSessionToken: () async => 'token',
      );
      await tester.pumpApp(
        AssistanceVolunteerScreen(session: _session, controller: controller),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group(
    'Smoke: Operator screens render under AppTheme without layout error',
    () {
      testWidgets('OperatorLoginScreen', (tester) async {
        await tester.pumpApp(
          OperatorLoginScreen(
            authBoundary: _FakeAuthBoundary(),
            onAuthenticated: (_) {},
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });

      testWidgets('OperatorHomeScreen', (tester) async {
        await tester.pumpApp(
          OperatorHomeScreen(
            profile: _profile,
            authBoundary: _FakeAuthBoundary(),
            taskCampaignBoundary: _FakeTaskBoundary(),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });

      testWidgets('TaskCatalogScreen', (tester) async {
        final controller = TaskCampaignController(_FakeTaskBoundary());
        await tester.pumpApp(
          TaskCatalogScreen(profile: _profile, controller: controller),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });

      testWidgets('TaskCampaignConfirmationScreen', (tester) async {
        final controller = TaskCampaignController(_FakeTaskBoundary());
        await tester.pumpApp(
          TaskCampaignConfirmationScreen(
            profile: _profile,
            campaign: _campaignRecord,
            controller: controller,
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });

      testWidgets('TaskActiveCampaignsScreen', (tester) async {
        final controller = TaskCampaignController(_FakeTaskBoundary());
        await tester.pumpApp(
          TaskActiveCampaignsScreen(profile: _profile, controller: controller),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });

      testWidgets('TaskHistoryScreen', (tester) async {
        final controller = TaskCampaignController(_FakeTaskBoundary());
        await tester.pumpApp(
          TaskHistoryScreen(profile: _profile, controller: controller),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });

      testWidgets('TaskVerificationQueueScreen', (tester) async {
        final controller = TaskResponseController(
          boundary: _FakeTaskResponseBoundary(),
          evidenceBoundary: _FakeEvidenceBoundary(),
          vault: _FakeVault(),
        );
        await tester.pumpApp(
          TaskVerificationQueueScreen(
            profile: _profile,
            controller: controller,
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });

      testWidgets('ResidentProposalReviewScreen', (tester) async {
        final controller = ResidentProposalReviewController(
          boundary: _FakeProposalBoundary(),
        );
        await tester.pumpApp(
          ResidentProposalReviewScreen(
            profile: _profile,
            controller: controller,
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });

      testWidgets('WeatherSuggestionReviewScreen', (tester) async {
        final controller = TaskCampaignController(_FakeTaskBoundary());
        await tester.pumpApp(
          WeatherSuggestionReviewScreen(
            profile: _profile,
            suggestionBoundary: _FakeSuggestionBoundary(),
            taskCampaignController: controller,
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });

      testWidgets('ProxyResidentScreen', (tester) async {
        final controller = ProxyResidentController(_FakeProxyBoundary());
        await tester.pumpApp(
          ProxyResidentScreen(profile: _profile, controller: controller),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    },
  );

  group('Smoke Tahap C: Responsive 360x640 and Text Scale 2.0 without layout exceptions', () {
    const smallScreen = Size(360, 640);
    const largeTextScale = 2.0;

    testWidgets('ResidentSessionHomeScreen under 360x640 and textScale 2.0', (
      tester,
    ) async {
      final vault = _FakeVault();
      final controller = ResidentSessionController(
        boundary: _FakeSessionBoundary(),
        vault: vault,
      );
      final emergencyController = EmergencyDirectoryController(
        boundary: _FakeEmergencyBoundary(),
        cache: EmergencyDirectoryCache(_FakeLocalStore()),
        vault: vault,
      );
      await tester.pumpApp(
        ResidentSessionHomeScreen(
          session: _session,
          controller: controller,
          emergencyDirectoryController: emergencyController,
        ),
        screenSize: smallScreen,
        textScaleFactor: largeTextScale,
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      emergencyController.dispose();
    });

    testWidgets('ResidentTaskListScreen under 360x640 and textScale 2.0', (
      tester,
    ) async {
      final controller = TaskResponseController(
        boundary: _FakeTaskResponseBoundary(),
        evidenceBoundary: _FakeEvidenceBoundary(),
        vault: _FakeVault(),
      );
      await tester.pumpApp(
        ResidentTaskListScreen(session: _session, controller: controller),
        screenSize: smallScreen,
        textScaleFactor: largeTextScale,
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('ResidentTaskDetailScreen under 360x640 and textScale 2.0', (
      tester,
    ) async {
      final controller = TaskResponseController(
        boundary: _FakeTaskResponseBoundary(),
        evidenceBoundary: _FakeEvidenceBoundary(),
        vault: _FakeVault(),
      );
      await tester.pumpApp(
        ResidentTaskDetailScreen(
          session: _session,
          controller: controller,
          task: _residentTask,
        ),
        screenSize: smallScreen,
        textScaleFactor: largeTextScale,
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('EmergencyDirectoryScreen under 360x640 and textScale 2.0', (
      tester,
    ) async {
      final controller = EmergencyDirectoryController(
        boundary: _FakeEmergencyBoundary(),
        cache: EmergencyDirectoryCache(_FakeLocalStore()),
        vault: _FakeVault(),
      );
      await tester.pumpApp(
        EmergencyDirectoryScreen(controller: controller, session: _session),
        screenSize: smallScreen,
        textScaleFactor: largeTextScale,
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      controller.dispose();
    });

    testWidgets('AssistanceVolunteerScreen under 360x640 and textScale 2.0', (
      tester,
    ) async {
      final controller = AssistanceVolunteerController(
        boundary: _FakeVolunteerBoundary(),
        readSessionToken: () async => 'token',
      );
      await tester.pumpApp(
        AssistanceVolunteerScreen(session: _session, controller: controller),
        screenSize: smallScreen,
        textScaleFactor: largeTextScale,
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('ResidentProposalScreen under 360x640 and textScale 2.0', (
      tester,
    ) async {
      final controller = ResidentProposalController(
        boundary: _FakeProposalBoundary(),
        vault: _FakeVault(),
        requestStore: InMemoryResidentProposalRequestStore(),
      );
      await tester.pumpApp(
        ResidentProposalScreen(session: _session, controller: controller),
        screenSize: smallScreen,
        textScaleFactor: largeTextScale,
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('OperatorHomeScreen under 360x640 and textScale 2.0', (
      tester,
    ) async {
      await tester.pumpApp(
        OperatorHomeScreen(
          profile: _profile,
          authBoundary: _FakeAuthBoundary(),
          taskCampaignBoundary: _FakeTaskBoundary(),
        ),
        screenSize: smallScreen,
        textScaleFactor: largeTextScale,
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('TaskCatalogScreen under 360x640 and textScale 2.0', (
      tester,
    ) async {
      final controller = TaskCampaignController(_FakeTaskBoundary());
      await tester.pumpApp(
        TaskCatalogScreen(profile: _profile, controller: controller),
        screenSize: smallScreen,
        textScaleFactor: largeTextScale,
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'TaskCampaignConfirmationScreen under 360x640 and textScale 2.0',
      (tester) async {
        final controller = TaskCampaignController(_FakeTaskBoundary());
        await tester.pumpApp(
          TaskCampaignConfirmationScreen(
            profile: _profile,
            campaign: _campaignRecord,
            controller: controller,
          ),
          screenSize: smallScreen,
          textScaleFactor: largeTextScale,
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('TaskActiveCampaignsScreen under 360x640 and textScale 2.0', (
      tester,
    ) async {
      final controller = TaskCampaignController(_FakeTaskBoundary());
      await tester.pumpApp(
        TaskActiveCampaignsScreen(profile: _profile, controller: controller),
        screenSize: smallScreen,
        textScaleFactor: largeTextScale,
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('TaskHistoryScreen under 360x640 and textScale 2.0', (
      tester,
    ) async {
      final controller = TaskCampaignController(_FakeTaskBoundary());
      await tester.pumpApp(
        TaskHistoryScreen(profile: _profile, controller: controller),
        screenSize: smallScreen,
        textScaleFactor: largeTextScale,
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('TaskVerificationQueueScreen under 360x640 and textScale 2.0', (
      tester,
    ) async {
      final controller = TaskResponseController(
        boundary: _FakeTaskResponseBoundary(),
        evidenceBoundary: _FakeEvidenceBoundary(),
        vault: _FakeVault(),
      );
      await tester.pumpApp(
        TaskVerificationQueueScreen(profile: _profile, controller: controller),
        screenSize: smallScreen,
        textScaleFactor: largeTextScale,
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'ResidentProposalReviewScreen under 360x640 and textScale 2.0',
      (tester) async {
        final controller = ResidentProposalReviewController(
          boundary: _FakeProposalBoundary(),
        );
        await tester.pumpApp(
          ResidentProposalReviewScreen(
            profile: _profile,
            controller: controller,
          ),
          screenSize: smallScreen,
          textScaleFactor: largeTextScale,
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'WeatherSuggestionReviewScreen under 360x640 and textScale 2.0',
      (tester) async {
        final controller = TaskCampaignController(_FakeTaskBoundary());
        await tester.pumpApp(
          WeatherSuggestionReviewScreen(
            profile: _profile,
            suggestionBoundary: _FakeSuggestionBoundary(),
            taskCampaignController: controller,
          ),
          screenSize: smallScreen,
          textScaleFactor: largeTextScale,
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('ProxyResidentScreen under 360x640 and textScale 2.0', (
      tester,
    ) async {
      final controller = ProxyResidentController(_FakeProxyBoundary());
      await tester.pumpApp(
        ProxyResidentScreen(profile: _profile, controller: controller),
        screenSize: smallScreen,
        textScaleFactor: largeTextScale,
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}
