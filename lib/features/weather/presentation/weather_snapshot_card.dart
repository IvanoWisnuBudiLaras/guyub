import 'package:flutter/material.dart';

import '../application/weather_snapshot.dart';
import '../application/weather_snapshot_store.dart';

/// Displays only the last locally persisted BMKG snapshot. It never implies a
/// live refresh or converts weather data into an automatic resident task.
final class WeatherSnapshotCard extends StatefulWidget {
  const WeatherSnapshotCard({required this.store, super.key});

  final WeatherSnapshotStore store;

  @override
  State<WeatherSnapshotCard> createState() => _WeatherSnapshotCardState();
}

final class _WeatherSnapshotCardState extends State<WeatherSnapshotCard> {
  late Future<WeatherSnapshot?> _snapshotFuture;

  @override
  void initState() {
    super.initState();
    _snapshotFuture = widget.store.readLastValid();
  }

  @override
  void didUpdateWidget(covariant WeatherSnapshotCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.store != widget.store) {
      _snapshotFuture = widget.store.readLastValid();
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<WeatherSnapshot?>(
    future: _snapshotFuture,
    builder: (context, snapshot) {
      final data = snapshot.data;
      final String status;
      if (snapshot.connectionState == ConnectionState.waiting) {
        status = 'Memuat data cuaca tersimpan…';
      } else if (snapshot.hasError) {
        status = 'Data cuaca tersimpan tidak dapat dibaca.';
      } else if (data == null) {
        status = 'Belum ada snapshot BMKG yang tersimpan di perangkat.';
      } else {
        status = 'Data tersimpan • tidak diperbarui secara langsung';
      }
      return Card(
        key: const Key('weather-snapshot-card'),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.cloud_outlined),
                  const SizedBox(width: 8),
                  Text(
                    'Cuaca dari BMKG',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(status, key: const Key('weather-snapshot-status')),
              if (data != null) ...[
                const SizedBox(height: 8),
                Text(
                  'Data curah hujan: '
                  '${data.rainfallMm.toStringAsFixed(1).replaceAll('.', ',')} mm',
                ),
                const SizedBox(height: 4),
                Text('Pembaruan sumber: ${_formatDate(data.sourceUpdatedAt)}'),
                Text('Diterima perangkat: ${_formatDate(data.fetchedAt)}'),
              ],
              const SizedBox(height: 8),
              const Text(
                'Informasi BMKG adalah konteks cuaca, bukan prediksi banjir '
                'tingkat RT atau peringatan darurat resmi.',
              ),
            ],
          ),
        ),
      );
    },
  );
}

String _formatDate(DateTime value) {
  final local = value.toLocal();
  String two(int part) => part.toString().padLeft(2, '0');
  return '${two(local.day)}/${two(local.month)}/${local.year} '
      '${two(local.hour)}:${two(local.minute)}';
}
