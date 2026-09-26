import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/config/app_config.dart';
import '../dev/fake_auth_controller.dart';
import '../features/auth/application/auth_controller.dart';
import 'router.dart';
import 'theme/app_theme.dart';

/// Root widget aplikasi Guyub.id.
///
/// Menyiapkan [MaterialApp], tema [AppTheme.light], dan pengelola state [AuthController].
final class GuyubApp extends StatelessWidget {
  final AuthController? authController;

  const GuyubApp({
    super.key,
    this.authController,
  });

  @override
  Widget build(BuildContext context) {
    final config = AppConfig.current;

    return ChangeNotifierProvider<AuthController>(
      create: (_) => authController ?? createDevAuthController(),
      child: MaterialApp(
        title: config.appName,
        debugShowCheckedModeBanner: config.environment.isDevelopment,
        theme: AppTheme.light(),
        initialRoute: AppRouter.initial,
        onGenerateRoute: AppRouter.onGenerateRoute,
      ),
    );
  }
}
