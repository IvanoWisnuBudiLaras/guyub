import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../features/auth/application/auth_controller.dart';
import '../features/home/presentation/screens/home_rt_screen.dart';
import '../features/home/presentation/screens/home_warga_screen.dart';
import '../features/tasks/presentation/screens/task_catalog_screen.dart';
import 'theme/app_colors.dart';

/// Shell 3 tab (Beranda/Tugas/Darurat).
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final authState = context.watch<AuthController>().state;
    final isOperator = authState.isOperatorSession;

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
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Beranda',
          ),
          NavigationDestination(
            icon: Icon(Icons.assignment_outlined),
            selectedIcon: Icon(Icons.assignment),
            label: 'Tugas',
          ),
          NavigationDestination(
            icon: Icon(Icons.warning_amber_outlined),
            selectedIcon: Icon(Icons.warning_amber),
            label: 'Darurat',
          ),
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
