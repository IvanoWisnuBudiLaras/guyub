import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guyub/app/app.dart';
import 'package:guyub/core/config/app_config.dart';
import 'package:guyub/features/auth/application/resident_session.dart';
import 'package:guyub/features/auth/application/resident_session_boundary.dart';
import 'package:guyub/features/auth/application/resident_session_controller.dart';
import 'package:guyub/features/auth/application/resident_session_vault.dart';

void main() {
  setUp(() => AppConfig.resetForTesting());

  testWidgets(
    'resident can enter a scoped session from the resident role path',
    (tester) async {
      final controller = ResidentSessionController(
        boundary: FakeResidentBoundary(),
        vault: MemoryResidentSessionVault(),
      );
      AppConfig.initialize(AppConfig.test());
      await tester.pumpWidget(GuyubApp(residentSessionController: controller));

      await tester.tap(find.text('Saya Warga'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('resident-join-code')), findsOneWidget);
      expect(find.byKey(const Key('resident-nickname')), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('resident-join-code')),
        'ABCD2345EFGH',
      );
      await tester.enterText(
        find.byKey(const Key('resident-nickname')),
        'Rani',
      );
      await tester.tap(find.byKey(const Key('resident-join-submit')));
      await tester.pumpAndSettle();

      expect(find.text('Warga • RT 01'), findsOneWidget);
      expect(find.text('Komunitas Uji'), findsOneWidget);
      expect(find.text('Halo, Rani'), findsOneWidget);
      expect(find.textContaining('token'), findsNothing);
    },
  );

  testWidgets('restores an existing session instead of creating a duplicate', (
    tester,
  ) async {
    final vault = MemoryResidentSessionVault()..token = 'saved-opaque-token';
    final controller = ResidentSessionController(
      boundary: FakeResidentBoundary(),
      vault: vault,
    );
    AppConfig.initialize(AppConfig.test());
    await tester.pumpWidget(GuyubApp(residentSessionController: controller));
    await tester.tap(find.text('Saya Warga'));
    await tester.pumpAndSettle();

    expect(find.text('Warga • RT 01'), findsOneWidget);
    expect(find.byKey(const Key('resident-join-submit')), findsNothing);
  });

  testWidgets(
    'keeps a saved token when session validation is temporarily offline',
    (tester) async {
      final vault = MemoryResidentSessionVault()..token = 'saved-opaque-token';
      final controller = ResidentSessionController(
        boundary: FakeResidentBoundary()..failValidationTemporarily = true,
        vault: vault,
      );
      AppConfig.initialize(AppConfig.test());
      await tester.pumpWidget(GuyubApp(residentSessionController: controller));
      await tester.tap(find.text('Saya Warga'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Sesi tersimpan belum dapat diverifikasi'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('resident-join-submit')), findsNothing);
      expect(vault.token, 'saved-opaque-token');
    },
  );

  testWidgets('invalid join code shows generic message and no RT identity', (
    tester,
  ) async {
    final controller = ResidentSessionController(
      boundary: FakeResidentBoundary()..failCreate = true,
      vault: MemoryResidentSessionVault(),
    );
    AppConfig.initialize(AppConfig.test());
    await tester.pumpWidget(GuyubApp(residentSessionController: controller));
    await tester.tap(find.text('Saya Warga'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('resident-join-code')),
      'WRONGCODE',
    );
    await tester.enterText(find.byKey(const Key('resident-nickname')), 'Rani');
    await tester.tap(find.byKey(const Key('resident-join-submit')));
    await tester.pumpAndSettle();

    expect(find.textContaining('Kode RT tidak valid'), findsOneWidget);
    expect(find.text('Komunitas Uji'), findsNothing);
    expect(find.text('RT 01'), findsNothing);
  });
}

final class MemoryResidentSessionVault implements ResidentSessionVault {
  String? token;
  String? pendingRequestId;

  @override
  Future<void> clear() async => token = null;

  @override
  Future<void> clearPendingEnrollmentId() async => pendingRequestId = null;

  @override
  Future<String?> read() async => token;

  @override
  Future<String?> readPendingEnrollmentId() async => pendingRequestId;

  @override
  Future<void> write(String sessionToken) async => token = sessionToken;

  @override
  Future<void> writePendingEnrollmentId(String requestId) async =>
      pendingRequestId = requestId;
}

final class FakeResidentBoundary implements ResidentSessionBoundary {
  bool failCreate = false;
  bool failValidationTemporarily = false;

  ResidentSession get session => ResidentSession(
    residentId: 'resident-a',
    communityId: 'rt-a',
    communityName: 'Komunitas Uji',
    rtLabel: 'RT 01',
    nickname: 'Rani',
    expiresAt: DateTime.utc(2026, 10, 11),
  );

  @override
  Future<ResidentSessionGrant> createSession({
    required String joinCode,
    required String nickname,
    required String requestId,
  }) async {
    if (failCreate) throw StateError('generic error');
    return ResidentSessionGrant(
      session: session,
      sessionToken: 'opaque-token-not-for-ui',
    );
  }

  @override
  Future<ResidentSession> validateSession(String sessionToken) async {
    if (failValidationTemporarily) throw StateError('offline');
    return session;
  }

  @override
  Future<void> revokeSession(String sessionToken) async {}
}
