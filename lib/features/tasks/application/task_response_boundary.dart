// ignore_for_file: prefer_initializing_formals

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import '../../auth/application/resident_session.dart';
import '../../evidence/application/task_evidence_boundary.dart';
import '../../auth/application/resident_session_vault.dart';
import 'task_response.dart';
import 'task_template.dart';
import 'task_location_reference.dart';

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
    String? evidenceId,
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
    this.completionNote,
    this.completionSubmittedAt,
    this.verifiedAt,
    this.evidenceId,
    this.pendingChoice,
    this.hasSyncConflict = false,
    this.hasPendingCompletionSync = false,
  });

  final String taskId;
  final String rtId;
  final TaskTemplateSnapshot templateSnapshot;
  final DateTime deadline;
  final String status;
  final ParticipationState participation;
  final CompletionState completion;
  final String? locationReference;
  final String? completionNote;
  final DateTime? completionSubmittedAt;
  final DateTime? verifiedAt;
  final String? evidenceId;

  /// Locally queued participation choice; never replaces server state.
  final ParticipationChoice? pendingChoice;

  /// True when the server has a conflicting or unavailable authoritative state.
  final bool hasSyncConflict;
  final bool hasPendingCompletionSync;

  factory ResidentTaskRecord.fromWire(Map<String, Object?> wire) {
    final snapshot = _asMap(wire['templateSnapshot'], 'templateSnapshot');
    final location = _optionalString(
      wire['locationReference'],
      'locationReference',
    );
    final completionNote = _optionalString(
      wire['completionNote'],
      'completionNote',
    );
    final status = _requiredString(wire['status'], 'status');
    if (status != 'ACTIVE') throw const FormatException('Invalid task status.');
    if (location != null &&
        !TaskLocationReferences.allowed.contains(location)) {
      throw const FormatException('Invalid task location.');
    }
    return ResidentTaskRecord(
      taskId: _requiredString(wire['taskId'], 'taskId'),
      rtId: _requiredString(wire['rtId'], 'rtId'),
      templateSnapshot: _snapshotFromWire(snapshot),
      deadline: _requiredDate(wire['deadline'], 'deadline'),
      status: status,
      participation: _participationFromWire(wire['participationState']),
      completion: _completionFromWire(wire['completionState']),
      locationReference: location,
      completionNote: completionNote,
      completionSubmittedAt: _optionalDate(
        wire['completionSubmittedAt'],
        'completionSubmittedAt',
      ),
      verifiedAt: _optionalDate(wire['verifiedAt'], 'verifiedAt'),
      evidenceId: _optionalEvidenceId(wire['evidenceId']),
    );
  }

  ResidentTaskRecord withResponse(
    TaskResponseRecord response, {
    bool clearPendingChoice = false,
    bool? hasSyncConflict,
    bool? hasPendingCompletionSync,
  }) {
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
      completionNote: response.completionNote,
      completionSubmittedAt: response.completionSubmittedAt,
      verifiedAt: response.verifiedAt,
      evidenceId: response.evidenceId,
      pendingChoice: clearPendingChoice ? null : response.pendingChoice,
      hasSyncConflict: hasSyncConflict ?? response.hasSyncConflict,
      hasPendingCompletionSync:
          hasPendingCompletionSync ?? response.isPendingCompletionSync,
    );
  }

  ResidentTaskRecord withoutEvidence() => ResidentTaskRecord(
    taskId: taskId,
    rtId: rtId,
    templateSnapshot: templateSnapshot,
    deadline: deadline,
    status: status,
    participation: participation,
    completion: completion,
    locationReference: locationReference,
    completionNote: completionNote,
    completionSubmittedAt: completionSubmittedAt,
    verifiedAt: verifiedAt,
    pendingChoice: pendingChoice,
    hasSyncConflict: hasSyncConflict,
    hasPendingCompletionSync: hasPendingCompletionSync,
  );
}

/// Bounded active-task page; [isPartial] warns that more tasks exist.
final class ResidentTaskList {
  const ResidentTaskList({
    required this.items,
    required this.isPartial,
    this.isCached = false,
    this.lastSyncedAt,
    this.syncIssues = const [],
  });

  final List<ResidentTaskRecord> items;
  final bool isPartial;

  /// True only when this list was loaded from the local snapshot.
  final bool isCached;

  /// Timestamp of the last successfully authorized server snapshot.
  final DateTime? lastSyncedAt;
  final List<ResidentTaskSyncIssue> syncIssues;
}

enum ResidentTaskSyncIssueKind {
  choicePending,
  choiceConflict,
  completionPending,
  completionConflict,
  taskUnavailable,
}

/// A small, non-sensitive sync status suitable for resident UI.
final class ResidentTaskSyncIssue {
  const ResidentTaskSyncIssue({
    required this.taskId,
    required this.kind,
    this.pendingChoice,
    this.authoritativeParticipation,
    this.taskTitle,
  });

  final String taskId;
  final ResidentTaskSyncIssueKind kind;
  final ParticipationChoice? pendingChoice;
  final ParticipationState? authoritativeParticipation;
  final String? taskTitle;
}

/// This exception is the only condition that allows resident-task cache fallback.
final class TransientTaskNetworkUnavailableException implements Exception {
  const TransientTaskNetworkUnavailableException();
}

/// A server response indicates an authoritative task/response conflict.
final class TaskResponseConflictException implements Exception {
  const TaskResponseConflictException({this.code = 'conflict'});

  final String code;
}

/// A server rejected the command. It is not an offline/cache fallback signal.
final class TaskResponseRejectedException implements Exception {
  const TaskResponseRejectedException({required this.code});

  final String code;
}

/// Application-layer contract for the resident task cache and durable outbox.
abstract interface class ResidentTaskOfflineStore {
  Future<void> cacheAuthorizedActiveTasks({
    required ResidentSession session,
    required ResidentTaskList taskList,
    required DateTime syncedAt,
  });

  Future<ResidentTaskCacheSnapshot?> readCachedActiveTasks({
    required ResidentSession session,
  });

  Future<PendingResidentTaskChoice> enqueueChoice({
    required ResidentSession session,
    required String taskId,
    required ParticipationChoice choice,
    required String commandId,
    required DateTime queuedAt,
    String? taskTitle,
  });

  Future<List<PendingResidentTaskChoice>> pendingChoices({
    required ResidentSession session,
  });

  Future<void> removeChoice({
    required ResidentSession session,
    required String commandId,
  });

  Future<void> markChoiceConflict({
    required ResidentSession session,
    required String commandId,
    ParticipationState? authoritativeParticipation,
    bool taskNoLongerActive = false,
  });

  Future<void> markChoiceAttempted({
    required ResidentSession session,
    required String commandId,
    required DateTime attemptedAt,
  });

  Future<PendingResidentTaskCompletion> enqueueCompletion({
    required ResidentSession session,
    required String taskId,
    required String commandId,
    required DateTime queuedAt,
    String? taskTitle,
  });

  Future<List<PendingResidentTaskCompletion>> pendingCompletions({
    required ResidentSession session,
  });

  Future<void> markCompletionAttempted({
    required ResidentSession session,
    required String commandId,
    required DateTime attemptedAt,
  });

  Future<void> removeCompletion({
    required ResidentSession session,
    required String commandId,
  });

  Future<void> markCompletionConflict({
    required ResidentSession session,
    required String commandId,
    bool taskNoLongerActive = false,
  });
}

final class ResidentTaskCacheSnapshot {
  const ResidentTaskCacheSnapshot({
    required this.taskList,
    required this.syncedAt,
  });

  final ResidentTaskList taskList;
  final DateTime syncedAt;
}

const int maxResidentTaskRetryCount = 1000000;

final class PendingResidentTaskChoice {
  const PendingResidentTaskChoice({
    required this.taskId,
    required this.choice,
    required this.commandId,
    required this.queuedAt,
    this.taskTitle,
    this.hasConflict = false,
    this.authoritativeParticipation,
    this.taskNoLongerActive = false,
    this.retryCount = 0,
    this.lastAttemptAt,
  });

  final String taskId;
  final ParticipationChoice choice;
  final String commandId;
  final DateTime queuedAt;
  final String? taskTitle;
  final bool hasConflict;
  final ParticipationState? authoritativeParticipation;
  final bool taskNoLongerActive;
  final int retryCount;
  final DateTime? lastAttemptAt;

  PendingResidentTaskChoice withAttempt(DateTime at) =>
      PendingResidentTaskChoice(
        taskId: taskId,
        choice: choice,
        commandId: commandId,
        queuedAt: queuedAt,
        taskTitle: taskTitle,
        hasConflict: hasConflict,
        authoritativeParticipation: authoritativeParticipation,
        taskNoLongerActive: taskNoLongerActive,
        retryCount: retryCount < maxResidentTaskRetryCount
            ? retryCount + 1
            : maxResidentTaskRetryCount,
        lastAttemptAt: at.toUtc(),
      );

  PendingResidentTaskChoice withConflict({
    ParticipationState? authoritativeParticipation,
    bool taskNoLongerActive = false,
  }) => PendingResidentTaskChoice(
    taskId: taskId,
    choice: choice,
    commandId: commandId,
    queuedAt: queuedAt,
    taskTitle: taskTitle,
    hasConflict: true,
    authoritativeParticipation: authoritativeParticipation,
    taskNoLongerActive: taskNoLongerActive,
    retryCount: retryCount,
    lastAttemptAt: lastAttemptAt,
  );
}

/// Durable no-note completion command. It intentionally has no note field.
final class PendingResidentTaskCompletion {
  const PendingResidentTaskCompletion({
    required this.taskId,
    required this.commandId,
    required this.queuedAt,
    this.taskTitle,
    this.hasConflict = false,
    this.taskNoLongerActive = false,
    this.retryCount = 0,
    this.lastAttemptAt,
  });

  final String taskId;
  final String commandId;
  final DateTime queuedAt;
  final String? taskTitle;
  final bool hasConflict;
  final bool taskNoLongerActive;
  final int retryCount;
  final DateTime? lastAttemptAt;

  PendingResidentTaskCompletion withAttempt(DateTime at) =>
      PendingResidentTaskCompletion(
        taskId: taskId,
        commandId: commandId,
        queuedAt: queuedAt,
        taskTitle: taskTitle,
        hasConflict: hasConflict,
        taskNoLongerActive: taskNoLongerActive,
        retryCount: retryCount < maxResidentTaskRetryCount
            ? retryCount + 1
            : maxResidentTaskRetryCount,
        lastAttemptAt: at.toUtc(),
      );

  PendingResidentTaskCompletion withConflict({
    bool taskNoLongerActive = false,
  }) => PendingResidentTaskCompletion(
    taskId: taskId,
    commandId: commandId,
    queuedAt: queuedAt,
    taskTitle: taskTitle,
    hasConflict: true,
    taskNoLongerActive: taskNoLongerActive,
    retryCount: retryCount,
    lastAttemptAt: lastAttemptAt,
  );
}

/// An optional completion note cannot be safely queued offline.
final class OfflineCompletionNoteException implements Exception {
  const OfflineCompletionNoteException();

  @override
  String toString() =>
      'Completion with a note needs a connection. The note was not saved.';
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
    this.evidenceId,
    this.pendingChoice,
    this.isPendingSync = false,
    this.hasSyncConflict = false,
    this.isPendingCompletionSync = false,
  });

  final String taskId;
  final ParticipationState participation;
  final CompletionState completion;
  final String? completionNote;
  final DateTime? completionSubmittedAt;
  final DateTime? verifiedAt;
  final String? evidenceId;
  final ParticipationChoice? pendingChoice;
  final bool isPendingSync;
  final bool hasSyncConflict;
  final bool isPendingCompletionSync;

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
        evidenceId: _optionalEvidenceId(wire['evidenceId']),
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
    this.evidenceId,
  });

  final String responseId;
  final String taskId;
  final String taskTitle;
  final String nickname;
  final DateTime submittedAt;
  final String? completionNote;
  final String? evidenceId;

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
        evidenceId: _optionalEvidenceId(wire['evidenceId']),
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
    TaskEvidenceBoundary? evidenceBoundary,
    required ResidentSessionVault vault,
    ResidentTaskOfflineStore? offlineStore,
    String Function()? commandIdFactory,
    DateTime Function()? clock,
  }) : _boundary = boundary,
       _evidenceBoundary = evidenceBoundary,
       _vault = vault,
       _offlineStore = offlineStore,
       _commandIdFactory = commandIdFactory ?? _newCommandId,
       _clock = clock ?? DateTime.now;

  final TaskResponseBoundary _boundary;
  final TaskEvidenceBoundary? _evidenceBoundary;
  final ResidentSessionVault _vault;
  final ResidentTaskOfflineStore? _offlineStore;
  final String Function() _commandIdFactory;
  final DateTime Function() _clock;
  final Map<String, String> _choiceCommands = {};
  final Map<String, String> _completionCommands = {};
  final Map<String, String?> _completionNotes = {};
  final Map<String, String?> _completionEvidenceIds = {};
  final Map<String, String> _evidenceDeleteCommands = {};
  final Map<String, String> _verificationCommands = {};

  Future<ResidentTaskList> listResidentActiveTasks({
    ResidentSession? session,
  }) async {
    final token = await _sessionToken();
    late final ResidentTaskList serverList;
    try {
      serverList = await _boundary.listResidentActiveTasks(sessionToken: token);
    } on TransientTaskNetworkUnavailableException {
      final store = _offlineStore;
      if (store == null || session == null) rethrow;
      final cached = await store.readCachedActiveTasks(session: session);
      if (cached == null) rethrow;
      final choices = await store.pendingChoices(session: session);
      final completions = await store.pendingCompletions(session: session);
      return _decorateList(
        cached.taskList,
        choices: choices,
        completions: completions,
        isCached: true,
        lastSyncedAt: cached.syncedAt,
      );
    }

    final store = _offlineStore;
    if (store == null || session == null) return serverList;
    _validateListScope(serverList, session);
    final syncedAt = _clock().toUtc();
    // A local persistence failure must not hide a valid remote list.
    try {
      await store.cacheAuthorizedActiveTasks(
        session: session,
        taskList: serverList,
        syncedAt: syncedAt,
      );
    } catch (_) {
      // The remote response is still safe to display.
    }
    return _replayQueuedCommands(
      serverList,
      session: session,
      sessionToken: token,
      syncedAt: syncedAt,
    );
  }

  Future<TaskResponseRecord> recordParticipation({
    required String taskId,
    required ParticipationChoice choice,
    ResidentSession? session,
  }) async {
    final token = await _sessionToken();
    final store = _offlineStore;
    if (store == null || session == null) {
      final commandId = _choiceCommands.putIfAbsent(taskId, _commandIdFactory);
      final result = await _boundary.recordResidentTaskResponse(
        sessionToken: token,
        taskId: taskId,
        choice: choice,
        commandId: commandId,
      );
      _choiceCommands.remove(taskId);
      return result;
    }

    final queued = await store.pendingChoices(session: session);
    PendingResidentTaskChoice? existing;
    for (final command in queued) {
      if (command.taskId == taskId) existing = command;
    }
    if (existing != null && existing.choice != choice) {
      throw StateError('A different participation choice is already pending.');
    }
    final cached = await _cachedTask(store, session, taskId);
    if (existing?.hasConflict ?? false) {
      return TaskResponseRecord(
        taskId: taskId,
        participation:
            existing!.authoritativeParticipation ??
            cached?.participation ??
            ParticipationState.unresponded,
        completion: cached?.completion ?? CompletionState.notSubmitted,
        pendingChoice: choice,
        isPendingSync: true,
        hasSyncConflict: true,
      );
    }

    // Enqueue is durable and intentionally happens before the callable request.
    // If it fails, no request is sent and no action is reported as queued.
    final command = await store.enqueueChoice(
      session: session,
      taskId: taskId,
      choice: choice,
      commandId: existing?.commandId ?? _commandIdFactory(),
      queuedAt: _clock().toUtc(),
      taskTitle: cached?.templateSnapshot.title,
    );
    try {
      final result = await _boundary.recordResidentTaskResponse(
        sessionToken: token,
        taskId: taskId,
        choice: choice,
        commandId: command.commandId,
      );
      if (result.participation != _stateFor(choice)) {
        await store.markChoiceConflict(
          session: session,
          commandId: command.commandId,
          authoritativeParticipation: result.participation,
        );
        return _responseWithChoiceState(
          result,
          pendingChoice: choice,
          pending: true,
          conflict: true,
        );
      }
      // The server accepted it. Failures in local cleanup/cache must not turn a
      // successful online response into an apparent failure; the idempotent
      // command remains available for reconciliation if cleanup did not persist.
      try {
        await store.removeChoice(
          session: session,
          commandId: command.commandId,
        );
      } catch (_) {}
      try {
        await _updateCachedTask(store, session, result);
      } catch (_) {}
      return result;
    } on TransientTaskNetworkUnavailableException {
      return TaskResponseRecord(
        taskId: taskId,
        participation: cached?.participation ?? ParticipationState.unresponded,
        completion: cached?.completion ?? CompletionState.notSubmitted,
        pendingChoice: choice,
        isPendingSync: true,
      );
    } on TaskResponseConflictException {
      await store.markChoiceConflict(
        session: session,
        commandId: command.commandId,
        authoritativeParticipation: cached?.participation,
        taskNoLongerActive: true,
      );
      return TaskResponseRecord(
        taskId: taskId,
        participation: cached?.participation ?? ParticipationState.unresponded,
        completion: cached?.completion ?? CompletionState.notSubmitted,
        pendingChoice: choice,
        isPendingSync: true,
        hasSyncConflict: true,
      );
    } on TaskResponseRejectedException {
      await store.markChoiceConflict(
        session: session,
        commandId: command.commandId,
        authoritativeParticipation: cached?.participation,
      );
      return TaskResponseRecord(
        taskId: taskId,
        participation: cached?.participation ?? ParticipationState.unresponded,
        completion: cached?.completion ?? CompletionState.notSubmitted,
        pendingChoice: choice,
        isPendingSync: true,
        hasSyncConflict: true,
      );
    } catch (_) {
      // Preserve the durable intent and stop automatic retries until the next
      // authorized list explains the server state.
      try {
        await store.markChoiceConflict(
          session: session,
          commandId: command.commandId,
          authoritativeParticipation: cached?.participation,
        );
      } catch (_) {}
      rethrow;
    }
  }

  Future<TaskResponseRecord> submitCompletion({
    required String taskId,
    required String? note,
    String? evidenceId,
    ResidentSession? session,
  }) async {
    if (evidenceId != null && !_isEvidenceId(evidenceId)) {
      throw ArgumentError.value(evidenceId, 'evidenceId');
    }
    final normalizedNote = _normalizeOptionalText(note);
    final token = await _sessionToken();
    final store = _offlineStore;
    if (normalizedNote == null &&
        evidenceId == null &&
        store != null &&
        session != null) {
      final cached = await _cachedTask(store, session, taskId);
      final queued = await store.pendingCompletions(session: session);
      PendingResidentTaskCompletion? existing;
      for (final command in queued) {
        if (command.taskId == taskId) existing = command;
      }
      if (existing?.hasConflict ?? false) {
        return TaskResponseRecord(
          taskId: taskId,
          participation:
              cached?.participation ?? ParticipationState.unresponded,
          completion: cached?.completion ?? CompletionState.notSubmitted,
          isPendingSync: true,
          isPendingCompletionSync: true,
          hasSyncConflict: true,
        );
      }
      final command = await store.enqueueCompletion(
        session: session,
        taskId: taskId,
        commandId: existing?.commandId ?? _commandIdFactory(),
        queuedAt: _clock().toUtc(),
        taskTitle: cached?.templateSnapshot.title,
      );
      try {
        final result = await _boundary.submitTaskCompletion(
          sessionToken: token,
          taskId: taskId,
          note: null,
          commandId: command.commandId,
        );
        if (result.completion == CompletionState.notSubmitted) {
          await store.markCompletionConflict(
            session: session,
            commandId: command.commandId,
          );
          return _completionWithPendingState(
            result,
            pending: true,
            conflict: true,
          );
        }
        try {
          await store.removeCompletion(
            session: session,
            commandId: command.commandId,
          );
        } catch (_) {}
        try {
          await _updateCachedTask(store, session, result);
        } catch (_) {}
        return result;
      } on TransientTaskNetworkUnavailableException {
        return TaskResponseRecord(
          taskId: taskId,
          participation:
              cached?.participation ?? ParticipationState.unresponded,
          completion: cached?.completion ?? CompletionState.notSubmitted,
          isPendingSync: true,
          isPendingCompletionSync: true,
        );
      } on TaskResponseConflictException {
        await store.markCompletionConflict(
          session: session,
          commandId: command.commandId,
          taskNoLongerActive: true,
        );
        return TaskResponseRecord(
          taskId: taskId,
          participation:
              cached?.participation ?? ParticipationState.unresponded,
          completion: cached?.completion ?? CompletionState.notSubmitted,
          isPendingSync: true,
          isPendingCompletionSync: true,
          hasSyncConflict: true,
        );
      } on TaskResponseRejectedException {
        await store.markCompletionConflict(
          session: session,
          commandId: command.commandId,
        );
        return TaskResponseRecord(
          taskId: taskId,
          participation:
              cached?.participation ?? ParticipationState.unresponded,
          completion: cached?.completion ?? CompletionState.notSubmitted,
          isPendingSync: true,
          isPendingCompletionSync: true,
          hasSyncConflict: true,
        );
      } catch (_) {
        try {
          await store.markCompletionConflict(
            session: session,
            commandId: command.commandId,
          );
        } catch (_) {}
        rethrow;
      }
    }

    // Notes are optional but private. Never add one to the outbox. If the call
    // is unavailable, tell the caller it was not saved locally.
    final previousNote = _completionNotes[taskId];
    final previousEvidenceId = _completionEvidenceIds[taskId];
    if (_completionCommands.containsKey(taskId) &&
        (previousNote != normalizedNote || previousEvidenceId != evidenceId)) {
      _completionCommands.remove(taskId);
      _completionNotes.remove(taskId);
      _completionEvidenceIds.remove(taskId);
    }
    final commandId = _completionCommands.putIfAbsent(
      taskId,
      _commandIdFactory,
    );
    _completionNotes.putIfAbsent(taskId, () => normalizedNote);
    _completionEvidenceIds.putIfAbsent(taskId, () => evidenceId);
    try {
      final result = await _boundary.submitTaskCompletion(
        sessionToken: token,
        taskId: taskId,
        note: normalizedNote,
        commandId: commandId,
        evidenceId: evidenceId,
      );
      _completionCommands.remove(taskId);
      _completionNotes.remove(taskId);
      _completionEvidenceIds.remove(taskId);
      return result;
    } on TransientTaskNetworkUnavailableException {
      _completionCommands.remove(taskId);
      _completionNotes.remove(taskId);
      _completionEvidenceIds.remove(taskId);
      if (normalizedNote != null) {
        throw const OfflineCompletionNoteException();
      }
      rethrow;
    }
  }

  Future<String> uploadEvidence({
    required String taskId,
    required Uint8List sanitizedJpegBytes,
  }) async {
    final evidenceBoundary = _evidenceBoundary;
    if (evidenceBoundary == null) {
      throw StateError('Evidence upload is not configured.');
    }
    return evidenceBoundary.uploadResidentTaskEvidence(
      sessionToken: await _sessionToken(),
      taskId: taskId,
      requestId: _commandIdFactory(),
      sanitizedJpegBytes: sanitizedJpegBytes,
    );
  }

  Future<void> deleteEvidence({required String evidenceId}) async {
    if (!_isEvidenceId(evidenceId)) {
      throw ArgumentError.value(evidenceId, 'evidenceId');
    }
    final evidenceBoundary = _evidenceBoundary;
    if (evidenceBoundary == null) {
      throw StateError('Evidence deletion is not configured.');
    }
    final commandId = _evidenceDeleteCommands.putIfAbsent(
      evidenceId,
      _commandIdFactory,
    );
    await evidenceBoundary.deleteResidentTaskEvidence(
      sessionToken: await _sessionToken(),
      evidenceId: evidenceId,
      commandId: commandId,
    );
    _evidenceDeleteCommands.remove(evidenceId);
  }

  Future<Uint8List> getEvidenceForVerification({required String evidenceId}) {
    if (!_isEvidenceId(evidenceId)) {
      throw ArgumentError.value(evidenceId, 'evidenceId');
    }
    final evidenceBoundary = _evidenceBoundary;
    if (evidenceBoundary == null) {
      throw StateError('Evidence review is not configured.');
    }
    return evidenceBoundary.getTaskEvidenceForVerification(
      evidenceId: evidenceId,
    );
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

  Future<ResidentTaskList> _replayQueuedCommands(
    ResidentTaskList serverList, {
    required ResidentSession session,
    required String sessionToken,
    required DateTime syncedAt,
  }) async {
    final store = _offlineStore!;
    final choices = await store.pendingChoices(session: session);
    final completions = await store.pendingCompletions(session: session);
    final items = serverList.items.toList(growable: true);
    final issues = <ResidentTaskSyncIssue>[];

    for (final command in choices) {
      final index = items.indexWhere((task) => task.taskId == command.taskId);
      if (command.hasConflict) {
        _applyPendingChoice(items, index, command);
        issues.add(_choiceIssue(command));
        continue;
      }
      if (index < 0) {
        await store.markChoiceConflict(
          session: session,
          commandId: command.commandId,
          taskNoLongerActive: true,
        );
        final conflict = command.withConflict(taskNoLongerActive: true);
        issues.add(_choiceIssue(conflict));
        continue;
      }
      final task = items[index];
      final desired = _stateFor(command.choice);
      if (task.participation != ParticipationState.unresponded) {
        if (task.participation == desired) {
          await store.removeChoice(
            session: session,
            commandId: command.commandId,
          );
        } else {
          await store.markChoiceConflict(
            session: session,
            commandId: command.commandId,
            authoritativeParticipation: task.participation,
          );
          final conflict = command.withConflict(
            authoritativeParticipation: task.participation,
          );
          _applyPendingChoice(items, index, conflict);
          issues.add(_choiceIssue(conflict));
        }
        continue;
      }
      await store.markChoiceAttempted(
        session: session,
        commandId: command.commandId,
        attemptedAt: _clock().toUtc(),
      );
      try {
        final response = await _boundary.recordResidentTaskResponse(
          sessionToken: sessionToken,
          taskId: command.taskId,
          choice: command.choice,
          commandId: command.commandId,
        );
        if (response.participation == desired) {
          await store.removeChoice(
            session: session,
            commandId: command.commandId,
          );
          items[index] = task.withResponse(
            response,
            clearPendingChoice: true,
            hasSyncConflict: false,
          );
        } else {
          await store.markChoiceConflict(
            session: session,
            commandId: command.commandId,
            authoritativeParticipation: response.participation,
          );
          final conflict = command.withConflict(
            authoritativeParticipation: response.participation,
          );
          items[index] = task
              .withResponse(response, hasSyncConflict: true)
              ._withPendingChoice(command.choice, conflict: true);
          issues.add(_choiceIssue(conflict));
        }
      } on TransientTaskNetworkUnavailableException {
        _applyPendingChoice(items, index, command);
        issues.add(_choiceIssue(command));
      } on TaskResponseConflictException {
        await store.markChoiceConflict(
          session: session,
          commandId: command.commandId,
          authoritativeParticipation: task.participation,
          taskNoLongerActive: true,
        );
        final conflict = command.withConflict(
          authoritativeParticipation: task.participation,
          taskNoLongerActive: true,
        );
        if (index >= 0) items.removeAt(index);
        issues.add(_choiceIssue(conflict));
      } on TaskResponseRejectedException {
        await store.markChoiceConflict(
          session: session,
          commandId: command.commandId,
          authoritativeParticipation: task.participation,
        );
        final conflict = command.withConflict(
          authoritativeParticipation: task.participation,
        );
        _applyPendingChoice(items, index, conflict);
        issues.add(_choiceIssue(conflict));
      }
    }

    for (final command in completions) {
      final index = items.indexWhere((task) => task.taskId == command.taskId);
      if (command.hasConflict) {
        _applyPendingCompletion(items, index, command);
        issues.add(_completionIssue(command));
        continue;
      }
      if (index < 0) {
        await store.markCompletionConflict(
          session: session,
          commandId: command.commandId,
          taskNoLongerActive: true,
        );
        final conflict = command.withConflict(taskNoLongerActive: true);
        issues.add(_completionIssue(conflict));
        continue;
      }
      final task = items[index];
      if (task.completion != CompletionState.notSubmitted) {
        // The prior command may have committed before its response was lost.
        await store.removeCompletion(
          session: session,
          commandId: command.commandId,
        );
        continue;
      }
      if (task.participation != ParticipationState.joined) {
        await store.markCompletionConflict(
          session: session,
          commandId: command.commandId,
        );
        final conflict = command.withConflict();
        _applyPendingCompletion(items, index, conflict);
        issues.add(_completionIssue(conflict));
        continue;
      }
      await store.markCompletionAttempted(
        session: session,
        commandId: command.commandId,
        attemptedAt: _clock().toUtc(),
      );
      try {
        final response = await _boundary.submitTaskCompletion(
          sessionToken: sessionToken,
          taskId: command.taskId,
          note: null,
          commandId: command.commandId,
        );
        if (response.completion != CompletionState.notSubmitted) {
          await store.removeCompletion(
            session: session,
            commandId: command.commandId,
          );
          items[index] = task.withResponse(
            response,
            hasPendingCompletionSync: false,
            hasSyncConflict: false,
          );
        } else {
          await store.markCompletionConflict(
            session: session,
            commandId: command.commandId,
          );
          final conflict = command.withConflict();
          _applyPendingCompletion(items, index, conflict);
          issues.add(_completionIssue(conflict));
        }
      } on TransientTaskNetworkUnavailableException {
        _applyPendingCompletion(items, index, command);
        issues.add(_completionIssue(command));
      } on TaskResponseConflictException {
        await store.markCompletionConflict(
          session: session,
          commandId: command.commandId,
          taskNoLongerActive: true,
        );
        final conflict = command.withConflict(taskNoLongerActive: true);
        if (index >= 0) items.removeAt(index);
        issues.add(_completionIssue(conflict));
      } on TaskResponseRejectedException {
        await store.markCompletionConflict(
          session: session,
          commandId: command.commandId,
        );
        final conflict = command.withConflict();
        _applyPendingCompletion(items, index, conflict);
        issues.add(_completionIssue(conflict));
      }
    }

    final result = ResidentTaskList(
      items: List<ResidentTaskRecord>.unmodifiable(items),
      isPartial: serverList.isPartial,
      isCached: false,
      lastSyncedAt: syncedAt,
      syncIssues: List<ResidentTaskSyncIssue>.unmodifiable(issues),
    );
    try {
      await store.cacheAuthorizedActiveTasks(
        session: session,
        taskList: result,
        syncedAt: syncedAt,
      );
    } catch (_) {
      // Fresh server data remains displayable when local writes fail.
    }
    return result;
  }

  ResidentTaskList _decorateList(
    ResidentTaskList list, {
    required List<PendingResidentTaskChoice> choices,
    required List<PendingResidentTaskCompletion> completions,
    required bool isCached,
    required DateTime lastSyncedAt,
  }) {
    final items = list.items.toList(growable: true);
    final issues = <ResidentTaskSyncIssue>[];
    for (final command in choices) {
      final index = items.indexWhere((task) => task.taskId == command.taskId);
      _applyPendingChoice(items, index, command);
      issues.add(_choiceIssue(command));
    }
    for (final command in completions) {
      final index = items.indexWhere((task) => task.taskId == command.taskId);
      _applyPendingCompletion(items, index, command);
      issues.add(_completionIssue(command));
    }
    return ResidentTaskList(
      items: List<ResidentTaskRecord>.unmodifiable(items),
      isPartial: list.isPartial,
      isCached: isCached,
      lastSyncedAt: lastSyncedAt,
      syncIssues: List<ResidentTaskSyncIssue>.unmodifiable(issues),
    );
  }

  void _applyPendingChoice(
    List<ResidentTaskRecord> items,
    int index,
    PendingResidentTaskChoice command,
  ) {
    if (index >= 0) {
      items[index] = items[index]._withPendingChoice(
        command.choice,
        conflict: command.hasConflict,
      );
    }
  }

  void _applyPendingCompletion(
    List<ResidentTaskRecord> items,
    int index,
    PendingResidentTaskCompletion command,
  ) {
    if (index >= 0) {
      items[index] = items[index]._withPendingCompletion(
        conflict: command.hasConflict,
      );
    }
  }

  ResidentTaskSyncIssue _choiceIssue(PendingResidentTaskChoice command) =>
      ResidentTaskSyncIssue(
        taskId: command.taskId,
        taskTitle: command.taskTitle,
        kind: command.taskNoLongerActive
            ? ResidentTaskSyncIssueKind.taskUnavailable
            : command.hasConflict
            ? ResidentTaskSyncIssueKind.choiceConflict
            : ResidentTaskSyncIssueKind.choicePending,
        pendingChoice: command.choice,
        authoritativeParticipation: command.authoritativeParticipation,
      );

  ResidentTaskSyncIssue _completionIssue(
    PendingResidentTaskCompletion command,
  ) => ResidentTaskSyncIssue(
    taskId: command.taskId,
    taskTitle: command.taskTitle,
    kind: command.taskNoLongerActive
        ? ResidentTaskSyncIssueKind.taskUnavailable
        : command.hasConflict
        ? ResidentTaskSyncIssueKind.completionConflict
        : ResidentTaskSyncIssueKind.completionPending,
  );

  Future<ResidentTaskRecord?> _cachedTask(
    ResidentTaskOfflineStore store,
    ResidentSession session,
    String taskId,
  ) async {
    try {
      final cached = await store.readCachedActiveTasks(session: session);
      for (final task
          in cached?.taskList.items ?? const <ResidentTaskRecord>[]) {
        if (task.taskId == taskId) return task;
      }
    } catch (_) {
      // The cache is advisory; the authorized callable remains authoritative.
    }
    return null;
  }

  Future<void> _updateCachedTask(
    ResidentTaskOfflineStore store,
    ResidentSession session,
    TaskResponseRecord response,
  ) async {
    final cached = await store.readCachedActiveTasks(session: session);
    if (cached == null) return;
    final items = cached.taskList.items
        .map(
          (task) => task.taskId == response.taskId
              ? task.withResponse(
                  response,
                  clearPendingChoice: true,
                  hasSyncConflict: false,
                  hasPendingCompletionSync: false,
                )
              : task,
        )
        .toList(growable: false);
    await store.cacheAuthorizedActiveTasks(
      session: session,
      taskList: ResidentTaskList(
        items: items,
        isPartial: cached.taskList.isPartial,
      ),
      syncedAt: _clock().toUtc(),
    );
  }

  TaskResponseRecord _responseWithChoiceState(
    TaskResponseRecord response, {
    required ParticipationChoice pendingChoice,
    required bool pending,
    required bool conflict,
  }) => TaskResponseRecord(
    taskId: response.taskId,
    participation: response.participation,
    completion: response.completion,
    completionNote: response.completionNote,
    completionSubmittedAt: response.completionSubmittedAt,
    verifiedAt: response.verifiedAt,
    evidenceId: response.evidenceId,
    pendingChoice: pendingChoice,
    isPendingSync: pending,
    hasSyncConflict: conflict,
  );

  TaskResponseRecord _completionWithPendingState(
    TaskResponseRecord response, {
    required bool pending,
    required bool conflict,
  }) => TaskResponseRecord(
    taskId: response.taskId,
    participation: response.participation,
    completion: response.completion,
    completionNote: response.completionNote,
    completionSubmittedAt: response.completionSubmittedAt,
    verifiedAt: response.verifiedAt,
    evidenceId: response.evidenceId,
    isPendingSync: pending,
    isPendingCompletionSync: pending,
    hasSyncConflict: conflict,
  );

  void _validateListScope(ResidentTaskList list, ResidentSession session) {
    for (final task in list.items) {
      if (task.rtId != session.communityId || task.status != 'ACTIVE') {
        throw const FormatException(
          'Resident task scope does not match session.',
        );
      }
    }
  }

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

extension on ResidentTaskRecord {
  ResidentTaskRecord _withPendingChoice(
    ParticipationChoice choice, {
    required bool conflict,
  }) => ResidentTaskRecord(
    taskId: taskId,
    rtId: rtId,
    templateSnapshot: templateSnapshot,
    deadline: deadline,
    status: status,
    participation: participation,
    completion: completion,
    locationReference: locationReference,
    completionNote: completionNote,
    completionSubmittedAt: completionSubmittedAt,
    verifiedAt: verifiedAt,
    evidenceId: evidenceId,
    pendingChoice: choice,
    hasSyncConflict: conflict,
    hasPendingCompletionSync: hasPendingCompletionSync,
  );

  ResidentTaskRecord _withPendingCompletion({required bool conflict}) =>
      ResidentTaskRecord(
        taskId: taskId,
        rtId: rtId,
        templateSnapshot: templateSnapshot,
        deadline: deadline,
        status: status,
        participation: participation,
        completion: completion,
        locationReference: locationReference,
        completionNote: completionNote,
        completionSubmittedAt: completionSubmittedAt,
        verifiedAt: verifiedAt,
        evidenceId: evidenceId,
        pendingChoice: pendingChoice,
        hasSyncConflict: conflict,
        hasPendingCompletionSync: true,
      );
}

ParticipationState _stateFor(ParticipationChoice choice) => switch (choice) {
  ParticipationChoice.join => ParticipationState.joined,
  ParticipationChoice.decline => ParticipationState.declined,
};

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

bool _isEvidenceId(String value) => RegExp(r'^[a-f0-9]{40}$').hasMatch(value);

String? _optionalEvidenceId(Object? value) {
  final id = _optionalString(value, 'evidenceId');
  if (id != null && !_isEvidenceId(id)) {
    throw const FormatException('Invalid evidenceId.');
  }
  return id;
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
