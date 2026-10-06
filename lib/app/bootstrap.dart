import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../core/config/app_config.dart';
import '../core/config/app_environment.dart';
import '../core/database/local_store.dart';
import '../core/database/shared_prefs_local_store.dart';
import '../features/auth/application/operator_auth_boundary.dart';
import '../features/auth/application/resident_session_controller.dart';
import '../features/auth/data/firebase_operator_auth_boundary.dart';
import '../features/auth/data/firebase_resident_session_boundary.dart';
import '../features/auth/data/flutter_secure_resident_session_vault.dart';
import '../features/emergency/application/emergency_directory.dart';
import '../features/emergency/application/emergency_directory_boundary.dart';
import '../features/emergency/application/emergency_directory_controller.dart';
import '../features/emergency/data/emergency_directory_cache.dart';
import '../features/emergency/data/firebase_emergency_directory_boundary.dart';
import '../features/tasks/application/task_campaign_boundary.dart';
import '../features/assistance/application/assistance_volunteer_boundary.dart';
import '../features/assistance/application/proxy_resident_boundary.dart';
import '../features/assistance/data/firebase_proxy_resident_boundary.dart';
import '../features/assistance/data/flutter_secure_proxy_create_request_store.dart';
import '../features/tasks/application/task_response_boundary.dart';
import '../features/tasks/data/firebase_task_campaign_boundary.dart';
import '../features/tasks/data/firebase_task_response_boundary.dart';
import '../features/tasks/data/resident_task_offline_store.dart';
import '../features/weather/application/weather_snapshot_store.dart';
import '../features/weather/data/weather_snapshot_cache.dart';
import '../features/notifications/application/task_push_notifications.dart';
import '../features/notifications/data/firebase_task_push_notifications_boundary.dart';
import '../features/proposals/application/resident_proposal_boundary.dart';
import '../features/proposals/data/firebase_resident_proposal_boundary.dart';
import '../firebase_options.dart';
import 'app.dart';

/// Builds the root widget for isolated widget tests without Firebase access.
Future<Widget> createBootstrapApp(
  AppConfig config, {
  OperatorAuthBoundary? operatorAuthBoundary,
  ResidentSessionController? residentSessionController,
  TaskCampaignBoundary? taskCampaignBoundary,
  TaskResponseController? taskResponseController,
  ResidentProposalController? residentProposalController,
  ResidentProposalReviewController? proposalReviewController,
  EmergencyDirectoryController? emergencyDirectoryController,
  WeatherSnapshotStore? weatherSnapshotStore,
  ProxyResidentController? proxyResidentController,
  AssistanceVolunteerController? assistanceVolunteerController,
  TaskPushNotificationsController? taskPushNotificationsController,
}) async {
  WidgetsFlutterBinding.ensureInitialized();
  AppConfig.initialize(config);
  return GuyubApp(
    operatorAuthBoundary: operatorAuthBoundary,
    residentSessionController: residentSessionController,
    taskCampaignBoundary: taskCampaignBoundary,
    taskResponseController: taskResponseController,
    residentProposalController: residentProposalController,
    proposalReviewController: proposalReviewController,
    emergencyDirectoryController: emergencyDirectoryController,
    weatherSnapshotStore: weatherSnapshotStore,
    proxyResidentController: proxyResidentController,
    assistanceVolunteerController: assistanceVolunteerController,
    taskPushNotificationsController: taskPushNotificationsController,
  );
}

/// Initializes Firebase and connects development builds to local emulators.
///
/// If Firebase or an emulator is unavailable, the app still opens to role
/// selection, but protected operator/resident operations fail closed. Emulator
/// failures never fall back to the configured production project.
Future<void> bootstrap(AppConfig config) async {
  WidgetsFlutterBinding.ensureInitialized();
  LocalStore? localStore;
  try {
    localStore = await SharedPrefsLocalStore.create();
  } catch (_) {
    // Directory and task offline features fail closed if local storage fails.
  }
  final residentVault = FlutterSecureResidentSessionVault();
  ResidentTaskOfflineStore? taskOfflineStore;
  if (localStore != null) {
    taskOfflineStore = LocalResidentTaskOfflineStore(localStore: localStore);
  }
  EmergencyDirectoryBoundary? emergencyDirectoryBoundary;
  EmergencyDirectoryController? emergencyDirectoryController;
  WeatherSnapshotStore? weatherSnapshotStore;
  ProxyResidentController? proxyResidentController;
  AssistanceVolunteerController? assistanceVolunteerController;
  TaskPushNotificationsController? taskPushNotificationsController;
  OperatorAuthBoundary? operatorAuthBoundary;
  ResidentSessionController? residentSessionController;
  TaskCampaignBoundary? taskCampaignBoundary;
  TaskResponseController? taskResponseController;
  ResidentProposalController? residentProposalController;
  ResidentProposalReviewController? proposalReviewController;
  var callableAppCheckReady = false;
  final useEmulator =
      config.useEmulator || config.environment == AppEnvironment.development;

  if (config.environment != AppEnvironment.test) {
    try {
      await Firebase.initializeApp(
        options: useEmulator
            ? _developmentEmulatorOptions()
            : DefaultFirebaseOptions.currentPlatform,
      );
      if (useEmulator) {
        callableAppCheckReady = true;
      } else {
        try {
          // [app-check:debug-provider]: Pakai debug provider saat kDebugMode agar build APK debug pilot tidak ditolak callable.
          await FirebaseAppCheck.instance.activate(
            providerAndroid: kDebugMode
                ? const AndroidDebugProvider()
                : const AndroidPlayIntegrityProvider(),
          );
          callableAppCheckReady = true;
        } catch (_) {
          // Callable features stay unavailable without App Check.
        }
      }
      if (useEmulator) {
        await FirebaseAuth.instance.useAuthEmulator(
          config.emulatorHost,
          config.authPort,
        );
        FirebaseFirestore.instance.useFirestoreEmulator(
          config.emulatorHost,
          config.firestorePort,
        );
      }
      operatorAuthBoundary = FirebaseOperatorAuthBoundary(
        auth: FirebaseAuth.instance,
        firestore: FirebaseFirestore.instance,
      );
    } catch (_) {
      // Fail closed: no Firebase boundary is injected when setup is incomplete.
    }

    if (operatorAuthBoundary != null && callableAppCheckReady) {
      try {
        final functions = FirebaseFunctions.instanceFor(
          region: 'asia-southeast2',
        );
        if (useEmulator) {
          functions.useFunctionsEmulator(
            config.emulatorHost,
            config.functionsPort,
          );
        }
        emergencyDirectoryBoundary = FirebaseEmergencyDirectoryBoundary(
          functions,
        );
        residentSessionController = ResidentSessionController(
          boundary: FirebaseResidentSessionBoundary(functions),
          vault: residentVault,
        );
        taskCampaignBoundary = FirebaseTaskCampaignBoundary(functions);
        final assistanceBoundary = FirebaseProxyResidentBoundary(functions);
        proxyResidentController = ProxyResidentController(
          assistanceBoundary,
          createRequestStore: FlutterSecureProxyCreateRequestStore(),
        );
        assistanceVolunteerController = AssistanceVolunteerController(
          boundary: assistanceBoundary,
          readSessionToken: residentVault.read,
        );
        final responseBoundary = FirebaseTaskResponseBoundary(functions);
        taskResponseController = TaskResponseController(
          boundary: responseBoundary,
          evidenceBoundary: responseBoundary,
          vault: residentVault,
          offlineStore: taskOfflineStore,
        );
        final proposalBoundary = FirebaseResidentProposalBoundary(functions);
        residentProposalController = ResidentProposalController(
          boundary: proposalBoundary,
          vault: residentVault,
        );
        proposalReviewController = ResidentProposalReviewController(
          boundary: proposalBoundary,
        );
        if (localStore != null) {
          try {
            taskPushNotificationsController = TaskPushNotificationsController(
              boundary: FirebaseTaskPushNotificationsBoundary(
                messaging: FirebaseMessaging.instance,
                functions: functions,
              ),
              preferences: LocalTaskPushPreferenceStore(localStore),
              deviceTokens: FlutterSecureTaskPushDeviceTokenStore(),
              readResidentSessionToken: residentVault.read,
            );
          } catch (_) {
            // Task access remains available if platform push setup is unavailable.
          }
        }
      } catch (_) {
        // Operator sign-in remains available; callable features stay unavailable.
      }
    }
  }

  if (localStore != null) {
    final weatherCache = WeatherSnapshotCache(localStore);
    weatherSnapshotStore = weatherCache;
    emergencyDirectoryController = EmergencyDirectoryController(
      boundary:
          emergencyDirectoryBoundary ??
          _UnavailableEmergencyDirectoryBoundary(),
      cache: EmergencyDirectoryCache(localStore),
      vault: residentVault,
    );
  }

  runApp(
    await createBootstrapApp(
      config,
      operatorAuthBoundary: operatorAuthBoundary,
      residentSessionController: residentSessionController,
      taskCampaignBoundary: taskCampaignBoundary,
      taskResponseController: taskResponseController,
      residentProposalController: residentProposalController,
      proposalReviewController: proposalReviewController,
      emergencyDirectoryController: emergencyDirectoryController,
      weatherSnapshotStore: weatherSnapshotStore,
      proxyResidentController: proxyResidentController,
      assistanceVolunteerController: assistanceVolunteerController,
      taskPushNotificationsController: taskPushNotificationsController,
    ),
  );
}

FirebaseOptions _developmentEmulatorOptions() {
  final platform = DefaultFirebaseOptions.currentPlatform;
  return FirebaseOptions(
    apiKey: 'demo-api-key',
    appId: platform.appId,
    messagingSenderId: platform.messagingSenderId,
    projectId: 'demo-guyub-development',
  );
}

final class _UnavailableEmergencyDirectoryBoundary
    implements EmergencyDirectoryBoundary {
  @override
  Future<EmergencyDirectoryResponse> getEmergencyDirectory({
    required String sessionToken,
  }) async => throw StateError('Emergency directory callable is unavailable.');
}
