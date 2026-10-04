import 'package:cloud_functions/cloud_functions.dart';

import '../application/task_response.dart';
import '../application/task_response_boundary.dart';

/// Firebase callable adapter. Task responses never use direct Firestore writes.
final class FirebaseTaskResponseBoundary implements TaskResponseBoundary {
  const FirebaseTaskResponseBoundary(this.functions);

  final FirebaseFunctions functions;

  @override
  Future<ResidentTaskList> listResidentActiveTasks({
    required String sessionToken,
  }) async {
    final result = await _mapCallable(
      () => functions.httpsCallable('listResidentActiveTasks').call(
        <String, Object?>{'sessionToken': sessionToken},
      ),
    );
    final wire = _wireMap(result.data, 'resident task list');
    return ResidentTaskList(
      items: _wireList(
        wire['items'],
        'resident tasks',
      ).map(ResidentTaskRecord.fromWire).toList(growable: false),
      isPartial: _requiredBool(wire['isPartial'], 'isPartial'),
    );
  }

  @override
  Future<TaskResponseRecord> recordResidentTaskResponse({
    required String sessionToken,
    required String taskId,
    required ParticipationChoice choice,
    required String commandId,
  }) async {
    final result = await _mapCallable(
      () => functions.httpsCallable('recordResidentTaskResponse').call(
        <String, Object?>{
          'sessionToken': sessionToken,
          'taskId': taskId,
          'choice': choice == ParticipationChoice.join ? 'JOINED' : 'DECLINED',
          'commandId': commandId,
        },
      ),
    );
    return TaskResponseRecord.fromWire(_wireMap(result.data, 'task response'));
  }

  @override
  Future<TaskResponseRecord> submitTaskCompletion({
    required String sessionToken,
    required String taskId,
    required String? note,
    required String commandId,
  }) async {
    final result = await _mapCallable(
      () => functions.httpsCallable('submitTaskCompletion').call(
        <String, Object?>{
          'sessionToken': sessionToken,
          'taskId': taskId,
          'note': note,
          'commandId': commandId,
        },
      ),
    );
    return TaskResponseRecord.fromWire(_wireMap(result.data, 'task response'));
  }

  @override
  Future<TaskVerificationQueue> listPendingVerifications() async {
    final result = await _mapCallable(
      () => functions
          .httpsCallable('listPendingTaskVerifications')
          .call(<String, Object?>{}),
    );
    final wire = _wireMap(result.data, 'verification queue');
    return TaskVerificationQueue(
      items: _wireList(
        wire['items'],
        'pending verifications',
      ).map(TaskVerificationRecord.fromWire).toList(growable: false),
      isPartial: _requiredBool(wire['isPartial'], 'isPartial'),
    );
  }

  @override
  Future<TaskResponseRecord> verifyTaskCompletion({
    required String responseId,
    required String commandId,
  }) async {
    final result = await _mapCallable(
      () => functions.httpsCallable('verifyTaskCompletion').call(
        <String, Object?>{'responseId': responseId, 'commandId': commandId},
      ),
    );
    return TaskResponseRecord.fromWire(_wireMap(result.data, 'task response'));
  }

  @override
  Future<TaskResponseRecap> getResponseRecap({required String taskId}) async {
    final result = await _mapCallable(
      () => functions.httpsCallable('getTaskResponseRecap').call(
        <String, Object?>{'taskId': taskId},
      ),
    );
    return TaskResponseRecap.fromWire(_wireMap(result.data, 'task recap'));
  }
}

/// Maps only callable codes with a defined offline/reconciliation meaning.
/// Unknown Firebase errors stay unclassified and never enable cache fallback.
final class FirebaseTaskResponseErrorMapper {
  const FirebaseTaskResponseErrorMapper._();

  static Exception? map(FirebaseFunctionsException error) =>
      switch (error.code) {
        'unavailable' ||
        'deadline-exceeded' => const TransientTaskNetworkUnavailableException(),
        'failed-precondition' ||
        'not-found' ||
        'already-exists' => const TaskResponseConflictException(),
        'permission-denied' ||
        'unauthenticated' ||
        'invalid-argument' => TaskResponseRejectedException(code: error.code),
        _ => null,
      };
}

Future<T> _mapCallable<T>(Future<T> Function() call) async {
  try {
    return await call();
  } on FirebaseFunctionsException catch (error) {
    final mapped = FirebaseTaskResponseErrorMapper.map(error);
    if (mapped == null) rethrow;
    throw mapped;
  }
}

List<Map<String, Object?>> _wireList(Object? value, String name) {
  if (value is! List) throw FormatException('Invalid $name.');
  return value.map((item) => _wireMap(item, name)).toList(growable: false);
}

Map<String, Object?> _wireMap(Object? value, String name) {
  if (value is Map<String, Object?>) return value;
  if (value is Map) return value.cast<String, Object?>();
  throw FormatException('Invalid $name.');
}

bool _requiredBool(Object? value, String name) {
  if (value is bool) return value;
  throw FormatException('Invalid $name.');
}
