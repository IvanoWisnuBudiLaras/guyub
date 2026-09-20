import 'user_role.dart';

/// Profil operator formal (Ketua RT/RW atau Pendamping RT) yang terhubung ke
/// Firebase Authentication dan terdaftar pada satu komunitas RT.
///
/// Profil ini **hanya** menyimpan data minimal yang diperlukan untuk
/// otorisasi dan tampilan, tanpa NIK/alamat/GPS (INV-06).
final class OperatorProfile {
  /// Firebase Auth UID pemilik akun.
  final String uid;

  /// Identitas RT tempat operator bernaung — batas otorisasi utama.
  final String rtId;

  /// Peran operator (harus [UserRole.isOperator]).
  final UserRole role;

  /// Nama tampilan operator untuk ditampilkan di UI (bukan nama legal lengkap).
  final String displayName;

  /// Menandakan akun masih aktif dan boleh beroperasi.
  final bool active;

  OperatorProfile({
    required this.uid,
    required this.rtId,
    required this.role,
    required this.displayName,
    required this.active,
  }) : assert(
         role.isOperator,
         'OperatorProfile hanya boleh digunakan untuk peran operator formal.',
       );

  /// Salinan profil dengan perubahan sebagian, menjaga immutability.
  OperatorProfile copyWith({
    String? uid,
    String? rtId,
    UserRole? role,
    String? displayName,
    bool? active,
  }) {
    return OperatorProfile(
      uid: uid ?? this.uid,
      rtId: rtId ?? this.rtId,
      role: role ?? this.role,
      displayName: displayName ?? this.displayName,
      active: active ?? this.active,
    );
  }

  @override
  String toString() => 'OperatorProfile($uid, role=${role.name})';
}