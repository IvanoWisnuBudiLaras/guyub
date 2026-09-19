import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';

import 'app_environment.dart';

/// Menyimpan konfigurasi runtime aplikasi Guyub.id.
///
/// Objek ini tidak boleh berisi secret produksi yang ditanam langsung
/// di source code (sesuai aturan PRD §21 SEC-06).
///
/// Konfigurasi dipilih dan disuntikkan ketika aplikasi melakukan bootstrap
/// sehingga presentation dan application layer tidak perlu mengetahui
/// bagaimana environment dikonfigurasi.
final class AppConfig {
  /// Lingkungan eksekusi aktif aplikasi.
  final AppEnvironment environment;

  /// Judul tampilan aplikasi pada window atau status bar.
  final String appName;

  /// Menandakan apakah koneksi backend harus diarahkan ke emulator lokal.
  final bool useEmulator;

  /// Host emulator backend (misalnya `10.0.2.2` untuk Android emulator).
  final String emulatorHost;

  /// Port emulator Auth Firebase/backend.
  final int authPort;

  /// Port emulator Firestore/database dokumen.
  final int firestorePort;

  // ponytail: static singleton ceiling; ganti dengan InheritedWidget/Riverpod jika aplikasi membutuhkan multi-tenant dinamis.
  static AppConfig? _instance;

  /// Mengambil instance konfigurasi global saat ini.
  ///
  /// Menghasilkan [AppConfig.development] secara default jika belum diinisialisasi
  /// agar widget test atau eksekusi ad-hoc tidak mengalami runtime crash.
  static AppConfig get current {
    _instance ??= AppConfig.development();
    return _instance!;
  }

  /// Mendaftarkan konfigurasi aktif saat proses [bootstrap].
  static void initialize(AppConfig config) {
    _instance = config;
  }

  /// Mengembalikan state singleton ke `null`, terutama berguna untuk isolasi pengujian.
  static void resetForTesting() {
    _instance = null;
  }

  const AppConfig({
    required this.environment,
    required this.appName,
    required this.useEmulator,
    required this.emulatorHost,
    this.authPort = 9099,
    this.firestorePort = 8080,
  });

  /// Menentukan default emulator host berdasarkan platform eksekusi.
  ///
  /// Android Emulator menggunakan IP virtual gateway `10.0.2.2` untuk
  /// mengakses localhost mesin host pengembangan.
  static String get defaultEmulatorHost {
    if (kIsWeb) return 'localhost';
    try {
      if (Platform.isAndroid) return '10.0.2.2';
    } catch (_) {}
    return 'localhost';
  }

  /// Konfigurasi untuk lingkungan pengembangan lokal (development).
  factory AppConfig.development({
    bool useEmulator = true,
    String? emulatorHost,
  }) {
    return AppConfig(
      environment: AppEnvironment.development,
      appName: 'Guyub [DEV]',
      useEmulator: useEmulator,
      emulatorHost: emulatorHost ?? defaultEmulatorHost,
    );
  }

  /// Konfigurasi untuk lingkungan pengujian otomatis (test/CI).
  ///
  /// Mengisolasi network dan menggunakan mock/in-memory boundary.
  factory AppConfig.test() {
    return const AppConfig(
      environment: AppEnvironment.test,
      appName: 'Guyub [TEST]',
      useEmulator: true,
      emulatorHost: '127.0.0.1',
    );
  }

  /// Konfigurasi untuk lingkungan rilis produksi (production).
  factory AppConfig.production() {
    return const AppConfig(
      environment: AppEnvironment.production,
      appName: 'Guyub',
      useEmulator: false,
      emulatorHost: '',
    );
  }
}
