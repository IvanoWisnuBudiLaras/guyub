import 'package:flutter/material.dart';

import '../../../../core/widgets/app_logo.dart';
import '../../../../core/theme/app_colors.dart';

/// Entry point that keeps operator and resident paths visually distinct.
final class RoleSelectionScreen extends StatelessWidget {
  const RoleSelectionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final isCompact = screenHeight < 700; // Layar kecil seperti 360x640

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.all(isCompact ? 16 : 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: 480,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                    Center(child: AppLogo(size: isCompact ? 64 : 80)),
                    SizedBox(height: isCompact ? 12 : 16),
                    Text(
                      'Guyub.id',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.displayLarge,
                    ),
                    SizedBox(height: isCompact ? 4 : 8),
                    Text(
                      'Kesiapsiagaan banjir bersama warga',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            color: context.appColors.textSecondary,
                          ),
                    ),
                    SizedBox(height: isCompact ? 32 : 48),
                    Text(
                      'Masuk sebagai siapa Anda?',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    SizedBox(height: isCompact ? 16 : 24),
                    // Operator card (kartu biru primary)
                    _RoleCard(
                      key: const Key('role-selection-operator'),
                      title: 'Saya Ketua RT/RW atau Pendamping',
                      description:
                          'Kelola tugas, pantau kesiapan warga, koordinasi banjir',
                      icon: Icons.admin_panel_settings_outlined,
                      actionLabel: 'MASUK DENGAN AKUN',
                      isPrimary: true,
                      isCompact: isCompact,
                      onTap: () =>
                          Navigator.of(context).pushNamed('/operator/login'),
                    ),
                    SizedBox(height: isCompact ? 12 : 16),
                    // Warga card (kartu outline)
                    _RoleCard(
                      key: const Key('role-selection-resident'),
                      title: 'Saya Warga',
                      description: 'Ikuti tugas kesiapan banjir di RT Anda',
                      icon: Icons.home_outlined,
                      actionLabel: 'MASUK DENGAN KODE RT',
                      isPrimary: false,
                      isCompact: isCompact,
                      onTap: () =>
                          Navigator.of(context).pushNamed('/resident/entry'),
                    ),
                    SizedBox(height: isCompact ? 24 : 32),
                    // Darurat button (outline merah penuh lebar)
                    OutlinedButton.icon(
                      key: const Key('emergency-directory-entry'),
                      onPressed: () =>
                          Navigator.of(context).pushNamed('/emergency'),
                      icon: const Icon(
                        Icons.health_and_safety_outlined,
                        size: 20,
                      ),
                      label: const Text('Informasi Darurat'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: context.appColors.danger,
                        side: BorderSide(color: context.appColors.danger),
                        minimumSize: const Size.fromHeight(48),
                      ),
                    ),
                    SizedBox(height: isCompact ? 16 : 32),
                    // Disclaimer
                    Container(
                      padding: EdgeInsets.all(isCompact ? 12 : 16),
                      decoration: BoxDecoration(
                        color: context.appColors.background,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: context.appColors.border),
                      ),
                      child: Text(
                        'Guyub.id membantu koordinasi persiapan. Aplikasi ini bukan '
                        'prediksi banjir tingkat RT atau pengganti layanan darurat resmi.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
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

/// Kartu besar untuk role selection (meniru proposal Figma).
class _RoleCard extends StatelessWidget {
  const _RoleCard({
    required this.title,
    required this.description,
    required this.icon,
    required this.actionLabel,
    required this.isPrimary,
    required this.isCompact,
    required this.onTap,
    super.key,
  });

  final String title;
  final String description;
  final IconData icon;
  final String actionLabel;
  final bool isPrimary;
  final bool isCompact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final bgColor = isPrimary ? colors.primary : Colors.white;
    final fgColor = isPrimary ? Colors.white : colors.textPrimary;
    final borderColor = isPrimary ? colors.primary : colors.border;

    return Material(
      color: bgColor,
      borderRadius: BorderRadius.circular(16),
      elevation: isPrimary ? 2 : 0,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: EdgeInsets.all(isCompact ? 16 : 24),
          decoration: BoxDecoration(
            border: Border.all(color: borderColor, width: 1.5),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Icon in semi-transparent box
              Container(
                width: isCompact ? 48 : 56,
                height: isCompact ? 48 : 56,
                decoration: BoxDecoration(
                  color: isPrimary
                      ? Colors.white.withOpacity(0.2)
                      : colors.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  icon,
                  size: isCompact ? 28 : 32,
                  color: isPrimary ? Colors.white : colors.primary,
                ),
              ),
              SizedBox(height: isCompact ? 12 : 16),
              // Title
              Text(
                title,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: fgColor,
                      fontWeight: FontWeight.w600,
                      fontSize: isCompact ? 16 : null,
                    ),
              ),
              SizedBox(height: isCompact ? 6 : 8),
              // Description
              Text(
                description,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: isPrimary
                          ? Colors.white.withOpacity(0.9)
                          : colors.textSecondary,
                      fontSize: isCompact ? 13 : null,
                    ),
              ),
              SizedBox(height: isCompact ? 14 : 20),
              // Action footer
              Row(
                children: [
                  Flexible(
                    child: Text(
                      actionLabel,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                            color: fgColor,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.5,
                            fontSize: isCompact ? 12 : null,
                          ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.arrow_forward,
                    size: isCompact ? 14 : 16,
                    color: fgColor,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
