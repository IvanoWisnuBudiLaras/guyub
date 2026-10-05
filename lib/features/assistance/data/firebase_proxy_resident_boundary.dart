import 'package:cloud_functions/cloud_functions.dart';

import '../application/assistance_volunteer_boundary.dart';
import '../application/proxy_resident_boundary.dart';

typedef ProxyResidentCallableInvoker = Future<Object?> Function(
  String name,
  Map<String, Object?> data,
);

/// All proxy-resident reads and writes use server-authorized callable Functions.
final class FirebaseProxyResidentBoundary
    implements ProxyResidentBoundary, AssistanceVolunteerBoundary {
  const FirebaseProxyResidentBoundary(this.functions) : _invoker = null;
  const FirebaseProxyResidentBoundary.withInvoker(this._invoker)
    : functions = null;

  final FirebaseFunctions? functions;
  final ProxyResidentCallableInvoker? _invoker;

  Future<Object?> _call(String name, Map<String, Object?> data) async {
    final invoker = _invoker;
    if (invoker != null) return invoker(name, data);
    final value = functions;
    if (value == null) throw StateError('Callable client unavailable.');
    final result = await value.httpsCallable(name).call(data);
    return result.data;
  }

  @override
  Future<ProxyResidentList> listProxyResidents() async =>
      ProxyResidentList.fromWire(await _call('listProxyResidents', const {}));

  @override
  Future<ProxyTaskStatusRecord> getProxyTaskStatus({
    required String residentId,
    required String taskId,
  }) async {
    final value = await _call('getProxyTaskStatus', {
      'residentId': residentId,
      'taskId': taskId,
    });
    return ProxyTaskStatusRecord.fromWire(value, expectedTaskId: taskId);
  }

  @override
  Future<ProxyResidentRecord> createProxyResident({
    required String nickname,
    required String? houseNumber,
    required bool needsAssistance,
    required bool residentConsentConfirmed,
    required String requestId,
  }) async {
    final value = await _call('createProxyResident', {
      'nickname': nickname,
      'houseNumber': houseNumber,
      'needsAssistance': needsAssistance,
      'residentConsentConfirmed': residentConsentConfirmed,
      'requestId': requestId,
    });
    return ProxyResidentRecord.fromWire(value);
  }

  @override
  Future<String> cancelPendingProxyResidentCreate({
    required String requestId,
  }) async {
    final value = await _call('cancelPendingProxyResidentCreate', {
      'requestId': requestId,
    });
    if (value is! Map ||
        value.keys.any((key) => key is! String) ||
        value.keys.toSet().difference(const {'state'}).isNotEmpty ||
        value.length != 1 ||
        !const {'CANCELLED', 'CREATED', 'DELETED'}.contains(value['state'])) {
      throw const FormatException('Status permintaan warga tidak valid.');
    }
    return value['state']! as String;
  }

  @override
  Future<ProxyAssistanceUpdate> updateProxyAssistance({
    required String residentId,
    required bool needsAssistance,
    required bool residentConsentConfirmed,
    required String commandId,
  }) async {
    final value = await _call('updateProxyResidentAssistance', {
      'residentId': residentId,
      'needsAssistance': needsAssistance,
      'residentConsentConfirmed': residentConsentConfirmed,
      'commandId': commandId,
    });
    return ProxyAssistanceUpdate.fromWire(
      value,
      expectedResidentId: residentId,
    );
  }

  @override
  Future<void> deleteResidentData({
    required String residentId,
    required bool residentRequestConfirmed,
    required bool identityVerificationConfirmed,
    required String commandId,
  }) async {
    final value = await _call('deleteResidentData', {
      'residentId': residentId,
      'residentRequestConfirmed': residentRequestConfirmed,
      'identityVerificationConfirmed': identityVerificationConfirmed,
      'commandId': commandId,
    });
    if (value is! Map ||
        value.keys.any((key) => key is! String) ||
        value.keys.toSet().difference(const {
          'residentId',
          'deleted',
        }).isNotEmpty ||
        value.length != 2 ||
        value['residentId'] != residentId ||
        value['deleted'] != true) {
      throw const FormatException('Penghapusan data warga belum dikonfirmasi.');
    }
  }

  @override
  Future<VolunteerHelperList> listVolunteerHelpers() async =>
      VolunteerHelperList.fromWire(
        await _call('listAvailableAssistanceHelpers', const {}),
      );

  @override
  Future<HelperAssignmentResult> createHelperAssignment({
    required String residentId,
    required String helperResidentId,
    required String commandId,
  }) async => HelperAssignmentResult.fromWire(
    await _call('createAssistanceHelperAssignment', {
      'residentId': residentId,
      'helperResidentId': helperResidentId,
      'commandId': commandId,
    }),
  );

  @override
  Future<ResidentVolunteerData> getVolunteerData({
    required String sessionToken,
  }) async => ResidentVolunteerData.fromWire(
    await _call('getAssistanceVolunteerData', {'sessionToken': sessionToken}),
  );

  @override
  Future<bool> updateVolunteerConsent({
    required String sessionToken,
    required bool willingToHelp,
    required bool residentConsentConfirmed,
    required String commandId,
  }) async {
    final value = await _call('updateAssistanceVolunteerConsent', {
      'sessionToken': sessionToken,
      'willingToHelp': willingToHelp,
      'residentConsentConfirmed': residentConsentConfirmed,
      'commandId': commandId,
    });
    if (value is! Map ||
        value.keys.any((key) => key is! String) ||
        value.keys.toSet().difference(const {'willingToHelp'}).isNotEmpty ||
        value.length != 1 ||
        value['willingToHelp'] is! bool) {
      throw const FormatException('Kesediaan relawan belum dikonfirmasi.');
    }
    return value['willingToHelp']! as bool;
  }

  @override
  Future<HelperAssignmentResult> respondToHelperAssignment({
    required String sessionToken,
    required String assignmentId,
    required String decision,
    required bool residentConsentConfirmed,
    required String commandId,
  }) async => HelperAssignmentResult.fromWire(
    await _call('respondToAssistanceAssignment', {
      'sessionToken': sessionToken,
      'assignmentId': assignmentId,
      'decision': decision,
      'residentConsentConfirmed': residentConsentConfirmed,
      'commandId': commandId,
    }),
    expectedAssignmentId: assignmentId,
  );

  @override
  Future<ProxyTaskStatusRecord> updateProxyTaskStatus({
    required String residentId,
    required String taskId,
    required String participationState,
    required bool completionReported,
    required bool residentConsentConfirmed,
    required String commandId,
  }) async {
    final value = await _call('updateProxyTaskStatus', {
      'residentId': residentId,
      'taskId': taskId,
      'participationState': participationState,
      'completionReported': completionReported,
      'residentConsentConfirmed': residentConsentConfirmed,
      'commandId': commandId,
    });
    return ProxyTaskStatusRecord.fromWire(value, expectedTaskId: taskId);
  }
}
