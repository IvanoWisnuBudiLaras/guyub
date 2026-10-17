import 'package:flutter/material.dart';

/// Token visual tambahan yang diekstrak dari mockup proposal Guyub.id.
///
/// Ini murni presentasi (warna/ukuran) dan tidak menyentuh data maupun backend.
final class GuyubTokens {
  const GuyubTokens._();

  /// Biru tombol utama (CTA) pada mockup — "Kirim Usulan ke Ketua RT", dll.
  static const Color ctaBlue = Color(0xFF3CB0F4);

  /// Biru solid kartu hero operator & kartu "Saya Ketua RT/RW".
  static const Color heroBlue = Color(0xFF0288D1);

  /// Isi kartu hero warga (cyan muda) dan garis tepinya.
  static const Color wargaHeroFill = Color(0xFFC9EEFD);
  static const Color wargaHeroBorder = Color(0xFF4DB8F0);

  /// Latar bottom navigation (biru sangat muda).
  static const Color navBackground = Color(0xFFEAF3FB);

  /// Banner kuning "perlu dibantu" / "prioritas".
  static const Color yellowFill = Color(0xFFFFF3B0);
  static const Color yellowBorder = Color(0xFFF2C230);
  static const Color yellowText = Color(0xFFB45309);

  /// Hijau tombol "Ikut" / "Konfirmasi" serta chip Aktif.
  static const Color green = Color(0xFF16A34A);
  static const Color greenSoft = Color(0xFFDCFCE7);

  /// Oranye angka "Tertunda" / "Belum mulai".
  static const Color orange = Color(0xFFF59E0B);

  /// Kartu informasi darurat (hitam) dan strip mode offline.
  static const Color darkCard = Color(0xFF17181A);

  /// Abu-abu kotak catatan/placeholder.
  static const Color greyFill = Color(0xFFF1F3F5);
  static const Color greyHeader = Color(0xFFCBD0D6);
  static const Color greyBorder = Color(0xFFC9D1D9);

  /// Latar kartu template pada Katalog Tugas.
  static const Color templateFill = Color(0xFFDDF1FD);

  /// Radius kartu & input pada mockup.
  static const double cardRadius = 14;
  static const double inputRadius = 8;

  /// Bayangan lembut kartu mockup.
  static List<BoxShadow> get softShadow => [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.08),
      blurRadius: 10,
      offset: const Offset(0, 3),
    ),
  ];
}
