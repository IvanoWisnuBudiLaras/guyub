import 'package:cloud_functions/cloud_functions.dart';

import '../application/proxy_resident_boundary.dart';

typedef ProxyResidentCallableInvoker = Future<Object?> Function(
  String name,
  Map<String, Object?> data,
);

/// All proxy-resident reads and writes use server-authorized callable Functions.
final class FirebaseProxyResidentBoundary implements ProxyResidentBoundary {
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
  Future<List<ProxyResidentRecord>> listProxyResidents() async =>
      ProxyResidentRecord.listFromWire(
        await _call('listProxyResidents', const {}),
      );

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
