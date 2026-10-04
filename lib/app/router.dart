import 'package:flutter/material.dart';

import '../features/auth/application/operator_auth_boundary.dart';
import '../features/auth/application/operator_profile.dart';
import '../features/auth/presentation/screens/operator_home_screen.dart';
import '../features/auth/presentation/screens/operator_login_screen.dart';
import '../features/auth/presentation/screens/resident_entry_screen.dart';
import '../features/auth/presentation/screens/role_selection_screen.dart';

/// Role-aware routes for the Android MVP.
final class AppRouter {
  static const String initial = '/';
  static const String operatorLogin = '/operator/login';
  static const String operatorHome = '/operator/home';
  static const String residentEntry = '/resident/entry';

  static Route<dynamic> onGenerateRoute(
    RouteSettings settings, {
    OperatorAuthBoundary? operatorAuthBoundary,
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
          ),
          settings: settings,
        );
      case residentEntry:
        return MaterialPageRoute<void>(
          builder: (_) => const ResidentEntryScreen(),
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
