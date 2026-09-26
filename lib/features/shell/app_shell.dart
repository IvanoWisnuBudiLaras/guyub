import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../domain/models/app_session.dart';
import '../home/home_rt_screen.dart';
import '../home/home_warga_screen.dart';
import '../tasks/task_catalog_screen.dart';

/// Shell 3 tab (Beranda/Tugas/Darurat). Tab "Tugas" & "Darurat" masih
/// placeholder untuk role yang belum ada layarnya (Daftar Tugas Warga,
/// Emergency screen) — lihat komentar TODO di masing-masing.
class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.role});

  final UserRole role;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final isOperator = widget.role == UserRole.operator;

    final tabs = <Widget>[
      isOperator ? const HomeRtScreen() : const HomeWargaScreen(),
      isOperator
          ? const TaskCatalogScreen()
          // TODO(integrasi): ganti ke Daftar Tugas Warga (SCR-04), belum dibangun.
          : const _ComingSoon(label: 'Daftar Tugas (segera hadir)'),
      // TODO(integrasi): ganti ke Emergency Screen (SCR-06), belum dibangun.
      const _ComingSoon(label: 'Darurat (segera hadir)'),
    ];

    return Scaffold(
      body: IndexedStack(index: _index, children: tabs),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        indicatorColor: AppColors.primaryBlue.withValues(alpha: 0.12),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Beranda'),
          NavigationDestination(icon: Icon(Icons.assignment_outlined), selectedIcon: Icon(Icons.assignment), label: 'Tugas'),
          NavigationDestination(icon: Icon(Icons.warning_amber_outlined), selectedIcon: Icon(Icons.warning_amber), label: 'Darurat'),
        ],
      ),
    );
  }
}

class _ComingSoon extends StatelessWidget {
  const _ComingSoon({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(label, style: const TextStyle(color: AppColors.textSecondary)),
    );
  }
}
