import 'package:flutter/material.dart';

import '../core/config/app_config.dart';
import '../features/auth/application/operator_auth_boundary.dart';
import '../features/auth/application/resident_session_controller.dart';
import '../features/tasks/application/task_campaign_boundary.dart';
import '../features/tasks/application/task_response_boundary.dart';
import '../features/proposals/application/resident_proposal_boundary.dart';
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
    super.key,
  });

  final OperatorAuthBoundary? operatorAuthBoundary;
  final ResidentSessionController? residentSessionController;
  final TaskCampaignBoundary? taskCampaignBoundary;
  final TaskResponseController? taskResponseController;
  final ResidentProposalController? residentProposalController;
  final ResidentProposalReviewController? proposalReviewController;

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
      ),
    );
  }
}
