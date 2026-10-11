import 'package:flutter/material.dart';

import '../core/config/app_config.dart';
import '../features/auth/application/operator_auth_boundary.dart';
import '../features/auth/application/resident_session_controller.dart';
import '../features/tasks/application/task_campaign_boundary.dart';
import '../features/assistance/application/assistance_volunteer_boundary.dart';
import '../features/assistance/application/proxy_resident_boundary.dart';
import '../features/tasks/application/task_response_boundary.dart';
import '../features/proposals/application/resident_proposal_boundary.dart';
import '../features/emergency/application/emergency_directory_controller.dart';
import '../features/weather/application/weather_snapshot_store.dart';
import '../features/weather/application/weather_snapshot_boundary.dart';
import '../features/weather/application/weather_suggestion_boundary.dart';
import '../features/notifications/application/task_push_notifications.dart';
import 'router.dart';

/// Root widget and dependency assembly point for Guyub.id.
final class GuyubApp extends StatelessWidget {
  const GuyubApp({
    this.operatorAuthBoundary,
    this.residentSessionController,
    this.taskCampaignBoundary,
    this.taskResponseController,
    this.residentProposalController,
    this.proposalReviewController,
    this.emergencyDirectoryController,
    this.weatherSnapshotStore,
    this.weatherSnapshotSyncController,
    this.weatherSuggestionBoundary,
    this.proxyResidentController,
    this.assistanceVolunteerController,
    this.taskPushNotificationsController,
    this.connectivityChanges,
    super.key,
  });

  final OperatorAuthBoundary? operatorAuthBoundary;
  final ResidentSessionController? residentSessionController;
  final TaskCampaignBoundary? taskCampaignBoundary;
  final TaskResponseController? taskResponseController;
  final ResidentProposalController? residentProposalController;
  final ResidentProposalReviewController? proposalReviewController;
  final EmergencyDirectoryController? emergencyDirectoryController;
  final WeatherSnapshotStore? weatherSnapshotStore;
  final WeatherSnapshotSyncController? weatherSnapshotSyncController;
  final WeatherSuggestionBoundary? weatherSuggestionBoundary;
  final ProxyResidentController? proxyResidentController;
  final AssistanceVolunteerController? assistanceVolunteerController;
  final TaskPushNotificationsController? taskPushNotificationsController;
  final Stream<bool>? connectivityChanges;

  @override
  Widget build(BuildContext context) {
    final config = AppConfig.current;

    return MaterialApp(
      title: config.appName,
      debugShowCheckedModeBanner: config.environment.isDevelopment,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1E88E5)),
        useMaterial3: true,
      ),
      initialRoute: AppRouter.initial,
      onGenerateRoute: (settings) => AppRouter.onGenerateRoute(
        settings,
        operatorAuthBoundary: operatorAuthBoundary,
        residentSessionController: residentSessionController,
        taskCampaignBoundary: taskCampaignBoundary,
        taskResponseController: taskResponseController,
        residentProposalController: residentProposalController,
        proposalReviewController: proposalReviewController,
        emergencyDirectoryController: emergencyDirectoryController,
        weatherSnapshotStore: weatherSnapshotStore,
        weatherSnapshotSyncController: weatherSnapshotSyncController,
        weatherSuggestionBoundary: weatherSuggestionBoundary,
        proxyResidentController: proxyResidentController,
        assistanceVolunteerController: assistanceVolunteerController,
        taskPushNotificationsController: taskPushNotificationsController,
        connectivityChanges: connectivityChanges,
      ),
    );
  }
}
