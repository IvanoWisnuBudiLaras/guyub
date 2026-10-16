import 'package:flutter/material.dart';

/// Design tokens: typography scale
/// Consistent text styles for the app
class AppTextStyles {
  AppTextStyles._();

  // Display styles
  static const displayLarge = TextStyle(
    fontSize: 32,
    fontWeight: FontWeight.bold,
    height: 1.25,
  );

  static const displayMedium = TextStyle(
    fontSize: 28,
    fontWeight: FontWeight.bold,
    height: 1.25,
  );

  static const displaySmall = TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.bold,
    height: 1.3,
  );

  // Heading styles
  static const headingLarge = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w600,
    height: 1.4,
  );

  static const headingMedium = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w600,
    height: 1.4,
  );

  static const headingSmall = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    height: 1.4,
  );

  // Body styles
  static const bodyLarge = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.normal,
    height: 1.5,
  );

  static const bodyMedium = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.normal,
    height: 1.5,
  );

  static const bodySmall = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.normal,
    height: 1.5,
  );

  // Label styles
  static const labelLarge = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w500,
    height: 1.4,
  );

  static const labelMedium = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w500,
    height: 1.4,
  );

  static const labelSmall = TextStyle(
    fontSize: 10,
    fontWeight: FontWeight.w500,
    height: 1.4,
  );
}
