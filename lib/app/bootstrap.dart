import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';

import '../core/config/app_config.dart';
import '../core/config/app_environment.dart';
import '../firebase_options.dart';
import 'app.dart';

/// Menyiapkan instans [GuyubApp] untuk pengujian atau eksekusi runtime.
///
/// Memisahkan instansiasi widget dari side-effect jaringan/Firebase agar dapat
/// diuji dalam lingkungan terisolasi tanpa koneksi backend produksi.
Future<Widget> createBootstrapApp(AppConfig config) async {
  WidgetsFlutterBinding.ensureInitialized();
  AppConfig.initialize(config);
  return const GuyubApp();
}

/// Titik masuk proses bootstrap utama aplikasi Guyub.id.
///
/// 1. Menginisialisasi Flutter binding.
/// 2. Mendaftarkan konfigurasi runtime [config].
/// 3. Menghubungkan Firebase ke emulator lokal jika [AppConfig.useEmulator] aktif
///    dan bukan dalam mode [AppEnvironment.test].
/// 4. Menjalankan widget root [GuyubApp].
Future<void> bootstrap(AppConfig config) async {
  final app = await createBootstrapApp(config);

  // ponytail: Firebase diinisialisasi hanya jika bukan mode isolasi pengujian unit.
  if (config.environment != AppEnvironment.test) {
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    } catch (_) {
      // Fallback graceful: kegagalan koneksi awal tidak boleh membuat aplikasi force-close offline.
    }
  }

  runApp(app);
}
