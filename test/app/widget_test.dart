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
    AppConfig.initialize(AppConfig.test());

    await tester.pumpWidget(const GuyubApp());

    expect(
      find.byWidgetPredicate(
        (widget) => widget is MaterialApp && widget.title == 'Guyub [TEST]',
      ),
      findsOneWidget,
    );
    expect(find.text('Saya Ketua RT/RW atau Pendamping'), findsOneWidget);
    expect(find.text('Saya Warga'), findsOneWidget);
    expect(find.text('Foundation Ready'), findsNothing);
  });

  testWidgets('role selection routes each role to its entry path', (
    WidgetTester tester,
  ) async {
    AppConfig.initialize(AppConfig.test());
    await tester.pumpWidget(const GuyubApp());

    await tester.tap(find.text('Saya Ketua RT/RW atau Pendamping'));
    await tester.pumpAndSettle();
    expect(find.text('Masuk Operator RT/RW'), findsOneWidget);
    expect(find.byKey(const Key('operator-password')), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Saya Warga'));
    await tester.pumpAndSettle();
    expect(find.text('Akses warga belum tersedia'), findsOneWidget);
  });
}
