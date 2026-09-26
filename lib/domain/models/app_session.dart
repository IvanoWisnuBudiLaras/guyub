enum UserRole { operator, resident }

/// Session hasil login/join, disimpan lokal secara scoped (bukan akun penuh
/// untuk resident — sesuai PRD §5/§13: resident pakai token opaque per-RT,
/// bukan akun formal).
///
/// PENTING: jangan tambahkan field PII di sini (NIK, alamat lengkap, GPS presisi)
/// — lihat AT-009 di TEST_ACCEPTANCE_MATRIX.md.
class AppSession {
  const AppSession({
    required this.role,
    required this.token,
    required this.rtId,
    required this.rtName,
    required this.displayName,
    this.expiresAt,
  });

  final UserRole role;
  final String token; // Firebase idToken (operator) ATAU participant token (resident)
  final String rtId;
  final String rtName;
  final String displayName;
  final DateTime? expiresAt;

  Map<String, dynamic> toJson() => {
        'role': role.name,
        'token': token,
        'rtId': rtId,
        'rtName': rtName,
        'displayName': displayName,
        'expiresAt': expiresAt?.toIso8601String(),
      };

  factory AppSession.fromJson(Map<String, dynamic> json) => AppSession(
        role: UserRole.values.byName(json['role'] as String),
        token: json['token'] as String,
        rtId: json['rtId'] as String,
        rtName: json['rtName'] as String,
        displayName: json['displayName'] as String,
        expiresAt: json['expiresAt'] == null
            ? null
            : DateTime.parse(json['expiresAt'] as String),
      );
}

/// Dilempar saat login/join gagal — pesan sudah dalam Bahasa Indonesia
/// dan aman ditampilkan langsung ke user (tidak bocorin detail internal,
/// sesuai S-05: RT code enumeration harus generic failure).
class AuthException implements Exception {
  const AuthException(this.message);
  final String message;
}
