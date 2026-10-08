import 'package:flutter_test/flutter_test.dart';
import 'package:guyub/features/assistance/application/assistance_volunteer_boundary.dart';
import 'package:guyub/features/assistance/application/proxy_resident_boundary.dart';

final _residentId = List.filled(40, 'a').join();
final _taskId = List.filled(40, 'b').join();
const _communityId = 'rt-a';
String _repeat(String value, int count) => List.filled(count, value).join();
const _createdAt = '2026-10-06T12:00:00.000Z';

final class _FakeCreateRequestStore implements ProxyCreateRequestStore {
  PendingProxyResidentCreate? value;

  @override
  Future<PendingProxyResidentCreate?> read({
    required String communityId,
  }) async {
    if (value != null && value!.communityId != communityId) {
      throw const ProxyCreateRequestScopeMismatch();
    }
    return value;
  }

  @override
  Future<void> write(PendingProxyResidentCreate request) async {
    value = request;
  }

  @override
  Future<void> clear() async {
    value = null;
  }
}

final class _FakeBoundary implements ProxyResidentBoundary {
  bool failCreateOnce = true;
  bool commitBeforeCreateFailure = true;
  bool failStatusOnce = true;
  final calls = <Map<String, Object?>>[];
  final committedCreates = <String, ProxyResidentRecord>{};

  @override
  Future<ProxyResidentRecord> createProxyResident({
    required String nickname,
    required String? houseNumber,
    required bool needsAssistance,
    required bool residentConsentConfirmed,
    required String requestId,
  }) async {
    calls.add({
      'op': 'create',
      'requestId': requestId,
      'nickname': nickname,
      'houseNumber': houseNumber,
      'needsAssistance': needsAssistance,
      'deletionPending': false,
      'residentConsentConfirmed': residentConsentConfirmed,
    });
    final prior = committedCreates[requestId];
    if (prior != null) return prior;
    if (failCreateOnce) {
      failCreateOnce = false;
      if (commitBeforeCreateFailure) {
        committedCreates[requestId] = _resident(
          nickname: nickname,
          houseNumber: houseNumber,
        );
      }
      throw StateError('create response was unavailable');
    }
    final created = _resident(nickname: nickname, houseNumber: houseNumber);
    committedCreates[requestId] = created;
    return created;
  }

  @override
  Future<String> cancelPendingProxyResidentCreate({
    required String requestId,
  }) async => committedCreates.containsKey(requestId) ? 'CREATED' : 'CANCELLED';

  @override
  Future<ProxyResidentList> listProxyResidents() async =>
      ProxyResidentList(residents: [_resident()], isPartial: false);

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
  Future<ProxyAssistanceUpdate> updateProxyAssistance({
    required String residentId,
    required bool needsAssistance,
    required bool residentConsentConfirmed,
    required String commandId,
  }) async {
    calls.add({'op': 'assistance', 'commandId': commandId});
    return ProxyAssistanceUpdate(
      residentId: residentId,
      needsAssistance: needsAssistance,
    );
  }

  @override
  Future<void> deleteResidentData({
    required String residentId,
    required bool residentRequestConfirmed,
    required bool identityVerificationConfirmed,
    required String commandId,
  }) async {
    calls.add({'op': 'delete', 'commandId': commandId});
  }

  @override
  Future<VolunteerHelperList> listVolunteerHelpers() async =>
      VolunteerHelperList(items: const [], isPartial: false);

  @override
  Future<HelperAssignmentResult> createHelperAssignment({
    required String residentId,
    required String helperResidentId,
    required String commandId,
  }) async =>
      HelperAssignmentResult(assignmentId: _repeat('f', 40), state: 'OFFERED');

  @override
  Future<ProxyTaskStatusRecord> updateProxyTaskStatus({
    required String residentId,
    required String taskId,
    required String participationState,
    required bool completionReported,
    required bool residentConsentConfirmed,
    required String commandId,
  }) async {
    calls.add({'op': 'status', 'commandId': commandId});
    if (failStatusOnce) {
      failStatusOnce = false;
      throw StateError('temporary failure');
    }
    return ProxyTaskStatusRecord(
      taskId: taskId,
      participationState: participationState,
      completionState: completionReported
          ? 'PENDING_RT_VERIFICATION'
          : 'NOT_SUBMITTED',
    );
  }
}

ProxyResidentRecord _resident({
  String nickname = 'Warga A',
  String? houseNumber = '2A',
  bool needsAssistance = true,
}) => ProxyResidentRecord.fromWire({
  'residentId': _residentId,
  'nickname': nickname,
  'houseNumber': houseNumber,
  'needsAssistance': needsAssistance,
  'deletionPending': false,
  'createdAt': _createdAt,
});

void main() {
  test(
    'proxy profile parser accepts only minimal, bounded RT-private fields',
    () {
      final resident = _resident();
      expect(resident.nickname, 'Warga A');
      expect(resident.houseNumber, '2A');
      expect(resident.needsAssistance, isTrue);
      expect(
        () => ProxyResidentRecord.fromWire({
          'residentId': _residentId,
          'nickname': 'Warga A',
          'houseNumber': '2A',
          'needsAssistance': true,
          'deletionPending': false,
          'createdAt': _createdAt,
          'rtId': 'rt-b',
        }),
        throwsFormatException,
      );
      expect(
        () => ProxyResidentRecord.fromWire({
          'residentId': _residentId,
          'nickname': 'Warga A',
          'houseNumber': '2A',
          'needsAssistance': true,
          'deletionPending': false,
          'createdAt': _createdAt,
          'diagnosis': 'private medical details',
        }),
        throwsFormatException,
      );
      expect(
        () => ProxyResidentRecord.fromWire({
          'residentId': _residentId,
          'nickname': 'Warga A',
          'houseNumber': 'Jalan Mawar 12',
          'needsAssistance': true,
          'deletionPending': false,
          'createdAt': _createdAt,
        }),
        throwsFormatException,
      );
    },
  );

  test('proxy profile parser accepts real resident-session UUID IDs', () {
    final resident = ProxyResidentRecord.fromWire({
      'residentId': '550e8400-e29b-41d4-a716-446655440000',
      'nickname': 'Warga A',
      'houseNumber': null,
      'needsAssistance': false,
      'deletionPending': false,
      'createdAt': _createdAt,
    });
    expect(resident.residentId, '550e8400-e29b-41d4-a716-446655440000');
  });

  test(
    'proxy profile parser retains a pending deletion marker for safe retry',
    () {
      final pending = ProxyResidentRecord.fromWire({
        'residentId': _residentId,
        'nickname': 'Warga A',
        'houseNumber': null,
        'needsAssistance': false,
        'deletionPending': true,
        'createdAt': _createdAt,
      });
      expect(pending.deletionPending, isTrue);
    },
  );

  test('proxy profile listing rejects duplicate and malformed rows', () {
    final row = {
      'residentId': _residentId,
      'nickname': 'Warga A',
      'houseNumber': null,
      'needsAssistance': false,
      'deletionPending': false,
      'createdAt': _createdAt,
    };
    final partial = ProxyResidentList.fromWire({
      'items': [row],
      'isPartial': true,
    });
    expect(partial.residents, hasLength(1));
    expect(partial.isPartial, isTrue);
    expect(
      () => ProxyResidentList.fromWire({
        'items': [row, row],
        'isPartial': false,
      }),
      throwsFormatException,
    );
  });

  test(
    'proxy task status distinguishes no response from a declined choice',
    () {
      final unresponded = ProxyTaskStatusRecord.fromWire({
        'taskId': _taskId,
        'participationState': 'UNRESPONDED',
        'completionState': 'NOT_SUBMITTED',
      }, expectedTaskId: _taskId);
      expect(unresponded.participationState, 'UNRESPONDED');
      expect(
        () => ProxyTaskStatusRecord.fromWire({
          'taskId': _taskId,
          'participationState': 'UNRESPONDED',
          'completionState': 'NOT_SUBMITTED',
          'rtId': 'rt-b',
        }, expectedTaskId: _taskId),
        throwsFormatException,
      );
    },
  );

  test('pending create ID and payload survive controller restart', () async {
    final boundary = _FakeBoundary();
    final store = _FakeCreateRequestStore();
    final first = ProxyResidentController(
      boundary,
      createRequestStore: store,
      idFactory: () => _repeat('c', 48),
    );
    await expectLater(
      first.createProxyResident(
        communityId: _communityId,
        nickname: 'Warga A',
        houseNumber: null,
        needsAssistance: false,
        residentConsentConfirmed: true,
      ),
      throwsStateError,
    );
    expect(
      (await store.read(communityId: _communityId))?.requestId,
      _repeat('c', 48),
    );

    final afterRestart = ProxyResidentController(
      boundary,
      createRequestStore: store,
      idFactory: () => _repeat('d', 48),
    );
    await expectLater(
      afterRestart.createProxyResident(
        communityId: 'rt-b',
        nickname: 'Warga A',
        houseNumber: null,
        needsAssistance: false,
        residentConsentConfirmed: true,
      ),
      throwsA(isA<ProxyCreateRequestScopeMismatch>()),
    );
    expect(boundary.calls, hasLength(1));
    await afterRestart.createProxyResident(
      communityId: _communityId,
      nickname: 'Warga A',
      houseNumber: null,
      needsAssistance: false,
      residentConsentConfirmed: true,
    );
    expect(boundary.calls.map((call) => call['requestId']).toSet(), {
      _repeat('c', 48),
    });
    expect(boundary.committedCreates, hasLength(1));
    expect(await store.read(communityId: _communityId), isNull);
  });

  test(
    'pending create clears only after backend cancellation confirmation',
    () async {
      final boundary = _FakeBoundary()..commitBeforeCreateFailure = false;
      final store = _FakeCreateRequestStore();
      var idCounter = 0;
      final controller = ProxyResidentController(
        boundary,
        createRequestStore: store,
        idFactory: () => _repeat(idCounter++ == 0 ? 'c' : 'd', 48),
      );
      await expectLater(
        controller.createProxyResident(
          communityId: _communityId,
          nickname: 'Warga A',
          houseNumber: null,
          needsAssistance: false,
          residentConsentConfirmed: true,
        ),
        throwsStateError,
      );
      expect(
        await controller.cancelPendingProxyResidentCreate(
          communityId: _communityId,
        ),
        'CANCELLED',
      );
      expect(await store.read(communityId: _communityId), isNull);
      await controller.createProxyResident(
        communityId: _communityId,
        nickname: 'Warga B',
        houseNumber: null,
        needsAssistance: false,
        residentConsentConfirmed: true,
      );
      expect(boundary.committedCreates, hasLength(1));
    },
  );

  test(
    'confirmed create reconciliation clears local payload without resending',
    () async {
      final boundary = _FakeBoundary();
      final store = _FakeCreateRequestStore();
      final controller = ProxyResidentController(
        boundary,
        createRequestStore: store,
        idFactory: () => _repeat('c', 48),
      );
      await expectLater(
        controller.createProxyResident(
          communityId: _communityId,
          nickname: 'Warga A',
          houseNumber: null,
          needsAssistance: false,
          residentConsentConfirmed: true,
        ),
        throwsStateError,
      );
      expect(
        await controller.cancelPendingProxyResidentCreate(
          communityId: _communityId,
        ),
        'CREATED',
      );
      expect(await store.read(communityId: _communityId), isNull);
      expect(
        boundary.calls.where((call) => call['op'] == 'create'),
        hasLength(1),
      );
      expect(boundary.committedCreates, hasLength(1));
    },
  );

  test(
    'pending create rejects changed payload after uncertain response',
    () async {
      final boundary = _FakeBoundary();
      final store = _FakeCreateRequestStore();
      final first = ProxyResidentController(
        boundary,
        createRequestStore: store,
        idFactory: () => _repeat('c', 48),
      );
      await expectLater(
        first.createProxyResident(
          communityId: _communityId,
          nickname: 'Warga A',
          houseNumber: null,
          needsAssistance: false,
          residentConsentConfirmed: true,
        ),
        throwsStateError,
      );
      final afterRestart = ProxyResidentController(
        boundary,
        createRequestStore: store,
        idFactory: () => _repeat('d', 48),
      );
      await expectLater(
        afterRestart.createProxyResident(
          communityId: _communityId,
          nickname: 'Warga B',
          houseNumber: null,
          needsAssistance: false,
          residentConsentConfirmed: true,
        ),
        throwsStateError,
      );
      expect(boundary.calls, hasLength(1));
    },
  );

  test(
    'controller keeps task update id stable and rejects invalid status locally',
    () async {
      final boundary = _FakeBoundary();
      final ids = <String>[_repeat('e', 48), _repeat('f', 48)];
      final controller = ProxyResidentController(
        boundary,
        idFactory: () => ids.removeAt(0),
      );
      Future<ProxyTaskStatusRecord> update() =>
          controller.updateProxyTaskStatus(
            residentId: _residentId,
            taskId: _taskId,
            participationState: 'JOINED',
            completionReported: true,
            residentConsentConfirmed: true,
          );
      await expectLater(update(), throwsStateError);
      final result = await update();
      expect(result.completionState, 'PENDING_RT_VERIFICATION');
      expect(boundary.calls.map((call) => call['commandId']).toSet(), {
        _repeat('e', 48),
      });
      await expectLater(
        controller.updateProxyTaskStatus(
          residentId: _residentId,
          taskId: _taskId,
          participationState: 'PUNISHED',
          completionReported: false,
          residentConsentConfirmed: true,
        ),
        throwsArgumentError,
      );
    },
  );
}
