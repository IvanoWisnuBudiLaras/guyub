import 'package:flutter/material.dart';

/// Design tokens: border radius scale
/// Consistent corner rounding for UI elements
class AppRadius {
  AppRadius._();

  static const double sm = 8.0;
  static const double md = 12.0;
  static const double lg = 14.7; // From Figma logout button
  static const double xl = 16.0;
  static const double xxl = 24.0;
  static const double full = 9999.0;

  // BorderRadius shortcuts
  static BorderRadius get smRadius => BorderRadius.circular(sm);
  static BorderRadius get mdRadius => BorderRadius.circular(md);
  static BorderRadius get lgRadius => BorderRadius.circular(lg);
  static BorderRadius get xlRadius => BorderRadius.circular(xl);
  static BorderRadius get xxlRadius => BorderRadius.circular(xxl);
  static BorderRadius get fullRadius => BorderRadius.circular(full);
}
