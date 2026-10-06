import 'package:flutter/material.dart';

import '../../auth/application/resident_session.dart';
import '../application/task_push_notifications.dart';
import '../../tasks/application/task_response_boundary.dart';
import '../../tasks/presentation/screens/task_response_screens.dart';

/// Resolves notification IDs through the authenticated resident's task list.
/// A notification ID alone never grants access to task data.
final class ResidentTaskNotificationScreen extends StatefulWidget {
  const ResidentTaskNotificationScreen({
    required this.session,
    required this.controller,
    required this.notification,
    super.key,
  });

  final ResidentSession session;
  final TaskResponseController controller;
  final TaskPushNotification notification;

  @override
  State<ResidentTaskNotificationScreen> createState() =>
      _ResidentTaskNotificationScreenState();
}

final class _ResidentTaskNotificationScreenState
    extends State<ResidentTaskNotificationScreen> {
  late Future<ResidentTaskList> _tasks;

  String? get _terminalMessage => switch (widget.notification.eventType) {
    'TASK_CANCELLED' => 'Tugas dari notifikasi ini sudah dibatalkan.',
    'TASK_CLOSED' => 'Tugas dari notifikasi ini sudah ditutup.',
    _ => null,
  };

  @override
  void initState() {
    super.initState();
    if (_terminalMessage == null) {
      _tasks = widget.controller.listResidentActiveTasks(
        session: widget.session,
      );
    }
  }

  @override
  void didUpdateWidget(covariant ResidentTaskNotificationScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final wasTerminal = switch (oldWidget.notification.eventType) {
      'TASK_CANCELLED' || 'TASK_CLOSED' => true,
      _ => false,
    };
    if (wasTerminal && _terminalMessage == null) {
      _tasks = widget.controller.listResidentActiveTasks(
        session: widget.session,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final terminalMessage = _terminalMessage;
    if (terminalMessage != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Status Tugas')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              key: const Key('task-notification-terminal-state'),
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.info_outline, size: 44),
                const SizedBox(height: 12),
                Text(terminalMessage, textAlign: TextAlign.center),
                const SizedBox(height: 8),
                const Text(
                  'Detail tugas tidak dibuka dari notifikasi status terminal.',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      );
    }

    return FutureBuilder<ResidentTaskList>(
      future: _tasks,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return Scaffold(
            appBar: AppBar(title: const Text('Membuka Tugas')),
            body: const Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError || snapshot.data == null) {
          return _unavailable(
            context,
            'Tugas belum dapat dibuka. Periksa koneksi dan coba lagi.',
            retry: true,
          );
        }
        final taskList = snapshot.data!;
        for (final task in taskList.items) {
          if (task.taskId == widget.notification.taskId) {
            return ResidentTaskDetailScreen(
              session: widget.session,
              controller: widget.controller,
              task: task,
              isCached: taskList.isCached,
              lastSyncedAt: taskList.lastSyncedAt,
            );
          }
        }
        return _unavailable(
          context,
          'Tugas dari notifikasi ini sudah tidak aktif atau tidak dapat dibuka.',
        );
      },
    );
  }

  Widget _unavailable(
    BuildContext context,
    String message, {
    bool retry = false,
  }) => Scaffold(
    appBar: AppBar(title: const Text('Tugas dari Notifikasi')),
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.info_outline, size: 44),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            if (retry)
              OutlinedButton(
                key: const Key('task-notification-retry'),
                onPressed: () => setState(() {
                  _tasks = widget.controller.listResidentActiveTasks(
                    session: widget.session,
                  );
                }),
                child: const Text('Coba lagi'),
              ),
            OutlinedButton(
              key: const Key('task-notification-open-list'),
              onPressed: () =>
                  Navigator.of(context)
                      .pushNamed('/resident/tasks', arguments: widget.session),
              child: const Text('Lihat tugas aktif'),
            ),
          ],
        ),
      ),
    ),
  );
}
