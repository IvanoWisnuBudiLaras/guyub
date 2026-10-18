import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Clean row for metadata like Estimasi Waktu, Batas Waktu, Lokasi with icon, label, and value.
final class InfoRow extends StatelessWidget {
  const InfoRow({
    required this.label,
    required this.value,
    this.icon,
    this.valueColor,
    this.valueWidget,
    super.key,
  });

  final String label;
  final String value;
  final IconData? icon;
  final Color? valueColor;
  final Widget? valueWidget;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 16, color: colors.textSecondary),
            const SizedBox(width: 8),
          ],
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: colors.textSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child:
                valueWidget ??
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 13,
                    color: valueColor ?? colors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
          ),
        ],
      ),
    );
  }
}
