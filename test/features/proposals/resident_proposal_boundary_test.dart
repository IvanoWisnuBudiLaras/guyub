import 'package:flutter_test/flutter_test.dart';
import 'package:guyub/features/auth/application/resident_session_vault.dart';
import 'package:guyub/features/proposals/application/resident_proposal_boundary.dart';
import 'package:guyub/features/tasks/application/task_template.dart';

void main() {
  test(
    'resident proposal retries reuse the opaque ID for unchanged content',
    () async {
      final boundary = _FakeProposalBoundary()..failNextSubmit = true;
      final controller = ResidentProposalController(
        boundary: boundary,
        vault: _FakeVault(),
        requestStore: InMemoryResidentProposalRequestStore(),
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
          residentId: 'resident-1',
          communityId: 'rt-1',
          title: input['title']! as String,
          description: input['description']! as String,
          category: input['category']! as ResidentProposalCategory,
          locationReference: input['locationReference']! as String,
        ),
        throwsStateError,
      );
      await controller.submit(
        residentId: 'resident-1',
        communityId: 'rt-1',
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

  test('changed proposal content gets a new request ID', () async {
    final boundary = _FakeProposalBoundary()..failNextSubmit = true;
    final store = _FakeProposalRequestStore();
    var nextId = 0;
    final controller = ResidentProposalController(
      boundary: boundary,
      vault: _FakeVault(),
      requestStore: store,
      requestIdFactory: () => (++nextId == 1 ? 'r' : 's') * 40,
    );

    await expectLater(
      controller.submit(
        residentId: 'resident-1',
        communityId: 'rt-1',
        title: 'Persiapan rumah',
        description: 'Simpan barang penting di tempat aman.',
        category: ResidentProposalCategory.householdPreparation,
        locationReference: 'HOUSEHOLD',
      ),
      throwsStateError,
    );
    await controller.submit(
      residentId: 'resident-1',
      communityId: 'rt-1',
      title: 'Persiapan rumah',
      description: 'Siapkan kebutuhan keluarga.',
      category: ResidentProposalCategory.householdPreparation,
      locationReference: 'HOUSEHOLD',
    );

    expect(boundary.requestIds, ['r' * 40, 's' * 40]);
    expect(store.requests, isEmpty);
  });

  test('proposal retry metadata survives a new controller without saving proposal text', () async {
    final boundary = _FakeProposalBoundary()..failNextSubmit = true;
    final store = _FakeProposalRequestStore();
    final input = {
      'title': 'Persiapan rumah',
      'description': 'Simpan barang penting di tempat aman.',
      'category': ResidentProposalCategory.householdPreparation,
      'locationReference': 'HOUSEHOLD',
    };

    final firstController = ResidentProposalController(
      boundary: boundary,
      vault: _FakeVault(),
      requestStore: store,
      requestIdFactory: () => 'r' * 40,
    );
    await expectLater(
      firstController.submit(
        residentId: 'resident-1',
        communityId: 'rt-1',
        title: input['title']! as String,
        description: input['description']! as String,
        category: input['category']! as ResidentProposalCategory,
        locationReference: input['locationReference']! as String,
      ),
      throwsStateError,
    );

    expect(store.requests, hasLength(1));
    final stored = store.requests.values.single;
    expect(stored.requestId, 'r' * 40);
    expect(stored.payloadFingerprint, matches(RegExp(r'^[a-f0-9]{64}$')));
    expect(store.requests.keys.single, matches(RegExp(r'^[a-f0-9]{64}$')));

    final restartedController = ResidentProposalController(
      boundary: boundary,
      vault: _FakeVault(),
      requestStore: store,
      requestIdFactory: () => 'n' * 40,
    );
    await restartedController.submit(
      residentId: 'resident-1',
      communityId: 'rt-1',
      title: input['title']! as String,
      description: input['description']! as String,
      category: input['category']! as ResidentProposalCategory,
      locationReference: input['locationReference']! as String,
    );

    expect(boundary.requestIds, ['r' * 40, 'r' * 40]);
    expect(store.requests, isEmpty);
  });

  test(
    'confirmed resident deletion clears only that resident retry metadata',
    () async {
      final store = _FakeProposalRequestStore();
      final input = {
        'title': 'Persiapan rumah',
        'description': 'Simpan barang penting di tempat aman.',
        'category': ResidentProposalCategory.householdPreparation,
        'locationReference': 'HOUSEHOLD',
      };

      for (final resident in ['resident-1', 'resident-2']) {
        final controller = ResidentProposalController(
          boundary: _FakeProposalBoundary()..failNextSubmit = true,
          vault: _FakeVault(),
          requestStore: store,
          requestIdFactory: () =>
              resident == 'resident-1' ? 'r' * 40 : 's' * 40,
        );
        await expectLater(
          controller.submit(
            residentId: resident,
            communityId: 'rt-1',
            title: input['title']! as String,
            description: input['description']! as String,
            category: input['category']! as ResidentProposalCategory,
            locationReference: input['locationReference']! as String,
          ),
          throwsStateError,
        );
      }
      expect(
        store.requests.values.map((request) => request.requestId).toSet(),
        {'r' * 40, 's' * 40},
      );

      final cleanupController = ResidentProposalController(
        boundary: _FakeProposalBoundary(),
        vault: _FakeVault(),
        requestStore: store,
      );
      await cleanupController.clearPendingForResident(
        residentId: 'resident-1',
        communityId: 'rt-1',
      );

      expect(store.requests.values.single.requestId, 's' * 40);
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

  test(
    'proposal mapping command ID is stable across fresh controllers',
    () async {
      final boundary = _FakeProposalBoundary();
      final template = TaskTemplate(
        id: 'safe_household_prep',
        version: 2,
        title: 'Persiapan rumah',
        category: 'HOUSEHOLD_PREPARATION',
        coreInstruction: 'Simpan dokumen.',
        safetyInstruction: 'Jangan dekati air banjir.',
        enabled: true,
      );
      final deadline = DateTime.now().add(const Duration(days: 3));
      for (var attempt = 0; attempt < 2; attempt++) {
        final controller = ResidentProposalReviewController(
          boundary: boundary,
          commandIdFactory: () => 'random-never-used-' * 3,
        );
        await expectLater(
          controller.mapToDraft(
            proposalId: 'a' * 40,
            template: template,
            deadline: deadline,
            locationReference: 'HOUSEHOLD',
          ),
          throwsStateError,
        );
      }
      expect(boundary.mappingCommandIds, hasLength(2));
      expect(boundary.mappingCommandIds[0], boundary.mappingCommandIds[1]);
      expect(
        boundary.mappingCommandIds.first,
        matches(RegExp(r'^[a-f0-9]{64}$')),
      );
      final changedController = ResidentProposalReviewController(
        boundary: boundary,
      );
      await expectLater(
        changedController.mapToDraft(
          proposalId: 'a' * 40,
          template: template,
          deadline: deadline.add(const Duration(hours: 1)),
          locationReference: 'HOUSEHOLD',
        ),
        throwsStateError,
      );
      expect(
        boundary.mappingCommandIds[2],
        isNot(boundary.mappingCommandIds[0]),
      );
    },
  );

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

final class _FakeProposalRequestStore implements ResidentProposalRequestStore {
  final Map<String, PendingResidentProposalRequest> requests = {};

  @override
  Future<PendingResidentProposalRequest?> read({
    required String scopeHash,
  }) async => requests[scopeHash];

  @override
  Future<void> write({
    required String scopeHash,
    required PendingResidentProposalRequest request,
  }) async {
    requests[scopeHash] = request;
  }

  @override
  Future<void> clearIfMatches({
    required String scopeHash,
    required String requestId,
  }) async {
    if (requests[scopeHash]?.requestId == requestId) requests.remove(scopeHash);
  }
}

final class _FakeProposalBoundary implements ResidentProposalBoundary {
  bool failNextSubmit = false;
  bool failNextReview = false;
  final List<String> requestIds = [];
  final List<String> sessionTokens = [];
  final List<String> commandIds = [];
  final List<String> decisions = [];
  final List<String> states = [];
  final List<String> mappingCommandIds = [];

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

  @override
  Future<ResidentProposalDraftMapping> mapResidentProposalToDraft({
    required String proposalId,
    required String templateId,
    required int version,
    required DateTime deadline,
    required String? locationReference,
    required String commandId,
  }) async {
    mappingCommandIds.add(commandId);
    throw StateError('simulated lost mapping response');
  }
}
