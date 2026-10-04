import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../application/resident_session_vault.dart';

/// Uses platform secure storage for the bearer token and a retry-only request id.
final class FlutterSecureResidentSessionVault implements ResidentSessionVault {
  FlutterSecureResidentSessionVault({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const _key = 'guyub.resident.session-token.v1';
  static const _pendingRequestKey = 'guyub.resident.enrollment-request.v1';
  final FlutterSecureStorage _storage;

  @override
  Future<void> write(String sessionToken) =>
      _storage.write(key: _key, value: sessionToken);

  @override
  Future<String?> read() => _storage.read(key: _key);

  @override
  Future<void> clear() => _storage.delete(key: _key);

  @override
  Future<void> writePendingEnrollmentId(String requestId) =>
      _storage.write(key: _pendingRequestKey, value: requestId);

  @override
  Future<String?> readPendingEnrollmentId() =>
      _storage.read(key: _pendingRequestKey);

  @override
  Future<void> clearPendingEnrollmentId() =>
      _storage.delete(key: _pendingRequestKey);
}
