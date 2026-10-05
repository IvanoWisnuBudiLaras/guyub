import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guyub/features/auth/application/operator_profile.dart';
import 'package:guyub/features/tasks/application/task_campaign_boundary.dart';
import 'package:guyub/features/tasks/application/task_template.dart';
import 'package:guyub/features/tasks/presentation/screens/task_active_campaigns_screen.dart';

final _taskId = 'a' * 40;
final _snapshot = TaskTemplateSnapshot(
  templateId: 'household_ready',
  version: 3,
  title: 'Persiapan rumah tangga',
  category: 'HOUSEHOLD_PREPARATION',
  coreInstruction: 'Simpan dokumen penting di tempat aman.',
  safetyInstruction: 'Jangan mendekati air banjir atau kabel basah.',
);

ActiveTaskCampaignRecord _activeTask() => ActiveTaskCampaignRecord(
  taskId: _taskId,
  templateSnapshot: _snapshot,
  deadline: DateTime.utc(2026, 10, 5, 12),
  locationReference: 'COMMUNITY_GENERAL_AREA',
);

final class _ActiveBoundary
    implements
        TaskCampaignBoundary,
        TaskCampaignManagementBoundary,
        TaskCampaignLifecycleBoundary {
  List<ActiveTaskCampaignRecord> tasks = [_activeTask()];
  bool failList = false;
  bool failCancellation = false;
  bool failClosure = false;
  int listCalls = 0;
  int cancellationCalls = 0;
  int closureCalls = 0;
  String? lastTaskId;
  String? lastCommandId;
  String? lastClosureTaskId;
  String? lastClosureCommandId;

  @override
  Future<List<ActiveTaskCampaignRecord>> listActiveTaskCampaigns() async {
    listCalls++;
    if (failList) throw StateError('callable unavailable');
    return List.unmodifiable(tasks);
  }

  @override
  Future<TaskCampaignCancellationRecord> cancelTaskCampaign({
    required String taskId,
    required String commandId,
  }) async {
    cancellationCalls++;
    lastTaskId = taskId;
    lastCommandId = commandId;
    if (failCancellation) throw StateError('lost response');
    tasks = tasks.where((task) => task.taskId != taskId).toList();
    return TaskCampaignCancellationRecord(taskId: taskId, status: 'CANCELLED');
  }

  @override
  Future<TaskCampaignClosureRecord> closeTaskCampaign({
    required String taskId,
    required String commandId,
  }) async {
    closureCalls++;
    lastClosureTaskId = taskId;
    lastClosureCommandId = commandId;
    if (failClosure) throw StateError('lost response');
    tasks = tasks.where((task) => task.taskId != taskId).toList();
    return TaskCampaignClosureRecord(taskId: taskId, status: 'CLOSED');
  }

  @override
  Future<List<RtTaskLifecycleEvent>> listTaskLifecycleEvents({
    required String taskId,
  }) async => [
    RtTaskLifecycleEvent(
      eventType: 'ACTIVATED',
      occurredAt: DateTime.utc(2026, 10, 4),
    ),
  ];

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

final _profile = OperatorProfile(
  uid: 'operator-1',
  communityId: 'rt-01',
  role: OperatorRole.pendampingRt,
  displayName: 'Operator Demo',
);

Future<void> _mount(WidgetTester tester, _ActiveBoundary boundary) async {
  await tester.pumpWidget(
    MaterialApp(
      home: TaskActiveCampaignsScreen(
        profile: _profile,
        controller: TaskCampaignController(boundary, idFactory: () => 'c' * 40),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _openCancellationDialog(WidgetTester tester) async {
  final cancelButton = find.byKey(Key('task-campaign-cancel-$_taskId'));
  await tester.drag(find.byType(ListView), const Offset(0, -600));
  await tester.pumpAndSettle();
  await tester.tap(cancelButton);
  await tester.pumpAndSettle();
}

Future<void> _openClosureDialog(WidgetTester tester) async {
  final closeButton = find.byKey(Key('task-campaign-close-$_taskId'));
  await tester.drag(find.byType(ListView), const Offset(0, -600));
  await tester.pumpAndSettle();
  await tester.tap(closeButton);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows locked server snapshot and asks before cancellation', (
    tester,
  ) async {
    final boundary = _ActiveBoundary();
    await _mount(tester, boundary);

    expect(boundary.listCalls, 1);
    expect(find.text('Pendamping RT · RT rt-01'), findsOneWidget);
    expect(find.text(_snapshot.title), findsOneWidget);
    expect(find.text('Snapshot terkunci · Versi 3'), findsOneWidget);
    expect(find.text(_snapshot.coreInstruction), findsOneWidget);
    expect(find.text(_snapshot.safetyInstruction), findsOneWidget);
    expect(find.text('Batas waktu'), findsOneWidget);
    expect(find.text('Lokasi umum'), findsOneWidget);
    expect(find.text('Area umum RT yang ditentukan operator'), findsOneWidget);
    expect(find.textContaining('riwayat audit'), findsOneWidget);
    expect(find.textContaining('antre secara offline'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(find.text('Nama warga'), findsNothing);
    expect(find.text('Telepon'), findsNothing);

    await _openCancellationDialog(tester);
    expect(boundary.cancellationCalls, 0);
    expect(find.text('Batalkan tugas aktif?'), findsOneWidget);
    expect(
      find.textContaining('Tidak ada notifikasi yang dikirim'),
      findsOneWidget,
    );
    expect(find.textContaining('antre secara offline'), findsWidgets);

    await tester.tap(find.text('Kembali'));
    await tester.pumpAndSettle();
    expect(boundary.cancellationCalls, 0);
    expect(find.text(_snapshot.title), findsOneWidget);
  });

  testWidgets(
    'confirmed cancellation calls the server and reloads active tasks',
    (tester) async {
      final boundary = _ActiveBoundary();
      await _mount(tester, boundary);
      await _openCancellationDialog(tester);

      await tester.tap(find.byKey(const Key('task-campaign-cancel-confirm')));
      await tester.pumpAndSettle();

      expect(boundary.cancellationCalls, 1);
      expect(boundary.lastTaskId, _taskId);
      expect(boundary.lastCommandId, 'c' * 40);
      expect(boundary.listCalls, 2);
      expect(find.byKey(const Key('active-task-empty')), findsOneWidget);
    },
  );

  testWidgets(
    'closure requires confirmation and remains distinct from completion',
    (tester) async {
      final boundary = _ActiveBoundary();
      await _mount(tester, boundary);
      await _openClosureDialog(tester);

      expect(boundary.closureCalls, 0);
      expect(find.text('Tutup tugas aktif?'), findsOneWidget);
      expect(
        find.textContaining('tidak menandai tanggapan sebagai selesai'),
        findsOneWidget,
      );
      await tester.tap(find.text('Kembali'));
      await tester.pumpAndSettle();
      expect(boundary.closureCalls, 0);

      await _openClosureDialog(tester);
      await tester.tap(find.byKey(const Key('task-campaign-close-confirm')));
      await tester.pumpAndSettle();
      expect(boundary.closureCalls, 1);
      expect(boundary.lastClosureTaskId, _taskId);
      expect(boundary.lastClosureCommandId, 'c' * 40);
      expect(boundary.cancellationCalls, 0);
      expect(boundary.listCalls, 2);
      expect(find.byKey(const Key('active-task-empty')), findsOneWidget);
    },
  );

  testWidgets('uncertain closure is not shown as success', (tester) async {
    final boundary = _ActiveBoundary()..failClosure = true;
    await _mount(tester, boundary);
    await _openClosureDialog(tester);
    await tester.tap(find.byKey(const Key('task-campaign-close-confirm')));
    await tester.pumpAndSettle();

    expect(boundary.closureCalls, 1);
    expect(find.text(_snapshot.title), findsOneWidget);
    expect(
      find.textContaining('Penutupan belum dapat dipastikan'),
      findsOneWidget,
    );
    expect(find.text('Tidak ada tugas aktif untuk RT ini.'), findsNothing);
  });

  testWidgets('close control keeps its name and supports large text', (
    tester,
  ) async {
    final boundary = _ActiveBoundary();
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: TaskActiveCampaignsScreen(
            profile: _profile,
            controller: TaskCampaignController(
              boundary,
              idFactory: () => 'c' * 40,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final closeButton = find.byKey(Key('task-campaign-close-$_taskId'));
    await tester.dragUntilVisible(
      closeButton,
      find.byType(ListView),
      const Offset(0, -400),
    );
    await tester.pumpAndSettle();
    expect(
      tester.getSemantics(closeButton).label,
      contains('Tutup tugas aktif'),
    );
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  testWidgets('callable errors fail closed without showing a local task list', (
    tester,
  ) async {
    final boundary = _ActiveBoundary()..failList = true;
    await _mount(tester, boundary);

    expect(find.text(_snapshot.title), findsNothing);
    expect(find.byKey(const Key('active-task-retry')), findsOneWidget);
    expect(boundary.cancellationCalls, 0);

    boundary.failList = false;
    await tester.tap(find.byKey(const Key('active-task-retry')));
    await tester.pumpAndSettle();
    expect(find.text(_snapshot.title), findsOneWidget);
  });

  testWidgets('uncertain cancellation is not shown as success', (tester) async {
    final boundary = _ActiveBoundary()..failCancellation = true;
    await _mount(tester, boundary);
    await _openCancellationDialog(tester);
    await tester.tap(find.byKey(const Key('task-campaign-cancel-confirm')));
    await tester.pumpAndSettle();

    expect(boundary.cancellationCalls, 1);
    expect(find.text(_snapshot.title), findsOneWidget);
    expect(
      find.textContaining('Pembatalan belum dapat dipastikan'),
      findsOneWidget,
    );
    expect(find.text('Tidak ada tugas aktif untuk RT ini.'), findsNothing);
  });
}
