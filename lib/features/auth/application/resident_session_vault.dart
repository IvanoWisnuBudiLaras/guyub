/// Secure local storage for the resident bearer token and pending enrollment ID.
abstract interface class ResidentSessionVault {
  Future<void> write(String sessionToken);
  Future<String?> read();
  Future<void> clear();
  Future<void> writePendingEnrollmentId(String requestId);
  Future<String?> readPendingEnrollmentId();
  Future<void> clearPendingEnrollmentId();
}
