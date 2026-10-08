import 'dart:async';

import 'package:flutter/material.dart';
import 'package:guyub/core/database/local_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guyub/app/app.dart';
import 'package:guyub/core/config/app_config.dart';
import 'package:guyub/features/auth/application/resident_session.dart';
import 'package:guyub/features/auth/application/resident_session_boundary.dart';
import 'package:guyub/features/auth/application/resident_session_controller.dart';
import 'package:guyub/features/auth/application/resident_session_vault.dart';
import 'package:guyub/features/tasks/application/task_response.dart';
import 'package:guyub/features/tasks/application/task_response_boundary.dart';
import 'package:guyub/features/tasks/application/task_template.dart';
import 'package:guyub/features/tasks/data/resident_task_offline_store.dart';
import 'package:guyub/features/weather/application/weather_snapshot.dart';
import 'package:guyub/features/weather/application/weather_snapshot_boundary.dart';
import 'package:guyub/features/weather/application/weather_snapshot_store.dart';
import 'package:guyub/features/auth/presentation/screens/resident_session_home_screen.dart';

void main() {
  setUp(() => AppConfig.resetForTesting());

  testWidgets(
    'resident can enter a scoped session from the resident role path',
    (tester) async {
      final controller = ResidentSessionController(
        boundary: FakeResidentBoundary(),
        vault: MemoryResidentSessionVault(),
      );
      AppConfig.initialize(AppConfig.test());
      await tester.pumpWidget(GuyubApp(residentSessionController: controller));

      await tester.tap(find.text('Saya Warga'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('resident-join-code')), findsOneWidget);
      expect(find.byKey(const Key('resident-nickname')), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('resident-join-code')),
        'ABCD2345EFGH',
      );
      await tester.enterText(
        find.byKey(const Key('resident-nickname')),
        'Rani',
      );
      await tester.tap(find.byKey(const Key('resident-join-submit')));
      await tester.pumpAndSettle();

      expect(find.text('Warga • RT 01'), findsOneWidget);
      expect(find.text('Komunitas Uji'), findsOneWidget);
      expect(find.text('Halo, Rani'), findsOneWidget);
      expect(find.textContaining('token'), findsNothing);
    },
  );

  testWidgets('restores an existing session instead of creating a duplicate', (
    tester,
  ) async {
    final vault = MemoryResidentSessionVault()..token = 'saved-opaque-token';
    final controller = ResidentSessionController(
      boundary: FakeResidentBoundary(),
      vault: vault,
    );
    AppConfig.initialize(AppConfig.test());
    await tester.pumpWidget(GuyubApp(residentSessionController: controller));
    await tester.tap(find.text('Saya Warga'));
    await tester.pumpAndSettle();

    expect(find.text('Warga • RT 01'), findsOneWidget);
    expect(find.byKey(const Key('resident-join-submit')), findsNothing);
  });

  testWidgets(
    'keeps a saved token when session validation is temporarily offline',
    (tester) async {
      final vault = MemoryResidentSessionVault()..token = 'saved-opaque-token';
      final controller = ResidentSessionController(
        boundary: FakeResidentBoundary()..failValidationTemporarily = true,
        vault: vault,
      );
      AppConfig.initialize(AppConfig.test());
      await tester.pumpWidget(GuyubApp(residentSessionController: controller));
      await tester.tap(find.text('Saya Warga'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Sesi tersimpan belum dapat diverifikasi'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('resident-join-submit')), findsNothing);
      expect(vault.token, 'saved-opaque-token');
    },
  );

  testWidgets(
    'offline resident session is revalidated when connectivity returns',
    (tester) async {
      final vault = MemoryResidentSessionVault()..token = 'saved-opaque-token';
      final boundary = FakeResidentBoundary()..failValidationTemporarily = true;
      final controller = ResidentSessionController(
        boundary: boundary,
        vault: vault,
      );
      final connectivity = StreamController<bool>.broadcast();
      addTearDown(connectivity.close);
      await tester.pumpWidget(
        MaterialApp(
          home: ResidentSessionHomeScreen(
            session: boundary.session.asOfflineSnapshot(),
            controller: controller,
            connectivityChanges: connectivity.stream,
          ),
        ),
      );
      expect(find.textContaining('Mode offline'), findsOneWidget);

      boundary.failValidationTemporarily = false;
      connectivity.add(true);
      await tester.pumpAndSettle();

      expect(find.textContaining('Mode offline'), findsNothing);
      expect(find.text('Halo, Rani'), findsOneWidget);
    },
  );

  testWidgets('revoked session returns to read-only offline context', (
    tester,
  ) async {
    final vault = MemoryResidentSessionVault()..token = 'saved-opaque-token';
    final boundary = FakeResidentBoundary()..invalidateValidation = true;
    final controller = ResidentSessionController(
      boundary: boundary,
      vault: vault,
    );
    final connectivity = StreamController<bool>.broadcast();
    addTearDown(connectivity.close);
    await tester.pumpWidget(
      MaterialApp(
        home: ResidentSessionHomeScreen(
          session: boundary.session,
          controller: controller,
          connectivityChanges: connectivity.stream,
        ),
      ),
    );

    connectivity.add(true);
    await tester.pumpAndSettle();

    expect(vault.token, isNull);
    expect(find.textContaining('Mode offline'), findsOneWidget);
    expect(find.byKey(const Key('resident-delete-data')), findsNothing);
  });

  testWidgets(
    'reconnect replays queued commands and refreshes cached weather',
    (tester) async {
      final residentVault = MemoryResidentSessionVault()
        ..token = 'saved-opaque-token';
      final sessionBoundary = FakeResidentBoundary()
        ..failValidationTemporarily = true;
      final sessionController = ResidentSessionController(
        boundary: sessionBoundary,
        vault: residentVault,
      );
      final local = _MemoryLocalStore();
      final offlineStore = LocalResidentTaskOfflineStore(localStore: local);
      final session = sessionBoundary.session;
      final queuedAt = DateTime.utc(2026, 10, 5, 10);
      await offlineStore.cacheAuthorizedActiveTasks(
        session: session,
        taskList: ResidentTaskList(items: [_residentTask()], isPartial: false),
        syncedAt: queuedAt,
      );
      const commandId = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
      await offlineStore.enqueueChoice(
        session: session,
        taskId: 'task-a',
        choice: ParticipationChoice.join,
        commandId: commandId,
        queuedAt: queuedAt,
        taskTitle: 'Siapkan perlengkapan keluarga',
      );
      final taskBoundary = _ReconnectTaskBoundary(
        ResidentTaskList(items: [_residentTask()], isPartial: false),
      );
      final taskController = TaskResponseController(
        boundary: taskBoundary,
        vault: residentVault,
        offlineStore: offlineStore,
        commandIdFactory: () => 'a' * 40,
      );
      final weatherBoundary = _ReconnectWeatherBoundary();
      final weatherStore = _MemoryWeatherStore();
      final weatherController = WeatherSnapshotSyncController(
        boundary: weatherBoundary,
        store: weatherStore,
        readResidentSessionToken: residentVault.read,
      );
      final connectivity = StreamController<bool>.broadcast();
      addTearDown(connectivity.close);

      await tester.pumpWidget(
        MaterialApp(
          home: ResidentSessionHomeScreen(
            session: session.asOfflineSnapshot(),
            controller: sessionController,
            taskResponseController: taskController,
            weatherSnapshotStore: weatherStore,
            weatherSnapshotSyncController: weatherController,
            connectivityChanges: connectivity.stream,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(taskBoundary.choiceCommandIds, isEmpty);
      expect(weatherBoundary.residentCalls, 0);

      sessionBoundary.failValidationTemporarily = false;
      connectivity.add(true);
      await tester.pumpAndSettle();

      expect(taskBoundary.listCalls, 1);
      expect(taskBoundary.choiceCommandIds, [commandId]);
      expect(await offlineStore.pendingChoices(session: session), isEmpty);
      expect(weatherBoundary.residentCalls, 1);
      expect(weatherStore.snapshot?.communityId, session.communityId);
      expect(find.text('Data curah hujan: 2,5 mm'), findsOneWidget);
      expect(find.textContaining('Mode offline'), findsNothing);
    },
  );

  testWidgets('resident can request same-device deletion after confirmation', (
    tester,
  ) async {
    AppConfig.initialize(AppConfig.test());
    final vault = MemoryResidentSessionVault()..token = 'saved-opaque-token';
    final boundary = FakeResidentBoundary();
    final controller = ResidentSessionController(
      boundary: boundary,
      vault: vault,
    );
    await tester.pumpWidget(
      MaterialApp(
        initialRoute: '/resident',
        routes: {
          '/resident': (_) => ResidentSessionHomeScreen(
            session: boundary.session,
            controller: controller,
          ),
          '/': (_) => const Scaffold(body: Text('Data dihapus')),
        },
      ),
    );

    await tester.tap(find.byKey(const Key('resident-delete-data')));
    await tester.pumpAndSettle();
    expect(find.text('Hapus data warga?'), findsOneWidget);
    expect(boundary.deletedResidentId, isNull);

    await tester.tap(find.byKey(const Key('resident-delete-data-confirm')));
    await tester.pumpAndSettle();

    expect(boundary.deletedSessionToken, 'saved-opaque-token');
    expect(boundary.deletedResidentId, boundary.session.residentId);
    expect(boundary.deletedCommunityId, boundary.session.communityId);
    expect(vault.token, isNull);
    expect(find.text('Data dihapus'), findsOneWidget);
  });

  testWidgets('invalid join code shows generic message and no RT identity', (
    tester,
  ) async {
    final controller = ResidentSessionController(
      boundary: FakeResidentBoundary()..failCreate = true,
      vault: MemoryResidentSessionVault(),
    );
    AppConfig.initialize(AppConfig.test());
    await tester.pumpWidget(GuyubApp(residentSessionController: controller));
    await tester.tap(find.text('Saya Warga'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('resident-join-code')),
      'WRONGCODE',
    );
    await tester.enterText(find.byKey(const Key('resident-nickname')), 'Rani');
    await tester.tap(find.byKey(const Key('resident-join-submit')));
    await tester.pumpAndSettle();

    expect(find.textContaining('Kode RT tidak valid'), findsOneWidget);
    expect(find.text('Komunitas Uji'), findsNothing);
    expect(find.text('RT 01'), findsNothing);
  });
}

final class MemoryResidentSessionVault implements ResidentSessionVault {
  String? token;
  String? pendingRequestId;

  @override
  Future<void> clear() async => token = null;

  @override
  Future<void> clearPendingEnrollmentId() async => pendingRequestId = null;

  @override
  Future<String?> read() async => token;

  @override
  Future<String?> readPendingEnrollmentId() async => pendingRequestId;

  @override
  Future<void> write(String sessionToken) async => token = sessionToken;

  @override
  Future<void> writePendingEnrollmentId(String requestId) async =>
      pendingRequestId = requestId;
}

final class FakeResidentBoundary implements ResidentSessionBoundary {
  bool failCreate = false;
  bool failValidationTemporarily = false;
  bool invalidateValidation = false;
  String? deletedSessionToken;
  String? deletedResidentId;
  String? deletedCommunityId;

  ResidentSession get session => ResidentSession(
    residentId: 'resident-a',
    communityId: 'rt-a',
    communityName: 'Komunitas Uji',
    rtLabel: 'RT 01',
    nickname: 'Rani',
    expiresAt: DateTime.utc(2026, 10, 11),
  );

  @override
  Future<ResidentSessionGrant> createSession({
    required String joinCode,
    required String nickname,
    required String requestId,
  }) async {
    if (failCreate) throw StateError('generic error');
    return ResidentSessionGrant(
      session: session,
      sessionToken: 'opaque-token-not-for-ui',
    );
  }

  @override
  Future<ResidentSession> validateSession(String sessionToken) async {
    if (invalidateValidation) throw const ResidentSessionInvalidException();
    if (failValidationTemporarily) throw StateError('offline');
    return session;
  }

  @override
  Future<void> revokeSession(String sessionToken) async {}

  @override
  Future<void> deleteOwnResidentData({
    required String sessionToken,
    required String residentId,
    required String communityId,
  }) async {
    deletedSessionToken = sessionToken;
    deletedResidentId = residentId;
    deletedCommunityId = communityId;
  }
}

final class _ReconnectTaskBoundary implements TaskResponseBoundary {
  _ReconnectTaskBoundary(this.list);

  ResidentTaskList list;
  int listCalls = 0;
  final List<String> choiceCommandIds = [];

  @override
  Future<ResidentTaskList> listResidentActiveTasks({
    required String sessionToken,
  }) async {
    listCalls++;
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
  }) async => throw UnimplementedError();

  @override
  Future<TaskVerificationQueue> listPendingVerifications() async =>
      const TaskVerificationQueue(items: [], isPartial: false);

  @override
  Future<TaskResponseRecord> verifyTaskCompletion({
    required String responseId,
    required String commandId,
  }) async => throw UnimplementedError();

  @override
  Future<TaskResponseRecap> getResponseRecap({required String taskId}) async =>
      throw UnimplementedError();
}

ResidentTaskRecord _residentTask() => ResidentTaskRecord(
  taskId: 'task-a',
  rtId: 'rt-a',
  templateSnapshot: const TaskTemplateSnapshot(
    templateId: 'safe-prep',
    version: 1,
    title: 'Siapkan perlengkapan keluarga',
    category: 'HOUSEHOLD_PREPARATION',
    coreInstruction: 'Simpan dokumen penting di tempat aman.',
    safetyInstruction: 'Jangan mendekati air banjir.',
  ),
  deadline: DateTime.utc(2026, 10, 6),
  status: 'ACTIVE',
  participation: ParticipationState.unresponded,
  completion: CompletionState.notSubmitted,
);

final class _MemoryLocalStore implements LocalStore {
  final Map<String, String> _values = {};

  @override
  Future<void> write(String key, String value) async => _values[key] = value;
  @override
  Future<String?> read(String key) async => _values[key];
  @override
  Future<void> delete(String key) async => _values.remove(key);
  @override
  Future<void> clear() async => _values.clear();
  @override
  Future<bool> containsKey(String key) async => _values.containsKey(key);
  @override
  Future<void> close() async {}
}

final class _ReconnectWeatherBoundary implements WeatherSnapshotBoundary {
  int residentCalls = 0;

  @override
  Future<WeatherSnapshot?> getForOperator() async => null;

  @override
  Future<WeatherSnapshot?> getForResident({
    required String sessionToken,
  }) async {
    residentCalls++;
    return WeatherSnapshot(
      id: 'snapshot-a',
      communityId: 'rt-a',
      sourceUpdatedAt: DateTime.utc(2026, 10, 5, 9),
      fetchedAt: DateTime.utc(2026, 10, 5, 10),
      rainfallMm: 2.5,
    );
  }
}

final class _MemoryWeatherStore implements WritableWeatherSnapshotStore {
  WeatherSnapshot? snapshot;

  @override
  Future<WeatherSnapshot?> readLastValid({required String communityId}) async =>
      snapshot?.communityId == communityId ? snapshot : null;

  @override
  Future<bool> saveIfNewer(WeatherSnapshot snapshot) async {
    this.snapshot = snapshot;
    return true;
  }
}
