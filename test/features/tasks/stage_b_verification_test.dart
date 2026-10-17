import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guyub/features/assistance/application/assistance_volunteer_boundary.dart';
import 'package:guyub/features/assistance/application/proxy_resident_boundary.dart';
import 'package:guyub/features/assistance/presentation/proxy_resident_screen.dart';
import 'package:guyub/features/auth/application/operator_profile.dart';
import 'package:guyub/features/auth/application/resident_session.dart';
import 'package:guyub/features/auth/application/resident_session_vault.dart';
import 'package:guyub/features/proposals/application/resident_proposal_boundary.dart';
import 'package:guyub/features/proposals/presentation/resident_proposal_screen.dart';
import 'package:guyub/features/tasks/application/task_campaign_boundary.dart';
import 'package:guyub/features/tasks/presentation/screens/task_active_campaigns_screen.dart';
import 'package:guyub/features/tasks/presentation/screens/task_history_screen.dart';

import '../../helpers/pump_app.dart';

// --- Fakes for Testing ---

class _FailingCampaignBoundary implements TaskCampaignBoundary, TaskCampaignManagementBoundary {
  @override
  Future<List<ActiveTaskCampaignRecord>> listActiveTaskCampaigns() async {
    throw Exception('Simulated network error');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FailingHistoryBoundary implements TaskCampaignBoundary, TaskCampaignHistoryBoundary {
  @override
  Future<RtTaskHistoryPage> listRtTaskHistory({
    int pageSize = 25,
    String? cursor,
  }) async {
    throw Exception('Simulated history load failure');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _RecordingProxyBoundary implements ProxyResidentBoundary {
  _RecordingProxyBoundary({this.shouldFail = false, this.residents = const []});

  final bool shouldFail;
  final List<ProxyResidentRecord> residents;
  final List<String> calledMethods = [];

  @override
  Future<ProxyResidentList> listProxyResidents() async {
    calledMethods.add('listProxyResidents');
    if (shouldFail) {
      throw Exception('Simulated proxy load error');
    }
    return ProxyResidentList(residents: residents, isPartial: false);
  }

  @override
  Future<VolunteerHelperList> listVolunteerHelpers() async {
    calledMethods.add('listVolunteerHelpers');
    return VolunteerHelperList(items: const [], isPartial: false);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _DummyVault implements ResidentSessionVault {
  _DummyVault(this._token);
  final String? _token;

  @override
  Future<String?> read() async => _token;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _DummyProposalBoundary implements ResidentProposalBoundary {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  final operatorProfile = OperatorProfile(
    uid: 'operator-rt01',
    communityId: 'rt-01-demo',
    role: OperatorRole.ketuaRtRw,
    displayName: 'Ketua RT 01 Kedungwaru',
  );

  group('Tahap B — Invariant Button Width & Edge Margins (3 Screens)', () {
    testWidgets(
      'TaskActiveCampaignsScreen retry button has margin and does NOT touch screen edges',
      (tester) async {
        final boundary = _FailingCampaignBoundary();
        final controller = TaskCampaignController(
          boundary,
          idFactory: () => 'req-1',
        );

        await tester.pumpApp(
          TaskActiveCampaignsScreen(
            profile: operatorProfile,
            controller: controller,
          ),
          screenSize: const Size(400, 800),
        );
        await tester.pumpAndSettle();

        final retryFinder = find.byKey(const Key('active-task-retry'));
        expect(retryFinder, findsOneWidget);

        final buttonSize = tester.getSize(retryFinder);
        final topLeft = tester.getTopLeft(retryFinder);
        final topRight = tester.getTopRight(retryFinder);

        // Verifikasi tombol tidak menempel ke tepi layar (lebar < 350 dan margin kiri/kanan > 0)
        expect(buttonSize.width, lessThan(350), reason: 'Button should be shrink-wrapped inline');
        expect(topLeft.dx, greaterThan(20), reason: 'Button must have left margin from screen edge');
        expect(topRight.dx, lessThan(380), reason: 'Button must have right margin from screen edge');
      },
    );

    testWidgets(
      'TaskHistoryScreen retry button has margin and does NOT touch screen edges',
      (tester) async {
        final boundary = _FailingHistoryBoundary();
        final controller = TaskCampaignController(
          boundary,
          idFactory: () => 'req-hist-1',
        );

        await tester.pumpApp(
          TaskHistoryScreen(
            profile: operatorProfile,
            controller: controller,
          ),
          screenSize: const Size(400, 800),
        );
        await tester.pumpAndSettle();

        final retryFinder = find.byKey(const Key('task-history-retry'));
        expect(retryFinder, findsOneWidget);

        final buttonSize = tester.getSize(retryFinder);
        final topLeft = tester.getTopLeft(retryFinder);
        final topRight = tester.getTopRight(retryFinder);

        expect(buttonSize.width, lessThan(350), reason: 'Button should be shrink-wrapped inline');
        expect(topLeft.dx, greaterThan(20), reason: 'Button must have left margin from screen edge');
        expect(topRight.dx, lessThan(380), reason: 'Button must have right margin from screen edge');
      },
    );

    testWidgets(
      'ProxyResidentScreen retry button has 24px horizontal padding and does NOT touch screen edges',
      (tester) async {
        final boundary = _RecordingProxyBoundary(shouldFail: true);
        final controller = ProxyResidentController(
          boundary,
          idFactory: () => 'req-proxy-1',
        );

        await tester.pumpApp(
          ProxyResidentScreen(
            profile: operatorProfile,
            controller: controller,
          ),
          screenSize: const Size(400, 800),
        );
        await tester.pumpAndSettle();

        final retryFinder = find.byKey(const Key('proxy-resident-retry'));
        expect(retryFinder, findsOneWidget);

        final buttonSize = tester.getSize(retryFinder);
        final topLeft = tester.getTopLeft(retryFinder);
        final topRight = tester.getTopRight(retryFinder);

        expect(buttonSize.width, lessThan(350), reason: 'Button should be shrink-wrapped inline');
        expect(topLeft.dx, greaterThanOrEqualTo(24), reason: 'Padding horizontal >= 24');
        expect(topRight.dx, lessThanOrEqualTo(376), reason: 'Padding horizontal >= 24');
      },
    );
  });

  group('Tahap B — ProxyResidentScreen Data & Controller Verification', () {
    testWidgets(
      'ProxyResidentScreen calls listProxyResidents() and renders the 2 seeded residents',
      (tester) async {
        final seededResidents = [
          ProxyResidentRecord(
            residentId: 'proxy-mbah-supardi-000000000000000000000001',
            nickname: 'Mbah Supardi (DEMO)',
            houseNumber: '12',
            needsAssistance: true,
            createdAt: DateTime.utc(2026, 10, 17, 10),
          ),
          ProxyResidentRecord(
            residentId: 'proxy-ibu-aminah-00000000000000000000000002',
            nickname: 'Ibu Aminah (DEMO)',
            houseNumber: '05A',
            needsAssistance: true,
            createdAt: DateTime.utc(2026, 10, 17, 10),
          ),
        ];

        final boundary = _RecordingProxyBoundary(
          shouldFail: false,
          residents: seededResidents,
        );
        final controller = ProxyResidentController(
          boundary,
          idFactory: () => 'req-proxy-2',
        );

        await tester.pumpApp(
          ProxyResidentScreen(
            profile: operatorProfile,
            controller: controller,
          ),
          screenSize: const Size(400, 800),
        );
        await tester.pumpAndSettle();

        // 1. Konfirmasi method controller yang dipanggil adalah listProxyResidents
        expect(
          boundary.calledMethods,
          contains('listProxyResidents'),
          reason: 'ProxyResidentScreen must invoke listProxyResidents() controller method',
        );

        // 2. Bukti warga pertama tampil
        expect(find.text('Mbah Supardi (DEMO)'), findsOneWidget);
        expect(find.textContaining('Nomor rumah 12'), findsOneWidget);

        // 3. Scroll ke warga kedua dan buktikan tampil
        await tester.scrollUntilVisible(
          find.text('Ibu Aminah (DEMO)'),
          150,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();

        expect(find.text('Ibu Aminah (DEMO)'), findsOneWidget);
        expect(find.textContaining('Nomor rumah 05A'), findsOneWidget);
      },
    );
  });

  group('Tahap B — ResidentProposalScreen Layout Overlap Prevention', () {
    testWidgets(
      'Privacy helper text does not overlap with category dropdown at 360x640 and text scale 2.0',
      (tester) async {
        final controller = ResidentProposalController(
          boundary: _DummyProposalBoundary(),
          vault: _DummyVault('token-demo'),
          requestStore: InMemoryResidentProposalRequestStore(),
          requestIdFactory: () => 'req-prop-1',
        );

        final session = ResidentSession(
          residentId: 'res-budi-1',
          communityId: 'rt-01-demo',
          communityName: 'Kedungwaru',
          rtLabel: 'RT 01 / RW 02 Kedungwaru',
          nickname: 'Budi',
          expiresAt: DateTime.utc(2026, 10, 18),
        );

        // Render at 360x640 with text scale 2.0
        tester.view.physicalSize = const Size(360, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: const MediaQueryData(
                size: Size(360, 640),
                textScaler: TextScaler.linear(2.0),
              ),
              child: ResidentProposalScreen(
                session: session,
                controller: controller,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Scroll so description field and category dropdown enter viewport
        await tester.scrollUntilVisible(
          find.byKey(const Key('proposal-category')),
          100,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();

        final helperFinder = find.textContaining('Jangan masukkan NIK');
        final categoryFinder = find.byKey(const Key('proposal-category'));

        expect(helperFinder, findsOneWidget);
        expect(categoryFinder, findsOneWidget);

        final helperBottom = tester.getBottomLeft(helperFinder).dy;
        final categoryTop = tester.getTopLeft(categoryFinder).dy;

        // Zero vertical overlap assertion: bottom of helper text must be <= top of category dropdown
        expect(
          helperBottom,
          lessThanOrEqualTo(categoryTop),
          reason: 'Helper text (bottom: $helperBottom) must not overlap category dropdown (top: $categoryTop)',
        );
      },
    );
  });
}
