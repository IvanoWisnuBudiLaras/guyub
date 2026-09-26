import 'package:flutter/material.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../data/fake/fake_home_repository.dart';
import '../../../../domain/models/home_data.dart';
import '../../../../domain/repositories/home_repository.dart';
import '../../../../shared/widgets/primary_button.dart';
import '../../../../shared/widgets/stat_chip.dart';
import '../../../../shared/widgets/weather_summary_card.dart';

/// SCR-08. Sesuai mockup image12 di proposal.
class HomeRtScreen extends StatefulWidget {
  const HomeRtScreen({super.key});

  @override
  State<HomeRtScreen> createState() => _HomeRtScreenState();
}

class _HomeRtScreenState extends State<HomeRtScreen> {
  // TODO(integrasi): ganti ke agregasi Firestore asli begitu siap.
  final HomeRepository _homeRepository = FakeHomeRepository();
  late Future<RtHomeData> _future;

  @override
  void initState() {
    super.initState();
    _future = _homeRepository.getRtHome();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: FutureBuilder<RtHomeData>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(child: Text('Gagal memuat: ${snapshot.error}'));
            }
            final data = snapshot.data!;
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('GUYUB.ID',
                        style: TextStyle(color: AppColors.primaryBlue, fontWeight: FontWeight.w700)),
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
                    color: AppColors.ketuaHeader,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _Pill(text: 'Ketua RT, ${data.rtLabel}'),
                      const SizedBox(height: 8),
                      Text('Selamat Pagi, ${data.operatorName}',
                          style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                WeatherSummaryCard(snapshot: data.weather),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    border: Border.all(color: AppColors.borderGray),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('KESIAPAN RUMAH TANGGA',
                              style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                          Text('${data.readiness.percent}%',
                              style: const TextStyle(color: AppColors.primaryBlue, fontWeight: FontWeight.w700)),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text('${data.readiness.readyCount} dari ${data.readiness.totalCount} Rumah Tangga siap',
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: LinearProgressIndicator(
                          value: data.readiness.ratio,
                          minHeight: 8,
                          backgroundColor: AppColors.neutralBg,
                          color: AppColors.primaryBlue,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('${data.readiness.totalCount - data.readiness.readyCount} belum siap',
                              style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                          Text(data.readiness.targetDateLabel,
                              style: const TextStyle(fontSize: 11, color: Colors.orange)),
                        ],
                      ),
                    ],
                  ),
                ),
                if (data.vulnerableNeedingHelpCount > 0) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.warningYellowBg,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.favorite_outline, size: 18, color: Colors.brown),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '${data.vulnerableNeedingHelpCount} Warga perlu dibantu',
                            style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.brown),
                          ),
                        ),
                        const Icon(Icons.chevron_right, color: Colors.brown),
                      ],
                    ),
                  ),
                ],
                if (data.pendingVerification != null) ...[
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
                        const Text('⏳ Menunggu Verifikasi',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.brown)),
                        const SizedBox(height: 6),
                        Text('${data.pendingVerification!.residentName} — ${data.pendingVerification!.taskTitle}',
                            style: const TextStyle(fontWeight: FontWeight.w600)),
                        Text(data.pendingVerification!.submittedLabel,
                            style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: PrimaryButton(
                                label: 'Tolak',
                                outlined: true,
                                onPressed: () {
                                  // TODO(integrasi): ke antrian verifikasi RT, belum dibangun.
                                },
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: PrimaryButton(
                                label: 'Konfirmasi',
                                onPressed: () {
                                  // TODO(integrasi): ke antrian verifikasi RT, belum dibangun.
                                },
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                const Text('TUGAS WARGA', style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    StatChip(value: data.stats.activeTasks, label: 'Tugas Aktif'),
                    StatChip(value: data.stats.completed, label: 'Selesai'),
                    StatChip(value: data.stats.pending, label: 'Tertunda', valueColor: Colors.orange),
                  ],
                ),
                const SizedBox(height: 16),
                PrimaryButton(
                  label: 'Kirim Tugas Baru',
                  onPressed: () => Navigator.of(context).pushNamed('/task-catalog'),
                ),
                const SizedBox(height: 16),
                const Text('TUGAS TERKINI', style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                const SizedBox(height: 8),
                for (final task in data.recentTasks) _RecentTaskRow(task: task),
              ],
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
      decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(20)),
      child: Text(text, style: const TextStyle(fontSize: 11, color: Colors.white)),
    );
  }
}

class _RecentTaskRow extends StatelessWidget {
  const _RecentTaskRow({required this.task});
  final RecentTaskSummary task;

  @override
  Widget build(BuildContext context) {
    final isActive = task.statusLabel == 'Aktif';
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Icon(Icons.circle, size: 8, color: isActive ? AppColors.successGreen : Colors.orange),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(task.title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                Text(task.progressLabel, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: (isActive ? AppColors.successGreen : Colors.orange).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(task.statusLabel,
                style: TextStyle(fontSize: 10, color: isActive ? AppColors.successGreen : Colors.orange)),
          ),
        ],
      ),
    );
  }
}
