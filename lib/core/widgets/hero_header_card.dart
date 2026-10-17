import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/guyub_tokens.dart';
import '../utils/indonesian_date_formatter.dart';

/// Varian visual kartu hero pada proposal.
enum HeroVariant {
  /// Biru solid + chip putih (Beranda Ketua RT/RW).
  operator,

  /// Cyan muda + chip bergaris (Beranda Warga).
  resident,
}

/// Sapaan menurut waktu setempat: Pagi / Siang / Sore / Malam.
String guyubGreetingFor(DateTime now) {
  final hour = now.hour;
  final part = hour >= 4 && hour < 11
      ? 'Pagi'
      : hour >= 11 && hour < 15
      ? 'Siang'
      : hour >= 15 && hour < 18
      ? 'Sore'
      : 'Malam';
  return 'Selamat $part';
}

/// Kartu header hero Beranda sesuai proposal.
///
/// Menampilkan chip peran + RT/RW, sapaan pengguna dan tanggal lokal Indonesia.
final class HeroHeaderCard extends StatelessWidget {
  const HeroHeaderCard({
    required this.title,
    this.variant = HeroVariant.operator,
    this.roleLabel,
    this.roleIcon,
    this.communityLabel,
    this.secondaryCommunityLabel,
    this.dateText,
    this.subtitle,
    super.key,
  });

  final String title;
  final HeroVariant variant;
  final String? roleLabel;
  final IconData? roleIcon;
  final String? communityLabel;
  final String? secondaryCommunityLabel;
  final String? dateText;
  final String? subtitle;

  bool get _isOperator => variant == HeroVariant.operator;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final titleColor = _isOperator ? Colors.white : colors.textPrimary;
    final mutedColor = _isOperator
        ? Colors.white.withValues(alpha: 0.88)
        : colors.textSecondary;

    final chipParts = <String>[
      ?roleLabel,
      ?communityLabel,
      ?secondaryCommunityLabel,
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: _isOperator ? GuyubTokens.heroBlue : GuyubTokens.wargaHeroFill,
        borderRadius: BorderRadius.circular(GuyubTokens.cardRadius),
        border: _isOperator
            ? null
            : Border.all(color: GuyubTokens.wargaHeroBorder, width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (chipParts.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: _isOperator ? Colors.white : Colors.transparent,
                borderRadius: BorderRadius.circular(999),
                border: _isOperator
                    ? null
                    : Border.all(color: GuyubTokens.wargaHeroBorder),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (roleIcon case final icon?) ...[
                    Icon(icon, size: 13, color: colors.primary),
                    const SizedBox(width: 4),
                  ],
                  for (var i = 0; i < chipParts.length; i++) ...[
                    if (i > 0)
                      Text(
                        ', ',
                        style: TextStyle(
                          color: _isOperator
                              ? colors.primaryDark
                              : colors.textPrimary,
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
                    Flexible(
                      child: Text(
                        chipParts[i],
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: _isOperator
                              ? colors.primaryDark
                              : colors.textPrimary,
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          const SizedBox(height: 14),
          Text(
            title,
            style: Theme.of(context).textTheme.titleLarge
                ?.copyWith(color: titleColor, fontWeight: FontWeight.w800),
          ),
          if (subtitle case final text?) ...[
            const SizedBox(height: 2),
            Text(text, style: TextStyle(color: mutedColor, fontSize: 12)),
          ],
          const SizedBox(height: 22),
          Text(
            dateText ?? IndonesianDateFormatter.formatDateOnly(DateTime.now()),
            style: TextStyle(color: mutedColor, fontSize: 11),
          ),
        ],
      ),
    );
  }
}
