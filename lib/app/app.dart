import 'package:flutter/material.dart';

import '../core/config/app_config.dart';
import '../features/auth/application/operator_auth_boundary.dart';
import 'router.dart';

/// Root widget and dependency assembly point for Guyub.id.
final class GuyubApp extends StatelessWidget {
  const GuyubApp({this.operatorAuthBoundary, super.key});

  final OperatorAuthBoundary? operatorAuthBoundary;

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
      ),
    );
  }
}
