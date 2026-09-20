/// Peran (role) pengguna utama pada aplikasi Guyub.id.
///
/// Peran menentukan jalur masuk (entry path) dan hak akses dasar:
/// - [ketuaRtRw] dan [pendampingRt] adalah **operator formal** yang
///   menggunakan Firebase Authentication (email & kata sandi).
/// - [warga] **tidak** membuat akun formal dan masuk menggunakan kode RT
///   melalui mekanisme sesi peserta yang discope server.
///
/// Enum ini tidak boleh diakses langsung oleh widget UI untuk bercabang logika;
/// UI sebaiknya membaca nilai turunan pada state application layer.
enum UserRole {
  /// Ketua RT/RW — operator utama yang menyetujui dan mengirim tugas.
  ketuaRtRw,

  /// Pendamping RT — sekretaris/warga yang ditunjuk, memiliki hak operasional setara.
  pendampingRt,

  /// Warga — peserta sukarela tanpa akun formal.
  warga;

  /// Menandakan apakah peran termasuk operator formal (punya akun Firebase Auth).
  bool get isOperator => this == ketuaRtRw || this == pendampingRt;

  /// Label Bahasa Indonesia yang aman ditampilkan di UI.
  String get label => switch (this) {
    UserRole.ketuaRtRw => 'Ketua RT/RW',
    UserRole.pendampingRt => 'Pendamping RT',
    UserRole.warga => 'Warga',
  };
}