import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guyub/app/app.dart';
import 'package:guyub/core/config/app_config.dart';

void main() {
  setUp(() {
    AppConfig.resetForTesting();
  });

  testWidgets('GuyubApp starts at the distinct role selection screen', (
    WidgetTester tester,
  ) async {
    // Set realistic phone viewport (360x640 dp, pixel ratio 2.0)
    tester.view.physicalSize = const Size(720, 1280);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    AppConfig.initialize(AppConfig.test());

    await tester.pumpWidget(const GuyubApp());
    // Splash screen dengan delayed navigation (1.5 detik)
    await tester.pumpAndSettle(const Duration(seconds: 2));

    expect(
      find.byWidgetPredicate(
        (widget) => widget is MaterialApp && widget.title == 'Guyub [TEST]',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('Saya Ketua RT/RW'), findsOneWidget);
    expect(find.text('Saya Warga'), findsOneWidget);
    expect(find.text('Foundation Ready'), findsNothing);
  });

  testWidgets('role selection routes each role to its entry path', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(720, 1280);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    AppConfig.initialize(AppConfig.test());
    await tester.pumpWidget(const GuyubApp());
    await tester.pumpAndSettle(const Duration(seconds: 2));

    await tester.tap(find.textContaining('Saya Ketua RT/RW'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Masuk sebagai Ketua RT/RW'), findsOneWidget);
    expect(find.byKey(const Key('operator-password')), findsOneWidget);

    // Kembali dengan tap back button (Icon arrow_back)
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();

    // Pastikan kembali ke role selection screen
    expect(find.textContaining('Saya Ketua RT/RW'), findsOneWidget);

    await tester.tap(find.text('Saya Warga'));
    await tester.pumpAndSettle();
    expect(find.text('Akses warga belum tersedia'), findsOneWidget);
  });

  testWidgets('Darurat is reachable before sign-in', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(720, 1280);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    AppConfig.initialize(AppConfig.test());
    await tester.pumpWidget(const GuyubApp());
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // Scroll ke bawah untuk akses tombol darurat
    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, -200),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('emergency-directory-entry')));
    await tester.pumpAndSettle();

    expect(find.text('Informasi Darurat'), findsOneWidget);
    expect(find.textContaining('Direktori belum tersedia'), findsOneWidget);
    expect(
      find.textContaining('Guyub.id tidak menggantikan layanan darurat'),
      findsOneWidget,
    );
  });

  testWidgets('role selection adapts to large text scale', (
    WidgetTester tester,
  ) async {
    // Test dengan text scale 2.0 (aksesibilitas)
    tester.view.physicalSize = const Size(720, 1280);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    AppConfig.initialize(AppConfig.test());

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(2.0)),
        child: const GuyubApp(),
      ),
    );
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // Semua text tetap terlihat tanpa overflow
    expect(find.textContaining('Saya Ketua RT/RW'), findsOneWidget);
    expect(find.text('Saya Warga'), findsOneWidget);

    // Scroll hingga "Saya Warga" terlihat dan bisa di-tap
    await tester.ensureVisible(find.text('Saya Warga'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Saya Warga'));
    await tester.pumpAndSettle();
    expect(find.text('Akses warga belum tersedia'), findsOneWidget);
  });

  testWidgets('operator login adapts to large text scale with back button', (
    WidgetTester tester,
  ) async {
    // Test dengan text scale 2.0 di layar 360x640
    tester.view.physicalSize = const Size(720, 1280);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    AppConfig.initialize(AppConfig.test());

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(2.0)),
        child: const GuyubApp(),
      ),
    );
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // Navigate ke operator login
    await tester.ensureVisible(find.textContaining('Saya Ketua RT/RW'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Saya Ketua RT/RW'));
    await tester.pumpAndSettle();

    // Pastikan elemen penting terlihat
    expect(find.textContaining('Masuk sebagai Ketua RT/RW'), findsOneWidget);
    expect(find.byKey(const Key('operator-email')), findsOneWidget);
    expect(find.byKey(const Key('operator-password')), findsOneWidget);

    // Pastikan tombol back ada di AppBar
    expect(find.byIcon(Icons.arrow_back), findsOneWidget);

    // Scroll dan tap back untuk pastikan tidak overflow
    await tester.ensureVisible(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();

    // Pastikan kembali ke role selection
    expect(find.textContaining('Saya Ketua RT/RW'), findsOneWidget);
  });

  testWidgets('resident entry adapts to large text scale with back button', (
    WidgetTester tester,
  ) async {
    // Test dengan text scale 2.0 di layar 360x640
    tester.view.physicalSize = const Size(720, 1280);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    AppConfig.initialize(AppConfig.test());

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(2.0)),
        child: const GuyubApp(),
      ),
    );
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // Navigate ke resident entry
    await tester.ensureVisible(find.text('Saya Warga'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Saya Warga'));
    await tester.pumpAndSettle();

    // Pastikan elemen penting terlihat (unavailable state)
    expect(find.text('Akses warga belum tersedia'), findsOneWidget);
    expect(find.textContaining('Kode RT saja belum cukup'), findsOneWidget);

    // Pastikan tombol back ada di AppBar
    expect(find.byIcon(Icons.arrow_back), findsOneWidget);

    // Scroll dan tap back untuk pastikan tidak overflow
    await tester.ensureVisible(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();

    // Pastikan kembali ke role selection
    expect(find.text('Saya Warga'), findsOneWidget);
  });
}
