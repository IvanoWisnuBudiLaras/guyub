/// Lingkungan eksekusi (runtime environment) aplikasi Guyub.id.
///
/// Digunakan oleh [AppConfig] saat proses bootstrap untuk menentukan
/// profil konfigurasi (misalnya host emulator, prefix nama aplikasi, dan URL).
///
/// Feature layer tidak boleh membaca enum ini secara langsung; gunakan nilai
/// spesifik pada [AppConfig] untuk menghindari logic bercabang per environment
/// di dalam presentation atau business logic.
enum AppEnvironment {
  /// Lingkungan pengembangan lokal developer (menggunakan emulator/mock).
  development,

  /// Lingkungan khusus pengujian otomatis (unit, widget, dan integration test).
  test,

  /// Lingkungan produksi nyata untuk pengguna akhir (RT/RW dan warga).
  production;

  /// Menandakan apakah aplikasi berjalan dalam mode development.
  bool get isDevelopment => this == AppEnvironment.development;

  /// Menandakan apakah aplikasi berjalan dalam mode pengujian otomatis.
  bool get isTest => this == AppEnvironment.test;

  /// Menandakan apakah aplikasi berjalan dalam mode produksi.
  bool get isProduction => this == AppEnvironment.production;

  /// Melakukan parsing string environment (misal dari `--dart-define=ENV=...`).
  ///
  /// Mengembalikan [AppEnvironment.development] jika nilai tidak dikenali
  /// atau bernilai `null` agar aman untuk eksekusi lokal.
  static AppEnvironment fromString(String? raw) {
    return switch (raw?.toLowerCase().trim()) {
      'prod' || 'production' => AppEnvironment.production,
      'test' || 'testing' => AppEnvironment.test,
      _ => AppEnvironment.development,
    };
  }
}
