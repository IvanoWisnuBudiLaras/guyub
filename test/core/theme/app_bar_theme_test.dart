import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guyub/core/theme/app_colors.dart';
import 'package:guyub/core/theme/app_theme.dart';

void main() {
  testWidgets(
    'AppBar background (#0288D1) and foreground (white) stay consistent after scroll',
    (tester) async {
      final theme = AppTheme.light;
      final primaryBlue = AppColors.light.primary; // #0288D1

      expect(theme.appBarTheme.scrolledUnderElevation, 0);
      expect(theme.appBarTheme.surfaceTintColor, Colors.transparent);
      expect(theme.appBarTheme.backgroundColor, primaryBlue);
      expect(theme.appBarTheme.foregroundColor, Colors.white);

      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Scaffold(
            appBar: AppBar(
              title: const Text('Uji AppBar'),
              actions: [
                IconButton(
                  icon: const Icon(Icons.notifications),
                  onPressed: () {},
                ),
              ],
            ),
            body: ListView.builder(
              key: const Key('scrollable-content'),
              itemCount: 50,
              itemBuilder: (context, index) => ListTile(
                title: Text('Item $index'),
              ),
            ),
          ),
        ),
      );

      // Helper untuk inspect Material widget di dalam AppBar
      Material getAppBarMaterial() {
        return tester.widget<Material>(
          find.descendant(
            of: find.byType(AppBar),
            matching: find.byType(Material),
          ).first,
        );
      }

      // State awal sebelum scroll
      final materialBefore = getAppBarMaterial();
      expect(materialBefore.color, primaryBlue);
      expect(materialBefore.surfaceTintColor, Colors.transparent);
      expect(materialBefore.elevation, 0);

      // Scroll listview ke bawah sejauh 400 pixel
      await tester.drag(find.byKey(const Key('scrollable-content')), const Offset(0, -400));
      await tester.pumpAndSettle();

      // State setelah scroll: background, surfaceTintColor, dan elevation tetap tidak berubah
      final materialAfter = getAppBarMaterial();
      expect(materialAfter.color, primaryBlue);
      expect(materialAfter.surfaceTintColor, Colors.transparent);
      expect(materialAfter.elevation, 0);

      // Text dan Icon tetap putih
      final titleText = tester.widget<Text>(find.text('Uji AppBar'));
      final titleStyle = DefaultTextStyle.of(tester.element(find.text('Uji AppBar'))).style;
      expect(titleStyle.color, Colors.white);

      final icon = tester.widget<Icon>(find.byIcon(Icons.notifications));
      final iconTheme = IconTheme.of(tester.element(find.byIcon(Icons.notifications)));
      expect(iconTheme.color, Colors.white);
    },
  );
}
