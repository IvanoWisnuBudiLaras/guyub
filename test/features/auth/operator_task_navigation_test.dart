import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guyub/app/router.dart';
import 'package:guyub/features/auth/application/operator_profile.dart';
import 'package:guyub/features/auth/presentation/screens/operator_home_screen.dart';
import 'package:guyub/features/tasks/application/task_campaign_boundary.dart';
import 'package:guyub/features/tasks/application/task_template.dart';

class _EmptyTaskBoundary implements TaskCampaignBoundary {
  const _EmptyTaskBoundary();

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

final class _ManagementOnlyBoundary extends _EmptyTaskBoundary
    implements TaskCampaignManagementBoundary {
  const _ManagementOnlyBoundary();

  @override
  Future<List<ActiveTaskCampaignRecord>> listActiveTaskCampaigns() async =>
      const [];

  @override
  Future<TaskCampaignCancellationRecord> cancelTaskCampaign({
    required String taskId,
    required String commandId,
  }) => throw UnimplementedError();
}

final class _ActiveTaskBoundary extends _EmptyTaskBoundary
    implements TaskCampaignManagementBoundary, TaskCampaignHistoryBoundary {
  const _ActiveTaskBoundary();

  @override
  Future<List<ActiveTaskCampaignRecord>> listActiveTaskCampaigns() async =>
      const [];

  @override
  Future<TaskCampaignCancellationRecord> cancelTaskCampaign({
    required String taskId,
    required String commandId,
  }) => throw UnimplementedError();

  @override
  Future<RtTaskHistoryPage> listRtTaskHistory({
    int pageSize = 25,
    String? cursor,
  }) async => const RtTaskHistoryPage(tasks: [], nextCursor: null);
}

void main() {
  testWidgets('verified operator can open the safe task catalog', (
    tester,
  ) async {
    const boundary = _EmptyTaskBoundary();
    final profile = OperatorProfile(
      uid: 'operator-a',
      communityId: 'rt-01',
      role: OperatorRole.ketuaRtRw,
      displayName: 'Ketua RT',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: OperatorHomeScreen(
          profile: profile,
          authBoundary: null,
          taskCampaignBoundary: boundary,
        ),
        onGenerateRoute: (settings) =>
            AppRouter.onGenerateRoute(settings, taskCampaignBoundary: boundary),
      ),
    );

    expect(find.text('Ketua RT/RW'), findsOneWidget);
    expect(find.text('RT rt-01'), findsOneWidget);
    expect(find.byKey(const Key('operator-task-history')), findsNothing);
    await tester.tap(find.byKey(const Key('operator-task-catalog')));
    await tester.pumpAndSettle();

    expect(find.text('Katalog Tugas Aman'), findsOneWidget);
    expect(
      find.textContaining('Belum ada template yang disetujui'),
      findsOneWidget,
    );
  });

  testWidgets('history entry is hidden without the history capability', (
    tester,
  ) async {
    const boundary = _ManagementOnlyBoundary();
    final profile = OperatorProfile(
      uid: 'operator-a',
      communityId: 'rt-01',
      role: OperatorRole.ketuaRtRw,
      displayName: 'Ketua RT',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: OperatorHomeScreen(
          profile: profile,
          authBoundary: null,
          taskCampaignBoundary: boundary,
        ),
      ),
    );

    expect(
      find.byKey(const Key('operator-active-task-campaigns')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('operator-task-history')), findsNothing);
  });

  testWidgets('operator can open RT task history from the home screen', (
    tester,
  ) async {
    const boundary = _ActiveTaskBoundary();
    final profile = OperatorProfile(
      uid: 'operator-a',
      communityId: 'rt-01',
      role: OperatorRole.ketuaRtRw,
      displayName: 'Ketua RT',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: OperatorHomeScreen(
          profile: profile,
          authBoundary: null,
          taskCampaignBoundary: boundary,
        ),
        onGenerateRoute: (settings) =>
            AppRouter.onGenerateRoute(settings, taskCampaignBoundary: boundary),
      ),
    );

    await tester.tap(find.byKey(const Key('operator-task-history')));
    await tester.pumpAndSettle();

    expect(find.text('Riwayat Tugas RT'), findsOneWidget);
    expect(find.byKey(const Key('task-history-empty')), findsOneWidget);
  });

  testWidgets('operator can reach server-scoped active task cancellation', (
    tester,
  ) async {
    const boundary = _ActiveTaskBoundary();
    final profile = OperatorProfile(
      uid: 'operator-a',
      communityId: 'rt-01',
      role: OperatorRole.ketuaRtRw,
      displayName: 'Ketua RT',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: OperatorHomeScreen(
          profile: profile,
          authBoundary: null,
          taskCampaignBoundary: boundary,
        ),
        onGenerateRoute: (settings) =>
            AppRouter.onGenerateRoute(settings, taskCampaignBoundary: boundary),
      ),
    );

    await tester.tap(find.byKey(const Key('operator-active-task-campaigns')));
    await tester.pumpAndSettle();

    expect(find.text('Tugas Aktif RT'), findsOneWidget);
    expect(find.byKey(const Key('active-task-empty')), findsOneWidget);
  });
}
