import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'inline_action_button.dart';

enum AlertBannerType { info, warning, danger, success }

/// Banner notifikasi/peringatan dengan palet warna severity muda (pastel),
/// teks selalu gelap dengan kontras tinggi (>= 4.5:1), dan aksi opsional.
final class AlertBanner extends StatelessWidget {
  const AlertBanner({
    required this.title,
    required this.message,
    this.type = AlertBannerType.info,
    this.icon,
    this.actionLabel,
    this.onAction,
    this.actionIcon,
    this.actionKey,
    this.customAction,
    super.key,
  });

  const AlertBanner.warning({
    required this.title,
    required this.message,
    this.icon = Icons.warning_amber_rounded,
    this.actionLabel,
    this.onAction,
    this.actionIcon,
    this.actionKey,
    this.customAction,
    super.key,
  }) : type = AlertBannerType.warning;

  const AlertBanner.danger({
    required this.title,
    required this.message,
    this.icon = Icons.error_outline,
    this.actionLabel,
    this.onAction,
    this.actionIcon,
    this.actionKey,
    this.customAction,
    super.key,
  }) : type = AlertBannerType.danger;

  const AlertBanner.info({
    required this.title,
    required this.message,
    this.icon = Icons.info_outline,
    this.actionLabel,
    this.onAction,
    this.actionIcon,
    this.actionKey,
    this.customAction,
    super.key,
  }) : type = AlertBannerType.info;

  final String title;
  final String message;
  final AlertBannerType type;
  final IconData? icon;
  final String? actionLabel;
  final VoidCallback? onAction;
  final IconData? actionIcon;
  final Key? actionKey;
  final Widget? customAction;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    final (
      Color bg,
      Color border,
      Color fg,
      IconData defaultIcon,
    ) = switch (type) {
      AlertBannerType.info => (
        colors.primarySoft,
        colors.primary.withValues(alpha: 0.3),
        colors.primaryDark,
        Icons.info_outline,
      ),
      AlertBannerType.warning => (
        colors.warningBg,
        colors.warning.withValues(alpha: 0.35),
        const Color(0xFF92400E), // Amber tua kontras tinggi
        Icons.warning_amber_rounded,
      ),
      AlertBannerType.danger => (
        colors.danger.withValues(alpha: 0.08),
        colors.danger.withValues(alpha: 0.3),
        colors.danger,
        Icons.error_outline,
      ),
      AlertBannerType.success => (
        colors.successBg,
        colors.success.withValues(alpha: 0.35),
        const Color(0xFF166534), // Hijau tua kontras tinggi
        Icons.check_circle_outline,
      ),
    };

    final effectiveIcon = icon ?? defaultIcon;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(effectiveIcon, color: fg, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700, color: fg),
                ),
              ),
            ],
          ),
          if (message.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              message,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: const Color(0xFF334155), // Teks gelap kontras >= 4.5:1
                height: 1.4,
              ),
            ),
          ],
          if (customAction != null) ...[
            const SizedBox(height: 10),
            customAction!,
          ] else if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 10),
            InlineActionButton(
              key: actionKey,
              variant: InlineActionButtonVariant.outlined,
              icon: actionIcon ?? Icons.refresh,
              label: actionLabel!,
              onPressed: onAction,
            ),
          ],
        ],
      ),
    );
  }
}
