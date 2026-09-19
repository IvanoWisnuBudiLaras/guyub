import 'package:flutter/material.dart';

import 'app.dart';

/// Rute navigasi deklaratif aplikasi Guyub.id.
///
/// Pada Phase 0, router menyediakan rute beranda [initial] menuju [FoundationScreen].
/// Rute fitur berikutnya (login, tasks, emergency) akan didaftarkan di sini
/// seiring berjalannya fase implementasi.
final class AppRouter {
  /// Rute default beranda awal aplikasi.
  static const String initial = '/';

  /// Handler pembuatan rute dinamis berbasis [RouteSettings].
  static Route<dynamic> onGenerateRoute(RouteSettings settings) {
    switch (settings.name) {
      case initial:
      default:
        return MaterialPageRoute(
          builder: (_) => const FoundationScreen(),
          settings: settings,
        );
    }
  }
}
