import 'package:flutter/material.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../data/fake/fake_home_repository.dart';
import '../../../../domain/models/home_data.dart';
import '../../../../domain/repositories/home_repository.dart';
import '../../../../shared/widgets/stat_chip.dart';
import '../../../../shared/widgets/weather_summary_card.dart';

/// SCR-03. Sesuai mockup image14 di proposal.
class HomeWargaScreen extends StatefulWidget {
  const HomeWargaScreen({super.key});

  @override
  State<HomeWargaScreen> createState() => _HomeWargaScreenState();
}

class _HomeWargaScreenState extends State<HomeWargaScreen> {
  // TODO(integrasi): ganti ke agregasi Firestore asli begitu siap.
  final HomeRepository _homeRepository = FakeHomeRepository();
  late Future<WargaHomeData> _future;

  @override
  void initState() {
    super.initState();
    _future = _homeRepository.getWargaHome();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: FutureBuilder<WargaHomeData>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(child: Text('Gagal memuat: ${snapshot.error}'));
            }
            final data = snapshot.data!;
            return RefreshIndicator(
              onRefresh: () async {
                setState(() => _future = _homeRepository.getWargaHome());
                await _future;
              },
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('GUYUB.ID',
                          style: TextStyle(
                              color: AppColors.primaryBlue,
                              fontWeight: FontWeight.w700)),
                      Row(children: const [
                        Icon(Icons.notifications_none),
                        SizedBox(width: 12),
                        Icon(Icons.settings_outlined),
                      ]),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.wargaHeaderBg,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _Pill(text: 'Warga, ${data.rtLabel}'),
                        const SizedBox(height: 8),
                        Text('Selamat Pagi, ${data.residentName}',
                            style: const TextStyle(
                                fontSize: 18, fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  WeatherSummaryCard(snapshot: data.weather),
                  const SizedBox(height: 16),
                  const Text('TUGAS SAYA',
                      style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      StatChip(value: data.stats.inProgress, label: 'Dalam proses'),
                      StatChip(value: data.stats.completed, label: 'Selesai'),
                      StatChip(
                        value: data.stats.notStarted,
                        label: 'Belum mulai',
                        valueColor: Colors.orange,
                      ),
                    ],
                  ),
                  if (data.priorityTask != null) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.warningYellowBg,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(children: [
                            Icon(Icons.warning_amber_rounded, size: 16, color: Colors.brown),
                            SizedBox(width: 6),
                            Text('PRIORITAS — segera diselesaikan',
                                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.brown)),
                          ]),
                          const SizedBox(height: 8),
                          Text(data.priorityTask!.title,
                              style: const TextStyle(fontWeight: FontWeight.w700)),
                          const SizedBox(height: 4),
                          Text('${data.priorityTask!.deadlineLabel}   •   ${data.priorityTask!.locationLabel}',
                              style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  const Text('LAINNYA',
                      style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                  const SizedBox(height: 8),
                  _NavRow(icon: Icons.list_alt_outlined, label: 'Semua Tugas', onTap: () {
                    // TODO(integrasi): ke Daftar Tugas (SCR-04), belum dibangun.
                  }),
                  const SizedBox(height: 8),
                  _NavRow(icon: Icons.flag_outlined, label: 'Usulkan Tugas Baru', onTap: () {
                    // TODO(integrasi): ke Usulkan Tugas (SCR-07), belum dibangun.
                  }),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(text, style: const TextStyle(fontSize: 11, color: AppColors.primaryBlue)),
    );
  }
}

class _NavRow extends StatelessWidget {
  const _NavRow({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.borderGray),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(icon, size: 18, color: AppColors.textSecondary),
              const SizedBox(width: 10),
              Expanded(child: Text(label)),
              const Icon(Icons.chevron_right, size: 18, color: AppColors.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}
