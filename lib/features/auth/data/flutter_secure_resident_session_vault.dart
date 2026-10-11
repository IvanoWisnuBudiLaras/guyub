import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../application/resident_session.dart';
import '../application/resident_session_vault.dart';

/// Uses platform secure storage for the bearer token and a retry-only request id.
final class FlutterSecureResidentSessionVault
    implements ResidentSessionVault, ResidentSessionMetadataVault {
  FlutterSecureResidentSessionVault({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const _key = 'guyub.resident.session-token.v1';
  static const _pendingRequestKey = 'guyub.resident.enrollment-request.v1';
  static const _cachedSessionKey = 'guyub.resident.session-snapshot.v1';
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

  @override
  Future<void> writeCachedSession(ResidentSession session) async {
    await _storage.write(
      key: _cachedSessionKey,
      value: jsonEncode({
        'residentId': session.residentId,
        'communityId': session.communityId,
        'communityName': session.communityName,
        'rtLabel': session.rtLabel,
        'nickname': session.nickname,
        'expiresAt': session.expiresAt.toUtc().toIso8601String(),
      }),
    );
  }

  @override
  Future<ResidentSession?> readCachedSession() async {
    final encoded = await _storage.read(key: _cachedSessionKey);
    if (encoded == null) return null;
    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! Map<String, dynamic>) return null;
      final residentId = decoded['residentId'];
      final communityId = decoded['communityId'];
      final communityName = decoded['communityName'];
      final rtLabel = decoded['rtLabel'];
      final nickname = decoded['nickname'];
      final expiresAt = decoded['expiresAt'];
      if ([
            residentId,
            communityId,
            communityName,
            rtLabel,
            nickname,
          ].any((value) => value is! String || value.trim().isEmpty) ||
          expiresAt is! String) {
        return null;
      }
      final parsedExpiry = DateTime.tryParse(expiresAt);
      if (parsedExpiry == null) return null;
      return ResidentSession(
        residentId: residentId as String,
        communityId: communityId as String,
        communityName: communityName as String,
        rtLabel: rtLabel as String,
        nickname: nickname as String,
        expiresAt: parsedExpiry.toUtc(),
        isOfflineSnapshot: true,
      );
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }

  @override
  Future<void> clearCachedSession() => _storage.delete(key: _cachedSessionKey);
}
