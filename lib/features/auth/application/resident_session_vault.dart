import 'resident_session.dart';

/// Secure local storage for the resident bearer token and pending enrollment ID.
abstract interface class ResidentSessionVault {
  Future<void> write(String sessionToken);
  Future<String?> read();
  Future<void> clear();
  Future<void> writePendingEnrollmentId(String requestId);
  Future<String?> readPendingEnrollmentId();
  Future<void> clearPendingEnrollmentId();
}

/// Optional secure storage for a minimal display-only profile snapshot.
/// The snapshot is never used as server authorization.
abstract interface class ResidentSessionMetadataVault {
  Future<void> writeCachedSession(ResidentSession session);
  Future<ResidentSession?> readCachedSession();
  Future<void> clearCachedSession();
}
