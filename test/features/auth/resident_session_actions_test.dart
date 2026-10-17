import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guyub/core/config/app_config.dart';
import 'package:guyub/core/result/app_error.dart';
import 'package:guyub/core/result/result.dart';
import 'package:guyub/core/theme/app_theme.dart';
import 'package:guyub/features/auth/application/operator_auth_boundary.dart';
import 'package:guyub/features/auth/application/operator_profile.dart';
import 'package:guyub/features/auth/application/resident_session.dart';
import 'package:guyub/features/auth/application/resident_session_boundary.dart';
import 'package:guyub/features/auth/application/resident_session_controller.dart';
import 'package:guyub/features/auth/application/resident_session_vault.dart';
import 'package:guyub/features/auth/presentation/screens/resident_session_home_screen.dart';
import 'package:guyub/features/auth/presentation/screens/role_selection_screen.dart';

final class _MemoryVault implements ResidentSessionVault {
  String? token = 'saved-opaque-token';

  @override
  Future<String?> read() async => token;

  @override
  Future<void> write(String sessionToken) async {
    token = sessionToken;
  }

  @override
  Future<void> clear() async {
    token = null;
  }

  @override
  Future<String?> readPendingEnrollmentId() async => null;

  @override
  Future<void> writePendingEnrollmentId(String requestId) async {}

  @override
  Future<void> clearPendingEnrollmentId() async {}
}

final class _FakeResidentBoundary implements ResidentSessionBoundary {
  final ResidentSession session = ResidentSession(
    residentId: 'res-1',
    communityId: 'rt-01',
    communityName: 'Kedungwaru',
    rtLabel: 'RT 01',
    nickname: 'Budi',
    expiresAt: DateTime.utc(2026, 12, 31),
  );

  String? deletedToken;
  String? deletedResidentId;

  @override
  Future<ResidentSessionGrant> createSession({
    required String joinCode,
    required String nickname,
    required String requestId,
  }) async => ResidentSessionGrant(
    session: session,
    sessionToken: 'saved-opaque-token',
  );

  @override
  Future<ResidentSession> validateSession(String sessionToken) async => session;

  @override
  Future<void> revokeSession(String sessionToken) async {}

  @override
  Future<void> deleteOwnResidentData({
    required String sessionToken,
    required String residentId,
    required String communityId,
  }) async {
    deletedToken = sessionToken;
    deletedResidentId = residentId;
  }
}

final class _FakeOperatorAuthBoundary implements OperatorAuthBoundary {
  _FakeOperatorAuthBoundary({this.profile});

  final OperatorProfile? profile;
  bool signedOut = false;

  @override
  Future<Result<OperatorProfile>> signIn({
    required String email,
    required String password,
  }) async {
    if (profile != null) return Result.ok(profile!);
    return const Result.err(AuthError(message: 'Failed'));
  }

  @override
  Future<Result<OperatorProfile>> restoreCurrentSession() async {
    if (profile != null) return Result.ok(profile!);
    return const Result.err(AuthError(message: 'No session'));
  }

  @override
  Future<void> signOut() async {
    signedOut = true;
  }
}

void main() {
  setUp(() {
    AppConfig.initialize(AppConfig.test());
  });

  Widget buildApp({required Widget home, Map<String, WidgetBuilder>? routes}) {
    return MaterialApp(theme: AppTheme.light, home: home, routes: routes ?? {});
  }

  testWidgets(
    'Tahap B3.d: Ganti Peran dari Beranda Warga navigasi ke Role Selection tanpa menghapus sesi lokal',
    (tester) async {
      final vault = _MemoryVault();
      final boundary = _FakeResidentBoundary();
      final controller = ResidentSessionController(
        boundary: boundary,
        vault: vault,
      );

      var navigatedToRoot = false;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          initialRoute: '/resident',
          routes: {
            '/resident': (_) => ResidentSessionHomeScreen(
              session: boundary.session,
              controller: controller,
            ),
            '/': (_) {
              navigatedToRoot = true;
              return const Scaffold(body: Text('Role Selection Root'));
            },
          },
        ),
      );
      await tester.pumpAndSettle();

      // Tombol Ganti Peran tersedia di AppBar dan di Body
      expect(find.byKey(const Key('resident-switch-role')), findsOneWidget);
      expect(
        find.byKey(const Key('resident-switch-role-appbar')),
        findsOneWidget,
      );

      // Tap Ganti Peran
      await tester.tap(find.byKey(const Key('resident-switch-role')));
      await tester.pumpAndSettle();

      // Memastikan navigasi ke root berhasil TANPA menghapus token sesi lokal
      expect(navigatedToRoot, isTrue);
      expect(vault.token, 'saved-opaque-token');
    },
  );

  testWidgets(
    'Tahap B3.e: Role Selection menampilkan kartu Lanjutkan sebagai... bila ada sesi warga tersimpan',
    (tester) async {
      final vault = _MemoryVault();
      final boundary = _FakeResidentBoundary();
      final controller = ResidentSessionController(
        boundary: boundary,
        vault: vault,
      );

      var resumedResidentHome = false;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          routes: {
            '/': (_) =>
                RoleSelectionScreen(residentSessionController: controller),
            '/resident/home': (context) {
              resumedResidentHome = true;
              final arg = ModalRoute.of(context)?.settings.arguments;
              return Scaffold(
                body: Text('Home Warga: ${(arg as ResidentSession).nickname}'),
              );
            },
          },
        ),
      );
      await tester.pumpAndSettle();

      // Kartu Lanjutkan sebagai warga muncul
      expect(find.byKey(const Key('resume-resident-session')), findsOneWidget);
      expect(find.text('Lanjutkan sebagai Budi (RT 01)'), findsOneWidget);

      // Tap kartu untuk melanjutkan sesi
      await tester.tap(find.byKey(const Key('resume-resident-session')));
      await tester.pumpAndSettle();

      expect(resumedResidentHome, isTrue);
      expect(find.text('Home Warga: Budi'), findsOneWidget);
    },
  );

  testWidgets(
    'Tahap B3.e: Role Selection menampilkan kartu Lanjutkan sebagai... bila ada sesi operator tersimpan',
    (tester) async {
      final operatorProfile = OperatorProfile(
        uid: 'op-1',
        communityId: 'rt-01-demo',
        role: OperatorRole.ketuaRtRw,
        displayName: 'Pak Joko',
      );
      final operatorAuth = _FakeOperatorAuthBoundary(profile: operatorProfile);

      var resumedOperatorHome = false;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          routes: {
            '/': (_) => RoleSelectionScreen(operatorAuthBoundary: operatorAuth),
            '/operator/home': (context) {
              resumedOperatorHome = true;
              final arg = ModalRoute.of(context)?.settings.arguments;
              return Scaffold(
                body: Text(
                  'Home Operator: ${(arg as OperatorProfile).displayName}',
                ),
              );
            },
          },
        ),
      );
      await tester.pumpAndSettle();

      // Kartu Lanjutkan sebagai operator muncul
      expect(find.byKey(const Key('resume-operator-session')), findsOneWidget);
      expect(find.textContaining('Lanjutkan sebagai Pak Joko'), findsOneWidget);

      // Tap kartu untuk melanjutkan sesi operator
      await tester.tap(find.byKey(const Key('resume-operator-session')));
      await tester.pumpAndSettle();

      expect(resumedOperatorHome, isTrue);
      expect(find.text('Home Operator: Pak Joko'), findsOneWidget);
    },
  );

  testWidgets(
    'Tahap B3.e: Role Selection tidak menampilkan kartu Lanjutkan bila tidak ada sesi tersimpan',
    (tester) async {
      final vault = _MemoryVault()..token = null;
      final boundary = _FakeResidentBoundary();
      final controller = ResidentSessionController(
        boundary: boundary,
        vault: vault,
      );
      final operatorAuth = _FakeOperatorAuthBoundary(profile: null);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: RoleSelectionScreen(
            residentSessionController: controller,
            operatorAuthBoundary: operatorAuth,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('resume-resident-session')), findsNothing);
      expect(find.byKey(const Key('resume-operator-session')), findsNothing);
    },
  );

  testWidgets(
    'Tahap B3.f: Dialog Keluar menampilkan peringatan jelas dan dapat dibatalkan',
    (tester) async {
      final vault = _MemoryVault();
      final boundary = _FakeResidentBoundary();
      final controller = ResidentSessionController(
        boundary: boundary,
        vault: vault,
      );

      await tester.pumpWidget(
        buildApp(
          home: ResidentSessionHomeScreen(
            session: boundary.session,
            controller: controller,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap tombol Keluar dari sesi ini
      await tester.tap(find.byKey(const Key('resident-sign-out-button')));
      await tester.pumpAndSettle();

      // Dialog peringatan muncul
      expect(find.text('Keluar dari sesi ini?'), findsOneWidget);
      expect(
        find.textContaining(
          'Jika keluar lalu masuk lagi, kamu dianggap warga baru dan '
          'riwayat tugas di perangkat ini tidak terbawa. '
          'Pakai Ganti Peran bila hanya ingin pindah peran.',
        ),
        findsOneWidget,
      );

      // Batal
      await tester.tap(find.text('Batal'));
      await tester.pumpAndSettle();

      // Sesi masih tersimpan
      expect(vault.token, 'saved-opaque-token');
      expect(find.text('Keluar dari sesi ini?'), findsNothing);
    },
  );

  testWidgets(
    'Tahap B3.f: Konfirmasi Keluar menghapus sesi lokal dan kembali ke Role Selection',
    (tester) async {
      final vault = _MemoryVault();
      final boundary = _FakeResidentBoundary();
      final controller = ResidentSessionController(
        boundary: boundary,
        vault: vault,
      );

      var navigatedToRoot = false;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          initialRoute: '/resident',
          routes: {
            '/resident': (_) => ResidentSessionHomeScreen(
              session: boundary.session,
              controller: controller,
            ),
            '/': (_) {
              navigatedToRoot = true;
              return const Scaffold(body: Text('Root Role Selection'));
            },
          },
        ),
      );
      await tester.pumpAndSettle();

      // Tap Keluar di AppBar
      await tester.tap(find.byKey(const Key('resident-sign-out')));
      await tester.pumpAndSettle();

      expect(find.text('Keluar dari sesi ini?'), findsOneWidget);

      // Konfirmasi Keluar
      await tester.tap(find.byKey(const Key('resident-sign-out-confirm')));
      await tester.pumpAndSettle();

      // Token dihapus dan kembali ke root
      expect(vault.token, isNull);
      expect(navigatedToRoot, isTrue);
    },
  );

  testWidgets(
    'Tahap B3.g: Hapus Data Saya berada di paling bawah dengan gaya destruktif dan butuh konfirmasi',
    (tester) async {
      final vault = _MemoryVault();
      final boundary = _FakeResidentBoundary();
      final controller = ResidentSessionController(
        boundary: boundary,
        vault: vault,
      );

      await tester.pumpWidget(
        buildApp(
          home: ResidentSessionHomeScreen(
            session: boundary.session,
            controller: controller,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Urutan tombol di UI: Ganti Peran, Keluar, lalu Hapus Data Saya
      final switchRoleY = tester
          .getTopLeft(find.byKey(const Key('resident-switch-role')))
          .dy;
      final signOutY = tester
          .getTopLeft(find.byKey(const Key('resident-sign-out-button')))
          .dy;
      final deleteDataY = tester
          .getTopLeft(find.byKey(const Key('resident-delete-data')))
          .dy;

      expect(switchRoleY < signOutY, isTrue);
      expect(signOutY < deleteDataY, isTrue);

      // Tap Hapus Data Saya
      await tester.tap(find.byKey(const Key('resident-delete-data')));
      await tester.pumpAndSettle();

      // Dialog konfirmasi terpisah untuk Hapus Data
      expect(find.text('Hapus data warga?'), findsOneWidget);
      expect(boundary.deletedResidentId, isNull);

      // Batal
      await tester.tap(find.text('Batal'));
      await tester.pumpAndSettle();

      expect(boundary.deletedResidentId, isNull);
      expect(vault.token, 'saved-opaque-token');
    },
  );
}
