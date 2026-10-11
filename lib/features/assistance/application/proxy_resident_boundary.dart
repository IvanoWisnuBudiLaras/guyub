import 'dart:math';

import 'assistance_volunteer_boundary.dart';

final _residentIdPattern = RegExp(
  r'^(?:[a-f0-9]{40}|[a-f0-9]{8}-(?:[a-f0-9]{4}-){3}[a-f0-9]{12})$',
  caseSensitive: false,
);
final _taskIdPattern = RegExp(r'^[a-f0-9]{40}$');
final _commandIdPattern = RegExp(r'^[A-Za-z0-9_-]{32,128}$');

abstract interface class ProxyCreateRequestStore {
  Future<PendingProxyResidentCreate?> read({required String communityId});
  Future<void> write(PendingProxyResidentCreate request);
  Future<void> clear();
}

final class ProxyCreateRequestScopeMismatch implements Exception {
  const ProxyCreateRequestScopeMismatch();
}

final class PendingProxyResidentCreate {
  const PendingProxyResidentCreate({
    required this.communityId,
    required this.requestId,
    required this.nickname,
    required this.houseNumber,
    required this.needsAssistance,
    required this.residentConsentConfirmed,
  });

  final String communityId;
  final String requestId;
  final String nickname;
  final String? houseNumber;
  final bool needsAssistance;
  final bool residentConsentConfirmed;

  bool matches({
    required String nickname,
    required String? houseNumber,
    required bool needsAssistance,
    required bool residentConsentConfirmed,
  }) =>
      this.nickname == nickname &&
      this.houseNumber == houseNumber &&
      this.needsAssistance == needsAssistance &&
      this.residentConsentConfirmed == residentConsentConfirmed;
}

final class ProxyResidentList {
  ProxyResidentList({
    required List<ProxyResidentRecord> residents,
    required this.isPartial,
  }) : residents = List<ProxyResidentRecord>.unmodifiable(residents);

  final List<ProxyResidentRecord> residents;
  final bool isPartial;

  factory ProxyResidentList.fromWire(Object? value) {
    final wire = _strictMap(value);
    _onlyKeys(wire, const {'items', 'isPartial'});
    final items = wire['items'];
    if (items is! List || items.length > 200 || wire['isPartial'] is! bool) {
      throw const FormatException('Daftar warga tidak valid.');
    }
    final ids = <String>{};
    final residents = items.map(ProxyResidentRecord.fromWire).toList();
    if (residents.any((item) => !ids.add(item.residentId))) {
      throw const FormatException('Daftar warga tidak valid.');
    }
    return ProxyResidentList(
      residents: residents,
      isPartial: wire['isPartial']! as bool,
    );
  }
}

abstract interface class ProxyResidentBoundary {
  Future<ProxyResidentList> listProxyResidents();

  Future<ProxyTaskStatusRecord> getProxyTaskStatus({
    required String residentId,
    required String taskId,
  });

  Future<String> cancelPendingProxyResidentCreate({required String requestId});

  Future<ProxyResidentRecord> createProxyResident({
    required String nickname,
    required String? houseNumber,
    required bool needsAssistance,
    required bool residentConsentConfirmed,
    required String requestId,
  });

  Future<ProxyAssistanceUpdate> updateProxyAssistance({
    required String residentId,
    required bool needsAssistance,
    required bool residentConsentConfirmed,
    required String commandId,
  });

  Future<void> deleteResidentData({
    required String residentId,
    required bool residentRequestConfirmed,
    required bool identityVerificationConfirmed,
    required String commandId,
  });

  Future<VolunteerHelperList> listVolunteerHelpers();

  Future<HelperAssignmentResult> createHelperAssignment({
    required String residentId,
    required String helperResidentId,
    required String commandId,
  });

  Future<ProxyTaskStatusRecord> updateProxyTaskStatus({
    required String residentId,
    required String taskId,
    required String participationState,
    required bool completionReported,
    required bool residentConsentConfirmed,
    required String commandId,
  });
}

final class ProxyResidentRecord {
  const ProxyResidentRecord({
    required this.residentId,
    required this.nickname,
    required this.houseNumber,
    required this.needsAssistance,
    this.deletionPending = false,
    required this.createdAt,
  });

  final String residentId;
  final String nickname;
  final String? houseNumber;
  final bool needsAssistance;
  final bool deletionPending;
  final DateTime createdAt;

  factory ProxyResidentRecord.fromWire(Object? value) {
    final wire = _strictMap(value);
    _onlyKeys(wire, const {
      'residentId',
      'nickname',
      'houseNumber',
      'needsAssistance',
      'deletionPending',
      'createdAt',
    });
    final residentId = _requiredString(wire['residentId']);
    final nickname = _requiredString(wire['nickname']);
    final houseNumber = wire['houseNumber'];
    if (!_residentIdPattern.hasMatch(residentId) ||
        nickname.charactersLength > 40 ||
        (houseNumber != null &&
            (houseNumber is! String ||
                !RegExp(r'^[A-Za-z0-9-]{1,12}$').hasMatch(houseNumber))) ||
        wire['needsAssistance'] is! bool ||
        wire['deletionPending'] is! bool) {
      throw const FormatException('Data warga tidak valid.');
    }
    return ProxyResidentRecord(
      residentId: residentId,
      nickname: nickname,
      houseNumber: houseNumber as String?,
      needsAssistance: wire['needsAssistance']! as bool,
      deletionPending: wire['deletionPending']! as bool,
      createdAt: _requiredDate(wire['createdAt']),
    );
  }
}

final class ProxyAssistanceUpdate {
  const ProxyAssistanceUpdate({
    required this.residentId,
    required this.needsAssistance,
  });

  final String residentId;
  final bool needsAssistance;

  factory ProxyAssistanceUpdate.fromWire(
    Object? value, {
    required String expectedResidentId,
  }) {
    final wire = _strictMap(value);
    _onlyKeys(wire, const {'residentId', 'needsAssistance'});
    final residentId = _requiredString(wire['residentId']);
    if (residentId != expectedResidentId ||
        !_residentIdPattern.hasMatch(residentId) ||
        wire['needsAssistance'] is! bool) {
      throw const FormatException('Perubahan status bantuan tidak valid.');
    }
    return ProxyAssistanceUpdate(
      residentId: residentId,
      needsAssistance: wire['needsAssistance']! as bool,
    );
  }
}

final class ProxyTaskStatusRecord {
  const ProxyTaskStatusRecord({
    required this.taskId,
    required this.participationState,
    required this.completionState,
  });

  final String taskId;
  final String participationState;
  final String completionState;

  factory ProxyTaskStatusRecord.fromWire(
    Object? value, {
    required String expectedTaskId,
  }) {
    final wire = _strictMap(value);
    _onlyKeys(wire, const {'taskId', 'participationState', 'completionState'});
    final taskId = _requiredString(wire['taskId']);
    final participation = _requiredString(wire['participationState']);
    final completion = _requiredString(wire['completionState']);
    if (taskId != expectedTaskId ||
        !_taskIdPattern.hasMatch(taskId) ||
        !const {'UNRESPONDED', 'JOINED', 'DECLINED'}.contains(participation) ||
        !const {
          'NOT_SUBMITTED',
          'PENDING_RT_VERIFICATION',
          'VERIFIED_COMPLETE',
        }.contains(completion)) {
      throw const FormatException('Status tugas warga tidak valid.');
    }
    return ProxyTaskStatusRecord(
      taskId: taskId,
      participationState: participation,
      completionState: completion,
    );
  }
}

/// Keeps command IDs stable while a callable request is retried after failure.
final class ProxyResidentController {
  ProxyResidentController(
    this.boundary, {
    String Function()? idFactory,
    ProxyCreateRequestStore? createRequestStore,
  }) : _idFactory = idFactory ?? _newOpaqueId,
       _createRequestStore =
           createRequestStore ?? _MemoryProxyCreateRequestStore();

  final ProxyResidentBoundary boundary;
  final String Function() _idFactory;
  final ProxyCreateRequestStore _createRequestStore;
  final Map<String, String> _commandIds = {};

  Future<ProxyResidentList> listProxyResidents() =>
      boundary.listProxyResidents();

  Future<PendingProxyResidentCreate?> getPendingCreate({
    required String communityId,
  }) => _createRequestStore.read(communityId: communityId);

  Future<ProxyTaskStatusRecord> getProxyTaskStatus({
    required String residentId,
    required String taskId,
  }) {
    _requireId(residentId, _residentIdPattern, 'residentId');
    _requireId(taskId, _taskIdPattern, 'taskId');
    return boundary.getProxyTaskStatus(residentId: residentId, taskId: taskId);
  }

  Future<String> cancelPendingProxyResidentCreate({
    required String communityId,
  }) async {
    final pending = await _createRequestStore.read(communityId: communityId);
    if (pending == null) return 'NONE';
    final state = await boundary.cancelPendingProxyResidentCreate(
      requestId: pending.requestId,
    );
    if (state == 'CANCELLED' || state == 'CREATED' || state == 'DELETED') {
      await _createRequestStore.clear();
    }
    return state;
  }

  Future<ProxyResidentRecord> createProxyResident({
    required String communityId,
    required String nickname,
    required String? houseNumber,
    required bool needsAssistance,
    required bool residentConsentConfirmed,
  }) async {
    var pending = await _createRequestStore.read(communityId: communityId);
    if (pending == null) {
      pending = PendingProxyResidentCreate(
        communityId: communityId,
        requestId: _validId(_idFactory()),
        nickname: nickname,
        houseNumber: houseNumber,
        needsAssistance: needsAssistance,
        residentConsentConfirmed: residentConsentConfirmed,
      );
      await _createRequestStore.write(pending);
    } else if (!pending.matches(
      nickname: nickname,
      houseNumber: houseNumber,
      needsAssistance: needsAssistance,
      residentConsentConfirmed: residentConsentConfirmed,
    )) {
      throw StateError(
        'An uncertain resident create must be retried with its original data.',
      );
    }
    final result = await boundary.createProxyResident(
      nickname: pending.nickname,
      houseNumber: pending.houseNumber,
      needsAssistance: pending.needsAssistance,
      residentConsentConfirmed: pending.residentConsentConfirmed,
      requestId: pending.requestId,
    );
    await _createRequestStore.clear();
    return result;
  }

  Future<ProxyAssistanceUpdate> updateProxyAssistance({
    required String residentId,
    required bool needsAssistance,
    required bool residentConsentConfirmed,
  }) async {
    _requireId(residentId, _residentIdPattern, 'residentId');
    final key = 'assistance:$residentId:$needsAssistance';
    final commandId = _commandIds.putIfAbsent(
      key,
      () => _validId(_idFactory()),
    );
    try {
      final result = await boundary.updateProxyAssistance(
        residentId: residentId,
        needsAssistance: needsAssistance,
        residentConsentConfirmed: residentConsentConfirmed,
        commandId: commandId,
      );
      _commandIds.remove(key);
      return result;
    } catch (_) {
      rethrow;
    }
  }

  Future<void> deleteResidentData({
    required String residentId,
    required bool residentRequestConfirmed,
    required bool identityVerificationConfirmed,
  }) async {
    _requireId(residentId, _residentIdPattern, 'residentId');
    final commandId = _commandIds.putIfAbsent(
      'delete:$residentId',
      () => _validId(_idFactory()),
    );
    await boundary.deleteResidentData(
      residentId: residentId,
      residentRequestConfirmed: residentRequestConfirmed,
      identityVerificationConfirmed: identityVerificationConfirmed,
      commandId: commandId,
    );
    _commandIds.remove('delete:$residentId');
  }

  Future<VolunteerHelperList> listVolunteerHelpers() =>
      boundary.listVolunteerHelpers();

  Future<HelperAssignmentResult> createHelperAssignment({
    required String residentId,
    required String helperResidentId,
  }) async {
    _requireId(residentId, _residentIdPattern, 'residentId');
    _requireId(helperResidentId, _residentIdPattern, 'helperResidentId');
    final key = 'assignment:$residentId:$helperResidentId';
    final commandId = _commandIds.putIfAbsent(
      key,
      () => _validId(_idFactory()),
    );
    final result = await boundary.createHelperAssignment(
      residentId: residentId,
      helperResidentId: helperResidentId,
      commandId: commandId,
    );
    _commandIds.remove(key);
    return result;
  }

  Future<ProxyTaskStatusRecord> updateProxyTaskStatus({
    required String residentId,
    required String taskId,
    required String participationState,
    required bool completionReported,
    required bool residentConsentConfirmed,
  }) async {
    _requireId(residentId, _residentIdPattern, 'residentId');
    _requireId(taskId, _taskIdPattern, 'taskId');
    if (!const {'JOINED', 'DECLINED'}.contains(participationState) ||
        (completionReported && participationState != 'JOINED')) {
      throw ArgumentError('Invalid proxy participation status.');
    }
    final key =
        'task:$residentId:$taskId:$participationState:$completionReported';
    final commandId = _commandIds.putIfAbsent(
      key,
      () => _validId(_idFactory()),
    );
    try {
      final result = await boundary.updateProxyTaskStatus(
        residentId: residentId,
        taskId: taskId,
        participationState: participationState,
        completionReported: completionReported,
        residentConsentConfirmed: residentConsentConfirmed,
        commandId: commandId,
      );
      _commandIds.remove(key);
      return result;
    } catch (_) {
      rethrow;
    }
  }
}

String _validId(String value) {
  _requireId(value, _commandIdPattern, 'commandId');
  return value;
}

void _requireId(String value, RegExp pattern, String field) {
  if (!pattern.hasMatch(value)) throw ArgumentError.value(value, field);
}

Map<String, Object?> _strictMap(Object? value) {
  if (value is! Map) throw const FormatException('Respons warga tidak valid.');
  final result = <String, Object?>{};
  for (final entry in value.entries) {
    if (entry.key is! String) {
      throw const FormatException('Respons warga tidak valid.');
    }
    result[entry.key as String] = entry.value;
  }
  return result;
}

void _onlyKeys(Map<String, Object?> value, Set<String> keys) {
  if (value.keys.any((key) => !keys.contains(key)) ||
      keys.any((key) => !value.containsKey(key))) {
    throw const FormatException('Respons warga tidak valid.');
  }
}

String _requiredString(Object? value) {
  if (value is! String || value.trim().isEmpty) {
    throw const FormatException('Respons warga tidak valid.');
  }
  return value;
}

DateTime _requiredDate(Object? value) {
  if (value is! String) throw const FormatException('Waktu warga tidak valid.');
  final result = DateTime.tryParse(value);
  if (result == null || !result.isUtc || result.toIso8601String() != value) {
    throw const FormatException('Waktu warga tidak valid.');
  }
  return result;
}

final class _MemoryProxyCreateRequestStore implements ProxyCreateRequestStore {
  PendingProxyResidentCreate? _pending;

  @override
  Future<PendingProxyResidentCreate?> read({
    required String communityId,
  }) async {
    if (_pending != null && _pending!.communityId != communityId) {
      throw const ProxyCreateRequestScopeMismatch();
    }
    return _pending;
  }

  @override
  Future<void> write(PendingProxyResidentCreate request) async {
    _pending = request;
  }

  @override
  Future<void> clear() async {
    _pending = null;
  }
}

String _newOpaqueId() {
  const alphabet =
      'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-';
  final random = Random.secure();
  return List<String>.generate(
    48,
    (_) => alphabet[random.nextInt(alphabet.length)],
  ).join();
}

extension on String {
  int get charactersLength => runes.length;
}
