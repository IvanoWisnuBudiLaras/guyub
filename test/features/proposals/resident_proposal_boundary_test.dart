import 'package:flutter_test/flutter_test.dart';
import 'package:guyub/features/auth/application/resident_session_vault.dart';
import 'package:guyub/features/proposals/application/resident_proposal_boundary.dart';

void main() {
  test(
    'resident proposal retries reuse the opaque ID for unchanged content',
    () async {
      final boundary = _FakeProposalBoundary()..failNextSubmit = true;
      final controller = ResidentProposalController(
        boundary: boundary,
        vault: _FakeVault(),
        requestIdFactory: () => 'r' * 40,
      );
      final input = {
        'title': 'Persiapan rumah',
        'description': 'Simpan barang penting di tempat aman.',
        'category': ResidentProposalCategory.householdPreparation,
        'locationReference': 'HOUSEHOLD',
      };

      await expectLater(
        controller.submit(
          title: input['title']! as String,
          description: input['description']! as String,
          category: input['category']! as ResidentProposalCategory,
          locationReference: input['locationReference']! as String,
        ),
        throwsStateError,
      );
      await controller.submit(
        title: input['title']! as String,
        description: input['description']! as String,
        category: input['category']! as ResidentProposalCategory,
        locationReference: input['locationReference']! as String,
      );

      expect(boundary.requestIds, ['r' * 40, 'r' * 40]);
      expect(boundary.sessionTokens, ['opaque-token', 'opaque-token']);
      expect(boundary.states, ['SUBMITTED']);
    },
  );

  test('operator review retry reuses its command ID', () async {
    final boundary = _FakeProposalBoundary()..failNextReview = true;
    final controller = ResidentProposalReviewController(
      boundary: boundary,
      commandIdFactory: () => 'c' * 40,
    );

    await expectLater(controller.dismiss('p' * 40), throwsStateError);
    final result = await controller.dismiss('p' * 40);

    expect(result.state, 'DISMISSED');
    expect(boundary.commandIds, ['c' * 40, 'c' * 40]);
    expect(boundary.decisions, ['DISMISSED', 'DISMISSED']);
  });

  test('wire parser accepts NEEDS_OFFICIAL_REPORT and rejects unknown workflow states', () {
    final payload = _proposalWire();
    final official = ResidentProposalRecord.fromWire({
      ...payload,
      'state': 'NEEDS_OFFICIAL_REPORT',
      'reviewedAt': '2026-10-04T13:00:00.000Z',
    });
    expect(official.state, 'NEEDS_OFFICIAL_REPORT');
    expect(official.reviewedAt, isNotNull);

    expect(
      () => ResidentProposalRecord.fromWire({...payload, 'state': 'ACTIVE'}),
      throwsFormatException,
    );
    expect(
      () => ResidentProposalRecord.fromWire({
        ...payload,
        'locationReference': 'Masuk ke saluran air',
      }),
      throwsFormatException,
    );
  });

  test('operator review can mark proposal as NEEDS_OFFICIAL_REPORT with stable command ID', () async {
    final boundary = _FakeProposalBoundary()..failNextReview = true;
    final controller = ResidentProposalReviewController(
      boundary: boundary,
      commandIdFactory: () => 'cmd-official-001',
    );
    await expectLater(
      controller.markNeedsOfficialReport('a' * 40),
      throwsStateError,
    );
    final record = await controller.markNeedsOfficialReport('a' * 40);
    expect(record.state, 'NEEDS_OFFICIAL_REPORT');
    expect(boundary.decisions, [
      'NEEDS_OFFICIAL_REPORT',
      'NEEDS_OFFICIAL_REPORT',
    ]);
    expect(boundary.commandIds, ['cmd-official-001', 'cmd-official-001']);
  });
}

Map<String, Object?> _proposalWire({String state = 'SUBMITTED'}) => {
  'proposalId': 'a' * 40,
  'title': 'Persiapan rumah',
  'description': 'Simpan barang penting.',
  'category': 'HOUSEHOLD_PREPARATION',
  'locationReference': 'HOUSEHOLD',
  'state': state,
  'submittedAt': '2026-10-04T12:00:00.000Z',
};

final class _FakeVault implements ResidentSessionVault {
  @override
  Future<String?> read() async => 'opaque-token';

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
  bool failNextSubmit = false;
  bool failNextReview = false;
  final List<String> requestIds = [];
  final List<String> sessionTokens = [];
  final List<String> commandIds = [];
  final List<String> decisions = [];
  final List<String> states = [];

  ResidentProposalRecord _record({String state = 'SUBMITTED'}) =>
      ResidentProposalRecord.fromWire(_proposalWire(state: state));

  @override
  Future<ResidentProposalRecord> submitResidentProposal({
    required String sessionToken,
    required String title,
    required String description,
    required ResidentProposalCategory category,
    required String? locationReference,
    required String requestId,
  }) async {
    requestIds.add(requestId);
    sessionTokens.add(sessionToken);
    if (failNextSubmit) {
      failNextSubmit = false;
      throw StateError('simulated lost response');
    }
    states.add('SUBMITTED');
    return _record();
  }

  @override
  Future<ResidentProposalQueue> listResidentProposals() async =>
      const ResidentProposalQueue(items: [], isPartial: false);

  @override
  Future<ResidentProposalRecord> reviewResidentProposal({
    required String proposalId,
    required String decision,
    required String commandId,
  }) async {
    commandIds.add(commandId);
    decisions.add(decision);
    if (failNextReview) {
      failNextReview = false;
      throw StateError('simulated lost response');
    }
    return _record(state: decision);
  }
}
