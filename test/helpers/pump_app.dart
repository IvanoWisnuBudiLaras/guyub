import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guyub/core/theme/app_theme.dart';

/// Pumps [widget] inside a [MaterialApp] with the real [AppTheme.light] theme.
///
/// Use this for smoke / layout tests to catch theme-related rendering issues
/// (e.g., buttons with minimumSize = double.infinity in unconstrained parents).
extension PumpApp on WidgetTester {
  Future<void> pumpApp(
    Widget widget, {
    Size screenSize = const Size(400, 800),
    NavigatorObserver? navigatorObserver,
  }) async {
    view.physicalSize = screenSize;
    view.devicePixelRatio = 1;
    addTearDown(view.resetPhysicalSize);
    addTearDown(view.resetDevicePixelRatio);

    await pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        debugShowCheckedModeBanner: false,
        navigatorObservers: [?navigatorObserver],
        home: widget,
      ),
    );
  }
}
