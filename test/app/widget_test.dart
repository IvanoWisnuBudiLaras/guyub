import 'package:flutter_test/flutter_test.dart';
import 'package:guyub/app/app.dart';
import 'package:guyub/core/config/app_config.dart';

void main() {
  setUp(() {
    AppConfig.resetForTesting();
  });

  group('GuyubApp & FoundationScreen Baseline Widget Tests', () {
    testWidgets(
      'GuyubApp dapat di-pump tanpa crash, menampilkan judul dan theme Material 3',
      (WidgetTester tester) async {
        AppConfig.initialize(AppConfig.test());

        await tester.pumpWidget(const GuyubApp());

        // Verifikasi MaterialApp dan judul
        expect(find.text('Guyub [TEST]'), findsOneWidget);
        expect(find.text('Guyub.id'), findsOneWidget);
        expect(find.text('Foundation Ready'), findsOneWidget);
        expect(
          find.text('Sistem Kesiapsiagaan Banjir Komunitas RT/RW'),
          findsOneWidget,
        );
        expect(find.text('Environment: TEST'), findsOneWidget);
      },
    );

    testWidgets(
      'FoundationButton dapat menerima interaksi tap dan memicu callback',
      (WidgetTester tester) async {
        AppConfig.initialize(AppConfig.test());

        await tester.pumpWidget(const GuyubApp());

        // Verifikasi state awal tombol interaksi
        expect(find.text('Verifikasi Interaksi (0)'), findsOneWidget);

        // Lakukan tap pada tombol primitive
        await tester.tap(find.byType(FoundationButton));
        await tester.pump();

        // Verifikasi callback berjalan dan state bertambah
        expect(find.text('Verifikasi Interaksi (1)'), findsOneWidget);

        await tester.tap(find.byType(FoundationButton));
        await tester.pump();

        expect(find.text('Verifikasi Interaksi (2)'), findsOneWidget);
      },
    );
  });
}
