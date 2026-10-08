import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guyub/features/auth/application/operator_profile.dart';
import 'package:guyub/features/auth/application/resident_session.dart';
import 'package:guyub/features/auth/application/resident_session_vault.dart';
import 'package:guyub/features/proposals/application/resident_proposal_boundary.dart';
import 'package:guyub/features/proposals/presentation/resident_proposal_review_screen.dart';
import 'package:guyub/features/proposals/presentation/resident_proposal_screen.dart';

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
      await tester.tap(find.byKey(const Key('proposal-dismiss-proposal-1')));
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
      await tester.tap(find.byKey(const Key('proposal-official-proposal-1')));
      await tester.pumpAndSettle();

      expect(boundary.lastDecision, 'NEEDS_OFFICIAL_REPORT');
      expect(boundary.activationCalls, 0);
    },
  );
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
  String? lastSessionToken;
  String? lastRequestId;
  String? lastDecision;
  String? lastCommandId;
  String lastState = 'SUBMITTED';

  ResidentProposalRecord _record({String state = 'SUBMITTED'}) =>
      ResidentProposalRecord(
        proposalId: 'proposal-1',
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
}
