import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../core/config/app_config.dart';
import '../core/config/app_environment.dart';
import '../features/auth/application/operator_auth_boundary.dart';
import '../features/auth/application/resident_session_controller.dart';
import '../features/auth/data/firebase_operator_auth_boundary.dart';
import '../features/auth/data/firebase_resident_session_boundary.dart';
import '../features/auth/data/flutter_secure_resident_session_vault.dart';
import '../features/tasks/application/task_campaign_boundary.dart';
import '../features/tasks/data/firebase_task_campaign_boundary.dart';
import '../firebase_options.dart';
import 'app.dart';

/// Builds the root widget for isolated widget tests without Firebase access.
Future<Widget> createBootstrapApp(
  AppConfig config, {
  OperatorAuthBoundary? operatorAuthBoundary,
  ResidentSessionController? residentSessionController,
  TaskCampaignBoundary? taskCampaignBoundary,
}) async {
  WidgetsFlutterBinding.ensureInitialized();
  AppConfig.initialize(config);
  return GuyubApp(
    operatorAuthBoundary: operatorAuthBoundary,
    residentSessionController: residentSessionController,
    taskCampaignBoundary: taskCampaignBoundary,
  );
}

/// Initializes Firebase and connects development builds to local emulators.
///
/// If Firebase or an emulator is unavailable, the app still opens to role
/// selection, but protected operator/resident operations fail closed. Emulator
/// failures never fall back to the configured production project.
Future<void> bootstrap(AppConfig config) async {
  WidgetsFlutterBinding.ensureInitialized();
  OperatorAuthBoundary? operatorAuthBoundary;
  ResidentSessionController? residentSessionController;
  TaskCampaignBoundary? taskCampaignBoundary;
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
          // Resident enrollment stays unavailable without App Check.
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
        residentSessionController = ResidentSessionController(
          boundary: FirebaseResidentSessionBoundary(functions),
          vault: FlutterSecureResidentSessionVault(),
        );
        taskCampaignBoundary = FirebaseTaskCampaignBoundary(functions);
      } catch (_) {
        // Operator sign-in remains available; callable features stay unavailable.
      }
    }
  }

  runApp(
    await createBootstrapApp(
      config,
      operatorAuthBoundary: operatorAuthBoundary,
      residentSessionController: residentSessionController,
      taskCampaignBoundary: taskCampaignBoundary,
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
