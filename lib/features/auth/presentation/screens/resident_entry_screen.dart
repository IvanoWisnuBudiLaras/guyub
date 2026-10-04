import 'package:flutter/material.dart';

/// Fail-closed resident entry placeholder until scoped sessions are available.
///
/// An RT code alone is not authorization. Do not accept or persist it here until
/// a backend-mediated, short-lived resident session is implemented.
final class ResidentEntryScreen extends StatelessWidget {
  const ResidentEntryScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Akses Warga')),
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lock_outline, size: 48),
            const SizedBox(height: 16),
            Text(
              'Akses warga belum tersedia',
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            const Text(
              'Kode RT saja belum cukup untuk melindungi data warga. '
              'Akses akan tersedia setelah sesi warga yang aman disiapkan.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    ),
  );
}
