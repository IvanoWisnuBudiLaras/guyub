// ignore_for_file: prefer_initializing_formals

import 'dart:convert';
import 'dart:math';

import 'resident_session.dart';
import 'resident_session_boundary.dart';
import 'resident_session_vault.dart';

/// Mengelola sesi warga tanpa mengekspos token ke lapisan presentasi.
final class ResidentSessionController {
  ResidentSessionController({
    required ResidentSessionBoundary boundary,
    required ResidentSessionVault vault,
    String Function()? requestIdFactory,
  }) : _boundary = boundary,
       _vault = vault,
       _requestIdFactory = requestIdFactory ?? _newRequestId;

  final ResidentSessionBoundary _boundary;
  final ResidentSessionVault _vault;
  final String Function() _requestIdFactory;

  Future<ResidentSession> createSession({
    required String joinCode,
    required String nickname,
  }) async {
    var requestId = await _vault.readPendingEnrollmentId();
    if (requestId == null || requestId.isEmpty) {
      requestId = _requestIdFactory();
      await _vault.writePendingEnrollmentId(requestId);
    }

    late final ResidentSessionGrant grant;
    try {
      grant = await _boundary.createSession(
        joinCode: joinCode,
        nickname: nickname,
        requestId: requestId,
      );
    } on ResidentSessionEnrollmentRejectedException {
      await _vault.clearPendingEnrollmentId();
      rethrow;
    }

    try {
      await _vault.write(grant.sessionToken);
    } catch (_) {
      try {
        await _boundary.revokeSession(grant.sessionToken);
      } catch (_) {
        // Backend expiry remains the final guard if remote revocation is offline.
      }
      rethrow;
    }
    try {
      await _vault.clearPendingEnrollmentId();
    } catch (_) {
      // A stale id only rotates the same resident's token on a later retry.
    }
    return grant.session;
  }

  /// A cached token alone does not authorize network reads; the backend validates it.
  Future<ResidentSession?> restoreSession() async {
    final token = await _vault.read();
    if (token == null || token.isEmpty) return null;
    try {
      return await _boundary.validateSession(token);
    } on ResidentSessionInvalidException {
      await _vault.clear();
      return null;
    }
  }

  /// Local access is removed before best-effort remote revocation.
  Future<void> signOut() async {
    final token = await _vault.read();
    await _vault.clear();
    try {
      await _vault.clearPendingEnrollmentId();
    } catch (_) {
      // The request id is not an authorization token.
    }
    if (token == null || token.isEmpty) return;
    try {
      await _boundary.revokeSession(token);
    } catch (_) {
      // The server-side expiry bounds any still-valid token.
    }
  }

  static String _newRequestId() {
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    return base64Url.encode(bytes).replaceAll('=', '');
  }
}
