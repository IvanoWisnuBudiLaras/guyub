// ignore_for_file: prefer_initializing_formals

import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../../core/database/local_store.dart';
import '../../auth/application/resident_session.dart';
import '../application/task_response.dart';
import '../application/task_response_boundary.dart';

/// Durable, resident-scoped storage for authorized task snapshots and commands.
///
/// Scope identifiers are used only to derive storage keys. Neither the
/// resident ID, RT ID, nor bearer token is written into stored values.
final class LocalResidentTaskOfflineStore implements ResidentTaskOfflineStore {
  LocalResidentTaskOfflineStore({required LocalStore localStore})
    : _localStore = localStore;

  static const _cachePrefix = 'resident-task-cache.v1.';
  static const _outboxPrefix = 'resident-task-outbox.v1.';
  final LocalStore _localStore;
  Future<void> _outboxTail = Future<void>.value();

  @override
  Future<void> cacheAuthorizedActiveTasks({
    required ResidentSession session,
    required ResidentTaskList taskList,
    required DateTime syncedAt,
  }) async {
    for (final item in taskList.items) {
      if (item.status != 'ACTIVE' || item.rtId != session.communityId) {
        throw const FormatException(
          'Only authorized active tasks can be cached.',
        );
      }
    }
    final wire = <String, Object?>{
      'version': 1,
      'syncedAt': syncedAt.toUtc().toIso8601String(),
      'isPartial': taskList.isPartial,
      'items': taskList.items.map(_taskToWire).toList(growable: false),
    };
    await _localStore.write(
      '$_cachePrefix${_scopeHash(session)}',
      jsonEncode(wire),
    );
  }

  @override
  Future<void> clearResidentData({required ResidentSession session}) async {
    await _withOutboxLock(() async {
      await _localStore.delete('$_cachePrefix${_scopeHash(session)}');
      await _localStore.delete('$_outboxPrefix${_scopeHash(session)}');
    });
  }

  @override
  Future<ResidentTaskCacheSnapshot?> readCachedActiveTasks({
    required ResidentSession session,
  }) async {
    final encoded = await _localStore.read(
      '$_cachePrefix${_scopeHash(session)}',
    );
    if (encoded == null) return null;
    try {
      final root = _readMap(jsonDecode(encoded), 'cached task snapshot');
      if (root['version'] != 1) return null;
      final rawItems = root['items'];
      if (rawItems is! List) return null;
      final syncedAt = DateTime.tryParse(root['syncedAt'] as String? ?? '');
      if (syncedAt == null || root['isPartial'] is! bool) return null;
      final records = <ResidentTaskRecord>[];
      for (final rawItem in rawItems) {
        final wire = Map<String, Object?>.from(
          _readMap(rawItem, 'cached task'),
        );
        // RT ID is supplied from the already validated hashed storage scope.
        wire['rtId'] = session.communityId;
        final task = ResidentTaskRecord.fromWire(wire);
        if (task.rtId != session.communityId || task.status != 'ACTIVE') {
          return null;
        }
        records.add(task);
      }
      return ResidentTaskCacheSnapshot(
        taskList: ResidentTaskList(
          items: List<ResidentTaskRecord>.unmodifiable(records),
          isPartial: root['isPartial'] as bool,
          isCached: true,
          lastSyncedAt: syncedAt.toUtc(),
        ),
        syncedAt: syncedAt.toUtc(),
      );
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }

  /// Persists a choice before the first request is sent. A retry for the same
  /// task/choice returns the original command ID. A different queued choice is
  /// not allowed to replace an already durable command.
  @override
  Future<PendingResidentTaskChoice> enqueueChoice({
    required ResidentSession session,
    required String taskId,
    required ParticipationChoice choice,
    required String commandId,
    required DateTime queuedAt,
    String? taskTitle,
  }) async {
    return _withOutboxLock(() async {
      final outbox = await _readOutbox(session);
      for (final command in outbox.choices) {
        if (command.taskId != taskId) continue;
        if (command.choice != choice) {
          throw StateError(
            'A different participation choice is already pending.',
          );
        }
        return command;
      }
      final command = PendingResidentTaskChoice(
        taskId: taskId,
        choice: choice,
        commandId: commandId,
        queuedAt: queuedAt.toUtc(),
        taskTitle: taskTitle,
      );
      await _writeOutbox(
        session,
        choices: [...outbox.choices, command],
        completions: outbox.completions,
      );
      return command;
    });
  }

  @override
  Future<List<PendingResidentTaskChoice>> pendingChoices({
    required ResidentSession session,
  }) async => (await _readOutbox(session)).choices;

  @override
  Future<void> removeChoice({
    required ResidentSession session,
    required String commandId,
  }) async => _withOutboxLock(() async {
    final outbox = await _readOutbox(session);
    await _writeOutbox(
      session,
      choices: outbox.choices
          .where((item) => item.commandId != commandId)
          .toList(growable: false),
      completions: outbox.completions,
    );
  });

  @override
  Future<void> markChoiceConflict({
    required ResidentSession session,
    required String commandId,
    ParticipationState? authoritativeParticipation,
    bool taskNoLongerActive = false,
  }) async => _withOutboxLock(() async {
    final outbox = await _readOutbox(session);
    await _writeOutbox(
      session,
      choices: outbox.choices
          .map(
            (item) => item.commandId == commandId
                ? item.withConflict(
                    authoritativeParticipation: authoritativeParticipation,
                    taskNoLongerActive: taskNoLongerActive,
                  )
                : item,
          )
          .toList(growable: false),
      completions: outbox.completions,
    );
  });

  @override
  Future<void> markChoiceAttempted({
    required ResidentSession session,
    required String commandId,
    required DateTime attemptedAt,
  }) async => _withOutboxLock(() async {
    final outbox = await _readOutbox(session);
    await _writeOutbox(
      session,
      choices: outbox.choices
          .map(
            (item) => item.commandId == commandId
                ? item.withAttempt(attemptedAt)
                : item,
          )
          .toList(growable: false),
      completions: outbox.completions,
    );
  });

  @override
  Future<PendingResidentTaskCompletion> enqueueCompletion({
    required ResidentSession session,
    required String taskId,
    required String commandId,
    required DateTime queuedAt,
    String? taskTitle,
  }) async => _withOutboxLock(() async {
    final outbox = await _readOutbox(session);
    for (final command in outbox.completions) {
      if (command.taskId == taskId) return command;
    }
    final command = PendingResidentTaskCompletion(
      taskId: taskId,
      commandId: commandId,
      queuedAt: queuedAt.toUtc(),
      taskTitle: taskTitle,
    );
    await _writeOutbox(
      session,
      choices: outbox.choices,
      completions: [...outbox.completions, command],
    );
    return command;
  });

  @override
  Future<List<PendingResidentTaskCompletion>> pendingCompletions({
    required ResidentSession session,
  }) async => (await _readOutbox(session)).completions;

  @override
  Future<void> markCompletionAttempted({
    required ResidentSession session,
    required String commandId,
    required DateTime attemptedAt,
  }) async => _withOutboxLock(() async {
    final outbox = await _readOutbox(session);
    await _writeOutbox(
      session,
      choices: outbox.choices,
      completions: outbox.completions
          .map(
            (item) => item.commandId == commandId
                ? item.withAttempt(attemptedAt)
                : item,
          )
          .toList(growable: false),
    );
  });

  @override
  Future<void> removeCompletion({
    required ResidentSession session,
    required String commandId,
  }) async => _withOutboxLock(() async {
    final outbox = await _readOutbox(session);
    await _writeOutbox(
      session,
      choices: outbox.choices,
      completions: outbox.completions
          .where((item) => item.commandId != commandId)
          .toList(growable: false),
    );
  });

  @override
  Future<void> markCompletionConflict({
    required ResidentSession session,
    required String commandId,
    bool taskNoLongerActive = false,
  }) async => _withOutboxLock(() async {
    final outbox = await _readOutbox(session);
    await _writeOutbox(
      session,
      choices: outbox.choices,
      completions: outbox.completions
          .map(
            (item) => item.commandId == commandId
                ? item.withConflict(taskNoLongerActive: taskNoLongerActive)
                : item,
          )
          .toList(growable: false),
    );
  });

  Future<_ResidentTaskOutbox> _readOutbox(ResidentSession session) async {
    final encoded = await _localStore.read(
      '$_outboxPrefix${_scopeHash(session)}',
    );
    if (encoded == null) return const _ResidentTaskOutbox();
    final root = _readMap(jsonDecode(encoded), 'task outbox');
    if (root['version'] != 1) {
      throw const FormatException('Invalid task outbox.');
    }
    final rawChoices = root['choices'] ?? root['commands'] ?? const <Object?>[];
    final rawCompletions = root['completions'] ?? const <Object?>[];
    if (rawChoices is! List || rawCompletions is! List) {
      throw const FormatException('Invalid task outbox.');
    }
    return _ResidentTaskOutbox(
      choices: rawChoices
          .map((item) => _choiceFromWire(_readMap(item, 'pending task choice')))
          .toList(growable: false),
      completions: rawCompletions
          .map(
            (item) =>
                _completionFromWire(_readMap(item, 'pending task completion')),
          )
          .toList(growable: false),
    );
  }

  Future<void> _writeOutbox(
    ResidentSession session, {
    required List<PendingResidentTaskChoice> choices,
    required List<PendingResidentTaskCompletion> completions,
  }) async {
    final key = '$_outboxPrefix${_scopeHash(session)}';
    if (choices.isEmpty && completions.isEmpty) {
      await _localStore.delete(key);
      return;
    }
    await _localStore.write(
      key,
      jsonEncode(<String, Object?>{
        'version': 1,
        'choices': choices.map(_choiceToWire).toList(growable: false),
        'completions': completions
            .map(_pendingCompletionToWire)
            .toList(growable: false),
      }),
    );
  }

  Future<T> _withOutboxLock<T>(Future<T> Function() action) async {
    final previous = _outboxTail;
    final gate = Completer<void>();
    _outboxTail = gate.future;
    await previous;
    try {
      return await action();
    } finally {
      gate.complete();
    }
  }
}

final class _ResidentTaskOutbox {
  const _ResidentTaskOutbox({
    this.choices = const [],
    this.completions = const [],
  });

  final List<PendingResidentTaskChoice> choices;
  final List<PendingResidentTaskCompletion> completions;
}

Map<String, Object?> _choiceToWire(PendingResidentTaskChoice item) =>
    <String, Object?>{
      'taskId': item.taskId,
      'choice': item.choice == ParticipationChoice.join ? 'JOIN' : 'DECLINE',
      'commandId': item.commandId,
      'queuedAt': item.queuedAt.toUtc().toIso8601String(),
      'taskTitle': item.taskTitle,
      'hasConflict': item.hasConflict,
      'authoritativeParticipation': item.authoritativeParticipation == null
          ? null
          : _participationToWire(item.authoritativeParticipation!),
      'taskNoLongerActive': item.taskNoLongerActive,
      'retryCount': item.retryCount,
      'lastAttemptAt': item.lastAttemptAt?.toUtc().toIso8601String(),
    };

PendingResidentTaskChoice _choiceFromWire(Map<String, Object?> wire) {
  final choice = switch (wire['choice']) {
    'JOIN' => ParticipationChoice.join,
    'DECLINE' => ParticipationChoice.decline,
    _ => throw const FormatException('Invalid pending choice.'),
  };
  final conflictState = wire['authoritativeParticipation'];
  return PendingResidentTaskChoice(
    taskId: _requiredString(wire['taskId'], 'taskId'),
    choice: choice,
    commandId: _requiredString(wire['commandId'], 'commandId'),
    queuedAt: _requiredDate(wire['queuedAt'], 'queuedAt'),
    taskTitle: _optionalString(wire['taskTitle'], 'taskTitle'),
    hasConflict: _requiredBool(wire['hasConflict'], 'hasConflict'),
    authoritativeParticipation: conflictState == null
        ? null
        : _participationFromWire(conflictState),
    taskNoLongerActive: _requiredBool(
      wire['taskNoLongerActive'],
      'taskNoLongerActive',
    ),
    retryCount: wire['retryCount'] == null
        ? 0
        : _nonNegativeInt(wire['retryCount'], 'retryCount'),
    lastAttemptAt: wire['lastAttemptAt'] == null
        ? null
        : _requiredDate(wire['lastAttemptAt'], 'lastAttemptAt'),
  );
}

Map<String, Object?> _pendingCompletionToWire(
  PendingResidentTaskCompletion item,
) => <String, Object?>{
  'taskId': item.taskId,
  'commandId': item.commandId,
  'queuedAt': item.queuedAt.toUtc().toIso8601String(),
  'taskTitle': item.taskTitle,
  'hasConflict': item.hasConflict,
  'taskNoLongerActive': item.taskNoLongerActive,
  'retryCount': item.retryCount,
  'lastAttemptAt': item.lastAttemptAt?.toUtc().toIso8601String(),
};

PendingResidentTaskCompletion _completionFromWire(Map<String, Object?> wire) =>
    PendingResidentTaskCompletion(
      taskId: _requiredString(wire['taskId'], 'taskId'),
      commandId: _requiredString(wire['commandId'], 'commandId'),
      queuedAt: _requiredDate(wire['queuedAt'], 'queuedAt'),
      taskTitle: _optionalString(wire['taskTitle'], 'taskTitle'),
      hasConflict: _requiredBool(wire['hasConflict'], 'hasConflict'),
      taskNoLongerActive: _requiredBool(
        wire['taskNoLongerActive'],
        'taskNoLongerActive',
      ),
      retryCount: wire['retryCount'] == null
          ? 0
          : _nonNegativeInt(wire['retryCount'], 'retryCount'),
      lastAttemptAt: wire['lastAttemptAt'] == null
          ? null
          : _requiredDate(wire['lastAttemptAt'], 'lastAttemptAt'),
    );

Map<String, Object?> _taskToWire(ResidentTaskRecord task) => <String, Object?>{
  'taskId': task.taskId,
  // rtId is recovered from the validated storage scope; it is not persisted.
  'status': task.status,
  'deadline': task.deadline.toUtc().toIso8601String(),
  'locationReference': task.locationReference,
  'participationState': _participationToWire(task.participation),
  'completionState': _completionToWire(task.completion),
  // Completion notes are intentionally never cached.
  'completionSubmittedAt': task.completionSubmittedAt
      ?.toUtc()
      .toIso8601String(),
  'verifiedAt': task.verifiedAt?.toUtc().toIso8601String(),
  'templateSnapshot': <String, Object?>{
    'templateId': task.templateSnapshot.templateId,
    'version': task.templateSnapshot.version,
    'title': task.templateSnapshot.title,
    'category': task.templateSnapshot.category,
    'coreInstruction': task.templateSnapshot.coreInstruction,
    'safetyInstruction': task.templateSnapshot.safetyInstruction,
    'estimatedDurationMinutes': task.templateSnapshot.estimatedDurationMinutes,
  },
};

String _scopeHash(ResidentSession session) {
  final scope = jsonEncode(<String>[session.communityId, session.residentId]);
  return sha256.convert(utf8.encode(scope)).toString();
}

Map<String, Object?> _readMap(Object? value, String name) {
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

int _nonNegativeInt(Object? value, String name) {
  if (value is int && value >= 0 && value <= maxResidentTaskRetryCount) {
    return value;
  }
  throw FormatException('Invalid $name.');
}

bool _requiredBool(Object? value, String name) {
  if (value is bool) return value;
  throw FormatException('Invalid $name.');
}

DateTime _requiredDate(Object? value, String name) {
  if (value is! String) throw FormatException('Invalid $name.');
  final date = DateTime.tryParse(value);
  if (date == null) throw FormatException('Invalid $name.');
  return date.toUtc();
}

String _participationToWire(ParticipationState value) => switch (value) {
  ParticipationState.unresponded => 'UNRESPONDED',
  ParticipationState.joined => 'JOINED',
  ParticipationState.declined => 'DECLINED',
};

String _completionToWire(CompletionState value) => switch (value) {
  CompletionState.notSubmitted => 'NOT_SUBMITTED',
  CompletionState.pendingRtVerification => 'PENDING_RT_VERIFICATION',
  CompletionState.verifiedComplete => 'VERIFIED_COMPLETE',
};

ParticipationState _participationFromWire(Object? value) => switch (value) {
  'UNRESPONDED' => ParticipationState.unresponded,
  'JOINED' => ParticipationState.joined,
  'DECLINED' => ParticipationState.declined,
  _ => throw const FormatException('Invalid participation state.'),
};
