import '../../domain/models/app_session.dart';
import '../../domain/repositories/auth_repository.dart';

/// Implementasi sementara. Ketik "salah" di field manapun untuk simulasi
/// login gagal (buat ngetes UI error state).
class FakeAuthRepository implements AuthRepository {
  @override
  Future<AppSession> loginOperator({
    required String email,
    required String password,
  }) async {
    await Future.delayed(const Duration(milliseconds: 600));

    if (password == 'salah') {
      throw const AuthException('Email atau kata sandi salah.');
    }

    return AppSession(
      role: UserRole.operator,
      token: 'fake-operator-token',
      rtId: 'rt-03-rw-07',
      rtName: 'RT 03 / RW 07',
      displayName: 'Pak Hendra',
      expiresAt: DateTime.now().add(const Duration(hours: 1)),
    );
  }

  @override
  Future<AppSession> joinWithRtCode(String rtCode) async {
    await Future.delayed(const Duration(milliseconds: 600));

    if (rtCode.trim().toLowerCase() == 'salah') {
      throw const AuthException('Kode RT tidak valid.');
    }

    return AppSession(
      role: UserRole.resident,
      token: 'fake-participant-token',
      rtId: 'rt-03-rw-07',
      rtName: 'RT 03 / RW 07',
      displayName: 'Pak Joko',
    );
  }

  @override
  Future<void> logout() async {
    await Future.delayed(const Duration(milliseconds: 200));
  }
}
