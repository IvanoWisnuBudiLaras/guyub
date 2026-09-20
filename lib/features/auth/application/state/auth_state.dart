import '../entities/operator_profile.dart';
import '../entities/resident_session.dart';

/// Status tingkat tinggi siklus hidup sesi pada fitur Auth.
///
/// Digunakan presentation layer untuk menentukan layar yang ditampilkan tanpa
/// perlu menebak-nebak dari kombinasi field lain.
enum AuthStatus {
  /// Kondisi belum diketahui — aplikasi masih memulihkan sesi tersimpan.
  unknown,

  /// Belum ada sesi. Pengguna harus memilih peran di SCR-02.
  unauthenticated,

  /// Operator formal sudah terautentikasi (Ketua RT/RW atau Pendamping RT).
  operatorAuthenticated,

  /// Warga memiliki sesi peserta yang sah (tanpa akun formal).
  residentAuthenticated,
}

/// State immutable untuk fitur Auth.
///
/// **Aturan lapisan:** state ini adalah satu-satunya sumber kebenaran bagi
/// presentation layer. Widget tidak boleh membaca boundary atau melakukan
/// validasi otorisasi sendiri; semua keputusan mengalir dari controller.
final class AuthState {
  /// Status siklus hidup sesi saat ini.
  final AuthStatus status;

  /// Profil operator aktif, tersedia hanya saat status operator terautentikasi.
  final OperatorProfile? operator;

  /// Sesi peserta aktif, tersedia hanya saat status warga terautentikasi.
  final ResidentSession? residentSession;

  /// Menandakan sedang ada operasi async berjalan (login/join/restore).
  final bool isBusy;

  /// Pesan kesalahan ramah pengguna dalam Bahasa Indonesia, bila ada.
  final String? errorMessage;

  const AuthState._({
    required this.status,
    this.operator,
    this.residentSession,
    this.isBusy = false,
    this.errorMessage,
  });

  /// State awal sebelum pemulihan sesi dijalankan.
  static const AuthState initial = AuthState._(status: AuthStatus.unknown);

  /// State tanpa sesi, siap menampilkan pemilihan peran.
  static const AuthState unauthenticated = AuthState._(
    status: AuthStatus.unauthenticated,
  );

  /// State operator formal yang sudah terautentikasi.
  factory AuthState.forOperator(OperatorProfile profile) => AuthState._(
    status: AuthStatus.operatorAuthenticated,
    operator: profile,
  );

  /// State warga dengan sesi peserta yang sah.
  factory AuthState.forResident(ResidentSession session) => AuthState._(
    status: AuthStatus.residentAuthenticated,
    residentSession: session,
  );

  /// `true` jika tidak ada sesi aktif dan UI boleh menampilkan pilihan peran.
  bool get showRoleSelection => status == AuthStatus.unauthenticated;

  /// `true` jika peran yang aktif adalah operator formal.
  bool get isOperatorSession => status == AuthStatus.operatorAuthenticated;

  /// `true` jika peran yang aktif adalah warga.
  bool get isResidentSession => status == AuthStatus.residentAuthenticated;

  /// Menyalin state dengan perubahan sebagian, menjaga immutability.
  AuthState copyWith({
    AuthStatus? status,
    OperatorProfile? operator,
    ResidentSession? residentSession,
    bool? isBusy,
    String? errorMessage,
    bool clearError = false,
    bool clearOperator = false,
    bool clearResidentSession = false,
  }) {
    return AuthState._(
      status: status ?? this.status,
      operator: clearOperator ? null : (operator ?? this.operator),
      residentSession: clearResidentSession
          ? null
          : (residentSession ?? this.residentSession),
      isBusy: isBusy ?? this.isBusy,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }

  @override
  String toString() =>
      'AuthState(status=${status.name}, isBusy=$isBusy, hasError=${errorMessage != null})';
}