import 'package:flutter/material.dart';

enum InlineActionButtonVariant { filled, tonal, outlined }

/// Tombol aksi dengan lebar fit-content (inline) yang aman diletakkan
/// di dalam [Row], [Wrap], [ListTile], atau kontainer dengan lebar tak terbatas.
///
/// Komponen ini secara eksplisit mengesampingkan [minimumSize] tema global
/// (`double.infinity`) agar tidak memicu assertion layout rendering engine.
final class InlineActionButton extends StatelessWidget {
  const InlineActionButton({
    required this.onPressed,
    required this.label,
    this.icon,
    this.variant = InlineActionButtonVariant.filled,
    this.isDestructive = false,
    super.key,
  });

  final VoidCallback? onPressed;
  final String label;
  final IconData? icon;
  final InlineActionButtonVariant variant;
  final bool isDestructive;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final Color foregroundColor;
    final Color backgroundColor;

    if (isDestructive) {
      foregroundColor = colorScheme.error;
      backgroundColor = colorScheme.errorContainer.withValues(alpha: 0.3);
    } else {
      switch (variant) {
        case InlineActionButtonVariant.filled:
          foregroundColor = colorScheme.onPrimary;
          backgroundColor = colorScheme.primary;
        case InlineActionButtonVariant.tonal:
          foregroundColor = colorScheme.onSecondaryContainer;
          backgroundColor = colorScheme.secondaryContainer;
        case InlineActionButtonVariant.outlined:
          foregroundColor = colorScheme.primary;
          backgroundColor = Colors.transparent;
      }
    }

    final buttonStyle = switch (variant) {
      InlineActionButtonVariant.filled => FilledButton.styleFrom(
        backgroundColor: backgroundColor,
        foregroundColor: foregroundColor,
        minimumSize: const Size(0, 36),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        textStyle: theme.textTheme.labelMedium?.copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),
      InlineActionButtonVariant.tonal => FilledButton.styleFrom(
        backgroundColor: backgroundColor,
        foregroundColor: foregroundColor,
        minimumSize: const Size(0, 36),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        textStyle: theme.textTheme.labelMedium?.copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),
      InlineActionButtonVariant.outlined => OutlinedButton.styleFrom(
        foregroundColor: foregroundColor,
        side: BorderSide(
          color: isDestructive ? colorScheme.error : colorScheme.outline,
          width: 1,
        ),
        minimumSize: const Size(0, 36),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        textStyle: theme.textTheme.labelMedium?.copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),
    };

    if (variant == InlineActionButtonVariant.outlined) {
      if (icon != null) {
        return OutlinedButton.icon(
          onPressed: onPressed,
          style: buttonStyle,
          icon: Icon(icon, size: 18),
          label: Text(label),
        );
      }
      return OutlinedButton(
        onPressed: onPressed,
        style: buttonStyle,
        child: Text(label),
      );
    }

    if (icon != null) {
      return FilledButton.icon(
        onPressed: onPressed,
        style: buttonStyle,
        icon: Icon(icon, size: 18),
        label: Text(label),
      );
    }
    return FilledButton(
      onPressed: onPressed,
      style: buttonStyle,
      child: Text(label),
    );
  }
}
