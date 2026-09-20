import '../../../../core/result/result.dart';
import '../entities/resident_session.dart';

/// Kontrak boundary untuk mekanisme **sesi peserta warga** yang dimediasi backend.
///
/// Warga tidak membuat akun Firebase Auth (PRD §13). Alur yang benar:
/// 1. warga memasukkan kode RT,
/// 2. aplikasi memanggil endpoint backend untuk memvalidasi kode,
/// 3. backend mengembalikan kontak RT non-sensitif + token sesi opaque,
/// 4. token disimpan aman di perangkat dan dipakai untuk mutasi warga yang
///    divalidasi ulang backend.
///
/// **Larangan (SEC-02, SEC-03):** kode RT bukanlah rahasia admin global dan
/// tidak boleh menjadi otorisasi permanen untuk menulis koleksi terlindungi.
/// Implementasi client tidak boleh menulis langsung ke Firestore atas nama warga.
abstract interface class ResidentSessionBoundary {
  /// Memvalidasi [joinCode] dan menukarnya dengan [ResidentSession].
  ///
  /// Jika kode tidak valid/kedaluwarsa, mengembalikan [ValidationError] dengan
  /// pesan **generik** tanpa membocorkan keberadaan RT/warga mana pun (ERR-04).
  Future<Result<ResidentSession>> joinWithCode(String joinCode);

  /// Mengambil sesi peserta yang tersimpan di perangkat, bila masih berlaku.
  ///
  /// Mengembalikan `null` di dalam [Success] jika tidak ada sesi tersimpan.
  /// Sesi yang kedaluwarsa tidak boleh dikembalikan sebagai valid.
  Future<Result<ResidentSession?>> restoreSession();

  /// Menghapus sesi peserta dari perangkat (mis. warga keluar atau sesi dicabut).
  Future<Result<void>> clearSession();
}