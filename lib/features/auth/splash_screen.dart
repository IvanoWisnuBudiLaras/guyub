import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../data/local/session_storage.dart';
import '../../domain/models/app_session.dart';
import 'role_selection_screen.dart';

/// SCR-01. Auto-navigate setelah cek apakah ada session tersimpan.
/// TODO(integrasi): kalau session ada & valid, arahkan ke home shell
/// sesuai role (Phase 3/8) — untuk sekarang selalu balik ke Role Selection
/// karena home shell belum dibangun.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key, required this.sessionStorage});

  final SessionStorage sessionStorage;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final existing = await widget.sessionStorage.read();
    await Future.delayed(const Duration(seconds: 2));
    if (!mounted) return;

    if (existing != null) {
      // TODO(integrasi): ganti dengan navigasi ke home shell per role
      // (HomeWargaScreen / HomeRtScreen) begitu Phase 3/8 selesai.
      debugPrint('Session ditemukan untuk ${existing.displayName}, '
          'role: ${existing.role}. Home shell belum ada, ke Role Selection.');
    }

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const RoleSelectionScreen()),
    );
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

/// Placeholder logo — ganti dengan Image.asset() begitu file logo resmi
/// (dari mockup: rumah + 3 orang teal/biru/oranye + gelombang) di-drop
/// ke assets/.
class _LogoPlaceholder extends StatelessWidget {
  const _LogoPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.home_rounded, size: 64, color: AppColors.logoRoof),
        const SizedBox(height: 8),
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
