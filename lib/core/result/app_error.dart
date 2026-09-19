/// Kelas dasar (sealed) untuk seluruh representasi kegagalan domain aplikasi.
///
/// **Panduan Penggunaan: Exception vs Result/AppError**
/// - Gunakan `Exception` untuk developer defect atau kondisi fatal yang tidak dapat
///   dipulihkan (misalnya kegagalan assertion internal, kesalahan konfigurasi kode).
/// - Gunakan `Result<T>` dan turunan [AppError] untuk kondisi gagal yang wajar
///   terjadi saat runtime (jaringan terputus, validasi form gagal, data lokal kosong).
///
/// Semua pesan kegagalan ramah pengguna wajib menggunakan Bahasa Indonesia
/// sesuai spesifikasi Guyub.id MVP.
sealed class AppError {
  /// Pesan yang aman ditampilkan kepada pengguna aplikasi.
  final String userMessage;

  /// Kode klasifikasi error (misalnya `ERR_NETWORK`, `ERR_VALIDATION`).
  final String code;

  /// Penyebab asli teknis jika berasal dari exception/error underlying layer.
  final Object? cause;

  const AppError({required this.userMessage, required this.code, this.cause});

  @override
  String toString() => '\$runtimeType(\$code): \$userMessage';
}

/// Kesalahan akibat masalah koneksi jaringan internet atau kegagalan fetch remote API.
final class NetworkError extends AppError {
  const NetworkError({
    String message = 'Koneksi internet bermasalah. Periksa sambungan Anda.',
    super.code = 'ERR_NETWORK',
    super.cause,
  }) : super(userMessage: message);
}

/// Kesalahan hak akses atau otentikasi peran operator RT/RW.
final class AuthError extends AppError {
  const AuthError({
    String message =
        'Akses tidak diizinkan. Silakan verifikasi identitas Anda.',
    super.code = 'ERR_AUTH',
    super.cause,
  }) : super(userMessage: message);
}

/// Kesalahan validasi data input dari pengguna (misal kode RT tidak valid, format salah).
final class ValidationError extends AppError {
  const ValidationError({
    required String message,
    super.code = 'ERR_VALIDATION',
    super.cause,
  }) : super(userMessage: message);
}

/// Kesalahan saat berinteraksi dengan media penyimpanan lokal perangkat.
final class DatabaseError extends AppError {
  const DatabaseError({
    String message = 'Gagal mengakses penyimpanan data lokal.',
    super.code = 'ERR_DATABASE',
    super.cause,
  }) : super(userMessage: message);
}

/// Kesalahan saat melakukan sinkronisasi data offline ke backend atau sebaliknya.
final class SyncError extends AppError {
  const SyncError({
    String message = 'Sinkronisasi tertunda atau terjadi konflik data.',
    super.code = 'ERR_SYNC',
    super.cause,
  }) : super(userMessage: message);
}

/// Kesalahan umum tak terduga yang belum terpetakan ke subtipe spesifik.
final class UnknownError extends AppError {
  const UnknownError({
    String message = 'Terjadi kesalahan sistem. Silakan coba kembali.',
    super.code = 'ERR_UNKNOWN',
    super.cause,
  }) : super(userMessage: message);
}
