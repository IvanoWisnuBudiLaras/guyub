import 'package:flutter/material.dart';

/// Skala tipografi konsisten untuk Guyub.id
///
/// Pakai satu font family bersih. Kalau butuh custom font (Inter/Poppins),
/// tambahkan via google_fonts atau bundle di assets.
final class AppTypography {
  const AppTypography._();

  /// Headline besar (splash, judul utama)
  static const TextStyle headline1 = TextStyle(
    fontSize: 28,
    fontWeight: FontWeight.bold,
    height: 1.2,
    letterSpacing: -0.5,
  );

  /// Headline sedang (judul section, screen title)
  static const TextStyle headline2 = TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.w600,
    height: 1.3,
    letterSpacing: -0.25,
  );

  /// Headline kecil (judul kartu, judul tugas)
  static const TextStyle headline3 = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w600,
    height: 1.4,
  );

  /// Body besar (konten utama, instruksi penting)
  static const TextStyle bodyLarge = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.normal,
    height: 1.5,
  );

  /// Body regular (konten biasa)
  static const TextStyle bodyRegular = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.normal,
    height: 1.5,
  );

  /// Body kecil (caption, meta info, timestamp)
  static const TextStyle bodySmall = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.normal,
    height: 1.4,
  );

  /// Button text (tombol penuh lebar, tombol aksi)
  static const TextStyle button = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    height: 1.25,
    letterSpacing: 0.5,
  );

  /// Button text kecil (chip, badge, tombol kecil)
  static const TextStyle buttonSmall = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    height: 1.25,
    letterSpacing: 0.25,
  );

  /// Label (form label, judul field)
  static const TextStyle label = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w500,
    height: 1.3,
  );

  /// Caption (keterangan kecil, disclaimer, info tambahan)
  static const TextStyle caption = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.normal,
    height: 1.4,
    color: Color(0xFF5E6B78), // textSecondary
  );
}
