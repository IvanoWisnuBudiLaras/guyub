import 'package:flutter_test/flutter_test.dart';
import 'package:guyub/features/assistance/application/proxy_resident_boundary.dart';

final _residentId = List.filled(40, 'a').join();
final _taskId = List.filled(40, 'b').join();
String _repeat(String value, int count) => List.filled(count, value).join();
const _createdAt = '2026-10-06T12:00:00.000Z';

final class _FakeBoundary implements ProxyResidentBoundary {
  bool failCreateOnce = true;
  bool failStatusOnce = true;
  final calls = <Map<String, Object?>>[];

  @override
  Future<ProxyResidentRecord> createProxyResident({
    required String nickname,
    required String? houseNumber,
    required bool needsAssistance,
    required bool residentConsentConfirmed,
    required String requestId,
  }) async {
    calls.add({'op': 'create', 'requestId': requestId});
    if (failCreateOnce) {
      failCreateOnce = false;
      throw StateError('temporary failure');
    }
    return _resident(nickname: nickname, houseNumber: houseNumber);
  }

  @override
  Future<List<ProxyResidentRecord>> listProxyResidents() async => [_resident()];

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
          'createdAt': _createdAt,
        }),
        throwsFormatException,
      );
    },
  );

  test('proxy profile listing rejects duplicate and malformed rows', () {
    final row = {
      'residentId': _residentId,
      'nickname': 'Warga A',
      'houseNumber': null,
      'needsAssistance': false,
      'createdAt': _createdAt,
    };
    expect(
      ProxyResidentRecord.listFromWire({
        'items': [row],
        'isPartial': false,
      }),
      hasLength(1),
    );
    expect(
      () => ProxyResidentRecord.listFromWire({
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

  test('controller retains one create id through uncertain retries', () async {
    final boundary = _FakeBoundary();
    final ids = <String>[_repeat('c', 48), _repeat('d', 48)];
    final controller = ProxyResidentController(
      boundary,
      idFactory: () => ids.removeAt(0),
    );
    Future<ProxyResidentRecord> create() => controller.createProxyResident(
      nickname: 'Warga A',
      houseNumber: null,
      needsAssistance: false,
      residentConsentConfirmed: true,
    );
    await expectLater(create(), throwsStateError);
    await create();
    expect(boundary.calls.map((call) => call['requestId']).toSet(), {
      _repeat('c', 48),
    });
  });

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
