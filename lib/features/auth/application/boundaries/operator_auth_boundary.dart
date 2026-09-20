import '../../../../core/result/result.dart';
import '../entities/operator_profile.dart';

/// Kontrak boundary autentikasi operator formal (Ketua RT/RW dan Pendamping RT).
///
/// Presentation dan application layer mengonsumsi kontrak ini tanpa mengetahui
/// provider konkret di baliknya (Firebase Authentication). Implementasi konkret
/// berada pada data layer.
///
/// **Authorization boundary (SEC-01):** hasil otentikasi di client TIDAK boleh
/// dianggap sebagai otorisasi final. Setiap aksi operator tetap diverifikasi
/// server-side. Kontrak ini hanya menyediakan identitas sesi untuk kebutuhan UI
/// dan pemanggilan endpoint yang akan divalidasi ulang backend.
abstract interface class OperatorAuthBoundary {
  /// Masuk sebagai operator dengan kredensial email dan kata sandi.
  ///
  /// Mengembalikan [OperatorProfile] bila kredensial valid dan akun terdaftar
  /// sebagai operator aktif. Jika kredensial salah atau akun tidak berwenang,
  /// mengembalikan [AuthError] dengan pesan generik (tidak membocorkan apakah
  /// email terdaftar).
  Future<Result<OperatorProfile>> signInWithEmailPassword({
    required String email,
    required String password,
  });

  /// Keluar dari sesi operator saat ini dan membersihkan token lokal.
  Future<Result<void>> signOut();

  /// Memuat profil operator yang sedang aktif (mis. saat cold start).
  ///
  /// Mengembalikan `null` di dalam [Success] jika tidak ada sesi aktif.
  Future<Result<OperatorProfile?>> currentOperator();
}