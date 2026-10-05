import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_functions/cloud_functions.dart';

import '../../evidence/application/task_evidence_boundary.dart';

import '../application/task_response.dart';
import '../application/task_response_boundary.dart';

/// Firebase callable adapter. Task responses never use direct Firestore writes.
final class FirebaseTaskResponseBoundary
    implements TaskResponseBoundary, TaskEvidenceBoundary {
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
    String? evidenceId,
  }) async {
    final result = await _mapCallable(
      () => functions.httpsCallable('submitTaskCompletion').call(
        <String, Object?>{
          'sessionToken': sessionToken,
          'taskId': taskId,
          'note': note,
          'commandId': commandId,
          'evidenceId': evidenceId,
        },
      ),
    );
    return TaskResponseRecord.fromWire(_wireMap(result.data, 'task response'));
  }

  @override
  Future<String> uploadResidentTaskEvidence({
    required String sessionToken,
    required String taskId,
    required String requestId,
    required Uint8List sanitizedJpegBytes,
  }) async {
    if (sanitizedJpegBytes.isEmpty ||
        sanitizedJpegBytes.length > 2 * 1024 * 1024) {
      throw ArgumentError.value(
        sanitizedJpegBytes.length,
        'sanitizedJpegBytes',
      );
    }
    final result = await _mapCallable(
      () => functions.httpsCallable('uploadResidentTaskEvidence').call(
        <String, Object?>{
          'sessionToken': sessionToken,
          'taskId': taskId,
          'requestId': requestId,
          'imageBase64': base64Encode(sanitizedJpegBytes),
        },
      ),
    );
    final wire = _wireMap(result.data, 'evidence upload');
    final evidenceId = wire['evidenceId'];
    if (evidenceId is! String ||
        !RegExp(r'^[a-f0-9]{40}$').hasMatch(evidenceId)) {
      throw const FormatException('Invalid evidence upload response.');
    }
    return evidenceId;
  }

  @override
  Future<void> deleteResidentTaskEvidence({
    required String sessionToken,
    required String evidenceId,
    required String commandId,
  }) async {
    final result = await _mapCallable(
      () => functions.httpsCallable('deleteResidentTaskEvidence').call(
        <String, Object?>{
          'sessionToken': sessionToken,
          'evidenceId': evidenceId,
          'commandId': commandId,
        },
      ),
    );
    final wire = _wireMap(result.data, 'evidence deletion');
    if (wire['deleted'] != true) {
      throw const FormatException('Invalid deletion response.');
    }
  }

  @override
  Future<Uint8List> getTaskEvidenceForVerification({
    required String evidenceId,
  }) async {
    final result = await _mapCallable(
      () => functions.httpsCallable('getTaskEvidenceForVerification').call(
        <String, Object?>{'evidenceId': evidenceId},
      ),
    );
    final wire = _wireMap(result.data, 'evidence review');
    if (wire['evidenceId'] != evidenceId ||
        wire['contentType'] != 'image/jpeg') {
      throw const FormatException('Invalid evidence review response.');
    }
    final encoded = wire['imageBase64'];
    if (encoded is! String || encoded.length > 3 * 1024 * 1024) {
      throw const FormatException('Invalid evidence image.');
    }
    final bytes = base64Decode(encoded);
    if (bytes.isEmpty || bytes.length > 2 * 1024 * 1024) {
      throw const FormatException('Invalid evidence image.');
    }
    return bytes;
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
