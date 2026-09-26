import '../models/app_session.dart';

/// KONTRAK antara UI dan backend. Widget di features/auth/ HANYA bicara
/// lewat interface ini — tidak pernah import firebase_auth/cloud_functions
/// langsung.
///
/// Fake implementation (lib/data/fake/fake_auth_repository.dart) dipakai
/// Zaki sekarang untuk build & demo UI. Implementasi asli (manggil Firebase
/// Auth + RT-code validation Cloud Function) jadi bagian Hysan67 — begitu
/// siap, cukup di-swap di titik injection (lihat main.dart), UI tidak
/// berubah sama sekali.
///
/// CATATAN KOORDINASI (harus disepakati sebelum Hysan67 mulai backend):
/// - loginOperator melempar AuthException dengan pesan generic kalau
///   email/password salah (jangan bedakan pesan "email tidak ditemukan"
///   vs "password salah" — itu bocorin info, lihat S-05).
/// - joinWithRtCode melempar AuthException generic juga untuk kode RT
///   yang salah/kadaluarsa (jangan bocorin apakah RT-nya ada atau tidak).
abstract class AuthRepository {
  /// Login Ketua RT/RW dengan email & password (Firebase Auth di baliknya).
  Future<AppSession> loginOperator({
    required String email,
    required String password,
  });

  /// Warga masuk pakai kode RT — tanpa akun formal, hasilnya token
  /// opaque yang di-scope ke satu RT saja (S-06).
  Future<AppSession> joinWithRtCode(String rtCode);

  Future<void> logout();
}
