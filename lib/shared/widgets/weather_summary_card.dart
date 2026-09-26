import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../domain/models/weather_snapshot.dart';

/// AT-008: kalau isStale true, HARUS ada indikasi jelas bahwa ini data
/// cache lama (bukan cuma warna, jangan sampai ke-skip pas offline).
class WeatherSummaryCard extends StatelessWidget {
  const WeatherSummaryCard({super.key, required this.snapshot});

  final WeatherSnapshot snapshot;

  String _timeLabel(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}.${t.minute.toString().padLeft(2, '0')} WIB';

  @override
  Widget build(BuildContext context) {
    return Container(
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
              const Text('CUACA SEKARANG',
                  style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
              Row(
                children: [
                  if (snapshot.isStale) ...[
                    const Icon(Icons.cloud_off, size: 13, color: AppColors.dangerRed),
                    const SizedBox(width: 4),
                    const Text('Data tersimpan',
                        style: TextStyle(fontSize: 11, color: AppColors.dangerRed)),
                  ] else ...[
                    const Icon(Icons.refresh, size: 13, color: AppColors.textSecondary),
                    const SizedBox(width: 4),
                    Text(_timeLabel(snapshot.observedAt),
                        style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                  ],
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(snapshot.condition,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              Text('${snapshot.temperatureC.toStringAsFixed(0)}°C',
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _MiniStat(icon: Icons.water_drop_outlined, value: '${snapshot.humidityPercent}%', label: 'Kelembapan'),
              const SizedBox(width: 8),
              _MiniStat(icon: Icons.cloud_outlined, value: '${snapshot.rainfallMm.toStringAsFixed(0)} mm', label: 'Curah Hujan'),
              const SizedBox(width: 8),
              _MiniStat(icon: Icons.air, value: '${snapshot.windKmh.toStringAsFixed(0)} Km/j', label: 'Angin'),
            ],
          ),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.icon, required this.value, required this.label});
  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.wargaHeaderBg,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            Icon(icon, size: 16, color: AppColors.primaryBlue),
            const SizedBox(height: 2),
            Text(value, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
            Text(label, style: const TextStyle(fontSize: 9, color: AppColors.textSecondary)),
          ],
        ),
      ),
    );
  }
}
