import 'dart:math';

final _residentIdPattern = RegExp(r'^[a-f0-9]{40}$');
final _assignmentIdPattern = RegExp(r'^[a-f0-9]{40}$');
final _commandIdPattern = RegExp(r'^[A-Za-z0-9_-]{32,128}$');

abstract interface class AssistanceVolunteerBoundary {
  Future<ResidentVolunteerData> getVolunteerData({
    required String sessionToken,
  });

  Future<bool> updateVolunteerConsent({
    required String sessionToken,
    required bool willingToHelp,
    required bool residentConsentConfirmed,
    required String commandId,
  });

  Future<HelperAssignmentResult> respondToHelperAssignment({
    required String sessionToken,
    required String assignmentId,
    required String decision,
    required bool residentConsentConfirmed,
    required String commandId,
  });
}

final class VolunteerHelperRecord {
  const VolunteerHelperRecord({
    required this.residentId,
    required this.nickname,
  });

  final String residentId;
  final String nickname;

  factory VolunteerHelperRecord.fromWire(Object? value) {
    final wire = _strictMap(value);
    _onlyKeys(wire, const {'residentId', 'nickname'});
    final residentId = _string(wire['residentId']);
    final nickname = _string(wire['nickname']);
    if (!_residentIdPattern.hasMatch(residentId) ||
        nickname.runes.length > 40 ||
        nickname.contains(RegExp(r'[\u0000-\u001F\u007F]'))) {
      throw const FormatException('Data relawan tidak valid.');
    }
    return VolunteerHelperRecord(residentId: residentId, nickname: nickname);
  }
}

final class VolunteerHelperList {
  VolunteerHelperList({
    required List<VolunteerHelperRecord> items,
    required this.isPartial,
  }) : items = List<VolunteerHelperRecord>.unmodifiable(items);

  final List<VolunteerHelperRecord> items;
  final bool isPartial;

  factory VolunteerHelperList.fromWire(Object? value) {
    final wire = _strictMap(value);
    _onlyKeys(wire, const {'items', 'isPartial'});
    final items = wire['items'];
    if (items is! List || items.length > 200 || wire['isPartial'] is! bool) {
      throw const FormatException('Daftar relawan tidak valid.');
    }
    final parsed = items.map(VolunteerHelperRecord.fromWire).toList();
    final ids = <String>{};
    if (parsed.any((item) => !ids.add(item.residentId))) {
      throw const FormatException('Daftar relawan tidak valid.');
    }
    return VolunteerHelperList(
      items: parsed,
      isPartial: wire['isPartial']! as bool,
    );
  }
}

final class HelperAssignmentRecord {
  const HelperAssignmentRecord({
    required this.assignmentId,
    required this.state,
    required this.createdAt,
  });

  final String assignmentId;
  final String state;
  final DateTime createdAt;

  factory HelperAssignmentRecord.fromWire(Object? value) {
    final wire = _strictMap(value);
    _onlyKeys(wire, const {'assignmentId', 'state', 'createdAt'});
    final assignmentId = _string(wire['assignmentId']);
    final state = _string(wire['state']);
    final rawDate = _string(wire['createdAt']);
    final date = DateTime.tryParse(rawDate);
    if (!_assignmentIdPattern.hasMatch(assignmentId) ||
        !const {'OFFERED', 'ACCEPTED'}.contains(state) ||
        date == null ||
        !date.isUtc ||
        date.toIso8601String() != rawDate) {
      throw const FormatException('Permintaan bantuan tidak valid.');
    }
    return HelperAssignmentRecord(
      assignmentId: assignmentId,
      state: state,
      createdAt: date,
    );
  }
}

final class ResidentVolunteerData {
  ResidentVolunteerData({
    required this.willingToHelp,
    required List<HelperAssignmentRecord> assignments,
    required this.isPartial,
  }) : assignments = List<HelperAssignmentRecord>.unmodifiable(assignments);

  final bool willingToHelp;
  final List<HelperAssignmentRecord> assignments;
  final bool isPartial;

  factory ResidentVolunteerData.fromWire(Object? value) {
    final wire = _strictMap(value);
    _onlyKeys(wire, const {'willingToHelp', 'assignments', 'isPartial'});
    final assignments = wire['assignments'];
    if (wire['willingToHelp'] is! bool ||
        assignments is! List ||
        assignments.length > 200 ||
        wire['isPartial'] is! bool) {
      throw const FormatException('Status relawan tidak valid.');
    }
    final parsed = assignments.map(HelperAssignmentRecord.fromWire).toList();
    final ids = <String>{};
    if (parsed.any((item) => !ids.add(item.assignmentId))) {
      throw const FormatException('Status relawan tidak valid.');
    }
    return ResidentVolunteerData(
      willingToHelp: wire['willingToHelp']! as bool,
      assignments: parsed,
      isPartial: wire['isPartial']! as bool,
    );
  }
}

final class HelperAssignmentResult {
  const HelperAssignmentResult({
    required this.assignmentId,
    required this.state,
  });

  final String assignmentId;
  final String state;

  factory HelperAssignmentResult.fromWire(
    Object? value, {
    String? expectedAssignmentId,
  }) {
    final wire = _strictMap(value);
    _onlyKeys(wire, const {'assignmentId', 'state'});
    final assignmentId = _string(wire['assignmentId']);
    final state = _string(wire['state']);
    if (!_assignmentIdPattern.hasMatch(assignmentId) ||
        (expectedAssignmentId != null &&
            assignmentId != expectedAssignmentId) ||
        !const {
          'OFFERED',
          'ACCEPTED',
          'DECLINED',
          'WITHDRAWN',
        }.contains(state)) {
      throw const FormatException('Respons bantuan relawan tidak valid.');
    }
    return HelperAssignmentResult(assignmentId: assignmentId, state: state);
  }
}

/// Resident consent and assignment calls never expose the participant token to UI.
final class AssistanceVolunteerController {
  AssistanceVolunteerController({
    required this.boundary,
    required this.readSessionToken,
    String Function()? idFactory,
  }) : _idFactory = idFactory ?? _newOpaqueId;

  final AssistanceVolunteerBoundary boundary;
  final Future<String?> Function() readSessionToken;
  final String Function() _idFactory;
  final Map<String, String> _commandIds = {};

  Future<ResidentVolunteerData> getVolunteerData() async {
    final token = await _requireToken();
    return boundary.getVolunteerData(sessionToken: token);
  }

  Future<bool> updateVolunteerConsent({required bool willingToHelp}) async {
    final token = await _requireToken();
    final key = 'consent:$willingToHelp';
    final commandId = _commandIds.putIfAbsent(
      key,
      () => _validId(_idFactory()),
    );
    final result = await boundary.updateVolunteerConsent(
      sessionToken: token,
      willingToHelp: willingToHelp,
      residentConsentConfirmed: true,
      commandId: commandId,
    );
    _commandIds.remove(key);
    return result;
  }

  Future<HelperAssignmentResult> respondToHelperAssignment({
    required String assignmentId,
    required String decision,
  }) async {
    if (!_assignmentIdPattern.hasMatch(assignmentId) ||
        !const {'ACCEPTED', 'DECLINED', 'WITHDRAWN'}.contains(decision)) {
      throw ArgumentError('Invalid helper assignment decision.');
    }
    final token = await _requireToken();
    final key = 'assignment:$assignmentId:$decision';
    final commandId = _commandIds.putIfAbsent(
      key,
      () => _validId(_idFactory()),
    );
    final result = await boundary.respondToHelperAssignment(
      sessionToken: token,
      assignmentId: assignmentId,
      decision: decision,
      residentConsentConfirmed: true,
      commandId: commandId,
    );
    _commandIds.remove(key);
    return result;
  }

  Future<String> _requireToken() async {
    final token = await readSessionToken();
    if (token == null || token.isEmpty) {
      throw StateError('Sesi warga aman tidak tersedia.');
    }
    return token;
  }
}

String _validId(String value) {
  if (!_commandIdPattern.hasMatch(value)) {
    throw ArgumentError('Invalid command ID.');
  }
  return value;
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

Map<String, Object?> _strictMap(Object? value) {
  if (value is! Map) {
    throw const FormatException('Respons bantuan tidak valid.');
  }
  final result = <String, Object?>{};
  for (final entry in value.entries) {
    if (entry.key is! String) {
      throw const FormatException('Respons bantuan tidak valid.');
    }
    result[entry.key as String] = entry.value;
  }
  return result;
}

void _onlyKeys(Map<String, Object?> value, Set<String> keys) {
  if (value.keys.any((key) => !keys.contains(key)) ||
      keys.any((key) => !value.containsKey(key))) {
    throw const FormatException('Respons bantuan tidak valid.');
  }
}

String _string(Object? value) {
  if (value is! String || value.trim().isEmpty) {
    throw const FormatException('Respons bantuan tidak valid.');
  }
  return value;
}
