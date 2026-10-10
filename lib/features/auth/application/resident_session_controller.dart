import 'dart:convert';
import 'dart:math';

import 'resident_session.dart';
import 'resident_session_boundary.dart';
import 'resident_session_vault.dart';

/// Mengelola sesi warga tanpa mengekspos token ke lapisan presentasi.
final class ResidentSessionController {
  ResidentSessionController({
    required this.boundary,
    required this.vault,
    String Function()? requestIdFactory,
  }) : _requestIdFactory = requestIdFactory ?? _newRequestId;

  final ResidentSessionBoundary boundary;
  final ResidentSessionVault vault;
  final String Function() _requestIdFactory;

  Future<ResidentSession> createSession({
    required String joinCode,
    required String nickname,
  }) async {
    var requestId = await vault.readPendingEnrollmentId();
    if (requestId == null || requestId.isEmpty) {
      requestId = _requestIdFactory();
      await vault.writePendingEnrollmentId(requestId);
    }

    late final ResidentSessionGrant grant;
    try {
      grant = await boundary.createSession(
        joinCode: joinCode,
        nickname: nickname,
        requestId: requestId,
      );
    } on ResidentSessionEnrollmentRejectedException {
      await vault.clearPendingEnrollmentId();
      rethrow;
    }

    try {
      await vault.write(grant.sessionToken);
    } catch (_) {
      try {
        await boundary.revokeSession(grant.sessionToken);
      } catch (_) {
        // Backend expiry remains the final guard if remote revocation is offline.
      }
      rethrow;
    }
    try {
      await vault.clearPendingEnrollmentId();
    } catch (_) {
      // A stale id only rotates the same resident's token on a later retry.
    }
    return grant.session;
  }

  /// A cached token alone does not authorize network reads; the backend validates it.
  Future<ResidentSession?> restoreSession() async {
    final token = await vault.read();
    if (token == null || token.isEmpty) return null;
    try {
      return await boundary.validateSession(token);
    } on ResidentSessionInvalidException {
      await vault.clear();
      return null;
    }
  }

  /// Local access is removed before best-effort remote revocation.
  Future<void> signOut() async {
    final token = await vault.read();
    await vault.clear();
    try {
      await vault.clearPendingEnrollmentId();
    } catch (_) {
      // The request id is not an authorization token.
    }
    if (token == null || token.isEmpty) return;
    try {
      await boundary.revokeSession(token);
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
