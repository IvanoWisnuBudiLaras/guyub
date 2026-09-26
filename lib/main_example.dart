// Ini CONTOH — cek main.dart asli kamu (yang sudah ada firebase_options.dart
// di dalamnya) dan gabungkan bagian MaterialApp + SplashScreen ke situ,
// jangan langsung timpa filenya.

import 'package:flutter/material.dart';
import 'core/theme/app_theme.dart';
import 'data/local/session_storage.dart';
import 'features/auth/splash_screen.dart';

void main() {
  runApp(const GuyubApp());
}

class GuyubApp extends StatelessWidget {
  const GuyubApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Guyub.id',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: SplashScreen(sessionStorage: SecureSessionStorage()),
    );
  }
}
