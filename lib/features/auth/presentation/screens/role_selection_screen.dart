import 'package:flutter/material.dart';

import '../../../../core/widgets/app_logo.dart';
import '../../../../core/widgets/primary_button.dart';
import '../../../../core/widgets/secondary_button.dart';
import '../../../../core/theme/app_colors.dart';

/// Entry point that keeps operator and resident paths visually distinct.
final class RoleSelectionScreen extends StatelessWidget {
  const RoleSelectionScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.white,
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Center(child: AppLogo(size: 80)),
                const SizedBox(height: 16),
                Text(
                  'Guyub.id',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.displayLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  'Kesiapsiagaan banjir bersama warga',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyLarge
                      ?.copyWith(color: context.appColors.textSecondary),
                ),
                const SizedBox(height: 48),
                Text(
                  'Masuk sebagai siapa Anda?',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 24),
                // Operator card (biru)
                PrimaryButton(
                  key: const Key('role-selection-operator'),
                  label: 'Saya Ketua RT/RW',
                  icon: Icons.admin_panel_settings_outlined,
                  onPressed: () =>
                      Navigator.of(context).pushNamed('/operator/login'),
                ),
                const SizedBox(height: 8),
                Text(
                  'Masuk dengan akun',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 24),
                // Warga card (outline)
                SecondaryButton(
                  key: const Key('role-selection-resident'),
                  label: 'Saya Warga',
                  icon: Icons.home_outlined,
                  onPressed: () =>
                      Navigator.of(context).pushNamed('/resident/entry'),
                ),
                const SizedBox(height: 8),
                Text(
                  'Masuk dengan kode RT',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 32),
                // Darurat button (outline)
                TextButton.icon(
                  key: const Key('emergency-directory-entry'),
                  onPressed: () =>
                      Navigator.of(context).pushNamed('/emergency'),
                  icon: const Icon(Icons.health_and_safety_outlined, size: 20),
                  label: const Text('Informasi Darurat'),
                  style: TextButton.styleFrom(
                    foregroundColor: context.appColors.danger,
                  ),
                ),
                const SizedBox(height: 32),
                // Disclaimer
                Container(
                  padding: const EdgeInsets.all(16),
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
