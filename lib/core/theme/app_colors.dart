import 'package:flutter/material.dart';

/// Design tokens diambil langsung dari sample pixel mockup di proposal.
/// Kalau desainer kasih style guide resmi nanti, tinggal update di sini —
/// semua widget lain manggil lewat AppColors, bukan hardcode hex sendiri.
class AppColors {
  AppColors._();

  static const primaryBlue = Color(0xFF008CD2); // tombol utama, CTA
  static const ketuaHeader = Color(0xFF009ECA); // header beranda Ketua RT
  static const wargaHeaderBg = Color(0xFFD2F7FF); // header beranda Warga
  static const deepBlueBanner = Color(0xFF034EDA); // banner detail tugas
  static const successGreen = Color(0xFF14AE5C); // tombol Ikut / Konfirmasi
  static const warningYellowBg = Color(0xFFFFF7BA); // box prioritas
  static const darkSurface = Color(0xFF1D1B20); // banner mode offline
  static const dangerRed = Color(0xFFD32F2F); // tag "tinggi" prioritas

  static const logoRoof = Color(0xFF0671AD);
  static const logoTeal = Color(0xFF05ADAF);
  static const logoOrange = Color(0xFFF88105);

  static const neutralBg = Color(0xFFF5F5F5);
  static const borderGray = Color(0xFFE0E0E0);
  static const textPrimary = Color(0xFF1A1A1A);
  static const textSecondary = Color(0xFF6B6B6B);
}
