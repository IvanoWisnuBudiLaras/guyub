import 'package:flutter/material.dart';

import '../features/auth/presentation/screens/operator_login_screen.dart';
import '../features/auth/presentation/screens/resident_rt_code_screen.dart';
import '../features/auth/presentation/screens/role_selection_screen.dart';
import '../features/auth/presentation/screens/splash_screen.dart';
import '../features/tasks/presentation/screens/task_catalog_screen.dart';
import 'app_shell.dart';

/// Rute navigasi deklaratif aplikasi Guyub.id.
final class AppRouter {
  static const String initial = '/';
  static const String roleSelection = '/role-selection';
  static const String operatorLogin = '/operator-login';
  static const String residentRtCode = '/resident-rt-code';
  static const String shell = '/shell';
  static const String taskCatalog = '/task-catalog';

  /// Handler pembuatan rute dinamis berbasis [RouteSettings].
  static Route<dynamic> onGenerateRoute(RouteSettings settings) {
    switch (settings.name) {
      case initial:
        return MaterialPageRoute(
          builder: (_) => const SplashScreen(),
          settings: settings,
        );
      case roleSelection:
        return MaterialPageRoute(
          builder: (_) => const RoleSelectionScreen(),
          settings: settings,
        );
      case operatorLogin:
        return MaterialPageRoute(
          builder: (_) => const OperatorLoginScreen(),
          settings: settings,
        );
      case residentRtCode:
        return MaterialPageRoute(
          builder: (_) => const ResidentRtCodeScreen(),
          settings: settings,
        );
      case shell:
        return MaterialPageRoute(
          builder: (_) => const AppShell(),
          settings: settings,
        );
      case taskCatalog:
        return MaterialPageRoute(
          builder: (_) => const TaskCatalogScreen(),
          settings: settings,
        );
      default:
        return MaterialPageRoute(
          builder: (_) => const SplashScreen(),
          settings: settings,
        );
    }
  }
}
