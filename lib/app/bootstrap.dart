import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';

import '../core/config/app_config.dart';
import '../firebase_options.dart';
import 'app.dart';

/// Menyiapkan instans [GuyubApp] untuk pengujian atau eksekusi runtime.
Future<Widget> createBootstrapApp(AppConfig config) async {
  WidgetsFlutterBinding.ensureInitialized();
  AppConfig.initialize(config);
  return const GuyubApp();
}

/// Titik masuk proses bootstrap utama aplikasi Guyub.id.
Future<void> bootstrap(AppConfig config) async {
  WidgetsFlutterBinding.ensureInitialized();
  AppConfig.initialize(config);

  // Firebase diinisialisasi secara aman tanpa mengunci pemanggilan runApp
  if (!config.environment.isTest) {
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      debugPrint('[Guyub] Firebase terhubung di background.');
    } catch (e) {
      debugPrint('[Guyub] Graceful fallback Firebase: $e');
    }
  }

  runApp(const GuyubApp());
}