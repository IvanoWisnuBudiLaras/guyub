import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import '../core/config/app_config.dart';
import '../core/config/app_environment.dart';
import '../features/auth/application/operator_auth_boundary.dart';
import '../features/auth/data/firebase_operator_auth_boundary.dart';
import '../firebase_options.dart';
import 'app.dart';

/// Builds the root widget for isolated widget tests without Firebase access.
Future<Widget> createBootstrapApp(
  AppConfig config, {
  OperatorAuthBoundary? operatorAuthBoundary,
}) async {
  WidgetsFlutterBinding.ensureInitialized();
  AppConfig.initialize(config);
  return GuyubApp(operatorAuthBoundary: operatorAuthBoundary);
}

/// Initializes Firebase and connects development builds to local emulators.
///
/// If Firebase or the emulator is unavailable, the app still opens to role
/// selection, but operator sign-in remains unavailable. It never falls back
/// from a failed emulator connection to the configured production project.
Future<void> bootstrap(AppConfig config) async {
  WidgetsFlutterBinding.ensureInitialized();
  OperatorAuthBoundary? operatorAuthBoundary;
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
      operatorAuthBoundary = null;
    }
  }

  runApp(
    await createBootstrapApp(
      config,
      operatorAuthBoundary: operatorAuthBoundary,
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
