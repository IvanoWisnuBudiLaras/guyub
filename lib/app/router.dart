import 'package:flutter/material.dart';

import '../features/auth/application/operator_auth_boundary.dart';
import '../features/auth/application/operator_profile.dart';
import '../features/auth/application/resident_session.dart';
import '../features/auth/application/resident_session_controller.dart';
import '../features/tasks/application/task_campaign_boundary.dart';
import '../features/tasks/application/task_response_boundary.dart';
import '../features/tasks/presentation/screens/task_catalog_screen.dart';
import '../features/tasks/presentation/screens/task_response_screens.dart';
import '../features/auth/presentation/screens/operator_home_screen.dart';
import '../features/auth/presentation/screens/operator_login_screen.dart';
import '../features/auth/presentation/screens/resident_entry_screen.dart';
import '../features/auth/presentation/screens/resident_session_home_screen.dart';
import '../features/auth/presentation/screens/role_selection_screen.dart';

/// Role-aware routes for the Android MVP.
final class AppRouter {
  static const String initial = '/';
  static const String operatorLogin = '/operator/login';
  static const String operatorHome = '/operator/home';
  static const String operatorTaskCatalog = '/operator/tasks/catalog';
  static const String operatorTaskVerification = '/operator/tasks/verification';
  static const String residentEntry = '/resident/entry';
  static const String residentHome = '/resident/home';
  static const String residentTaskList = '/resident/tasks';

  static Route<dynamic> onGenerateRoute(
    RouteSettings settings, {
    OperatorAuthBoundary? operatorAuthBoundary,
    ResidentSessionController? residentSessionController,
    TaskCampaignBoundary? taskCampaignBoundary,
    TaskResponseController? taskResponseController,
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
          builder: (_) => OperatorHomeScreen(
            profile: profile,
            authBoundary: operatorAuthBoundary,
            taskCampaignBoundary: taskCampaignBoundary,
            taskResponseController: taskResponseController,
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
          builder: (_) => ResidentSessionHomeScreen(
            session: session,
            controller: residentSessionController,
            taskResponseController: taskResponseController,
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
