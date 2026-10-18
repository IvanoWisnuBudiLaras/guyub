import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Logo Guyub.id dengan fallback ke placeholder jika aset belum tersedia.
///
/// Prioritas:
/// 1. assets/images/guyub_logo.png (jika ada)
/// 2. Fallback: Material Icons kombinasi (rumah + 3 orang + gelombang air)
final class AppLogo extends StatelessWidget {
  const AppLogo({this.size = 80, super.key});

  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    // Coba load aset logo, fallback ke placeholder jika gagal
    return Image.asset(
      'assets/images/guyub_logo.png',
      width: size,
      height: size,
      fit: BoxFit.contain,
      errorBuilder: (context, error, stackTrace) => _buildPlaceholder(colors),
    );
  }

  Widget _buildPlaceholder(AppColors colors) => SizedBox(
    width: size,
    height: size,
    child: Stack(
      alignment: Alignment.center,
      children: [
        // Gelombang air (bawah, biru)
        Positioned(
          bottom: 0,
          child: Icon(Icons.water, size: size * 0.5, color: colors.primary),
        ),
        // Rumah + orang (tengah, mix)
        Icon(Icons.groups, size: size * 0.6, color: colors.primaryDark),
      ],
    ),
  );
}
