import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guyub/core/theme/app_theme.dart';
import 'package:guyub/core/widgets/guyub_bottom_nav_bar.dart';
import 'package:guyub/features/auth/application/operator_profile.dart';
import 'package:guyub/features/auth/presentation/screens/operator_home_screen.dart';
import 'package:guyub/features/tasks/application/task_campaign_boundary.dart';
import 'package:guyub/features/tasks/application/task_template.dart';
import 'package:guyub/features/tasks/presentation/screens/task_active_campaigns_screen.dart';

final class _FakeTaskBoundary
    implements
        TaskCampaignBoundary,
        TaskCampaignManagementBoundary,
        TaskCampaignHistoryBoundary,
        TaskCampaignLifecycleBoundary {
  @override
  Future<List<TaskTemplate>> listApprovedTemplates() async => const [];
  @override
  Future<TaskCampaignRecord> createDraft({
    required TaskTemplate template,
    required DateTime deadline,
    required String? locationReference,
    required String requestId,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<TaskCampaignRecord> activateCampaign({
    required String campaignId,
    required String commandId,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<List<ActiveTaskCampaignRecord>> listActiveTaskCampaigns() async =>
      const [];
  @override
  Future<TaskCampaignCancellationRecord> cancelTaskCampaign({
    required String taskId,
    required String commandId,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<TaskCampaignClosureRecord> closeTaskCampaign({
    required String taskId,
    required String commandId,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<List<RtTaskLifecycleEvent>> listTaskLifecycleEvents({
    required String taskId,
  }) async => const [];
  @override
  Future<RtTaskHistoryPage> listRtTaskHistory({
    int pageSize = 50,
    String? cursor,
  }) async => const RtTaskHistoryPage(tasks: [], nextCursor: null);
}

void main() {
  testWidgets('OperatorHomeScreen renders Tahap B3 improvements correctly', (
    tester,
  ) async {
    final profile = OperatorProfile(
      uid: 'op-123',
      communityId: 'rt-01-demo',
      role: OperatorRole.ketuaRtRw,
      displayName: 'Ketua RT 01 Kedungwaru',
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: OperatorHomeScreen(
          profile: profile,
          authBoundary: null,
          taskCampaignBoundary: _FakeTaskBoundary(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 1. Badge komunitas menampilkan nama manusiawi, bukan 'rt-01-demo'
    expect(find.text('RT 01 Kedungwaru'), findsOneWidget);
    expect(find.text('RT rt-01-demo'), findsNothing);

    // 2. Bottom nav menggunakan GuyubBottomNavBar dengan 3 tab
    expect(find.byType(GuyubBottomNavBar), findsOneWidget);
    expect(find.text('Beranda'), findsOneWidget);
    expect(find.text('Tugas'), findsOneWidget);
    expect(find.text('Darurat'), findsOneWidget);

    // 3. Menu operasional menggunakan grid 2-kolom kartu ikon
    expect(find.byKey(const Key('operator-task-catalog')), findsOneWidget);

    // 4. Beralih ke Tab Tugas (index 1)
    await tester.tap(find.text('Tugas'));
    await tester.pumpAndSettle();
    expect(find.byType(TaskActiveCampaignsScreen), findsOneWidget);
    expect(find.byKey(const Key('operator-appbar-history')), findsOneWidget);

    // 5. Beralih ke Tab Darurat (index 2)
    await tester.tap(find.text('Darurat'));
    await tester.pumpAndSettle();
    expect(find.text('Layanan Darurat Belum Terhubung'), findsOneWidget);
  });
}
