import 'package:flutter/material.dart';

/// Entry point that keeps operator and resident paths visually distinct.
final class RoleSelectionScreen extends StatelessWidget {
  const RoleSelectionScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Guyub.id')),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(
                Icons.groups_outlined,
                size: 56,
                color: Color(0xFF1E88E5),
              ),
              const SizedBox(height: 16),
              Text(
                'Kesiapsiagaan banjir bersama warga',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 32),
              FilledButton.icon(
                onPressed: () =>
                    Navigator.of(context).pushNamed('/operator/login'),
                icon: const Icon(Icons.admin_panel_settings_outlined),
                label: const Text('Saya Ketua RT/RW atau Pendamping'),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () =>
                    Navigator.of(context).pushNamed('/resident/entry'),
                icon: const Icon(Icons.home_outlined),
                label: const Text('Saya Warga'),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                key: const Key('emergency-directory-entry'),
                onPressed: () => Navigator.of(context).pushNamed('/emergency'),
                icon: const Icon(Icons.health_and_safety_outlined),
                label: const Text('Darurat'),
              ),
              const SizedBox(height: 16),
              const Text(
                'Guyub.id membantu koordinasi persiapan. Aplikasi ini bukan '
                'prediksi banjir tingkat RT atau pengganti layanan darurat resmi.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
