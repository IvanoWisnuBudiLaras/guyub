import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
      'createdAt': '2026-10-06T12:00:00.000Z',
    }),
  ];
  final calls = <String, Object?>{};

  @override
  Future<List<ProxyResidentRecord>> listProxyResidents() async => residents;

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
    final result = ProxyResidentRecord(
      residentId: List.filled(40, 'c').join(),
      nickname: nickname.trim(),
      houseNumber: houseNumber,
      needsAssistance: needsAssistance,
      createdAt: DateTime.utc(2026, 10, 6, 12),
    );
    residents.add(result);
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
