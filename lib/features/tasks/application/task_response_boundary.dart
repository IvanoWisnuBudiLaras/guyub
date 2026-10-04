// ignore_for_file: prefer_initializing_formals

import 'dart:convert';
import 'dart:math';

import '../../auth/application/resident_session_vault.dart';
import 'task_response.dart';
import 'task_template.dart';

/// Callable-only resident response and RT-verification boundary.
/// Resident bearer tokens are supplied only by the controller, never by UI.
abstract interface class TaskResponseBoundary {
  Future<ResidentTaskList> listResidentActiveTasks({
    required String sessionToken,
  });

  Future<TaskResponseRecord> recordResidentTaskResponse({
    required String sessionToken,
    required String taskId,
    required ParticipationChoice choice,
    required String commandId,
  });

  Future<TaskResponseRecord> submitTaskCompletion({
    required String sessionToken,
    required String taskId,
    required String? note,
    required String commandId,
  });

  Future<TaskVerificationQueue> listPendingVerifications();

  Future<TaskResponseRecord> verifyTaskCompletion({
    required String responseId,
    required String commandId,
  });

  Future<TaskResponseRecap> getResponseRecap({required String taskId});
}

/// Active campaign and only this resident's response state.
final class ResidentTaskRecord {
  const ResidentTaskRecord({
    required this.taskId,
    required this.rtId,
    required this.templateSnapshot,
    required this.deadline,
    required this.status,
    required this.participation,
    required this.completion,
    this.locationReference,
    this.additionalNote,
    this.completionNote,
    this.completionSubmittedAt,
    this.verifiedAt,
  });

  final String taskId;
  final String rtId;
  final TaskTemplateSnapshot templateSnapshot;
  final DateTime deadline;
  final String status;
  final ParticipationState participation;
  final CompletionState completion;
  final String? locationReference;
  final String? additionalNote;
  final String? completionNote;
  final DateTime? completionSubmittedAt;
  final DateTime? verifiedAt;

  factory ResidentTaskRecord.fromWire(Map<String, Object?> wire) {
    final snapshot = _asMap(wire['templateSnapshot'], 'templateSnapshot');
    final location = _optionalString(
      wire['locationReference'],
      'locationReference',
    );
    final note = _optionalString(wire['additionalNote'], 'additionalNote');
    final completionNote = _optionalString(
      wire['completionNote'],
      'completionNote',
    );
    final status = _requiredString(wire['status'], 'status');
    if (status != 'ACTIVE') throw const FormatException('Invalid task status.');
    return ResidentTaskRecord(
      taskId: _requiredString(wire['taskId'], 'taskId'),
      rtId: _requiredString(wire['rtId'], 'rtId'),
      templateSnapshot: _snapshotFromWire(snapshot),
      deadline: _requiredDate(wire['deadline'], 'deadline'),
      status: status,
      participation: _participationFromWire(wire['participationState']),
      completion: _completionFromWire(wire['completionState']),
      locationReference: location,
      additionalNote: note,
      completionNote: completionNote,
      completionSubmittedAt: _optionalDate(
        wire['completionSubmittedAt'],
        'completionSubmittedAt',
      ),
      verifiedAt: _optionalDate(wire['verifiedAt'], 'verifiedAt'),
    );
  }

  ResidentTaskRecord withResponse(TaskResponseRecord response) {
    if (response.taskId != taskId) {
      throw ArgumentError.value(response.taskId, 'response.taskId');
    }
    return ResidentTaskRecord(
      taskId: taskId,
      rtId: rtId,
      templateSnapshot: templateSnapshot,
      deadline: deadline,
      status: status,
      participation: response.participation,
      completion: response.completion,
      locationReference: locationReference,
      additionalNote: additionalNote,
      completionNote: response.completionNote,
      completionSubmittedAt: response.completionSubmittedAt,
      verifiedAt: response.verifiedAt,
    );
  }
}

/// Bounded active-task page; [isPartial] warns that more tasks exist.
final class ResidentTaskList {
  const ResidentTaskList({required this.items, required this.isPartial});

  final List<ResidentTaskRecord> items;
  final bool isPartial;
}

/// Response state returned by one resident or operator command.
final class TaskResponseRecord {
  const TaskResponseRecord({
    required this.taskId,
    required this.participation,
    required this.completion,
    this.completionNote,
    this.completionSubmittedAt,
    this.verifiedAt,
  });

  final String taskId;
  final ParticipationState participation;
  final CompletionState completion;
  final String? completionNote;
  final DateTime? completionSubmittedAt;
  final DateTime? verifiedAt;

  factory TaskResponseRecord.fromWire(Map<String, Object?> wire) =>
      TaskResponseRecord(
        taskId: _requiredString(wire['taskId'], 'taskId'),
        participation: _participationFromWire(wire['participationState']),
        completion: _completionFromWire(wire['completionState']),
        completionNote: _optionalString(
          wire['completionNote'],
          'completionNote',
        ),
        completionSubmittedAt: _optionalDate(
          wire['completionSubmittedAt'],
          'completionSubmittedAt',
        ),
        verifiedAt: _optionalDate(wire['verifiedAt'], 'verifiedAt'),
      );
}

/// Minimal same-RT queue entry. It contains no full resident address.
final class TaskVerificationRecord {
  const TaskVerificationRecord({
    required this.responseId,
    required this.taskId,
    required this.taskTitle,
    required this.nickname,
    required this.submittedAt,
    this.completionNote,
  });

  final String responseId;
  final String taskId;
  final String taskTitle;
  final String nickname;
  final DateTime submittedAt;
  final String? completionNote;

  factory TaskVerificationRecord.fromWire(Map<String, Object?> wire) =>
      TaskVerificationRecord(
        responseId: _requiredString(wire['responseId'], 'responseId'),
        taskId: _requiredString(wire['taskId'], 'taskId'),
        taskTitle: _requiredString(wire['taskTitle'], 'taskTitle'),
        nickname: _requiredString(wire['nickname'], 'nickname'),
        submittedAt: _requiredDate(wire['submittedAt'], 'submittedAt'),
        completionNote: _optionalString(
          wire['completionNote'],
          'completionNote',
        ),
      );
}

/// Bounded RT queue; [isPartial] warns that more items need a later review.
final class TaskVerificationQueue {
  const TaskVerificationQueue({required this.items, required this.isPartial});

  final List<TaskVerificationRecord> items;
  final bool isPartial;
}

/// Aggregate-only response recap. Non-response counts are intentionally absent.
final class TaskResponseRecap {
  const TaskResponseRecap({
    required this.taskId,
    required this.rtId,
    required this.recordedResponseCount,
    required this.joinedCount,
    required this.declinedCount,
    required this.pendingVerificationCount,
    required this.verifiedCompleteCount,
    required this.isPartial,
    required this.taskTitle,
  });

  final String taskId;
  final String rtId;
  final int recordedResponseCount;
  final int joinedCount;
  final int declinedCount;
  final int pendingVerificationCount;
  final int verifiedCompleteCount;
  final bool isPartial;
  final String taskTitle;

  factory TaskResponseRecap.fromWire(Map<String, Object?> wire) =>
      TaskResponseRecap(
        taskId: _requiredString(wire['taskId'], 'taskId'),
        rtId: _requiredString(wire['rtId'], 'rtId'),
        recordedResponseCount: _requiredInt(
          wire['recordedResponseCount'],
          'recordedResponseCount',
        ),
        joinedCount: _requiredInt(wire['joinedCount'], 'joinedCount'),
        declinedCount: _requiredInt(wire['declinedCount'], 'declinedCount'),
        pendingVerificationCount: _requiredInt(
          wire['pendingVerificationCount'],
          'pendingVerificationCount',
        ),
        verifiedCompleteCount: _requiredInt(
          wire['verifiedCompleteCount'],
          'verifiedCompleteCount',
        ),
        isPartial: _requiredBool(wire['isPartial'], 'isPartial'),
        taskTitle: _requiredString(wire['taskTitle'], 'taskTitle'),
      );
}

/// Reads the opaque resident token from secure storage and owns stable retry IDs.
final class TaskResponseController {
  TaskResponseController({
    required TaskResponseBoundary boundary,
    required ResidentSessionVault vault,
    String Function()? commandIdFactory,
  }) : _boundary = boundary,
       _vault = vault,
       _commandIdFactory = commandIdFactory ?? _newCommandId;

  final TaskResponseBoundary _boundary;
  final ResidentSessionVault _vault;
  final String Function() _commandIdFactory;
  final Map<String, String> _choiceCommands = {};
  final Map<String, String> _completionCommands = {};
  final Map<String, String?> _completionNotes = {};
  final Map<String, String> _verificationCommands = {};

  Future<ResidentTaskList> listResidentActiveTasks() async =>
      _boundary.listResidentActiveTasks(sessionToken: await _sessionToken());

  Future<TaskResponseRecord> recordParticipation({
    required String taskId,
    required ParticipationChoice choice,
  }) async {
    final commandId = _choiceCommands.putIfAbsent(taskId, _commandIdFactory);
    final result = await _boundary.recordResidentTaskResponse(
      sessionToken: await _sessionToken(),
      taskId: taskId,
      choice: choice,
      commandId: commandId,
    );
    _choiceCommands.remove(taskId);
    return result;
  }

  Future<TaskResponseRecord> submitCompletion({
    required String taskId,
    required String? note,
  }) async {
    final normalizedNote = _normalizeOptionalText(note);
    final previousNote = _completionNotes[taskId];
    if (_completionCommands.containsKey(taskId) &&
        previousNote != normalizedNote) {
      _completionCommands.remove(taskId);
      _completionNotes.remove(taskId);
    }
    final commandId = _completionCommands.putIfAbsent(
      taskId,
      _commandIdFactory,
    );
    _completionNotes.putIfAbsent(taskId, () => normalizedNote);
    final result = await _boundary.submitTaskCompletion(
      sessionToken: await _sessionToken(),
      taskId: taskId,
      note: normalizedNote,
      commandId: commandId,
    );
    _completionCommands.remove(taskId);
    _completionNotes.remove(taskId);
    return result;
  }

  Future<TaskVerificationQueue> listPendingVerifications() =>
      _boundary.listPendingVerifications();

  Future<TaskResponseRecord> verifyCompletion({
    required String responseId,
  }) async {
    final commandId = _verificationCommands.putIfAbsent(
      responseId,
      _commandIdFactory,
    );
    final result = await _boundary.verifyTaskCompletion(
      responseId: responseId,
      commandId: commandId,
    );
    _verificationCommands.remove(responseId);
    return result;
  }

  Future<TaskResponseRecap> getResponseRecap({required String taskId}) =>
      _boundary.getResponseRecap(taskId: taskId);

  Future<String> _sessionToken() async {
    final token = await _vault.read();
    if (token == null || token.isEmpty) {
      throw StateError(
        'Sesi warga tidak tersedia. Masuk kembali untuk melanjutkan.',
      );
    }
    return token;
  }
}

TaskTemplateSnapshot _snapshotFromWire(Map<String, Object?> wire) {
  final duration = wire['estimatedDurationMinutes'];
  return TaskTemplateSnapshot(
    templateId: _requiredString(wire['templateId'], 'templateId'),
    version: _requiredInt(wire['version'], 'version'),
    title: _requiredString(wire['title'], 'title'),
    category: _requiredString(wire['category'], 'category'),
    coreInstruction: _requiredString(
      wire['coreInstruction'],
      'coreInstruction',
    ),
    safetyInstruction: _requiredString(
      wire['safetyInstruction'],
      'safetyInstruction',
    ),
    estimatedDurationMinutes: duration == null
        ? null
        : _requiredInt(duration, 'estimatedDurationMinutes'),
  );
}

ParticipationState _participationFromWire(Object? value) => switch (value) {
  'UNRESPONDED' => ParticipationState.unresponded,
  'JOINED' => ParticipationState.joined,
  'DECLINED' => ParticipationState.declined,
  _ => throw const FormatException('Invalid participation state.'),
};

CompletionState _completionFromWire(Object? value) => switch (value) {
  'NOT_SUBMITTED' => CompletionState.notSubmitted,
  'PENDING_RT_VERIFICATION' => CompletionState.pendingRtVerification,
  'VERIFIED_COMPLETE' => CompletionState.verifiedComplete,
  _ => throw const FormatException('Invalid completion state.'),
};

Map<String, Object?> _asMap(Object? value, String name) {
  if (value is Map<String, Object?>) return value;
  if (value is Map) return value.cast<String, Object?>();
  throw FormatException('Invalid $name.');
}

String _requiredString(Object? value, String name) {
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('Invalid $name.');
  }
  return value;
}

String? _optionalString(Object? value, String name) {
  if (value == null) return null;
  if (value is! String) throw FormatException('Invalid $name.');
  return value;
}

int _requiredInt(Object? value, String name) {
  if (value is int) return value;
  if (value is num && value.isFinite && value == value.roundToDouble()) {
    return value.toInt();
  }
  throw FormatException('Invalid $name.');
}

bool _requiredBool(Object? value, String name) {
  if (value is bool) return value;
  throw FormatException('Invalid $name.');
}

DateTime _requiredDate(Object? value, String name) {
  final result = _optionalDate(value, name);
  if (result == null) throw FormatException('Invalid $name.');
  return result;
}

DateTime? _optionalDate(Object? value, String name) {
  if (value == null) return null;
  if (value is! String) throw FormatException('Invalid $name.');
  return DateTime.tryParse(value)?.toUtc();
}

String? _normalizeOptionalText(String? value) {
  final normalized = value?.trim();
  return normalized == null || normalized.isEmpty ? null : normalized;
}

String _newCommandId() {
  final random = Random.secure();
  final bytes = List<int>.generate(32, (_) => random.nextInt(256));
  return base64Url.encode(bytes).replaceAll('=', '');
}
