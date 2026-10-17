import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Data model untuk satu item metrik pada [MetricStrip].
final class MetricItemData {
  const MetricItemData({
    required this.label,
    required this.value,
    required this.icon,
    required this.accentColor,
    required this.backgroundColor,
    this.onTap,
    this.semanticsLabel,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color accentColor;
  final Color backgroundColor;
  final VoidCallback? onTap;
  final String? semanticsLabel;
}

/// Strip metrik bersih yang menampilkan angka kesiapan operasional / tugas
/// dalam 3 kolom (atau n kolom) terpisah divider tipis.
///
/// Mendukung state "gagal memuat / memuat" dengan nilai string default `"-"`.
final class MetricStrip extends StatelessWidget {
  const MetricStrip({required this.items, this.padding, super.key});

  final List<MetricItemData> items;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.border),
      ),
      padding:
          padding ?? const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
      child: Row(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) Container(height: 36, width: 1, color: colors.border),
            Expanded(child: _MetricItemWidget(item: items[i])),
          ],
        ],
      ),
    );
  }
}

class _MetricItemWidget extends StatelessWidget {
  const _MetricItemWidget({required this.item});

  final MetricItemData item;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    final content = Semantics(
      label: item.semanticsLabel ?? '${item.label}: ${item.value}',
      button: item.onTap != null,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: item.backgroundColor,
                  shape: BoxShape.circle,
                ),
                child: Icon(item.icon, color: item.accentColor, size: 14),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  item.value,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: colors.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            item.label,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              color: colors.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );

    if (item.onTap == null) return content;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: item.onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: content,
        ),
      ),
    );
  }
}
