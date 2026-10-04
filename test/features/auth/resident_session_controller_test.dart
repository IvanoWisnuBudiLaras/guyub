import 'package:flutter_test/flutter_test.dart';
import 'package:guyub/features/auth/application/resident_session.dart';
import 'package:guyub/features/auth/application/resident_session_boundary.dart';
import 'package:guyub/features/auth/application/resident_session_controller.dart';
import 'package:guyub/features/auth/application/resident_session_vault.dart';

void main() {
  final session = ResidentSession(
    residentId: 'resident-a',
    communityId: 'rt-a',
    communityName: 'Komunitas Uji',
    rtLabel: 'RT 01',
    nickname: 'Rani',
    expiresAt: DateTime.utc(2026, 10, 11),
  );

  test(
    'stores opaque token in vault and returns no token in session model',
    () async {
      final boundary = FakeResidentBoundary(session);
      final vault = MemoryResidentSessionVault();
      final controller = ResidentSessionController(
        boundary: boundary,
        vault: vault,
        requestIdFactory: () => 'test-enrollment-request-id-000000000000000000',
      );

      final result = await controller.createSession(
        joinCode: 'ABCD2345EFGH',
        nickname: ' Rani ',
      );

      expect(result, session);
      expect(vault.token, 'opaque-token-not-for-ui');
      expect(vault.cachedSession, session);
      expect(boundary.lastJoinCode, 'ABCD2345EFGH');
      expect(boundary.lastNickname, ' Rani ');
      expect(
        boundary.lastRequestId,
        'test-enrollment-request-id-000000000000000000',
      );
      expect(vault.pendingRequestId, isNull);
      expect(result.toString(), isNot(contains('opaque-token')));
    },
  );

  test(
    'retries an ambiguous enrollment with the same secure request id',
    () async {
      final boundary = FakeResidentBoundary(session)
        ..failCreateTemporarily = true;
      final vault = MemoryResidentSessionVault();
      final controller = ResidentSessionController(
        boundary: boundary,
        vault: vault,
        requestIdFactory: () => 'retry-enrollment-request-id-000000000000000',
      );

      await expectLater(
        controller.createSession(joinCode: 'ABCD2345EFGH', nickname: 'Rani'),
        throwsStateError,
      );
      final firstRequestId = vault.pendingRequestId;
      expect(firstRequestId, isNotNull);

      boundary.failCreateTemporarily = false;
      await controller.createSession(
        joinCode: 'ABCD2345EFGH',
        nickname: 'Rani',
      );
      expect(boundary.requestIds, [firstRequestId, firstRequestId]);
      expect(vault.pendingRequestId, isNull);
      expect(vault.token, 'opaque-token-not-for-ui');
    },
  );

  test(
    'restores only after backend validates the saved opaque token',
    () async {
      final boundary = FakeResidentBoundary(session);
      final vault = MemoryResidentSessionVault()..token = 'saved-opaque-token';
      final controller = ResidentSessionController(
        boundary: boundary,
        vault: vault,
      );

      expect(await controller.restoreSession(), session);
      expect(boundary.validatedToken, 'saved-opaque-token');
    },
  );

  test(
    'restores a secure profile snapshot read-only after transport loss',
    () async {
      final boundary = FakeResidentBoundary(session)..failUnavailable = true;
      final vault = MemoryResidentSessionVault()
        ..token = 'saved-opaque-token'
        ..cachedSession = session;
      final controller = ResidentSessionController(
        boundary: boundary,
        vault: vault,
      );

      final restored = await controller.restoreSession();

      expect(restored, session.asOfflineSnapshot());
      expect(restored!.isOfflineSnapshot, isTrue);
      expect(vault.token, 'saved-opaque-token');
    },
  );

  test(
    'clears invalid expired tokens rather than preserving stale access',
    () async {
      final boundary = FakeResidentBoundary(session)..failValidation = true;
      final vault = MemoryResidentSessionVault()..token = 'expired-token';
      final controller = ResidentSessionController(
        boundary: boundary,
        vault: vault,
      );

      expect(await controller.restoreSession(), isNull);
      expect(vault.token, isNull);
    },
  );

  test('a temporary validation failure preserves the opaque token', () async {
    final boundary = FakeResidentBoundary(session)..failTemporarily = true;
    final vault = MemoryResidentSessionVault()..token = 'saved-opaque-token';
    final controller = ResidentSessionController(
      boundary: boundary,
      vault: vault,
    );

    await expectLater(controller.restoreSession(), throwsStateError);
    expect(vault.token, 'saved-opaque-token');
  });

  test(
    'logout clears local access even if remote revocation is unavailable',
    () async {
      final boundary = FakeResidentBoundary(session)..failRevocation = true;
      final vault = MemoryResidentSessionVault()
        ..token = 'saved-opaque-token'
        ..pendingRequestId = 'pending-enrollment-request'
        ..cachedSession = session;
      final controller = ResidentSessionController(
        boundary: boundary,
        vault: vault,
      );

      await controller.signOut();

      expect(vault.token, isNull);
      expect(vault.pendingRequestId, isNull);
      expect(vault.cachedSession, isNull);
      expect(boundary.revokedToken, 'saved-opaque-token');
    },
  );
}

final class MemoryResidentSessionVault
    implements ResidentSessionVault, ResidentSessionMetadataVault {
  String? token;
  String? pendingRequestId;
  ResidentSession? cachedSession;

  @override
  Future<void> clear() async => token = null;

  @override
  Future<void> clearPendingEnrollmentId() async => pendingRequestId = null;

  @override
  Future<String?> read() async => token;

  @override
  Future<String?> readPendingEnrollmentId() async => pendingRequestId;

  @override
  Future<void> write(String value) async => token = value;

  @override
  Future<void> writePendingEnrollmentId(String value) async =>
      pendingRequestId = value;

  @override
  Future<void> writeCachedSession(ResidentSession session) async =>
      cachedSession = session;

  @override
  Future<ResidentSession?> readCachedSession() async => cachedSession;

  @override
  Future<void> clearCachedSession() async => cachedSession = null;
}

final class FakeResidentBoundary implements ResidentSessionBoundary {
  FakeResidentBoundary(this.session);

  final ResidentSession session;
  bool failValidation = false;
  bool failTemporarily = false;
  bool failUnavailable = false;
  bool failRevocation = false;
  bool failCreateTemporarily = false;
  String? lastJoinCode;
  String? lastNickname;
  String? lastRequestId;
  final List<String> requestIds = [];
  String? validatedToken;
  String? revokedToken;

  @override
  Future<ResidentSessionGrant> createSession({
    required String joinCode,
    required String nickname,
    required String requestId,
  }) async {
    lastJoinCode = joinCode;
    lastNickname = nickname;
    lastRequestId = requestId;
    requestIds.add(requestId);
    if (failCreateTemporarily) throw StateError('network unavailable');
    return ResidentSessionGrant(
      session: session,
      sessionToken: 'opaque-token-not-for-ui',
    );
  }

  @override
  Future<ResidentSession> validateSession(String sessionToken) async {
    validatedToken = sessionToken;
    if (failValidation) throw const ResidentSessionInvalidException();
    if (failTemporarily) throw StateError('network unavailable');
    if (failUnavailable) throw const ResidentSessionUnavailableException();
    return session;
  }

  @override
  Future<void> revokeSession(String sessionToken) async {
    revokedToken = sessionToken;
    if (failRevocation) throw StateError('offline');
  }
}
