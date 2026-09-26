// DEV ONLY — hapus sebelum merge
import '../core/result/app_error.dart';
import '../core/result/result.dart';
import '../features/auth/application/auth_controller.dart';
import '../features/auth/application/boundaries/operator_auth_boundary.dart';
import '../features/auth/application/boundaries/resident_session_boundary.dart';
import '../features/auth/application/entities/operator_profile.dart';
import '../features/auth/application/entities/resident_session.dart';
import '../features/auth/application/entities/rt_community.dart';
import '../features/auth/application/entities/user_role.dart';

final class FakeOperatorAuthBoundary implements OperatorAuthBoundary {
  OperatorProfile? _current;

  @override
  Future<Result<OperatorProfile>> signInWithEmailPassword({
    required String email,
    required String password,
  }) async {
    await Future.delayed(const Duration(milliseconds: 300));
    if (password == 'salah') {
      return const Result.err(
        AuthError(
          message: 'Email atau kata sandi tidak sesuai.',
        ),
      );
    }

    final profile = OperatorProfile(
      uid: 'op_dev_123',
      rtId: 'rt_03_rw_07',
      role: UserRole.ketuaRtRw,
      displayName: 'Bpk. Budi (Ketua RT)',
      active: true,
    );
    _current = profile;
    return Result.ok(profile);
  }

  @override
  Future<Result<void>> signOut() async {
    _current = null;
    return const Result.ok(null);
  }

  @override
  Future<Result<OperatorProfile?>> currentOperator() async {
    return Result.ok(_current);
  }
}

final class FakeResidentSessionBoundary implements ResidentSessionBoundary {
  ResidentSession? _current;

  @override
  Future<Result<ResidentSession>> joinWithCode(String joinCode) async {
    await Future.delayed(const Duration(milliseconds: 300));
    if (joinCode.toUpperCase().contains('SALAH')) {
      return const Result.err(
        ValidationError(
          message: 'Kode RT tidak valid atau sudah kedaluwarsa.',
        ),
      );
    }

    final session = ResidentSession(
      participantId: 'resident_dev_456',
      rtId: 'rt_03_rw_07',
      rtCommunity: const RtCommunity(
        id: 'rt_03_rw_07',
        kelurahanName: 'Kampung Melayu',
        rtLabel: 'RT 03',
        rwLabel: 'RW 07',
        displayName: 'RT 03 / RW 07 Kampung Melayu',
      ),
      token: 'dev_opaque_token_abc123',
      expiresAt: DateTime.now().add(const Duration(days: 30)),
    );
    _current = session;
    return Result.ok(session);
  }

  @override
  Future<Result<ResidentSession?>> restoreSession() async {
    return Result.ok(_current);
  }

  @override
  Future<Result<void>> clearSession() async {
    _current = null;
    return const Result.ok(null);
  }
}

/// Membuat instans [AuthController] asli Hysan dengan adapter in-memory dev-only.
AuthController createDevAuthController() {
  return AuthController(
    operatorAuth: FakeOperatorAuthBoundary(),
    residentSession: FakeResidentSessionBoundary(),
  );
}
