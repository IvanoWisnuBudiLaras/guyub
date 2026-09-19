import 'package:flutter/material.dart';

import '../core/config/app_config.dart';
import 'router.dart';

/// Root widget aplikasi Guyub.id.
///
/// Menyiapkan [MaterialApp], tema dasar (Material 3 dengan warna brand Guyub),
/// dan router awal aplikasi.
final class GuyubApp extends StatelessWidget {
  const GuyubApp({super.key});

  @override
  Widget build(BuildContext context) {
    final config = AppConfig.current;

    return MaterialApp(
      title: config.appName,
      debugShowCheckedModeBanner: config.environment.isDevelopment,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1E88E5), // Guyub brand blue
        ),
        useMaterial3: true,
      ),
      initialRoute: AppRouter.initial,
      onGenerateRoute: AppRouter.onGenerateRoute,
    );
  }
}

/// Smoke screen sementara khusus Phase 0 — Foundation.
///
/// **PERHATIAN (TODO):**
/// Screen ini BUKAN bagian dari product requirement akhir Guyub.id.
/// Screen ini semata-mata ada untuk membuktikan bahwa konfigurasi bootstrap,
/// widget tree, routing, dan interaksi primitive dapat di-pump dan diuji
/// pada baseline test tanpa error.
///
/// Screen ini akan diganti oleh Onboarding/Task Dashboard saat Phase 1 dimulai.
final class FoundationScreen extends StatefulWidget {
  const FoundationScreen({super.key});

  @override
  State<FoundationScreen> createState() => _FoundationScreenState();
}

class _FoundationScreenState extends State<FoundationScreen> {
  int _interactionCount = 0;

  @override
  Widget build(BuildContext context) {
    final config = AppConfig.current;

    return Scaffold(
      appBar: AppBar(title: Text(config.appName), centerTitle: true),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.shield_outlined,
                color: Color(0xFF1E88E5),
                size: 64,
              ),
              const SizedBox(height: 16),
              const Text(
                'Guyub.id',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'Foundation Ready',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Sistem Kesiapsiagaan Banjir Komunitas RT/RW',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: Colors.black54),
              ),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: config.environment.isDevelopment
                      ? Colors.amber.shade100
                      : (config.environment.isTest
                            ? Colors.blue.shade100
                            : Colors.green.shade100),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  'Environment: ${config.environment.name.toUpperCase()}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: config.environment.isDevelopment
                        ? Colors.amber.shade900
                        : (config.environment.isTest
                              ? Colors.blue.shade900
                              : Colors.green.shade900),
                  ),
                ),
              ),
              const SizedBox(height: 32),
              FoundationButton(
                onPressed: () {
                  setState(() {
                    _interactionCount++;
                  });
                },
                child: Text('Verifikasi Interaksi ($_interactionCount)'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Primitive button widget untuk menguji interaksi baseline pada widget test.
final class FoundationButton extends StatelessWidget {
  final VoidCallback onPressed;
  final Widget child;

  const FoundationButton({
    super.key,
    required this.onPressed,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(onPressed: onPressed, child: child);
  }
}
