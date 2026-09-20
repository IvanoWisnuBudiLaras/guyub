import '../../../../core/result/result.dart';
import '../entities/operator_profile.dart';

/// Kontrak boundary untuk penelusuran keanggotaan operator pada komunitas RT.
///
/// Memisahkan logika "operator mana bernaung di RT mana" dari penyimpanan
/// konkret (Firestore), sehingga application layer dapat diuji dengan adapter
/// in-memory tanpa menyentuh backend.
///
/// **Batas otorisasi (SEC-01, AT Phase 1):** operator tidak boleh mengakses
/// data RT lain. Implementasi wajib memastikan hanya profil milik operator
/// terkait yang dikembalikan.
abstract interface class RtMembershipBoundary {
  /// Mengambil profil operator berdasarkan [uid] Firebase Auth.
  ///
  /// Mengembalikan [AuthError] bila operator tidak terdaftar atau tidak aktif.
  Future<Result<OperatorProfile>> findByUid(String uid);
}