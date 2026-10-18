import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Data model untuk satu kartu aksi pada [ActionTileGrid].
final class ActionTileData {
  const ActionTileData({
    required this.icon,
    required this.label,
    required this.description,
    required this.onTap,
    this.key,
    this.iconColor,
    this.iconBackgroundColor,
    this.semanticsLabel,
  });

  final Key? key;
  final IconData icon;
  final String label;
  final String description;
  final VoidCallback? onTap;
  final Color? iconColor;
  final Color? iconBackgroundColor;
  final String? semanticsLabel;
}

/// Grid kartu pintasan aksi 2-kolom responsif untuk Beranda Operator dan Warga.
///
/// Menghindari stack/posisi absolut, mendukung text scale 2.0 tanpa overflow,
/// dan tap target minimal 48dp.
final class ActionTileGrid extends StatelessWidget {
  const ActionTileGrid({required this.items, this.spacing = 10, super.key});

  final List<ActionTileData> items;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Pada layar sempit (< 300dp) tampil 1 kolom, layar biasa 2 kolom
        final isVeryNarrow = constraints.maxWidth < 300;
        final itemWidth = isVeryNarrow
            ? constraints.maxWidth
            : (constraints.maxWidth - spacing) / 2;

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: items
              .where((item) => item.onTap != null)
              .map(
                (item) => SizedBox(
                  width: itemWidth,
                  child: _ActionTileCard(data: item),
                ),
              )
              .toList(),
        );
      },
    );
  }
}

final class _ActionTileCard extends StatelessWidget {
  const _ActionTileCard({required this.data});

  final ActionTileData data;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final effectiveIconColor = data.iconColor ?? colors.primary;
    final effectiveIconBg = data.iconBackgroundColor ?? colors.primarySoft;

    return Semantics(
      key: data.key,
      button: true,
      label: data.semanticsLabel ?? '${data.label}: ${data.description}',
      child: Material(
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: colors.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: data.onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 52),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: effectiveIconBg,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(data.icon, color: effectiveIconColor, size: 20),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    data.label,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      height: 1.2,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    data.description,
                    style: TextStyle(
                      fontSize: 11,
                      color: colors.textSecondary,
                      height: 1.3,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
