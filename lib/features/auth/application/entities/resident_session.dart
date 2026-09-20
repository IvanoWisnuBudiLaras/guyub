import 'rt_community.dart';

/// Sesi peserta warga yang dihasilkan **oleh backend** setelah kode RT
/// divalidasi (PRD §13.3 — mekanisme sesi peserta yang discope server).
///
/// Sesi ini bukan akun Firebase Auth. Token bersifat opaque dan berumur pendek;
/// warga tidak boleh menulis langsung ke koleksi Firestore terlindungi
/// (SEC-02). Semua mutasi warga wajib melewati endpoint backend yang
/// memvalidasi token ini.
///
/// **Data minimal (INV-06):** hanya menyimpan identitas komunitas yang aman
/// ditampilkan, identitas peserta opaque, dan masa berlaku token.
final class ResidentSession {
  /// Identitas peserta yang digenerate server (bukan NIK/identitas legal).
  final String participantId;

  /// Identitas RT tempat sesi ini discope.
  final String rtId;

  /// Kontak komunitas yang aman ditampilkan (bukan data pribadi warga).
  final RtCommunity rtCommunity;

  /// Token sesi opaque. Tidak boleh diinterpretasikan/di-decode di client.
  final String token;

  /// Waktu kedaluwarsa token. Sesi yang melewati waktu ini wajib divalidasi ulang.
  final DateTime expiresAt;

  const ResidentSession({
    required this.participantId,
    required this.rtId,
    required this.rtCommunity,
    required this.token,
    required this.expiresAt,
  });

  /// `true` jika sesi sudah kedaluwarsa pada waktu [now].
  bool isExpiredAt(DateTime now) => !now.isBefore(expiresAt);

  @override
  String toString() => 'ResidentSession(participantId=$participantId, rtId=$rtId)';
}