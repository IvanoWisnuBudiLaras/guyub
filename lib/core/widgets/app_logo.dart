import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Logo Guyub.id (rumah + 3 orang + gelombang air)
///
/// Placeholder pakai Material Icons kombinasi.
/// Nanti ganti dengan aset SVG/PNG final.
final class AppLogo extends StatelessWidget {
  const AppLogo({this.size = 80, super.key});

  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return SizedBox(
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
}
