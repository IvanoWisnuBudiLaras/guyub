import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Clean card container with a standardized section header, optional icon, badge, and trailing action.
final class SectionCard extends StatelessWidget {
  const SectionCard({
    required this.children,
    this.title,
    this.icon,
    this.trailing,
    this.padding = const EdgeInsets.all(16),
    this.margin = const EdgeInsets.only(bottom: 12),
    super.key,
  });

  final String? title;
  final IconData? icon;
  final Widget? trailing;
  final List<Widget> children;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Container(
      margin: margin,
      child: Material(
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: colors.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: padding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (title != null) ...[
                if (trailing == null)
                  Row(
                    children: [
                      if (icon != null) ...[
                        Icon(icon, size: 20, color: colors.primary),
                        const SizedBox(width: 8),
                      ],
                      Expanded(
                        child: Text(
                          title!,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: colors.textPrimary,
                              ),
                        ),
                      ),
                    ],
                  )
                else
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (icon != null) ...[
                            Icon(icon, size: 20, color: colors.primary),
                            const SizedBox(width: 8),
                          ],
                          Flexible(
                            child: Text(
                              title!,
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: colors.textPrimary,
                                  ),
                            ),
                          ),
                        ],
                      ),
                      trailing!,
                    ],
                  ),
                const SizedBox(height: 12),
              ],
              ...children,
            ],
          ),
        ),
      ),
    );
  }
}
