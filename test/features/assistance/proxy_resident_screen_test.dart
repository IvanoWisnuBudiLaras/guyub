import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guyub/features/assistance/application/assistance_volunteer_boundary.dart';
import 'package:guyub/features/assistance/application/proxy_resident_boundary.dart';
import 'package:guyub/features/assistance/presentation/proxy_resident_screen.dart';
import 'package:guyub/features/auth/application/operator_profile.dart';
import 'package:guyub/features/tasks/application/task_campaign_boundary.dart';
import 'package:guyub/features/tasks/application/task_template.dart';

final _residentId = List.filled(40, 'a').join();
final _taskId = List.filled(40, 'b').join();

final class _ProxyBoundary implements ProxyResidentBoundary {
  final residents = <ProxyResidentRecord>[
    ProxyResidentRecord.fromWire({
      'residentId': _residentId,
      'nickname': 'Nenek Sari',
      'houseNumber': '12A',
      'needsAssistance': true,
      'deletionPending': false,
      'createdAt': '2026-10-06T12:00:00.000Z',
    }),
  ];
  final calls = <String, Object?>{};
  bool partial = false;
  bool failDeleteOnce = false;
  bool failCreateAfterCommitOnce = false;
  final createdByRequestId = <String, ProxyResidentRecord>{};
  VolunteerHelperList helpers = VolunteerHelperList(
    items: const [],
    isPartial: false,
  );

  @override
  Future<String> cancelPendingProxyResidentCreate({
    required String requestId,
  }) async =>
      createdByRequestId.containsKey(requestId) ? 'CREATED' : 'CANCELLED';

  @override
  Future<ProxyResidentList> listProxyResidents() async =>
      ProxyResidentList(residents: residents, isPartial: partial);

  @override
  Future<ProxyTaskStatusRecord> getProxyTaskStatus({
    required String residentId,
    required String taskId,
  }) async {
    calls['statusReadCount'] = (calls['statusReadCount'] as int? ?? 0) + 1;
    return ProxyTaskStatusRecord(
      taskId: taskId,
      participationState:
          calls['participationState'] as String? ?? 'UNRESPONDED',
      completionState: calls['completionState'] as String? ?? 'NOT_SUBMITTED',
    );
  }

  @override
  Future<ProxyResidentRecord> createProxyResident({
    required String nickname,
    required String? houseNumber,
    required bool needsAssistance,
    required bool residentConsentConfirmed,
    required String requestId,
  }) async {
    calls['created'] = true;
    calls['consent'] = residentConsentConfirmed;
    calls['createCount'] = (calls['createCount'] as int? ?? 0) + 1;
    final existing = createdByRequestId[requestId];
    if (existing != null) return existing;
    final result = ProxyResidentRecord(
      residentId: List.filled(40, 'c').join(),
      nickname: nickname.trim(),
      houseNumber: houseNumber,
      needsAssistance: needsAssistance,
      createdAt: DateTime.utc(2026, 10, 6, 12),
    );
    createdByRequestId[requestId] = result;
    residents.add(result);
    if (failCreateAfterCommitOnce) {
      failCreateAfterCommitOnce = false;
      throw StateError('server committed but response was lost');
    }
    return result;
  }

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
  }) async {
    calls['deleted'] = residentId;
    calls['residentRequestConfirmed'] = residentRequestConfirmed;
    calls['identityVerificationConfirmed'] = identityVerificationConfirmed;
    if (failDeleteOnce) {
      failDeleteOnce = false;
      final index = residents.indexWhere(
        (item) => item.residentId == residentId,
      );
      final current = residents[index];
      residents[index] = ProxyResidentRecord(
        residentId: current.residentId,
        nickname: current.nickname,
        houseNumber: null,
        needsAssistance: false,
        deletionPending: true,
        createdAt: current.createdAt,
      );
      throw StateError('storage cleanup still pending');
    }
  }

  @override
  Future<VolunteerHelperList> listVolunteerHelpers() async => helpers;

  @override
  Future<HelperAssignmentResult> createHelperAssignment({
    required String residentId,
    required String helperResidentId,
    required String commandId,
  }) async {
    calls['assignedResidentId'] = residentId;
    calls['assignedHelperId'] = helperResidentId;
    return HelperAssignmentResult(
      assignmentId: List.filled(40, 'f').join(),
      state: 'OFFERED',
    );
  }

  @override
  Future<ProxyTaskStatusRecord> updateProxyTaskStatus({
    required String residentId,
    required String taskId,
    required String participationState,
    required bool completionReported,
    required bool residentConsentConfirmed,
    required String commandId,
  }) async {
    calls['participationState'] = participationState;
    calls['taskId'] = taskId;
    calls['completionReported'] = completionReported;
    calls['consent'] = residentConsentConfirmed;
    calls['completionState'] = completionReported
        ? 'PENDING_RT_VERIFICATION'
        : 'NOT_SUBMITTED';
    return ProxyTaskStatusRecord(
      taskId: taskId,
      participationState: participationState,
      completionState: calls['completionState']! as String,
    );
  }
}

final class _ActiveTaskBoundary
    implements TaskCampaignBoundary, TaskCampaignManagementBoundary {
  const _ActiveTaskBoundary();

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
  @override
  Future<List<ActiveTaskCampaignRecord>> listActiveTaskCampaigns() async => [
    ActiveTaskCampaignRecord(
      taskId: _taskId,
      templateSnapshot: const TaskTemplateSnapshot(
        templateId: 'safe_household_prep',
        version: 1,
        title: 'Siapkan perlengkapan keluarga',
        category: 'HOUSEHOLD_PREPARATION',
        coreInstruction: 'Simpan dokumen penting.',
        safetyInstruction: 'Jangan mendekati aliran berbahaya.',
      ),
      deadline: DateTime.utc(2026, 10, 7),
      locationReference: null,
    ),
  ];
  @override
  Future<TaskCampaignCancellationRecord> cancelTaskCampaign({
    required String taskId,
    required String commandId,
  }) => throw UnimplementedError();
}

OperatorProfile _profile() => OperatorProfile(
  uid: 'operator-a',
  communityId: 'rt-a',
  role: OperatorRole.ketuaRtRw,
  displayName: 'Ketua RT',
);

void main() {
  testWidgets('proxy assistance list exposes only minimal operator fields', (
    tester,
  ) async {
    final boundary = _ProxyBoundary();
    await tester.pumpWidget(
      MaterialApp(
        home: ProxyResidentScreen(
          profile: _profile(),
          controller: ProxyResidentController(boundary),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Dukungan Warga RT'), findsOneWidget);
    expect(find.text('Nenek Sari'), findsOneWidget);
    expect(find.text('Nomor rumah 12A'), findsOneWidget);
    expect(find.byKey(const Key('proxy-assistance-marker')), findsOneWidget);
    expect(find.textContaining('diagnosis'), findsOneWidget);
    expect(find.textContaining('Alamat lengkap'), findsNothing);
  });

  testWidgets('shows a clear warning when the resident list is partial', (
    tester,
  ) async {
    final boundary = _ProxyBoundary()..partial = true;
    await tester.pumpWidget(
      MaterialApp(
        home: ProxyResidentScreen(
          profile: _profile(),
          controller: ProxyResidentController(boundary),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('proxy-resident-partial-warning')),
      findsOneWidget,
    );
    expect(find.textContaining('200 warga pertama'), findsOneWidget);
    expect(find.textContaining('Daftar belum lengkap'), findsOneWidget);
  });

  testWidgets('failed deletion refreshes to a locked retry state', (
    tester,
  ) async {
    final boundary = _ProxyBoundary()..failDeleteOnce = true;
    await tester.pumpWidget(
      MaterialApp(
        home: ProxyResidentScreen(
          profile: _profile(),
          controller: ProxyResidentController(boundary),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('proxy-resident-delete')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('proxy-delete-request-consent')));
    await tester.tap(find.byKey(const Key('proxy-delete-identity-check')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('proxy-delete-confirm')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('proxy-deletion-pending')), findsOneWidget);
    expect(find.text('Nomor rumah 12A'), findsNothing);
    expect(
      tester
          .widget<TextButton>(find.byKey(const Key('proxy-assistance-toggle')))
          .onPressed,
      isNull,
    );
    expect(find.text('Lanjutkan penghapusan'), findsOneWidget);
  });

  testWidgets('pending deletion remains visible only for retry', (
    tester,
  ) async {
    final boundary = _ProxyBoundary();
    boundary.residents
      ..clear()
      ..add(
        ProxyResidentRecord(
          residentId: _residentId,
          nickname: 'Nenek Sari',
          houseNumber: '12A',
          needsAssistance: true,
          deletionPending: true,
          createdAt: DateTime.utc(2026, 10, 6, 12),
        ),
      );
    await tester.pumpWidget(
      MaterialApp(
        home: ProxyResidentScreen(
          profile: _profile(),
          controller: ProxyResidentController(boundary),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('proxy-deletion-pending')), findsOneWidget);
    expect(find.text('Nomor rumah 12A'), findsNothing);
    final assistance = tester.widget<TextButton>(
      find.byKey(const Key('proxy-assistance-toggle')),
    );
    final delete = tester.widget<TextButton>(
      find.byKey(const Key('proxy-resident-delete')),
    );
    expect(assistance.onPressed, isNull);
    expect(delete.onPressed, isNotNull);
    expect(find.text('Lanjutkan penghapusan'), findsOneWidget);
  });

  testWidgets('RT offers help only to a resident who opted in', (tester) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final boundary = _ProxyBoundary()
      ..helpers = VolunteerHelperList(
        items: [
          VolunteerHelperRecord(
            residentId: List.filled(40, 'd').join(),
            nickname: 'Relawan Sari',
          ),
        ],
        isPartial: false,
      );
    await tester.pumpWidget(
      MaterialApp(
        home: ProxyResidentScreen(
          profile: _profile(),
          controller: ProxyResidentController(boundary),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('proxy-helper-assign')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Relawan Sari'), findsOneWidget);
    await tester.tap(find.byKey(const Key('proxy-helper-assign-confirm')));
    await tester.pumpAndSettle();
    expect(boundary.calls['assignedResidentId'], _residentId);
    expect(boundary.calls['assignedHelperId'], List.filled(40, 'd').join());
  });

  testWidgets('RT deletion requires request and offline identity checks', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final boundary = _ProxyBoundary();
    await tester.pumpWidget(
      MaterialApp(
        home: ProxyResidentScreen(
          profile: _profile(),
          controller: ProxyResidentController(boundary),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('proxy-resident-delete')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('proxy-delete-confirm')));
    await tester.pumpAndSettle();
    expect(boundary.calls['deleted'], isNull);
    await tester.tap(find.byKey(const Key('proxy-delete-request-consent')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('proxy-delete-identity-check')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('proxy-delete-confirm')));
    await tester.pumpAndSettle();
    expect(boundary.calls['deleted'], _residentId);
    expect(boundary.calls['residentRequestConfirmed'], isTrue);
    expect(boundary.calls['identityVerificationConfirmed'], isTrue);
  });

  testWidgets(
    'confirmed pending create clears local payload and reloads profile',
    (tester) async {
      final boundary = _ProxyBoundary()..failCreateAfterCommitOnce = true;
      final controller = ProxyResidentController(boundary);
      await tester.pumpWidget(
        MaterialApp(
          home: ProxyResidentScreen(
            profile: _profile(),
            controller: controller,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('proxy-resident-create')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('proxy-nickname')),
        'Warga Baru',
      );
      await tester.tap(find.byKey(const Key('proxy-consent-attestation')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('proxy-create-confirm')));
      await tester.pumpAndSettle();
      expect(boundary.calls['createCount'], 1);
      expect(find.byKey(const Key('proxy-create-retry-notice')), findsNothing);
      await tester.tap(find.widgetWithText(TextButton, 'Batal'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('proxy-resident-create')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('proxy-create-retry-notice')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('proxy-create-cancel-pending')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('proxy-create-cancel-confirm')));
      await tester.pumpAndSettle();

      expect(boundary.calls['createCount'], 1);
      expect(await controller.getPendingCreate(communityId: 'rt-a'), isNull);
      await tester.scrollUntilVisible(find.text('Warga Baru'), 200);
      expect(find.text('Warga Baru'), findsOneWidget);
    },
  );

  testWidgets('creating a proxy profile requires consent attestation', (
    tester,
  ) async {
    final boundary = _ProxyBoundary();
    await tester.pumpWidget(
      MaterialApp(
        home: ProxyResidentScreen(
          profile: _profile(),
          controller: ProxyResidentController(boundary),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('proxy-resident-create')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('proxy-nickname')),
      'Warga Baru',
    );
    await tester.tap(find.byKey(const Key('proxy-create-confirm')));
    await tester.pumpAndSettle();
    expect(boundary.calls['created'], isNull);
    expect(find.text('Catat warga tanpa aplikasi'), findsNWidgets(2));

    await tester.tap(find.byKey(const Key('proxy-consent-attestation')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('proxy-create-confirm')));
    await tester.pumpAndSettle();
    expect(boundary.calls['created'], isTrue);
    expect(boundary.calls['consent'], isTrue);
    await tester.scrollUntilVisible(find.text('Warga Baru'), 200);
    expect(find.text('Warga Baru'), findsOneWidget);
  });

  testWidgets(
    'proxy completion report stays pending until operator verification',
    (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final boundary = _ProxyBoundary();
      await tester.pumpWidget(
        MaterialApp(
          home: ProxyResidentScreen(
            profile: _profile(),
            controller: ProxyResidentController(boundary),
            taskCampaignController: TaskCampaignController(
              const _ActiveTaskBoundary(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(boundary.calls['statusReadCount'], isNull);
      await tester.tap(find.byKey(const Key('proxy-task-status-section')));
      await tester.pumpAndSettle();
      expect(boundary.calls['statusReadCount'], 1);
      expect(find.byKey(const Key('proxy-task-picker')), findsOneWidget);
      expect(
        find.text('Simpan dokumen penting.'),
        findsOneWidget,
        reason: 'Locked core instructions must be visible before proxy action.',
      );
      expect(
        find.text('Keselamatan: Jangan mendekati aliran berbahaya.'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('proxy-status-save')), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('proxy-status-save')))
            .onPressed,
        isNull,
      );

      Future<void> chooseParticipation(String label) async {
        await tester.tap(find.byKey(const Key('proxy-participation-picker')));
        await tester.pumpAndSettle();
        await tester.tap(find.text(label).last);
        await tester.pumpAndSettle();
      }

      await chooseParticipation('Ikut');
      await tester.tap(find.byKey(const Key('proxy-status-consent')));
      await tester.pumpAndSettle();
      await chooseParticipation('Tidak Ikut');
      expect(
        tester
            .widget<CheckboxListTile>(
              find.byKey(const Key('proxy-status-consent')),
            )
            .value,
        isFalse,
        reason: 'Changing the choice must clear consent for the prior choice.',
      );
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('proxy-status-save')))
            .onPressed,
        isNull,
      );
      await chooseParticipation('Ikut');
      await tester.tap(find.byKey(const Key('proxy-status-consent')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const Key('proxy-completion-reported')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('proxy-completion-reported')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<CheckboxListTile>(
              find.byKey(const Key('proxy-status-consent')),
            )
            .value,
        isFalse,
        reason: 'Changing completion status must require fresh consent.',
      );
      await tester.ensureVisible(find.byKey(const Key('proxy-status-consent')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('proxy-status-consent')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('proxy-status-save')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('proxy-status-save')));
      await tester.pumpAndSettle();

      expect(boundary.calls['participationState'], 'JOINED');
      expect(boundary.calls['taskId'], _taskId);
      expect(boundary.calls['completionReported'], isTrue);
      expect(boundary.calls['consent'], isTrue);
      expect(find.text('Laporan menunggu verifikasi RT.'), findsOneWidget);
    },
  );
}
