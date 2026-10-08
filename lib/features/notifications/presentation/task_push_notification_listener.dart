import 'dart:async';

import 'package:flutter/material.dart';

import '../../auth/application/operator_profile.dart';
import '../../auth/application/resident_session.dart';
import '../../tasks/application/task_campaign_boundary.dart';
import '../../tasks/application/task_response_boundary.dart';
import '../../tasks/presentation/screens/task_active_campaigns_screen.dart';
import '../../tasks/presentation/screens/task_response_screens.dart';
import '../application/task_push_notifications.dart';
import 'resident_task_notification_screen.dart';

/// Resolves an allowlisted notification to the existing authorized screen.
/// Notification IDs are hints; each screen loads current task data through its
/// role-scoped server boundary.
Widget? taskNotificationDestination({
  required TaskPushNotification notification,
  ResidentSession? session,
  OperatorProfile? profile,
  TaskResponseController? taskResponseController,
  TaskCampaignBoundary? campaignBoundary,
}) {
  if (session != null) {
    if (notification.eventType == 'TASK_ESCALATION' ||
        notification.eventType == 'TASK_VERIFICATION_NEEDED' ||
        taskResponseController == null) {
      return null;
    }
    return ResidentTaskNotificationScreen(
      session: session,
      controller: taskResponseController,
      notification: notification,
    );
  }

  if (profile == null || profile.role != OperatorRole.pendampingRt) return null;
  if (notification.eventType == 'TASK_VERIFICATION_NEEDED') {
    if (taskResponseController == null) return null;
    return TaskVerificationQueueScreen(
      profile: profile,
      controller: taskResponseController,
      initialTaskId: notification.taskId,
    );
  }

  final boundary = campaignBoundary;
  if (notification.eventType != 'TASK_ESCALATION' ||
      boundary is! TaskCampaignManagementBoundary ||
      boundary is! TaskCampaignBoundary) {
    return null;
  }
  return TaskActiveCampaignsScreen(
    profile: profile,
    controller: TaskCampaignController(boundary),
    initialTaskId: notification.taskId,
  );
}

/// Connects verified role routes to FCM events without exposing IDs as authorization.
final class TaskPushNotificationListener extends StatefulWidget {
  const TaskPushNotificationListener.forResident({
    required this.controller,
    required this.session,
    required this.taskResponseController,
    required this.child,
    super.key,
  }) : profile = null,
       campaignBoundary = null;

  const TaskPushNotificationListener.forPendamping({
    required this.controller,
    required this.profile,
    required this.campaignBoundary,
    this.taskResponseController,
    required this.child,
    super.key,
  }) : session = null;

  final TaskPushNotificationsController controller;
  final ResidentSession? session;
  final OperatorProfile? profile;
  final TaskResponseController? taskResponseController;
  final TaskCampaignBoundary? campaignBoundary;
  final Widget child;

  @override
  State<TaskPushNotificationListener> createState() =>
      _TaskPushNotificationListenerState();
}

final class _TaskPushNotificationListenerState
    extends State<TaskPushNotificationListener> {
  StreamSubscription<TaskPushNotification>? _openedSubscription;
  StreamSubscription<TaskPushNotification>? _foregroundSubscription;
  bool _routing = false;

  @override
  void initState() {
    super.initState();
    _openedSubscription = widget.controller.openedNotifications.listen(_open);
    _foregroundSubscription = widget.controller.foregroundNotifications.listen(
      _showForeground,
    );
    final session = widget.session;
    if (session != null) {
      unawaited(widget.controller.syncResidentSession(session));
    } else if (widget.profile case final profile?) {
      unawaited(widget.controller.syncPendamping(profile));
    }
    unawaited(_openInitial());
  }

  @override
  void dispose() {
    _openedSubscription?.cancel();
    _foregroundSubscription?.cancel();
    super.dispose();
  }

  Future<void> _openInitial() async {
    final notification = await widget.controller
        .readPendingInitialNotification();
    if (mounted && notification != null) _open(notification, isInitial: true);
  }

  void _showForeground(TaskPushNotification notification) {
    if (!mounted) return;
    final isResident = widget.session != null;
    const operatorEventTypes = {'TASK_ESCALATION', 'TASK_VERIFICATION_NEEDED'};
    if (isResident && operatorEventTypes.contains(notification.eventType)) {
      return;
    }
    if (!isResident && !operatorEventTypes.contains(notification.eventType)) {
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            isResident
                ? 'Ada pemberitahuan tugas dari RT. Keikutsertaan tetap sukarela.'
                : notification.eventType == 'TASK_VERIFICATION_NEEDED'
                ? 'Ada penyelesaian tugas yang menunggu tinjauan RT.'
                : 'Ada tugas yang memerlukan tinjauan administratif.',
          ),
          action: SnackBarAction(
            label: isResident ? 'Buka' : 'Tinjau',
            onPressed: () => _open(notification),
          ),
        ),
      );
  }

  void _open(TaskPushNotification notification, {bool isInitial = false}) {
    if (!mounted || _routing) return;
    final destination = taskNotificationDestination(
      notification: notification,
      session: widget.session,
      profile: widget.profile,
      taskResponseController: widget.taskResponseController,
      campaignBoundary: widget.campaignBoundary,
    );
    if (destination == null) return;
    if (isInitial) {
      widget.controller.acknowledgeInitialNotification(notification);
    }
    _routing = true;
    unawaited(
      Navigator.of(context)
          .push<void>(MaterialPageRoute<void>(builder: (_) => destination))
          .whenComplete(() => _routing = false),
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
