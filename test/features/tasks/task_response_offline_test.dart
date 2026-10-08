import 'package:flutter_test/flutter_test.dart';
import 'package:guyub/core/database/local_store.dart';
import 'package:guyub/features/auth/application/resident_session.dart';
import 'package:guyub/features/auth/application/resident_session_vault.dart';
import 'package:guyub/features/tasks/application/task_response.dart';
import 'package:guyub/features/tasks/application/task_response_boundary.dart';
import 'package:guyub/features/tasks/application/task_template.dart';
import 'package:guyub/features/tasks/data/resident_task_offline_store.dart';

void main() {
  final session = _session('rt-secret-id', 'resident-secret-id');
  final token = 'bearer-token-must-not-persist';
  final syncedAt = DateTime.utc(2026, 10, 5, 10);

  test(
    'same-device deletion clears scoped cache and pending task commands',
    () async {
      final local = _RecordingLocalStore();
      final offline = LocalResidentTaskOfflineStore(localStore: local);
      await offline.cacheAuthorizedActiveTasks(
        session: session,
        taskList: _list([_task()]),
        syncedAt: syncedAt,
      );
      await offline.enqueueChoice(
        session: session,
        taskId: 'task-a',
        choice: ParticipationChoice.join,
        commandId: 'delete-test-command-000000000000000000000000',
        queuedAt: syncedAt,
      );
      expect(local.values, hasLength(2));

      await offline.clearResidentData(session: session);

      expect(local.values, isEmpty);
      expect(await offline.readCachedActiveTasks(session: session), isNull);
      expect(await offline.pendingChoices(session: session), isEmpty);
      expect(await offline.pendingCompletions(session: session), isEmpty);
    },
  );

  test(
    'authorized task snapshot persists and restores across controllers',
    () async {
      final local = _RecordingLocalStore();
      final offline = LocalResidentTaskOfflineStore(localStore: local);
      final boundary = _FakeBoundary(
        list: ResidentTaskList(
          items: [_task(completionNote: 'private-completion-note')],
          isPartial: true,
        ),
      );
      final first = _controller(
        boundary,
        _FakeVault(token),
        offline,
        clock: () => syncedAt,
      );

      final online = await first.listResidentActiveTasks(session: session);
      expect(online.isCached, isFalse);
      expect(online.lastSyncedAt, syncedAt);
      final snapshot = await offline.readCachedActiveTasks(session: session);
      expect(snapshot, isNotNull);
      expect(snapshot!.taskList.items.single.rtId, session.communityId);
      expect(
        snapshot.taskList.items.single.templateSnapshot.safetyInstruction,
        'Jangan mendekati air banjir.',
      );
      expect(snapshot.taskList.items.single.completionNote, isNull);

      boundary.nextChoiceError =
          const TransientTaskNetworkUnavailableException();
      final action = await first.recordParticipation(
        taskId: 'task-a',
        choice: ParticipationChoice.join,
        session: session,
      );
      expect(action.isPendingSync, isTrue);
      expect(action.pendingChoice, ParticipationChoice.join);

      final nextBoundary = _FakeBoundary(
        list: const ResidentTaskList(items: [], isPartial: false),
      )..nextListError = const TransientTaskNetworkUnavailableException();
      final recreated = _controller(
        nextBoundary,
        _FakeVault(token),
        offline,
        clock: () => syncedAt.add(const Duration(minutes: 1)),
      );
      final restored = await recreated.listResidentActiveTasks(
        session: session,
      );
      expect(restored.isCached, isTrue);
      expect(restored.isPartial, isTrue);
      expect(restored.lastSyncedAt, syncedAt);
      expect(restored.items.single.pendingChoice, ParticipationChoice.join);
      expect(
        restored.items.single.participation,
        ParticipationState.unresponded,
      );
      expect(
        restored.syncIssues.single.kind,
        ResidentTaskSyncIssueKind.choicePending,
      );

      final persisted = local.dump;
      expect(persisted, isNot(contains(token)));
      expect(persisted, isNot(contains('private-completion-note')));
      expect(persisted, isNot(contains(session.communityId)));
      expect(persisted, isNot(contains(session.residentId)));
      expect(persisted, isNot(contains(session.communityName)));
      expect(persisted, isNot(contains(session.nickname)));
      expect(persisted, contains('Jangan mendekati air banjir.'));
      expect(
        local.values.keys.every(
          (key) => RegExp(
            r'^(resident-task-cache|resident-task-outbox)\.v1\.[0-9a-f]{64}$',
          ).hasMatch(key),
        ),
        isTrue,
      );
    },
  );

  test('cache and outbox are isolated by RT and resident scope', () async {
    final local = _RecordingLocalStore();
    final offline = LocalResidentTaskOfflineStore(localStore: local);
    final boundary = _FakeBoundary(list: _list([_task()]));
    final controller = _controller(boundary, _FakeVault(token), offline);
    await controller.listResidentActiveTasks(session: session);
    boundary.nextChoiceError = const TransientTaskNetworkUnavailableException();
    await controller.recordParticipation(
      taskId: 'task-a',
      choice: ParticipationChoice.join,
      session: session,
    );

    final differentResident = _session(session.communityId, 'resident-b');
    final differentRt = _session('rt-b', session.residentId);
    expect(await offline.pendingChoices(session: differentResident), isEmpty);
    expect(await offline.pendingChoices(session: differentRt), isEmpty);
    expect(
      await offline.readCachedActiveTasks(session: differentResident),
      isNull,
    );
    expect(await offline.readCachedActiveTasks(session: differentRt), isNull);

    final offlineBoundary = _FakeBoundary(list: _list([_task()]))
      ..nextListError = const TransientTaskNetworkUnavailableException();
    final isolated = _controller(offlineBoundary, _FakeVault(token), offline);
    await expectLater(
      isolated.listResidentActiveTasks(session: differentResident),
      throwsA(isA<TransientTaskNetworkUnavailableException>()),
    );
  });

  test('only explicit network-unavailable falls back to cache', () async {
    final local = _RecordingLocalStore();
    final offline = LocalResidentTaskOfflineStore(localStore: local);
    final boundary = _FakeBoundary(list: _list([_task()]));
    final controller = _controller(boundary, _FakeVault(token), offline);
    await controller.listResidentActiveTasks(session: session);

    boundary.nextListError = const TaskResponseRejectedException(
      code: 'permission-denied',
    );
    await expectLater(
      controller.listResidentActiveTasks(session: session),
      throwsA(isA<TaskResponseRejectedException>()),
    );
    boundary.nextListError = const FormatException('malformed server response');
    await expectLater(
      controller.listResidentActiveTasks(session: session),
      throwsA(isA<FormatException>()),
    );
    boundary.nextListError = const TransientTaskNetworkUnavailableException();
    final cached = await controller.listResidentActiveTasks(session: session);
    expect(cached.isCached, isTrue);
  });

  test('durable choice is replayed once with its stable command ID', () async {
    final offline = LocalResidentTaskOfflineStore(
      localStore: _RecordingLocalStore(),
    );
    final boundary = _FakeBoundary(list: _list([_task()]));
    final first = _controller(boundary, _FakeVault(token), offline);
    await first.listResidentActiveTasks(session: session);
    boundary.nextChoiceError = const TransientTaskNetworkUnavailableException();
    final queued = await first.recordParticipation(
      taskId: 'task-a',
      choice: ParticipationChoice.join,
      session: session,
    );
    expect(queued.isPendingSync, isTrue);

    final fresh = await first.listResidentActiveTasks(session: session);
    expect(fresh.isCached, isFalse);
    expect(boundary.choiceCommandIds, hasLength(2));
    expect(boundary.choiceCommandIds.first, boundary.choiceCommandIds.last);
    expect(fresh.items.single.participation, ParticipationState.joined);
    expect(await offline.pendingChoices(session: session), isEmpty);

    await first.listResidentActiveTasks(session: session);
    expect(boundary.choiceCommandIds, hasLength(2));
  });

  test('server state wins and conflicting choice remains visible', () async {
    final offline = LocalResidentTaskOfflineStore(
      localStore: _RecordingLocalStore(),
    );
    final boundary = _FakeBoundary(list: _list([_task()]));
    final controller = _controller(boundary, _FakeVault(token), offline);
    await controller.listResidentActiveTasks(session: session);
    boundary.nextChoiceError = const TransientTaskNetworkUnavailableException();
    await controller.recordParticipation(
      taskId: 'task-a',
      choice: ParticipationChoice.join,
      session: session,
    );
    boundary.list = _list([_task(participation: ParticipationState.declined)]);

    final reconciled = await controller.listResidentActiveTasks(
      session: session,
    );
    final task = reconciled.items.single;
    expect(task.participation, ParticipationState.declined);
    expect(task.pendingChoice, ParticipationChoice.join);
    expect(task.hasSyncConflict, isTrue);
    expect(
      reconciled.syncIssues.single.kind,
      ResidentTaskSyncIssueKind.choiceConflict,
    );
    final pending = await offline.pendingChoices(session: session);
    expect(pending.single.hasConflict, isTrue);
    expect(
      pending.single.authoritativeParticipation,
      ParticipationState.declined,
    );
  });

  test(
    'immediate choice rejection returns pending conflict metadata',
    () async {
      final offline = LocalResidentTaskOfflineStore(
        localStore: _RecordingLocalStore(),
      );
      final boundary = _FakeBoundary(list: _list([_task()]));
      final controller = _controller(boundary, _FakeVault(token), offline);
      await controller.listResidentActiveTasks(session: session);
      boundary.nextChoiceError = const TaskResponseConflictException();

      final result = await controller.recordParticipation(
        taskId: 'task-a',
        choice: ParticipationChoice.join,
        session: session,
      );
      expect(result.pendingChoice, ParticipationChoice.join);
      expect(result.isPendingSync, isTrue);
      expect(result.hasSyncConflict, isTrue);
      final queued = (await offline.pendingChoices(session: session)).single;
      expect(queued.hasConflict, isTrue);
      expect(queued.taskNoLongerActive, isTrue);
    },
  );

  test('cancelled queued choice is retained with its safe title', () async {
    final offline = LocalResidentTaskOfflineStore(
      localStore: _RecordingLocalStore(),
    );
    final boundary = _FakeBoundary(list: _list([_task()]));
    final controller = _controller(boundary, _FakeVault(token), offline);
    await controller.listResidentActiveTasks(session: session);
    boundary.nextChoiceError = const TransientTaskNetworkUnavailableException();
    await controller.recordParticipation(
      taskId: 'task-a',
      choice: ParticipationChoice.join,
      session: session,
    );
    boundary.list = _list([]);

    final result = await controller.listResidentActiveTasks(session: session);
    expect(result.items, isEmpty);
    expect(
      result.syncIssues.single.kind,
      ResidentTaskSyncIssueKind.taskUnavailable,
    );
    expect(result.syncIssues.single.taskTitle, 'Siapkan keluarga');
    final pending = await offline.pendingChoices(session: session);
    expect(pending.single.hasConflict, isTrue);
    expect(pending.single.taskNoLongerActive, isTrue);
  });

  test(
    'no-note completion replays and cancelled completion remains a conflict',
    () async {
      final local = _RecordingLocalStore();
      final offline = LocalResidentTaskOfflineStore(localStore: local);
      final boundary = _FakeBoundary(
        list: _list([_task(participation: ParticipationState.joined)]),
      );
      final controller = _controller(boundary, _FakeVault(token), offline);
      await controller.listResidentActiveTasks(session: session);
      boundary.nextCompletionError =
          const TransientTaskNetworkUnavailableException();
      final result = await controller.submitCompletion(
        taskId: 'task-a',
        note: null,
        session: session,
      );
      expect(result.isPendingCompletionSync, isTrue);
      expect(boundary.completionCommandIds, hasLength(1));
      boundary.list = _list([]);

      final refreshed = await controller.listResidentActiveTasks(
        session: session,
      );
      expect(refreshed.items, isEmpty);
      expect(
        refreshed.syncIssues.single.kind,
        ResidentTaskSyncIssueKind.taskUnavailable,
      );
      expect(refreshed.syncIssues.single.taskTitle, 'Siapkan keluarga');
      final pending = await offline.pendingCompletions(session: session);
      expect(pending.single.hasConflict, isTrue);
      expect(pending.single.taskNoLongerActive, isTrue);
      expect(local.dump, isNot(contains(token)));
      expect(local.dump, isNot(contains('private-completion-note')));
    },
  );

  test(
    'no-note completion replays once with the same idempotency ID',
    () async {
      final offline = LocalResidentTaskOfflineStore(
        localStore: _RecordingLocalStore(),
      );
      final boundary = _FakeBoundary(
        list: _list([_task(participation: ParticipationState.joined)]),
      );
      final controller = _controller(boundary, _FakeVault(token), offline);
      await controller.listResidentActiveTasks(session: session);
      boundary.nextCompletionError =
          const TransientTaskNetworkUnavailableException();
      final queued = await controller.submitCompletion(
        taskId: 'task-a',
        note: null,
        session: session,
      );
      expect(queued.isPendingCompletionSync, isTrue);

      final reconciled = await controller.listResidentActiveTasks(
        session: session,
      );
      expect(
        reconciled.items.single.completion,
        CompletionState.pendingRtVerification,
      );
      expect(boundary.completionCommandIds, hasLength(2));
      expect(
        boundary.completionCommandIds.first,
        boundary.completionCommandIds.last,
      );
      expect(boundary.completionNotes, everyElement(isNull));
      expect(await offline.pendingCompletions(session: session), isEmpty);
      await controller.listResidentActiveTasks(session: session);
      expect(boundary.completionCommandIds, hasLength(2));
    },
  );

  test(
    'inactive-state rejection during completion replay is retained',
    () async {
      final offline = LocalResidentTaskOfflineStore(
        localStore: _RecordingLocalStore(),
      );
      final boundary = _FakeBoundary(
        list: _list([_task(participation: ParticipationState.joined)]),
      );
      final controller = _controller(boundary, _FakeVault(token), offline);
      await controller.listResidentActiveTasks(session: session);
      boundary.nextCompletionError =
          const TransientTaskNetworkUnavailableException();
      await controller.submitCompletion(
        taskId: 'task-a',
        note: null,
        session: session,
      );
      boundary.nextCompletionError = const TaskResponseConflictException();

      final result = await controller.listResidentActiveTasks(session: session);
      expect(result.items, isEmpty);
      expect(
        result.syncIssues.single.kind,
        ResidentTaskSyncIssueKind.taskUnavailable,
      );
      final pending = await offline.pendingCompletions(session: session);
      expect(pending.single.hasConflict, isTrue);
      expect(pending.single.taskNoLongerActive, isTrue);
    },
  );

  test('optional note is not queued when completion is offline', () async {
    final local = _RecordingLocalStore();
    final offline = LocalResidentTaskOfflineStore(localStore: local);
    final boundary = _FakeBoundary(
      list: _list([_task(participation: ParticipationState.joined)]),
    );
    final controller = _controller(boundary, _FakeVault(token), offline);
    await controller.listResidentActiveTasks(session: session);
    boundary.nextCompletionError =
        const TransientTaskNetworkUnavailableException();

    await expectLater(
      controller.submitCompletion(
        taskId: 'task-a',
        note: 'private note is never persisted',
        session: session,
      ),
      throwsA(isA<OfflineCompletionNoteException>()),
    );
    expect(await offline.pendingCompletions(session: session), isEmpty);
    expect(local.dump, isNot(contains('private note is never persisted')));
    expect(local.dump, isNot(contains(token)));
  });

  test('replay increments bounded retry metadata without saving raw errors', () async {
    final local = _RecordingLocalStore();
    final offline = LocalResidentTaskOfflineStore(localStore: local);
    final boundary = _FakeBoundary(list: _list([_task()]));
    final controller = _controller(
      boundary,
      _FakeVault(token),
      offline,
      clock: () => syncedAt,
    );
    await controller.listResidentActiveTasks(session: session);
    boundary.nextChoiceError = const TransientTaskNetworkUnavailableException();
    await controller.recordParticipation(
      taskId: 'task-a',
      choice: ParticipationChoice.join,
      session: session,
    );
    boundary.nextChoiceError = StateError('do not persist this raw error');
    // This is a malformed/unexpected replay failure, so the list call surfaces
    // it rather than treating it as a network cache fallback.
    await expectLater(
      controller.listResidentActiveTasks(session: session),
      throwsStateError,
    );
    final pending = await offline.pendingChoices(session: session);
    expect(pending.single.retryCount, 1);
    expect(pending.single.lastAttemptAt, syncedAt);
    expect(local.dump, isNot(contains('do not persist this raw error')));
  });

  test('rejected replay is retained and returned as a conflict', () async {
    final offline = LocalResidentTaskOfflineStore(
      localStore: _RecordingLocalStore(),
    );
    final boundary = _FakeBoundary(list: _list([_task()]));
    final controller = _controller(boundary, _FakeVault(token), offline);
    await controller.listResidentActiveTasks(session: session);
    boundary.nextChoiceError = const TransientTaskNetworkUnavailableException();
    await controller.recordParticipation(
      taskId: 'task-a',
      choice: ParticipationChoice.join,
      session: session,
    );
    boundary.nextChoiceError = const TaskResponseRejectedException(
      code: 'permission-denied',
    );
    final refreshed = await controller.listResidentActiveTasks(
      session: session,
    );
    expect(
      refreshed.syncIssues.single.kind,
      ResidentTaskSyncIssueKind.choiceConflict,
    );
    expect(
      refreshed.items.single.participation,
      ParticipationState.unresponded,
    );
    expect(refreshed.items.single.hasSyncConflict, isTrue);
    expect(
      (await offline.pendingChoices(session: session)).single.hasConflict,
      isTrue,
    );
  });

  test(
    'cache write failures do not hide remote list or successful action',
    () async {
      final local = _RecordingLocalStore()..failCacheWrites = true;
      final offline = LocalResidentTaskOfflineStore(localStore: local);
      final boundary = _FakeBoundary(list: _list([_task()]));
      final controller = _controller(boundary, _FakeVault(token), offline);
      final list = await controller.listResidentActiveTasks(session: session);
      expect(list.items, hasLength(1));
      final response = await controller.recordParticipation(
        taskId: 'task-a',
        choice: ParticipationChoice.join,
        session: session,
      );
      expect(response.participation, ParticipationState.joined);
    },
  );

  test('choice is not sent when durable enqueue fails', () async {
    final local = _RecordingLocalStore()..failOutboxWrites = true;
    final offline = LocalResidentTaskOfflineStore(localStore: local);
    final boundary = _FakeBoundary(list: _list([_task()]));
    final controller = _controller(boundary, _FakeVault(token), offline);
    await controller.listResidentActiveTasks(session: session);

    await expectLater(
      controller.recordParticipation(
        taskId: 'task-a',
        choice: ParticipationChoice.join,
        session: session,
      ),
      throwsStateError,
    );
    expect(boundary.choiceCommandIds, isEmpty);
  });

  test('concurrent durable commands do not overwrite each other', () async {
    final local = _RecordingLocalStore();
    final offline = LocalResidentTaskOfflineStore(localStore: local);
    await Future.wait([
      offline.enqueueChoice(
        session: session,
        taskId: 'task-a',
        choice: ParticipationChoice.join,
        commandId: 'command-a',
        queuedAt: syncedAt,
      ),
      offline.enqueueChoice(
        session: session,
        taskId: 'task-b',
        choice: ParticipationChoice.decline,
        commandId: 'command-b',
        queuedAt: syncedAt,
      ),
    ]);
    final commands = await offline.pendingChoices(session: session);
    expect(commands.map((item) => item.taskId).toSet(), {'task-a', 'task-b'});
  });
}

TaskResponseController _controller(
  TaskResponseBoundary boundary,
  ResidentSessionVault vault,
  ResidentTaskOfflineStore offline, {
  DateTime Function()? clock,
}) => TaskResponseController(
  boundary: boundary,
  vault: vault,
  offlineStore: offline,
  commandIdFactory: () => 'command-id'.padRight(40, 'x'),
  clock: clock,
);

ResidentSession _session(String rt, String resident) => ResidentSession(
  residentId: resident,
  communityId: rt,
  communityName: 'RT name not persisted',
  rtLabel: 'RT 01',
  nickname: 'Warga',
  expiresAt: DateTime.utc(2026, 12),
);

ResidentTaskList _list(List<ResidentTaskRecord> items) =>
    ResidentTaskList(items: items, isPartial: false);

ResidentTaskRecord _task({
  ParticipationState participation = ParticipationState.unresponded,
  CompletionState completion = CompletionState.notSubmitted,
  String? completionNote,
}) => ResidentTaskRecord(
  taskId: 'task-a',
  rtId: 'rt-secret-id',
  templateSnapshot: const TaskTemplateSnapshot(
    templateId: 'safe-prep',
    version: 1,
    title: 'Siapkan keluarga',
    category: 'HOUSEHOLD_PREPARATION',
    coreInstruction: 'Simpan dokumen penting.',
    safetyInstruction: 'Jangan mendekati air banjir.',
  ),
  deadline: DateTime.utc(2026, 10, 6),
  status: 'ACTIVE',
  participation: participation,
  completion: completion,
  completionNote: completionNote,
);

final class _FakeVault implements ResidentSessionVault {
  _FakeVault(this.token);
  final String? token;

  @override
  Future<String?> read() async => token;
  @override
  Future<void> write(String sessionToken) async {}
  @override
  Future<void> clear() async {}
  @override
  Future<void> writePendingEnrollmentId(String requestId) async {}
  @override
  Future<String?> readPendingEnrollmentId() async => null;
  @override
  Future<void> clearPendingEnrollmentId() async {}
}

final class _FakeBoundary implements TaskResponseBoundary {
  _FakeBoundary({required this.list});

  ResidentTaskList list;
  Object? nextListError;
  Object? nextChoiceError;
  Object? nextCompletionError;
  final List<String> choiceCommandIds = [];
  final List<String?> completionNotes = [];
  final List<String> completionCommandIds = [];

  @override
  Future<ResidentTaskList> listResidentActiveTasks({
    required String sessionToken,
  }) async {
    if (nextListError case final error?) {
      nextListError = null;
      throw error;
    }
    return list;
  }

  @override
  Future<TaskResponseRecord> recordResidentTaskResponse({
    required String sessionToken,
    required String taskId,
    required ParticipationChoice choice,
    required String commandId,
  }) async {
    choiceCommandIds.add(commandId);
    if (nextChoiceError case final error?) {
      nextChoiceError = null;
      throw error;
    }
    final response = TaskResponseRecord(
      taskId: taskId,
      participation: choice == ParticipationChoice.join
          ? ParticipationState.joined
          : ParticipationState.declined,
      completion: CompletionState.notSubmitted,
    );
    list = ResidentTaskList(
      items: list.items
          .map(
            (task) =>
                task.taskId == taskId ? task.withResponse(response) : task,
          )
          .toList(growable: false),
      isPartial: list.isPartial,
    );
    return response;
  }

  @override
  Future<TaskResponseRecord> submitTaskCompletion({
    required String sessionToken,
    required String taskId,
    required String? note,
    required String commandId,
    String? evidenceId,
  }) async {
    completionCommandIds.add(commandId);
    completionNotes.add(note);
    if (nextCompletionError case final error?) {
      nextCompletionError = null;
      throw error;
    }
    final response = TaskResponseRecord(
      taskId: taskId,
      participation: ParticipationState.joined,
      completion: CompletionState.pendingRtVerification,
      completionNote: note,
    );
    list = ResidentTaskList(
      items: list.items
          .map(
            (task) =>
                task.taskId == taskId ? task.withResponse(response) : task,
          )
          .toList(growable: false),
      isPartial: list.isPartial,
    );
    return response;
  }

  @override
  Future<TaskVerificationQueue> listPendingVerifications() async =>
      const TaskVerificationQueue(items: [], isPartial: false);
  @override
  Future<TaskResponseRecord> verifyTaskCompletion({
    required String responseId,
    required String commandId,
  }) async => TaskResponseRecord(
    taskId: 'task-a',
    participation: ParticipationState.joined,
    completion: CompletionState.verifiedComplete,
  );
  @override
  Future<TaskResponseRecap> getResponseRecap({required String taskId}) async =>
      const TaskResponseRecap(
        taskId: 'task-a',
        rtId: 'rt-secret-id',
        recordedResponseCount: 0,
        joinedCount: 0,
        declinedCount: 0,
        pendingVerificationCount: 0,
        verifiedCompleteCount: 0,
        isPartial: false,
        taskTitle: 'Siapkan keluarga',
      );
}

final class _RecordingLocalStore implements LocalStore {
  final Map<String, String> values = {};
  bool failCacheWrites = false;
  bool failOutboxWrites = false;

  String get dump => '${values.keys.join('|')}|${values.values.join('|')}';

  @override
  Future<void> write(String key, String value) async {
    if (failCacheWrites && key.startsWith('resident-task-cache.')) {
      throw StateError('cache write failed');
    }
    if (failOutboxWrites && key.startsWith('resident-task-outbox.')) {
      throw StateError('outbox write failed');
    }
    values[key] = value;
  }

  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> delete(String key) async => values.remove(key);
  @override
  Future<void> clear() async => values.clear();
  @override
  Future<bool> containsKey(String key) async => values.containsKey(key);
  @override
  Future<void> close() async {}
}
