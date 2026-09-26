import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../app/theme/app_colors.dart';
import '../../application/auth_controller.dart';
import '../../application/state/auth_state.dart';

/// SCR-01. Auto-navigate setelah memulihkan sesi tersimpan via [AuthController].
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _bootstrap();
    });
  }

  Future<void> _bootstrap() async {
    if (!mounted) return;
    // TODO(integrasi): Pemanggilan AuthController.initialize() menginisialisasi sesi tersimpan.
    final authController = context.read<AuthController>();
    await authController.initialize();
    await Future.delayed(const Duration(seconds: 1));

    if (!mounted) return;

    final state = authController.state;
    if (state.status == AuthStatus.operatorAuthenticated ||
        state.status == AuthStatus.residentAuthenticated) {
      Navigator.of(context).pushReplacementNamed('/shell');
    } else {
      Navigator.of(context).pushReplacementNamed('/role-selection');
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: _LogoPlaceholder(),
      ),
    );
  }
}

/// Widget logo aplikasi yang menggunakan gambar dari assets/images/logo.png.
class _LogoPlaceholder extends StatelessWidget {
  const _LogoPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Image.asset(
          'assets/images/logo.png',
          width: 120,
          height: 120,
          errorBuilder: (context, error, stackTrace) {
            return const Icon(Icons.home_rounded, size: 64, color: AppColors.logoRoof);
          },
        ),
        const SizedBox(height: 12),
        Text(
          'GUYUB.ID',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: AppColors.logoRoof,
                fontWeight: FontWeight.w700,
                letterSpacing: 1,
              ),
        ),
      ],
    );
  }
}
