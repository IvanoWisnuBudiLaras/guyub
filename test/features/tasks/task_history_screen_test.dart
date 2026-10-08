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

Map<String, Object?> _wire({
  String? taskId,
  String status = 'ACTIVE',
  Object? cancelledAt,
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
        TaskCampaignHistoryBoundary {
  _HistoryBoundary({this.failFirstPage = false});

  final bool failFirstPage;
  final List<(int, String?)> requests = [];

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
      nextCursor: null,
    );
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
    test('parses active and cancelled history rows and an opaque cursor', () {
      final page = RtTaskHistoryPage.fromWire({
        'tasks': [
          _wire(),
          _wire(
            taskId: _secondTaskId,
            status: 'CANCELLED',
            cancelledAt: _cancelled,
          ),
        ],
        'nextCursor': _cursor,
      }, pageSize: 2);

      expect(page.tasks, hasLength(2));
      expect(page.tasks.first.status, 'ACTIVE');
      expect(page.tasks.first.cancelledAt, isNull);
      expect(page.tasks.first.activatedAt, DateTime.utc(2026, 10, 4, 10));
      expect(page.tasks.last.status, 'CANCELLED');
      expect(page.tasks.last.cancelledAt, DateTime.utc(2026, 10, 4, 11));
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
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Text && widget.data?.startsWith('Diaktifkan: ') == true,
      ),
      findsNWidgets(2),
    );
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Text && widget.data?.startsWith('Dibatalkan: ') == true,
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
