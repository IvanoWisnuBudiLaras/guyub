import 'dart:math';

final _residentIdPattern = RegExp(r'^[a-f0-9]{40}$');
final _taskIdPattern = RegExp(r'^[a-f0-9]{40}$');
final _commandIdPattern = RegExp(r'^[A-Za-z0-9_-]{32,128}$');

abstract interface class ProxyResidentBoundary {
  Future<List<ProxyResidentRecord>> listProxyResidents();

  Future<ProxyTaskStatusRecord> getProxyTaskStatus({
    required String residentId,
    required String taskId,
  });

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
    required this.createdAt,
  });

  final String residentId;
  final String nickname;
  final String? houseNumber;
  final bool needsAssistance;
  final DateTime createdAt;

  factory ProxyResidentRecord.fromWire(Object? value) {
    final wire = _strictMap(value);
    _onlyKeys(wire, const {
      'residentId',
      'nickname',
      'houseNumber',
      'needsAssistance',
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
        wire['needsAssistance'] is! bool) {
      throw const FormatException('Data warga tidak valid.');
    }
    return ProxyResidentRecord(
      residentId: residentId,
      nickname: nickname,
      houseNumber: houseNumber as String?,
      needsAssistance: wire['needsAssistance']! as bool,
      createdAt: _requiredDate(wire['createdAt']),
    );
  }

  static List<ProxyResidentRecord> listFromWire(Object? value) {
    final wire = _strictMap(value);
    _onlyKeys(wire, const {'items', 'isPartial'});
    final items = wire['items'];
    if (items is! List || items.length > 200 || wire['isPartial'] is! bool) {
      throw const FormatException('Daftar warga tidak valid.');
    }
    final ids = <String>{};
    final result = items.map(ProxyResidentRecord.fromWire).toList();
    if (result.any((item) => !ids.add(item.residentId))) {
      throw const FormatException('Daftar warga tidak valid.');
    }
    return List<ProxyResidentRecord>.unmodifiable(result);
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
  ProxyResidentController(this.boundary, {String Function()? idFactory})
    : _idFactory = idFactory ?? _newOpaqueId;

  final ProxyResidentBoundary boundary;
  final String Function() _idFactory;
  String? _createRequestId;
  final Map<String, String> _commandIds = {};

  Future<List<ProxyResidentRecord>> listProxyResidents() =>
      boundary.listProxyResidents();

  Future<ProxyTaskStatusRecord> getProxyTaskStatus({
    required String residentId,
    required String taskId,
  }) {
    _requireId(residentId, _residentIdPattern, 'residentId');
    _requireId(taskId, _taskIdPattern, 'taskId');
    return boundary.getProxyTaskStatus(residentId: residentId, taskId: taskId);
  }

  Future<ProxyResidentRecord> createProxyResident({
    required String nickname,
    required String? houseNumber,
    required bool needsAssistance,
    required bool residentConsentConfirmed,
  }) async {
    final requestId = _createRequestId ??= _validId(_idFactory());
    try {
      final result = await boundary.createProxyResident(
        nickname: nickname,
        houseNumber: houseNumber,
        needsAssistance: needsAssistance,
        residentConsentConfirmed: residentConsentConfirmed,
        requestId: requestId,
      );
      _createRequestId = null;
      return result;
    } catch (_) {
      rethrow;
    }
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
