import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:guyub/core/database/in_memory_local_store.dart';
import 'package:guyub/features/auth/application/resident_session_vault.dart';
import 'package:guyub/features/tasks/application/task_response.dart';
import 'package:guyub/features/tasks/application/task_response_boundary.dart';
import 'package:guyub/features/tasks/application/task_template.dart';
import 'package:guyub/features/notifications/presentation/resident_task_notification_screen.dart';
import 'package:guyub/features/notifications/presentation/task_push_notification_listener.dart';
import 'package:guyub/features/tasks/presentation/screens/task_response_screens.dart';
import 'package:guyub/features/auth/application/operator_profile.dart';
import 'package:guyub/features/auth/application/resident_session.dart';
import 'package:guyub/features/notifications/application/task_push_notifications.dart';
import 'package:guyub/features/notifications/data/firebase_task_push_notifications_boundary.dart';

const _taskId = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
final _session = ResidentSession(
  residentId: 'resident-1',
  communityId: 'rt-1',
  communityName: 'Komunitas uji',
  rtLabel: 'RT 01',
  nickname: 'Warga',
  expiresAt: DateTime.utc(2027),
);

final class _FakeBoundary implements TaskPushNotificationsBoundary {
  bool permissionGranted = true;
  int permissionRequests = 0;
  String? token = 'fcm-token-aaaaaaaaaaaaaaaaaaaa';
  TaskPushNotification? initial;
  final refreshes = StreamController<String>.broadcast();
  final opened = StreamController<TaskPushNotification>.broadcast();
  final foreground = StreamController<TaskPushNotification>.broadcast();
  final registeredResidents = <(String, String)>[];
  final unregisteredResidents = <(String, String)>[];
  final registeredOperators = <String>[];
  final unregisteredOperators = <String>[];

  @override
  Future<bool> hasNotificationPermission() async => permissionGranted;
  @override
  Future<bool> requestNotificationPermission() async {
    permissionRequests += 1;
    return permissionGranted;
  }

  @override
  Future<String?> currentToken() async => token;
  @override
  Stream<String> get tokenRefreshes => refreshes.stream;
  @override
  Stream<TaskPushNotification> get openedNotifications => opened.stream;
  @override
  Stream<TaskPushNotification> get foregroundNotifications => foreground.stream;
  @override
  Future<TaskPushNotification?> getInitialNotification() async => initial;
  @override
  Future<void> registerResidentToken({
    required String sessionToken,
    required String token,
  }) async {
    registeredResidents.add((sessionToken, token));
  }

  @override
  Future<void> unregisterResidentToken({
    required String sessionToken,
    required String token,
  }) async {
    unregisteredResidents.add((sessionToken, token));
  }

  @override
  Future<void> registerPendampingToken({required String token}) async {
    registeredOperators.add(token);
  }

  @override
  Future<void> unregisterPendampingToken({required String token}) async {
    unregisteredOperators.add(token);
  }
}

final class _FakeTaskResponseBoundary implements TaskResponseBoundary {
  _FakeTaskResponseBoundary(
    this.taskList, {
    this.verificationQueue = const TaskVerificationQueue(
      items: [],
      isPartial: false,
    ),
  });

  final ResidentTaskList taskList;
  final TaskVerificationQueue verificationQueue;

  @override
  Future<ResidentTaskList> listResidentActiveTasks({
    required String sessionToken,
  }) async => taskList;

  @override
  Future<TaskVerificationQueue> listPendingVerifications() async =>
      verificationQueue;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _FakeVault implements ResidentSessionVault {
  @override
  Future<String?> read() async => 'opaque-session-token';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

ResidentTaskList _activeTaskList(String taskId) => ResidentTaskList(
  items: [
    ResidentTaskRecord(
      taskId: taskId,
      rtId: 'rt-1',
      templateSnapshot: const TaskTemplateSnapshot(
        templateId: 'safe-preparation',
        version: 1,
        title: 'Siapkan perlengkapan keluarga',
        category: 'HOUSEHOLD_PREPARATION',
        coreInstruction: 'Simpan perlengkapan di tempat aman.',
        safetyInstruction: 'Jangan mendekati aliran berbahaya.',
      ),
      deadline: DateTime.utc(2027),
      status: 'ACTIVE',
      participation: ParticipationState.unresponded,
      completion: CompletionState.notSubmitted,
    ),
  ],
  isPartial: false,
);

final class _FakePreferences implements TaskPushPreferenceStore {
  final values = <(TaskPushAudience, String), bool>{};
  @override
  Future<bool> isEnabled(
    TaskPushAudience audience, {
    required String identityId,
  }) async => values[(audience, identityId)] ?? false;
  @override
  Future<void> setEnabled(
    TaskPushAudience audience, {
    required String identityId,
    required bool enabled,
  }) async {
    values[(audience, identityId)] = enabled;
  }
}

final class _FakeDeviceTokens implements TaskPushDeviceTokenStore {
  final values = <(TaskPushAudience, String), String>{};
  @override
  Future<String?> read(
    TaskPushAudience audience, {
    required String identityId,
  }) async => values[(audience, identityId)];
  @override
  Future<void> write(
    TaskPushAudience audience, {
    required String identityId,
    required String token,
  }) async {
    values[(audience, identityId)] = token;
  }

  @override
  Future<void> clear(
    TaskPushAudience audience, {
    required String identityId,
  }) async => values.remove((audience, identityId));
}

void main() {
  test('notification routing accepts only known types and a task ID', () {
    expect(
      TaskPushNotification.fromData({
        'eventType': 'TASK_ACTIVATED',
        'taskId': _taskId,
      }),
      isNotNull,
    );
    expect(
      TaskPushNotification.fromData({
        'eventType': 'FLOOD_WARNING',
        'taskId': _taskId,
      }),
      isNull,
    );
    expect(
      TaskPushNotification.fromData({
        'eventType': 'TASK_ACTIVATED',
        'taskId': 'other-rt',
      }),
      isNull,
    );
  });

  test('cold-start notification remains pending until the matching role acknowledges it', () async {
    final boundary = _FakeBoundary()
      ..initial = TaskPushNotification(
        eventType: 'TASK_VERIFICATION_NEEDED',
        taskId: _taskId,
      );
    final controller = TaskPushNotificationsController(
      boundary: boundary,
      preferences: _FakePreferences(),
      deviceTokens: _FakeDeviceTokens(),
      readResidentSessionToken: () async => null,
    );
    final notification = boundary.initial!;
    final taskController = TaskResponseController(
      boundary: _FakeTaskResponseBoundary(_activeTaskList(_taskId)),
      vault: _FakeVault(),
    );

    expect(
      await controller.readPendingInitialNotification(),
      same(notification),
    );
    expect(
      taskNotificationDestination(
        notification: notification,
        session: _session,
        taskResponseController: taskController,
      ),
      isNull,
    );
    expect(
      await controller.readPendingInitialNotification(),
      same(notification),
    );

    final pendamping = OperatorProfile(
      uid: 'operator-cold-start',
      communityId: 'rt-1',
      role: OperatorRole.pendampingRt,
      displayName: 'Pendamping',
    );
    expect(
      taskNotificationDestination(
        notification: notification,
        profile: pendamping,
        taskResponseController: taskController,
      ),
      isA<TaskVerificationQueueScreen>(),
    );
    controller.acknowledgeInitialNotification(notification);
    expect(await controller.readPendingInitialNotification(), isNull);

    await controller.dispose();
    await boundary.refreshes.close();
    await boundary.opened.close();
    await boundary.foreground.close();
  });

  test('local push preferences are scoped to each identity', () async {
    final store = InMemoryLocalStore();
    final preferences = LocalTaskPushPreferenceStore(store);

    await preferences.setEnabled(
      TaskPushAudience.resident,
      identityId: 'resident-1',
      enabled: true,
    );
    await preferences.setEnabled(
      TaskPushAudience.pendamping,
      identityId: 'operator/1',
      enabled: true,
    );

    expect(
      await preferences.isEnabled(
        TaskPushAudience.resident,
        identityId: 'resident-1',
      ),
      isTrue,
    );
    await store.write('task_push_opt_in_resident', 'true');
    expect(
      await preferences.isEnabled(
        TaskPushAudience.resident,
        identityId: 'resident-2',
      ),
      isFalse,
    );
    expect(
      await preferences.isEnabled(
        TaskPushAudience.pendamping,
        identityId: 'operator/1',
      ),
      isTrue,
    );
    expect(
      await preferences.isEnabled(
        TaskPushAudience.pendamping,
        identityId: 'operator/2',
      ),
      isFalse,
    );
    await store.close();
  });

  test(
    'opening a resident dashboard never requests permission without opt-in',
    () async {
      final boundary = _FakeBoundary();
      final controller = TaskPushNotificationsController(
        boundary: boundary,
        preferences: _FakePreferences(),
        deviceTokens: _FakeDeviceTokens(),
        readResidentSessionToken: () async => 'opaque-session-token',
      );
      await controller.syncResidentSession(_session);
      expect(boundary.permissionRequests, 0);
      expect(boundary.registeredResidents, isEmpty);
      await controller.dispose();
      await boundary.refreshes.close();
      await boundary.opened.close();
      await boundary.foreground.close();
    },
  );

  test(
    'resident notification consent is not reused by another identity',
    () async {
      final boundary = _FakeBoundary();
      final preferences = _FakePreferences()
        ..values[(TaskPushAudience.resident, _session.residentId)] = true;
      final tokens = _FakeDeviceTokens()
        ..values[(TaskPushAudience.resident, _session.residentId)] =
            'resident-1-token';
      final controller = TaskPushNotificationsController(
        boundary: boundary,
        preferences: preferences,
        deviceTokens: tokens,
        readResidentSessionToken: () async => 'active-session-token',
      );
      final secondResident = ResidentSession(
        residentId: 'resident-2',
        communityId: 'rt-1',
        communityName: 'Komunitas uji',
        rtLabel: 'RT 01',
        nickname: 'Warga lain',
        expiresAt: DateTime.utc(2027),
      );

      await controller.syncResidentSession(secondResident);
      expect(boundary.registeredResidents, isEmpty);
      await controller.disableResident(secondResident);
      expect(boundary.unregisteredResidents, isEmpty);
      expect(
        await tokens.read(
          TaskPushAudience.resident,
          identityId: _session.residentId,
        ),
        'resident-1-token',
      );

      await controller.dispose();
      await boundary.refreshes.close();
      await boundary.opened.close();
      await boundary.foreground.close();
    },
  );

  test(
    'resident sign-out unregisters its push token before clearing the session',
    () async {
      final boundary = _FakeBoundary();
      final preferences = _FakePreferences()
        ..values[(TaskPushAudience.resident, _session.residentId)] = true;
      final tokens = _FakeDeviceTokens()
        ..values[(TaskPushAudience.resident, _session.residentId)] =
            boundary.token!;
      final controller = TaskPushNotificationsController(
        boundary: boundary,
        preferences: preferences,
        deviceTokens: tokens,
        readResidentSessionToken: () async => 'opaque-session-token',
      );

      await controller.syncResidentSession(_session);
      boundary.registeredResidents.clear();
      await controller.unregisterResidentBeforeSignOut(_session);
      boundary.refreshes.add('fcm-token-after-sign-out');
      await Future<void>.delayed(Duration.zero);

      expect(boundary.unregisteredResidents, [
        ('opaque-session-token', boundary.token!),
      ]);
      expect(
        await tokens.read(
          TaskPushAudience.resident,
          identityId: _session.residentId,
        ),
        isNull,
      );
      expect(boundary.registeredResidents, isEmpty);

      await controller.dispose();
      await boundary.refreshes.close();
      await boundary.opened.close();
      await boundary.foreground.close();
    },
  );

  test(
    'operator notification consent is not reused by another identity',
    () async {
      final boundary = _FakeBoundary();
      final preferences = _FakePreferences()
        ..values[(TaskPushAudience.pendamping, 'operator-1')] = true;
      final tokens = _FakeDeviceTokens()
        ..values[(TaskPushAudience.pendamping, 'operator-1')] =
            'operator-1-token';
      final controller = TaskPushNotificationsController(
        boundary: boundary,
        preferences: preferences,
        deviceTokens: tokens,
        readResidentSessionToken: () async => null,
      );
      final secondOperator = OperatorProfile(
        uid: 'operator-2',
        communityId: 'rt-1',
        role: OperatorRole.pendampingRt,
        displayName: 'Pendamping lain',
      );

      await controller.syncPendamping(secondOperator);
      expect(boundary.registeredOperators, isEmpty);
      await controller.disablePendamping(secondOperator);
      expect(boundary.unregisteredOperators, isEmpty);
      expect(
        await tokens.read(
          TaskPushAudience.pendamping,
          identityId: 'operator-1',
        ),
        'operator-1-token',
      );

      await controller.dispose();
      await boundary.refreshes.close();
      await boundary.opened.close();
      await boundary.foreground.close();
    },
  );

  test(
    'resident opt-in registers through the opaque session and can be revoked',
    () async {
      final boundary = _FakeBoundary();
      final preferences = _FakePreferences();
      final tokens = _FakeDeviceTokens();
      final controller = TaskPushNotificationsController(
        boundary: boundary,
        preferences: preferences,
        deviceTokens: tokens,
        readResidentSessionToken: () async => 'opaque-session-token',
      );

      expect(
        await controller.enableResident(_session),
        TaskPushOptInResult.enabled,
      );
      expect(boundary.permissionRequests, 1);
      expect(boundary.registeredResidents, [
        ('opaque-session-token', boundary.token!),
      ]);
      expect(
        await preferences.isEnabled(
          TaskPushAudience.resident,
          identityId: _session.residentId,
        ),
        isTrue,
      );

      await controller.disableResident(_session);
      expect(boundary.unregisteredResidents, [
        ('opaque-session-token', boundary.token!),
      ]);
      expect(
        await preferences.isEnabled(
          TaskPushAudience.resident,
          identityId: _session.residentId,
        ),
        isFalse,
      );
      expect(
        await tokens.read(
          TaskPushAudience.resident,
          identityId: _session.residentId,
        ),
        isNull,
      );
      await controller.dispose();
      await boundary.refreshes.close();
      await boundary.opened.close();
      await boundary.foreground.close();
    },
  );

  test(
    'failed resident opt-out does not hide a still-registered token',
    () async {
      final boundary = _FakeBoundary();
      final preferences = _FakePreferences()
        ..values[(TaskPushAudience.resident, _session.residentId)] = true;
      final tokens = _FakeDeviceTokens()
        ..values[(TaskPushAudience.resident, _session.residentId)] =
            boundary.token!;
      final controller = TaskPushNotificationsController(
        boundary: boundary,
        preferences: preferences,
        deviceTokens: tokens,
        readResidentSessionToken: () async => null,
      );

      await expectLater(controller.disableResident(_session), throwsStateError);
      expect(
        await preferences.isEnabled(
          TaskPushAudience.resident,
          identityId: _session.residentId,
        ),
        isTrue,
      );
      expect(
        await tokens.read(
          TaskPushAudience.resident,
          identityId: _session.residentId,
        ),
        boundary.token,
      );
      expect(boundary.unregisteredResidents, isEmpty);
      await controller.dispose();
      await boundary.refreshes.close();
      await boundary.opened.close();
      await boundary.foreground.close();
    },
  );

  test(
    'token refresh replaces the prior resident token without another prompt',
    () async {
      final boundary = _FakeBoundary()
        ..token = 'fcm-token-bbbbbbbbbbbbbbbbbbbb';
      final preferences = _FakePreferences()
        ..values[(TaskPushAudience.resident, _session.residentId)] = true;
      final tokens = _FakeDeviceTokens()
        ..values[(TaskPushAudience.resident, _session.residentId)] =
            'fcm-token-aaaaaaaaaaaaaaaaaaaa';
      final controller = TaskPushNotificationsController(
        boundary: boundary,
        preferences: preferences,
        deviceTokens: tokens,
        readResidentSessionToken: () async => 'opaque-session-token',
      );

      await controller.syncResidentSession(_session);
      expect(boundary.permissionRequests, 0);
      expect(boundary.unregisteredResidents, [
        ('opaque-session-token', 'fcm-token-aaaaaaaaaaaaaaaaaaaa'),
      ]);
      expect(boundary.registeredResidents, [
        ('opaque-session-token', 'fcm-token-bbbbbbbbbbbbbbbbbbbb'),
      ]);
      expect(
        await tokens.read(
          TaskPushAudience.resident,
          identityId: _session.residentId,
        ),
        boundary.token,
      );
      await controller.dispose();
      await boundary.refreshes.close();
      await boundary.opened.close();
      await boundary.foreground.close();
    },
  );

  test(
    'server-confirmed deletion clears resident push state and blocks refresh',
    () async {
      final boundary = _FakeBoundary();
      final preferences = _FakePreferences()
        ..values[(TaskPushAudience.resident, _session.residentId)] = true;
      final tokens = _FakeDeviceTokens()
        ..values[(TaskPushAudience.resident, _session.residentId)] =
            boundary.token!;
      final controller = TaskPushNotificationsController(
        boundary: boundary,
        preferences: preferences,
        deviceTokens: tokens,
        readResidentSessionToken: () async => 'opaque-session-token',
      );
      await controller.syncResidentSession(_session);
      boundary.registeredResidents.clear();

      await controller.clearResidentStateAfterDeletion(_session);
      boundary.refreshes.add('fcm-token-after-deletion');
      await Future<void>.delayed(Duration.zero);

      expect(
        await preferences.isEnabled(
          TaskPushAudience.resident,
          identityId: _session.residentId,
        ),
        isFalse,
      );
      expect(
        await tokens.read(
          TaskPushAudience.resident,
          identityId: _session.residentId,
        ),
        isNull,
      );
      expect(boundary.registeredResidents, isEmpty);
      await controller.dispose();
      await boundary.refreshes.close();
      await boundary.opened.close();
      await boundary.foreground.close();
    },
  );

  test('notification click resolves only the role-authorized task screen', () {
    final taskController = TaskResponseController(
      boundary: _FakeTaskResponseBoundary(_activeTaskList(_taskId)),
      vault: _FakeVault(),
    );
    final residentNotification = TaskPushNotification(
      eventType: 'TASK_ACTIVATED',
      taskId: _taskId,
    );
    final residentTarget = taskNotificationDestination(
      notification: residentNotification,
      session: _session,
      taskResponseController: taskController,
    );
    expect(residentTarget, isA<ResidentTaskNotificationScreen>());
    expect(
      (residentTarget! as ResidentTaskNotificationScreen).notification.taskId,
      _taskId,
    );

    final pendamping = OperatorProfile(
      uid: 'operator-1',
      communityId: 'rt-1',
      role: OperatorRole.pendampingRt,
      displayName: 'Pendamping',
    );
    final verificationTarget = taskNotificationDestination(
      notification: TaskPushNotification(
        eventType: 'TASK_VERIFICATION_NEEDED',
        taskId: _taskId,
      ),
      profile: pendamping,
      taskResponseController: taskController,
    );
    expect(verificationTarget, isA<TaskVerificationQueueScreen>());
    expect(
      (verificationTarget! as TaskVerificationQueueScreen).initialTaskId,
      _taskId,
    );

    final rtLeader = OperatorProfile(
      uid: 'operator-2',
      communityId: 'rt-1',
      role: OperatorRole.ketuaRtRw,
      displayName: 'Ketua RT',
    );
    expect(
      taskNotificationDestination(
        notification: TaskPushNotification(
          eventType: 'TASK_VERIFICATION_NEEDED',
          taskId: _taskId,
        ),
        profile: rtLeader,
        taskResponseController: taskController,
      ),
      isNull,
    );
    expect(
      taskNotificationDestination(
        notification: TaskPushNotification(
          eventType: 'TASK_ESCALATION',
          taskId: _taskId,
        ),
        session: _session,
        taskResponseController: taskController,
      ),
      isNull,
    );
  });

  testWidgets(
    'resident notification target resolves the authorized active task',
    (tester) async {
      final taskController = TaskResponseController(
        boundary: _FakeTaskResponseBoundary(_activeTaskList(_taskId)),
        vault: _FakeVault(),
      );
      final notification = TaskPushNotification.fromData({
        'eventType': 'TASK_ACTIVATED',
        'taskId': _taskId,
      })!;
      await tester.pumpWidget(
        MaterialApp(
          home: ResidentTaskNotificationScreen(
            session: _session,
            controller: taskController,
            notification: notification,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Siapkan perlengkapan keluarga'), findsOneWidget);
      expect(find.text('Detail Tugas'), findsOneWidget);
    },
  );

  testWidgets('Pendamping verification target highlights the pending task', (
    tester,
  ) async {
    final taskController = TaskResponseController(
      boundary: _FakeTaskResponseBoundary(
        _activeTaskList(_taskId),
        verificationQueue: TaskVerificationQueue(
          items: [
            TaskVerificationRecord(
              responseId: 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
              taskId: _taskId,
              taskTitle: 'Tugas menunggu verifikasi',
              nickname: 'Warga Uji',
              submittedAt: DateTime.utc(2027),
            ),
          ],
          isPartial: false,
        ),
      ),
      vault: _FakeVault(),
    );
    final profile = OperatorProfile(
      uid: 'operator-1',
      communityId: 'rt-1',
      role: OperatorRole.pendampingRt,
      displayName: 'Pendamping',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: TaskVerificationQueueScreen(
          profile: profile,
          controller: taskController,
          initialTaskId: _taskId,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Verifikasi Tugas'), findsOneWidget);
    expect(
      find.byKey(Key('verification-notification-$_taskId')),
      findsOneWidget,
    );
    expect(find.text('Dibuka dari notifikasi'), findsOneWidget);
  });

  test('only Pendamping RT can opt in to operator notifications', () async {
    final boundary = _FakeBoundary();
    final controller = TaskPushNotificationsController(
      boundary: boundary,
      preferences: _FakePreferences(),
      deviceTokens: _FakeDeviceTokens(),
      readResidentSessionToken: () async => null,
    );
    final ketua = OperatorProfile(
      uid: 'ketua',
      communityId: 'rt-1',
      role: OperatorRole.ketuaRtRw,
      displayName: 'Ketua',
    );
    final pendamping = OperatorProfile(
      uid: 'pendamping',
      communityId: 'rt-1',
      role: OperatorRole.pendampingRt,
      displayName: 'Pendamping',
    );

    expect(
      await controller.enablePendamping(ketua),
      TaskPushOptInResult.unavailable,
    );
    expect(boundary.permissionRequests, 0);
    expect(
      await controller.enablePendamping(pendamping),
      TaskPushOptInResult.enabled,
    );
    expect(boundary.registeredOperators, [boundary.token]);
    await controller.dispose();
    await boundary.refreshes.close();
    await boundary.opened.close();
    await boundary.foreground.close();
  });
}
