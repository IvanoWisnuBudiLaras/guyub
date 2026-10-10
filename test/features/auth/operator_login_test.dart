import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guyub/core/result/app_error.dart';
import 'package:guyub/core/result/result.dart';
import 'package:guyub/features/auth/application/operator_auth_boundary.dart';
import 'package:guyub/features/auth/application/operator_profile.dart';
import 'package:guyub/features/auth/presentation/screens/operator_login_screen.dart';

void main() {
  testWidgets(
    'operator sign-in keeps the password masked and opens scoped home',
    (WidgetTester tester) async {
      final boundary = _FakeOperatorAuthBoundary(
        signInResult: Result.ok(
          OperatorProfile(
            uid: 'operator-1',
            communityId: 'rt-01',
            role: OperatorRole.pendampingRt,
            displayName: 'Pendamping',
          ),
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: OperatorLoginScreen(
            authBoundary: boundary,
            onAuthenticated: (profile) =>
                Navigator.of(tester.element(find.byType(OperatorLoginScreen)))
                    .push(
                      MaterialPageRoute<void>(
                        builder: (_) => Text(profile.communityId),
                      ),
                    ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final passwordField = tester.widget<TextField>(
        find.descendant(
          of: find.byKey(const Key('operator-password')),
          matching: find.byType(TextField),
        ),
      );
      expect(passwordField.obscureText, isTrue);
      await tester.enterText(
        find.byKey(const Key('operator-email')),
        'operator@example.test',
      );
      await tester.enterText(
        find.byKey(const Key('operator-password')),
        'secret',
      );
      await tester.tap(find.text('Masuk'));
      await tester.pumpAndSettle();

      expect(boundary.lastEmail, 'operator@example.test');
      expect(find.text('rt-01'), findsOneWidget);
    },
  );

  testWidgets('operator sign-in displays a generic boundary error', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: OperatorLoginScreen(
          authBoundary: _FakeOperatorAuthBoundary(
            signInResult: const Result.err(
              AuthError(message: 'Tidak dapat masuk. Periksa akses operator.'),
            ),
          ),
          onAuthenticated: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('operator-email')),
      'bad@example.test',
    );
    await tester.enterText(find.byKey(const Key('operator-password')), 'wrong');
    await tester.tap(find.text('Masuk'));
    await tester.pumpAndSettle();

    expect(
      find.text('Tidak dapat masuk. Periksa akses operator.'),
      findsOneWidget,
    );
    expect(find.text('bad@example.test'), findsOneWidget);
    final passwordField = tester.widget<TextField>(
      find.descendant(
        of: find.byKey(const Key('operator-password')),
        matching: find.byType(TextField),
      ),
    );
    expect(passwordField.obscureText, isTrue);
  });
}

final class _FakeOperatorAuthBoundary implements OperatorAuthBoundary {
  _FakeOperatorAuthBoundary({required this.signInResult});

  final Result<OperatorProfile> signInResult;
  String? lastEmail;

  @override
  Future<Result<OperatorProfile>> signIn({
    required String email,
    required String password,
  }) async {
    lastEmail = email;
    return signInResult;
  }

  @override
  Future<Result<OperatorProfile>> restoreCurrentSession() async =>
      const Result.err(AuthError());

  @override
  Future<void> signOut() async {}
}
