import 'package:flutter_test/flutter_test.dart';
import 'package:guyub/app/app.dart';
import 'package:guyub/core/config/app_config.dart';
import 'package:guyub/features/auth/presentation/screens/role_selection_screen.dart';
import 'package:guyub/features/auth/presentation/screens/splash_screen.dart';

void main() {
  setUp(() {
    AppConfig.resetForTesting();
  });

  group('GuyubApp & Phase 1 Presentation Widget Tests', () {
    testWidgets(
      'GuyubApp dapat di-pump tanpa crash, menampilkan SplashScreen',
      (WidgetTester tester) async {
        AppConfig.initialize(AppConfig.test());

        await tester.pumpWidget(const GuyubApp());

        expect(find.byType(SplashScreen), findsOneWidget);
        expect(find.text('GUYUB.ID'), findsOneWidget);

        // Allow microtasks (initialize async completion)
        await tester.pump();
        // Advance timer for splash 1s delay
        await tester.pump(const Duration(seconds: 2));
        await tester.pumpAndSettle();

        // Navigasi setelah splash ke RoleSelectionScreen
        expect(find.byType(RoleSelectionScreen), findsOneWidget);
        expect(find.text('Masuk sebagai\nsiapa Anda?'), findsOneWidget);
        expect(find.text('Saya Ketua RT/RW'), findsOneWidget);
        expect(find.text('Saya Warga'), findsOneWidget);
      },
    );
  });
}
