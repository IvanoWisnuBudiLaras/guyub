import 'package:flutter/material.dart';

/// Palet warna Guyub.id — estimasi dari proposal, ganti di satu file ini.
///
/// Primary: biru untuk tombol, header, accent.
/// Success: hijau untuk Ikut, Konfirmasi, badge Selesai.
/// Warning: kuning/amber untuk Prioritas Tinggi, warning.
/// Danger: merah untuk prioritas tinggi, darurat.
/// Background: abu-abu sangat muda untuk background kartu.
/// Border: abu-abu untuk border kartu.
/// Text: primary hitam kebiruan, secondary abu-abu medium.
@immutable
final class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.primary,
    required this.primaryDark,
    required this.primarySoft,
    required this.success,
    required this.successBg,
    required this.warning,
    required this.warningBg,
    required this.danger,
    required this.dangerBg,
    required this.background,
    required this.border,
    required this.textPrimary,
    required this.textSecondary,
  });

  /// Biru primer untuk tombol, header, accent (#0288D1)
  final Color primary;

  /// Biru gelap untuk pressed state, dark mode (#01579B)
  final Color primaryDark;

  /// Biru sangat muda untuk background soft accent (#E1F3FD)
  final Color primarySoft;

  /// Hijau untuk aksi positif: Ikut, Konfirmasi, badge Selesai (#16A34A)
  final Color success;

  /// Background success card/badge (#E8F5E9 estimasi)
  final Color successBg;

  /// Kuning/amber untuk warning, Prioritas Tinggi (#F5A623)
  final Color warning;

  /// Background warning card/badge (#FFF4CC)
  final Color warningBg;

  /// Merah untuk prioritas tinggi, darurat (#E53935)
  final Color danger;

  /// Background danger card/badge (#FDE4E2)
  final Color dangerBg;

  /// Background abu-abu sangat muda untuk kartu (#F7FAFD)
  final Color background;

  /// Border abu-abu untuk kartu (#DDE5EC)
  final Color border;

  /// Text hitam kebiruan primer (#1B2733)
  final Color textPrimary;

  /// Text abu-abu sekunder (#5E6B78)
  final Color textSecondary;

  /// Light theme default
  static const light = AppColors(
    primary: Color(0xFF0288D1),
    primaryDark: Color(0xFF01579B),
    primarySoft: Color(0xFFE1F3FD),
    success: Color(0xFF16A34A),
    successBg: Color(0xFFE8F5E9),
    warning: Color(0xFFF5A623),
    warningBg: Color(0xFFFFF4CC),
    danger: Color(0xFFE53935),
    dangerBg: Color(0xFFFDE4E2),
    background: Color(0xFFF7FAFD),
    border: Color(0xFFDDE5EC),
    textPrimary: Color(0xFF1B2733),
    textSecondary: Color(0xFF5E6B78),
  );

  @override
  ThemeExtension<AppColors> copyWith({
    Color? primary,
    Color? primaryDark,
    Color? primarySoft,
    Color? success,
    Color? successBg,
    Color? warning,
    Color? warningBg,
    Color? danger,
    Color? dangerBg,
    Color? background,
    Color? border,
    Color? textPrimary,
    Color? textSecondary,
  }) => AppColors(
    primary: primary ?? this.primary,
    primaryDark: primaryDark ?? this.primaryDark,
    primarySoft: primarySoft ?? this.primarySoft,
    success: success ?? this.success,
    successBg: successBg ?? this.successBg,
    warning: warning ?? this.warning,
    warningBg: warningBg ?? this.warningBg,
    danger: danger ?? this.danger,
    dangerBg: dangerBg ?? this.dangerBg,
    background: background ?? this.background,
    border: border ?? this.border,
    textPrimary: textPrimary ?? this.textPrimary,
    textSecondary: textSecondary ?? this.textSecondary,
  );

  @override
  ThemeExtension<AppColors> lerp(
    covariant ThemeExtension<AppColors>? other,
    double t,
  ) {
    if (other is! AppColors) return this;
    return AppColors(
      primary: Color.lerp(primary, other.primary, t)!,
      primaryDark: Color.lerp(primaryDark, other.primaryDark, t)!,
      primarySoft: Color.lerp(primarySoft, other.primarySoft, t)!,
      success: Color.lerp(success, other.success, t)!,
      successBg: Color.lerp(successBg, other.successBg, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      warningBg: Color.lerp(warningBg, other.warningBg, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      dangerBg: Color.lerp(dangerBg, other.dangerBg, t)!,
      background: Color.lerp(background, other.background, t)!,
      border: Color.lerp(border, other.border, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
    );
  }
}

/// Extension untuk akses mudah AppColors dari BuildContext
extension AppColorsX on BuildContext {
  AppColors get appColors =>
      Theme.of(this).extension<AppColors>() ?? AppColors.light;
}
