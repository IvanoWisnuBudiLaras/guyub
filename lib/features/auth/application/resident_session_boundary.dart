import 'resident_session.dart';

/// Kontrak akses sesi warga yang ditegakkan oleh backend.
abstract interface class ResidentSessionBoundary {
  Future<ResidentSessionGrant> createSession({
    required String joinCode,
    required String nickname,
    required String requestId,
  });

  Future<ResidentSession> validateSession(String sessionToken);

  Future<void> revokeSession(String sessionToken);
}

/// The backend rejected a missing, revoked, or expired participant token.
final class ResidentSessionInvalidException implements Exception {
  const ResidentSessionInvalidException();
}

/// The backend could not be reached; a secure local snapshot may be used read-only.
final class ResidentSessionUnavailableException implements Exception {
  const ResidentSessionUnavailableException();
}

/// A permanent rejection of this enrollment attempt; a fresh attempt gets a new id.
final class ResidentSessionEnrollmentRejectedException implements Exception {
  const ResidentSessionEnrollmentRejectedException();
}
