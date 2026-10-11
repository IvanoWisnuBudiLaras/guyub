import 'package:flutter/material.dart';

import '../features/auth/application/operator_auth_boundary.dart';
import '../features/auth/application/operator_profile.dart';
import '../features/auth/application/resident_session.dart';
import '../features/auth/application/resident_session_controller.dart';
import '../features/tasks/application/task_campaign_boundary.dart';
import '../features/tasks/application/task_response_boundary.dart';
import '../features/tasks/presentation/screens/task_catalog_screen.dart';
import '../features/tasks/presentation/screens/task_active_campaigns_screen.dart';
import '../features/tasks/presentation/screens/task_history_screen.dart';
import '../features/tasks/presentation/screens/task_response_screens.dart';
import '../features/proposals/application/resident_proposal_boundary.dart';
import '../features/proposals/presentation/resident_proposal_screen.dart';
import '../features/proposals/presentation/resident_proposal_review_screen.dart';
import '../features/auth/presentation/screens/operator_home_screen.dart';
import '../features/auth/presentation/screens/operator_login_screen.dart';
import '../features/auth/presentation/screens/resident_entry_screen.dart';
import '../features/auth/presentation/screens/resident_session_home_screen.dart';
import '../features/auth/presentation/screens/role_selection_screen.dart';
import '../features/emergency/application/emergency_directory_controller.dart';
import '../features/emergency/presentation/emergency_directory_screen.dart';
import '../features/weather/application/weather_snapshot_store.dart';
import '../features/weather/application/weather_snapshot_boundary.dart';
import '../features/weather/application/weather_suggestion_boundary.dart';
import '../features/weather/presentation/weather_suggestion_review_screen.dart';
import '../features/assistance/application/assistance_volunteer_boundary.dart';
import '../features/assistance/application/proxy_resident_boundary.dart';
import '../features/assistance/presentation/assistance_volunteer_screen.dart';
import '../features/assistance/presentation/proxy_resident_screen.dart';
import '../features/notifications/application/task_push_notifications.dart';
import '../features/notifications/presentation/task_push_notification_listener.dart';

/// Role-aware routes for the Android MVP.
final class AppRouter {
  static const String initial = '/';
  static const String operatorLogin = '/operator/login';
  static const String operatorHome = '/operator/home';
  static const String operatorTaskCatalog = '/operator/tasks/catalog';
  static const String operatorActiveTasks = '/operator/tasks/active';
  static const String operatorTaskHistory = '/operator/tasks/history';
  static const String operatorWeatherSuggestions =
      '/operator/weather-suggestions';
  static const String operatorTaskVerification = '/operator/tasks/verification';
  static const String residentEntry = '/resident/entry';
  static const String residentHome = '/resident/home';
  static const String residentTaskList = '/resident/tasks';
  static const String residentProposals = '/resident/proposals';
  static const String operatorProposals = '/operator/proposals';
  static const String operatorAssistance = '/operator/assistance';
  static const String residentAssistance = '/resident/assistance';
  static const String emergencyDirectory = '/emergency';

  static Route<dynamic> onGenerateRoute(
    RouteSettings settings, {
    OperatorAuthBoundary? operatorAuthBoundary,
    ResidentSessionController? residentSessionController,
    TaskCampaignBoundary? taskCampaignBoundary,
    TaskResponseController? taskResponseController,
    ResidentProposalController? residentProposalController,
    ResidentProposalReviewController? proposalReviewController,
    EmergencyDirectoryController? emergencyDirectoryController,
    WeatherSnapshotStore? weatherSnapshotStore,
    WeatherSnapshotSyncController? weatherSnapshotSyncController,
    WeatherSuggestionBoundary? weatherSuggestionBoundary,
    ProxyResidentController? proxyResidentController,
    AssistanceVolunteerController? assistanceVolunteerController,
    TaskPushNotificationsController? taskPushNotificationsController,
    Stream<bool>? connectivityChanges,
  }) {
    switch (settings.name) {
      case initial:
        return MaterialPageRoute<void>(
          builder: (_) => const RoleSelectionScreen(),
          settings: settings,
        );
      case operatorLogin:
        return MaterialPageRoute<void>(
          builder: (context) => OperatorLoginScreen(
            authBoundary: operatorAuthBoundary,
            onAuthenticated: (profile) =>
                Navigator.of(context)
                    .pushReplacementNamed(operatorHome, arguments: profile),
          ),
          settings: settings,
        );
      case operatorHome:
        final profile = settings.arguments;
        if (profile is! OperatorProfile) return _roleSelection(settings);
        return MaterialPageRoute<void>(
          builder: (_) {
            final home = OperatorHomeScreen(
              profile: profile,
              authBoundary: operatorAuthBoundary,
              taskCampaignBoundary: taskCampaignBoundary,
              taskResponseController: taskResponseController,
              proposalReviewController: proposalReviewController,
              proxyResidentController: proxyResidentController,
              taskPushNotificationsController: taskPushNotificationsController,
              weatherSuggestionBoundary: weatherSuggestionBoundary,
            );
            if (taskPushNotificationsController == null ||
                profile.role != OperatorRole.pendampingRt) {
              return home;
            }
            return TaskPushNotificationListener.forPendamping(
              controller: taskPushNotificationsController,
              profile: profile,
              campaignBoundary: taskCampaignBoundary,
              taskResponseController: taskResponseController,
              child: home,
            );
          },
          settings: settings,
        );
      case operatorWeatherSuggestions:
        final profile = settings.arguments;
        final suggestions = weatherSuggestionBoundary;
        if (profile is! OperatorProfile ||
            suggestions == null ||
            taskCampaignBoundary == null) {
          return _roleSelection(settings);
        }
        return MaterialPageRoute<void>(
          builder: (_) => WeatherSuggestionReviewScreen(
            profile: profile,
            suggestionBoundary: suggestions,
            taskCampaignController: TaskCampaignController(
              taskCampaignBoundary,
            ),
            weatherSnapshotStore: weatherSnapshotStore,
            weatherSnapshotSyncController: weatherSnapshotSyncController,
          ),
          settings: settings,
        );
      case operatorTaskCatalog:
        final profile = settings.arguments;
        if (profile is! OperatorProfile || taskCampaignBoundary == null) {
          return _roleSelection(settings);
        }
        return MaterialPageRoute<void>(
          builder: (_) => TaskCatalogScreen(
            profile: profile,
            controller: TaskCampaignController(taskCampaignBoundary),
          ),
          settings: settings,
        );
      case operatorActiveTasks:
        final profile = settings.arguments;
        final boundary = taskCampaignBoundary;
        if (profile is! OperatorProfile ||
            boundary == null ||
            boundary is! TaskCampaignManagementBoundary) {
          return _roleSelection(settings);
        }
        return MaterialPageRoute<void>(
          builder: (_) => TaskActiveCampaignsScreen(
            profile: profile,
            controller: TaskCampaignController(boundary),
          ),
          settings: settings,
        );
      case operatorTaskHistory:
        final profile = settings.arguments;
        final boundary = taskCampaignBoundary;
        if (profile is! OperatorProfile ||
            boundary == null ||
            boundary is! TaskCampaignManagementBoundary ||
            boundary is! TaskCampaignHistoryBoundary) {
          return _roleSelection(settings);
        }
        return MaterialPageRoute<void>(
          builder: (_) => TaskHistoryScreen(
            profile: profile,
            controller: TaskCampaignController(boundary),
            taskResponseController: taskResponseController,
          ),
          settings: settings,
        );
      case operatorTaskVerification:
        final profile = settings.arguments;
        if (profile is! OperatorProfile || taskResponseController == null) {
          return _roleSelection(settings);
        }
        return MaterialPageRoute<void>(
          builder: (_) => TaskVerificationQueueScreen(
            profile: profile,
            controller: taskResponseController,
          ),
          settings: settings,
        );
      case operatorProposals:
        final profile = settings.arguments;
        if (profile is! OperatorProfile || proposalReviewController == null) {
          return _roleSelection(settings);
        }
        return MaterialPageRoute<void>(
          builder: (_) => ResidentProposalReviewScreen(
            profile: profile,
            controller: proposalReviewController,
            campaignController: taskCampaignBoundary == null
                ? null
                : TaskCampaignController(taskCampaignBoundary),
          ),
          settings: settings,
        );
      case operatorAssistance:
        final profile = settings.arguments;
        if (profile is! OperatorProfile || proxyResidentController == null) {
          return _roleSelection(settings);
        }
        return MaterialPageRoute<void>(
          builder: (_) => ProxyResidentScreen(
            profile: profile,
            controller: proxyResidentController,
            taskCampaignController: taskCampaignBoundary == null
                ? null
                : TaskCampaignController(taskCampaignBoundary),
          ),
          settings: settings,
        );
      case residentEntry:
        return MaterialPageRoute<void>(
          builder: (context) => ResidentEntryScreen(
            controller: residentSessionController,
            onAuthenticated: (session) =>
                Navigator.of(context)
                    .pushReplacementNamed(residentHome, arguments: session),
          ),
          settings: settings,
        );
      case residentHome:
        final session = settings.arguments;
        if (session is! ResidentSession || residentSessionController == null) {
          return _roleSelection(settings);
        }
        return MaterialPageRoute<void>(
          builder: (_) {
            final home = ResidentSessionHomeScreen(
              session: session,
              controller: residentSessionController,
              taskResponseController: taskResponseController,
              residentProposalController: residentProposalController,
              weatherSnapshotStore: weatherSnapshotStore,
              weatherSnapshotSyncController: weatherSnapshotSyncController,
              assistanceVolunteerController: assistanceVolunteerController,
              taskPushNotificationsController: taskPushNotificationsController,
              connectivityChanges: connectivityChanges,
            );
            if (taskPushNotificationsController == null ||
                taskResponseController == null) {
              return home;
            }
            return TaskPushNotificationListener.forResident(
              controller: taskPushNotificationsController,
              session: session,
              taskResponseController: taskResponseController,
              child: home,
            );
          },
          settings: settings,
        );
      case residentAssistance:
        final session = settings.arguments;
        if (session is! ResidentSession ||
            assistanceVolunteerController == null) {
          return _roleSelection(settings);
        }
        return MaterialPageRoute<void>(
          builder: (_) => AssistanceVolunteerScreen(
            session: session,
            controller: assistanceVolunteerController,
          ),
          settings: settings,
        );
      case residentTaskList:
        final session = settings.arguments;
        if (session is! ResidentSession || taskResponseController == null) {
          return _roleSelection(settings);
        }
        return MaterialPageRoute<void>(
          builder: (_) => ResidentTaskListScreen(
            session: session,
            controller: taskResponseController,
            connectivityChanges: connectivityChanges,
          ),
          settings: settings,
        );
      case residentProposals:
        final session = settings.arguments;
        if (session is! ResidentSession || residentProposalController == null) {
          return _roleSelection(settings);
        }
        return MaterialPageRoute<void>(
          builder: (_) => ResidentProposalScreen(
            session: session,
            controller: residentProposalController,
          ),
          settings: settings,
        );
      case emergencyDirectory:
        final directoryController = emergencyDirectoryController;
        if (directoryController == null) {
          return MaterialPageRoute<void>(
            builder: (_) => const EmergencyDirectoryUnavailableScreen(),
            settings: settings,
          );
        }
        final session = settings.arguments;
        return MaterialPageRoute<void>(
          builder: (_) => EmergencyDirectoryScreen(
            controller: directoryController,
            session: session is ResidentSession ? session : null,
          ),
          settings: settings,
        );
      default:
        return _roleSelection(settings);
    }
  }

  static MaterialPageRoute<void> _roleSelection(RouteSettings settings) =>
      MaterialPageRoute<void>(
        builder: (_) => const RoleSelectionScreen(),
        settings: settings,
      );
}
