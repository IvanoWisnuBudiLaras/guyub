import 'package:flutter/material.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../shared/widgets/app_card.dart';

/// SCR-02. Sesuai mockup: card solid biru untuk Ketua RT/RW,
/// card outline untuk Warga.
class RoleSelectionScreen extends StatelessWidget {
  const RoleSelectionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 24),
              Text(
                'Masuk sebagai\nsiapa Anda?',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Pilih peran Anda di RT/RW.',
                style: TextStyle(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 24),
              AppCard(
                filled: true,
                onTap: () => Navigator.of(context).pushNamed('/operator-login'),
                child: const _RoleOptionContent(
                  icon: Icons.assignment_outlined,
                  title: 'Saya Ketua RT/RW',
                  subtitle:
                      'Kelola Tugas, pantau kesiapan warga, koordinasi banjir',
                  actionLabel: 'Masuk dengan Akun',
                  isFilled: true,
                ),
              ),
              const SizedBox(height: 16),
              AppCard(
                onTap: () => Navigator.of(context).pushNamed('/resident-rt-code'),
                child: const _RoleOptionContent(
                  icon: Icons.home_outlined,
                  title: 'Saya Warga',
                  subtitle: 'Ikuti tugas kesiapan banjir di RT anda',
                  actionLabel: 'Masuk dengan Kode RT',
                  isFilled: false,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoleOptionContent extends StatelessWidget {
  const _RoleOptionContent({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.actionLabel,
    required this.isFilled,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String actionLabel;
  final bool isFilled;

  @override
  Widget build(BuildContext context) {
    final fg = isFilled ? Colors.white : AppColors.primaryBlue;
    final subFg = isFilled ? Colors.white70 : AppColors.textSecondary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isFilled ? Colors.white24 : AppColors.wargaHeaderBg,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: fg, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  color: isFilled ? Colors.white : AppColors.textPrimary,
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(subtitle, style: TextStyle(color: subFg, fontSize: 13)),
        const SizedBox(height: 16),
        Row(
          children: [
            Text(
              actionLabel,
              style: TextStyle(color: fg, fontWeight: FontWeight.w600),
            ),
            const SizedBox(width: 4),
            Icon(Icons.arrow_forward, size: 16, color: fg),
          ],
        ),
      ],
    );
  }
}
