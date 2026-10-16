import 'package:flutter/material.dart';

import '../../../../core/widgets/app_logo.dart';

/// Splash screen dengan logo Guyub.id di tengah
final class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

final class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    // Navigate ke role selection setelah 1.5 detik
    Future<void>.delayed(const Duration(milliseconds: 1500), () {
      if (mounted) {
        Navigator.of(context).pushReplacementNamed('/');
      }
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.white,
    body: Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const AppLogo(size: 120),
          const SizedBox(height: 24),
          Text('Guyub.id', style: Theme.of(context).textTheme.displayLarge),
          const SizedBox(height: 8),
          Text(
            'Kesiapsiagaan Banjir Bersama Warga',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    ),
  );
}
