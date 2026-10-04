import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guyub/app/router.dart';
import 'package:guyub/features/auth/application/operator_profile.dart';
import 'package:guyub/features/auth/presentation/screens/operator_home_screen.dart';
import 'package:guyub/features/tasks/application/task_campaign_boundary.dart';
import 'package:guyub/features/tasks/application/task_template.dart';

final class _EmptyTaskBoundary implements TaskCampaignBoundary {
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
    await tester.tap(find.byKey(const Key('operator-task-catalog')));
    await tester.pumpAndSettle();

    expect(find.text('Katalog Tugas Aman'), findsOneWidget);
    expect(
      find.textContaining('Belum ada template yang disetujui'),
      findsOneWidget,
    );
  });
}
