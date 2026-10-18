import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/guyub_tokens.dart';

/// Alias umum untuk bottom navigation bersama.
typedef AppBottomNav = GuyubBottomNavBar;

/// Bottom navigation bar bersama untuk Warga dan Operator RT
/// yang menjaga konsistensi visual 3 tab: Beranda, Tugas, Darurat.
final class GuyubBottomNavBar extends StatelessWidget {
  const GuyubBottomNavBar({
    required this.currentIndex,
    required this.onTap,
    super.key,
  });

  final int currentIndex;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Container(
      decoration: const BoxDecoration(color: GuyubTokens.navBackground),
      child: SafeArea(
        top: false,
        child: BottomNavigationBar(
          currentIndex: currentIndex,
          onTap: onTap,
          selectedItemColor: colors.primary,
          unselectedItemColor: const Color(0xFF9AA5B1),
          backgroundColor: GuyubTokens.navBackground,
          selectedFontSize: 12,
          unselectedFontSize: 12,
          type: BottomNavigationBarType.fixed,
          elevation: 0,
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.home_outlined),
              activeIcon: Icon(Icons.home_outlined),
              label: 'Beranda',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.assignment_outlined),
              activeIcon: Icon(Icons.assignment_outlined),
              label: 'Tugas',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.signal_cellular_alt),
              activeIcon: Icon(Icons.signal_cellular_alt),
              label: 'Darurat',
            ),
          ],
        ),
      ),
    );
  }
}
