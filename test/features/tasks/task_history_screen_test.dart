import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guyub/features/auth/application/operator_profile.dart';
import 'package:guyub/features/auth/application/resident_session_vault.dart';
import 'package:guyub/features/tasks/application/task_campaign_boundary.dart';
import 'package:guyub/features/tasks/application/task_response_boundary.dart';
import 'package:guyub/features/tasks/application/task_response.dart';
import 'package:guyub/features/tasks/application/task_template.dart';
import 'package:guyub/features/tasks/data/firebase_task_campaign_boundary.dart';
import 'package:guyub/features/tasks/presentation/screens/task_history_screen.dart';

final _taskId = 'a' * 40;
final _secondTaskId = 'b' * 40;
const _cursor = 'bmV4dF9wYWdl';
const _activated = '2026-10-04T10:00:00.000Z';
const _deadline = '2026-10-05T10:00:00.000Z';
const _cancelled = '2026-10-04T11:00:00.000Z';
const _closed = '2026-10-04T12:00:00.000Z';
final _thirdTaskId = 'c' * 40;
const _secondCursor = 'dGhpcmRfcGFnZQ';

Map<String, Object?> _wire({
  String? taskId,
  String status = 'ACTIVE',
  Object? cancelledAt,
  Object? closedAt,
}) => {
  'taskId': taskId ?? _taskId,
  'templateSnapshot': {
    'templateId': 'household_ready',
    'version': 3,
    'title': 'Persiapan rumah tangga',
    'category': 'HOUSEHOLD_PREPARATION',
    'coreInstruction': 'Simpan dokumen penting di tempat aman.',
    'safetyInstruction': 'Jangan mendekati air banjir.',
    'estimatedDurationMinutes': 30,
  },
  'deadline': _deadline,
  'locationReference': 'COMMUNITY_GENERAL_AREA',
  'status': status,
  'activatedAt': _activated,
  'cancelledAt': cancelledAt,
  'closedAt': closedAt,
};

final _profile = OperatorProfile(
  uid: 'operator-1',
  communityId: 'rt-01',
  role: OperatorRole.pendampingRt,
  displayName: 'Operator Demo',
);

final class _HistoryBoundary
    implements
        TaskCampaignBoundary,
        TaskCampaignManagementBoundary,
        TaskCampaignHistoryBoundary,
        TaskCampaignLifecycleBoundary {
  _HistoryBoundary({this.failFirstPage = false});

  final bool failFirstPage;
  final List<(int, String?)> requests = [];
  final List<String> lifecycleRequests = [];
  final List<(String, String)> closureRequests = [];

  @override
  Future<RtTaskHistoryPage> listRtTaskHistory({
    int pageSize = 25,
    String? cursor,
  }) async {
    requests.add((pageSize, cursor));
    if (failFirstPage && cursor == null) throw StateError('unavailable');
    if (cursor == null) {
      return RtTaskHistoryPage(
        tasks: [RtTaskHistoryRecord.fromWire(_wire())],
        nextCursor: _cursor,
      );
    }
    if (cursor == _cursor) {
      return RtTaskHistoryPage(
        tasks: [
          RtTaskHistoryRecord.fromWire(
            _wire(
              taskId: _secondTaskId,
              status: 'CANCELLED',
              cancelledAt: _cancelled,
            ),
          ),
        ],
        nextCursor: _secondCursor,
      );
    }
    return RtTaskHistoryPage(
      tasks: [
        RtTaskHistoryRecord.fromWire(
          _wire(taskId: _thirdTaskId, status: 'CLOSED', closedAt: _closed),
        ),
      ],
      nextCursor: null,
    );
  }

  @override
  Future<TaskCampaignClosureRecord> closeTaskCampaign({
    required String taskId,
    required String commandId,
  }) async {
    closureRequests.add((taskId, commandId));
    return TaskCampaignClosureRecord(taskId: taskId, status: 'CLOSED');
  }

  @override
  Future<List<RtTaskLifecycleEvent>> listTaskLifecycleEvents({
    required String taskId,
  }) async {
    lifecycleRequests.add(taskId);
    final events = <RtTaskLifecycleEvent>[
      RtTaskLifecycleEvent(
        eventType: 'ACTIVATED',
        occurredAt: DateTime.utc(2026, 10, 4, 10),
      ),
    ];
    if (taskId == _secondTaskId) {
      events.add(
        RtTaskLifecycleEvent(
          eventType: 'CANCELLED',
          occurredAt: DateTime.utc(2026, 10, 4, 11),
        ),
      );
    } else if (taskId == _thirdTaskId) {
      events.add(
        RtTaskLifecycleEvent(
          eventType: 'CLOSED',
          occurredAt: DateTime.utc(2026, 10, 4, 12),
        ),
      );
    }
    return events;
  }

  @override
  Future<List<ActiveTaskCampaignRecord>> listActiveTaskCampaigns() async =>
      const [];

  @override
  Future<TaskCampaignCancellationRecord> cancelTaskCampaign({
    required String taskId,
    required String commandId,
  }) => throw UnimplementedError();

  @override
  Future<List<TaskTemplate>> listApprovedTemplates() async => const [];

  @override
  Future<TaskCampaignRecord> createDraft({
    required TaskTemplate template,
    required DateTime deadline,
    required String? locationReference,
    required String requestId,
  }) => throw UnimplementedError();

  @override
  Future<TaskCampaignRecord> activateCampaign({
    required String campaignId,
    required String commandId,
  }) => throw UnimplementedError();
}

final class _RecapBoundary implements TaskResponseBoundary {
  @override
  Future<TaskResponseRecap> getResponseRecap({required String taskId}) async =>
      TaskResponseRecap(
        taskId: taskId,
        rtId: 'rt-01',
        recordedResponseCount: 6,
        joinedCount: 5,
        declinedCount: 1,
        pendingVerificationCount: 2,
        verifiedCompleteCount: 3,
        isPartial: false,
        taskTitle: 'Persiapan rumah tangga',
      );

  @override
  Future<ResidentTaskList> listResidentActiveTasks({
    required String sessionToken,
  }) => throw UnimplementedError();

  @override
  Future<TaskResponseRecord> recordResidentTaskResponse({
    required String sessionToken,
    required String taskId,
    required ParticipationChoice choice,
    required String commandId,
  }) => throw UnimplementedError();

  @override
  Future<TaskResponseRecord> submitTaskCompletion({
    required String sessionToken,
    required String taskId,
    required String? note,
    required String commandId,
    String? evidenceId,
  }) => throw UnimplementedError();

  @override
  Future<TaskVerificationQueue> listPendingVerifications() =>
      throw UnimplementedError();

  @override
  Future<TaskResponseRecord> verifyTaskCompletion({
    required String responseId,
    required String commandId,
  }) => throw UnimplementedError();
}

final class _EmptyVault implements ResidentSessionVault {
  @override
  Future<void> clear() async {}

  @override
  Future<void> clearPendingEnrollmentId() async {}

  @override
  Future<String?> read() async => null;

  @override
  Future<String?> readPendingEnrollmentId() async => null;

  @override
  Future<void> write(String sessionToken) async {}

  @override
  Future<void> writePendingEnrollmentId(String requestId) async {}
}

TaskResponseController _responseController() =>
    TaskResponseController(boundary: _RecapBoundary(), vault: _EmptyVault());

void main() {
  group('RT task history parsing', () {
    test('parses active, cancelled, and closed rows with exclusive dates', () {
      final page = RtTaskHistoryPage.fromWire({
        'tasks': [
          _wire(),
          _wire(
            taskId: _secondTaskId,
            status: 'CANCELLED',
            cancelledAt: _cancelled,
          ),
          _wire(taskId: _thirdTaskId, status: 'CLOSED', closedAt: _closed),
        ],
        'nextCursor': _cursor,
      }, pageSize: 3);

      expect(page.tasks, hasLength(3));
      expect(page.tasks.first.status, 'ACTIVE');
      expect(page.tasks.first.cancelledAt, isNull);
      expect(page.tasks.first.closedAt, isNull);
      expect(page.tasks.first.activatedAt, DateTime.utc(2026, 10, 4, 10));
      expect(page.tasks[1].status, 'CANCELLED');
      expect(page.tasks[1].cancelledAt, DateTime.utc(2026, 10, 4, 11));
      expect(page.tasks.last.status, 'CLOSED');
      expect(page.tasks.last.closedAt, DateTime.utc(2026, 10, 4, 12));
      expect(page.tasks.first.templateSnapshot.title, 'Persiapan rumah tangga');
      expect(page.nextCursor, _cursor);
    });

    test('rejects resident data, unknown fields, invalid dates and cursor', () {
      final withResident = _wire()..['residentId'] = 'resident-secret-id';
      expect(
        () => RtTaskHistoryPage.fromWire({
          'tasks': [withResident],
          'nextCursor': null,
        }),
        throwsFormatException,
      );

      final malformedDate = _wire()..['activatedAt'] = '2026-10-04';
      expect(
        () => RtTaskHistoryRecord.fromWire(malformedDate),
        throwsFormatException,
      );

      expect(
        () => RtTaskHistoryPage.fromWire({
          'tasks': [_wire(status: 'CANCELLED')],
          'nextCursor': null,
        }),
        throwsFormatException,
      );
      expect(
        () => RtTaskHistoryPage.fromWire({
          'tasks': [_wire()],
          'nextCursor': 'not/base64url',
        }),
        throwsFormatException,
      );
      expect(
        () => RtTaskHistoryPage.fromWire({
          'tasks': [_wire(), _wire(taskId: _secondTaskId)],
          'nextCursor': null,
        }, pageSize: 1),
        throwsFormatException,
      );
    });

    test('validates page size and opaque cursor request bounds', () async {
      final calls = <(String, Map<String, Object?>)>[];
      final boundary = FirebaseTaskCampaignBoundary.withInvoker((
        name,
        data,
      ) async {
        calls.add((name, data));
        return {
          'tasks': [_wire()],
          'nextCursor': null,
        };
      });

      await expectLater(
        boundary.listRtTaskHistory(pageSize: 0),
        throwsArgumentError,
      );
      await expectLater(
        boundary.listRtTaskHistory(cursor: 'bad/cursor'),
        throwsArgumentError,
      );
      expect(calls, isEmpty);
    });

    test(
      'Firebase adapter sends only paging arguments to the RT callable',
      () async {
        final calls = <(String, Map<String, Object?>)>[];
        final boundary = FirebaseTaskCampaignBoundary.withInvoker((
          name,
          data,
        ) async {
          calls.add((name, data));
          return {
            'tasks': [_wire()],
            'nextCursor': _cursor,
          };
        });

        final firstPage = await boundary.listRtTaskHistory();
        final secondPage = await boundary.listRtTaskHistory(
          pageSize: 12,
          cursor: _cursor,
        );

        expect(firstPage.tasks.single.taskId, _taskId);
        expect(secondPage.nextCursor, _cursor);
        expect(calls.map((call) => call.$1), [
          'listRtTaskHistory',
          'listRtTaskHistory',
        ]);
        expect(calls[0].$2, {'pageSize': 25});
        expect(calls[1].$2, {'pageSize': 12, 'cursor': _cursor});
      },
    );
  });

  test(
    'lifecycle wire models reject extra identifiers and invalid sequences',
    () {
      expect(
        () => RtTaskLifecycleEvent.fromWire({
          'eventType': 'ACTIVATED',
          'occurredAt': _activated,
          'actorUid': 'private-operator',
        }),
        throwsFormatException,
      );
      expect(
        () => RtTaskLifecycleEvent.listFromWire({
          'events': [
            {'eventType': 'CLOSED', 'occurredAt': _closed},
          ],
        }),
        throwsFormatException,
      );
      expect(
        () => RtTaskHistoryRecord.fromWire(
          _wire(status: 'CLOSED', closedAt: null),
        ),
        throwsFormatException,
      );
    },
  );

  test(
    'Firebase adapter calls close and reads lifecycle-only events',
    () async {
      final calls = <(String, Map<String, Object?>)>[];
      final boundary = FirebaseTaskCampaignBoundary.withInvoker((
        name,
        data,
      ) async {
        calls.add((name, data));
        if (name == 'closeTaskCampaign') {
          return {'taskId': _taskId, 'status': 'CLOSED'};
        }
        return {
          'events': [
            {'eventType': 'ACTIVATED', 'occurredAt': _activated},
            {'eventType': 'CLOSED', 'occurredAt': _closed},
          ],
        };
      });
      final closed = await boundary.closeTaskCampaign(
        taskId: _taskId,
        commandId: 'c' * 40,
      );
      final events = await boundary.listTaskLifecycleEvents(taskId: _taskId);
      expect(closed.status, 'CLOSED');
      expect(events.map((event) => event.eventType), ['ACTIVATED', 'CLOSED']);
      expect(calls.map((call) => call.$1), [
        'closeTaskCampaign',
        'listTaskLifecycleEvents',
      ]);
      expect(calls[0].$2, {'taskId': _taskId, 'commandId': 'c' * 40});
      expect(calls[1].$2, {'taskId': _taskId});
    },
  );

  test(
    'controller reuses its closure command after an uncertain response',
    () async {
      final boundary = _HistoryBoundary();
      final controller = TaskCampaignController(
        boundary,
        idFactory: () => 'c' * 40,
      );
      await controller.closeTaskCampaign(taskId: _taskId);
      await controller.closeTaskCampaign(taskId: _taskId);
      expect(boundary.closureRequests, [
        (_taskId, 'c' * 40),
        (_taskId, 'c' * 40),
      ]);
    },
  );

  test('management history method forwards through the controller', () async {
    final boundary = _HistoryBoundary();
    final page = await TaskCampaignController(boundary).listRtTaskHistory();
    expect(boundary.requests, [(25, null)]);
    expect(page.tasks.single.taskId, _taskId);
  });

  testWidgets('history is read-only, paginated, and links to aggregate recap', (
    tester,
  ) async {
    final boundary = _HistoryBoundary();
    await tester.pumpWidget(
      MaterialApp(
        home: TaskHistoryScreen(
          profile: _profile,
          controller: TaskCampaignController(boundary),
          taskResponseController: _responseController(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(boundary.requests, [(25, null)]);
    expect(find.text('Riwayat Tugas RT'), findsOneWidget);
    expect(find.text('Persiapan rumah tangga'), findsOneWidget);
    expect(find.text('Status: Aktif'), findsOneWidget);
    expect(
      find.text('Lokasi umum: Area umum RT yang ditentukan operator'),
      findsOneWidget,
    );
    expect(find.text('Nama warga'), findsNothing);
    expect(find.text('resident-secret-id'), findsNothing);
    expect(find.byKey(Key('history-recap-$_taskId')), findsOneWidget);

    await tester.tap(find.byKey(Key('history-events-toggle-$_taskId')));
    await tester.pumpAndSettle();
    expect(boundary.lifecycleRequests, [_taskId]);
    expect(find.text('Perubahan yang dicatat server:'), findsOneWidget);
    expect(find.textContaining('Diaktifkan:'), findsNWidgets(2));
    await tester.tap(find.byKey(Key('history-events-toggle-$_taskId')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(Key('history-recap-$_taskId')));
    await tester.pumpAndSettle();
    expect(find.text('Terverifikasi selesai'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.textContaining('peringkat'), findsOneWidget);
    expect(
      find.textContaining('belum menjawab tidak dihitung'),
      findsOneWidget,
    );

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('task-history-load-more')));
    await tester.pumpAndSettle();
    expect(boundary.requests, [(25, null), (25, _cursor)]);
    expect(find.text('Status: Dibatalkan'), findsOneWidget);
    await tester.drag(find.byType(ListView), const Offset(0, -600));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('task-history-load-more')), findsOneWidget);

    await tester.ensureVisible(find.byKey(const Key('task-history-load-more')));
    await tester.tap(find.byKey(const Key('task-history-load-more')));
    await tester.pumpAndSettle();
    expect(boundary.requests, [(25, null), (25, _cursor), (25, _secondCursor)]);
    expect(find.text('Status: Ditutup'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Text && widget.data?.startsWith('Ditutup: ') == true,
      ),
      findsOneWidget,
    );
    expect(find.byKey(const Key('task-history-load-more')), findsNothing);
  });

  testWidgets('failed history load is explicit and can be retried', (
    tester,
  ) async {
    final boundary = _HistoryBoundary(failFirstPage: true);
    await tester.pumpWidget(
      MaterialApp(
        home: TaskHistoryScreen(
          profile: _profile,
          controller: TaskCampaignController(boundary),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.textContaining('belum dapat dimuat dari server'),
      findsOneWidget,
    );
    expect(find.text('Belum ada riwayat tugas untuk RT ini.'), findsNothing);
    expect(find.byKey(const Key('task-history-retry')), findsOneWidget);
  });
}
