import 'package:flutter/material.dart';

import '../../../../core/widgets/app_logo.dart';
import '../../../auth/application/operator_auth_boundary.dart';
import '../../../auth/application/operator_profile.dart';
import '../../../auth/application/resident_session.dart';
import '../../../auth/application/resident_session_controller.dart';

/// Splash screen dengan restore sesi paralel (minimum 1.5s)
final class SplashScreen extends StatefulWidget {
  const SplashScreen({
    required this.operatorAuthBoundary,
    required this.residentSessionController,
    super.key,
  });

  final OperatorAuthBoundary? operatorAuthBoundary;
  final ResidentSessionController? residentSessionController;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

final class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _initializeAndNavigate();
  }

  Future<void> _initializeAndNavigate() async {
    // Jalankan restore sesi paralel dengan minimum delay
    final results = await Future.wait([
      _restoreSessions(),
      Future<void>.delayed(const Duration(milliseconds: 1500)),
    ]);

    final sessionResult = results[0] as _SessionResult;

    if (!mounted) return;

    if (sessionResult.hasOperator) {
      Navigator.of(context).pushReplacementNamed(
        '/operator/home',
        arguments: sessionResult.operatorProfile,
      );
    } else if (sessionResult.hasResident) {
      Navigator.of(context).pushReplacementNamed(
        '/resident/home',
        arguments: sessionResult.residentSession,
      );
    } else {
      // Belum punya sesi, ke role selection
      Navigator.of(context).pushReplacementNamed('/');
    }
  }

  /// Restore operator atau resident session.
  Future<_SessionResult> _restoreSessions() async {
    try {
      // Coba restore operator session
      final operatorBoundary = widget.operatorAuthBoundary;
      if (operatorBoundary != null) {
        final operatorResult = await operatorBoundary.restoreCurrentSession();
        if (operatorResult.isOk) {
          return _SessionResult(operatorProfile: operatorResult.dataOrNull);
        }
      }

      // Coba restore resident session
      final residentController = widget.residentSessionController;
      if (residentController != null) {
        final residentSession = await residentController.restoreSession();
        if (residentSession != null) {
          return _SessionResult(residentSession: residentSession);
        }
      }
    } catch (_) {
      // Restore gagal, tetap ke role selection
    }

    return _SessionResult();
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

/// Helper untuk menyimpan hasil restore session
class _SessionResult {
  _SessionResult({this.operatorProfile, this.residentSession});

  final OperatorProfile? operatorProfile;
  final ResidentSession? residentSession;

  bool get hasOperator => operatorProfile != null;
  bool get hasResident => residentSession != null;
}
