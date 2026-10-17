import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/indonesian_date_formatter.dart';
import '../application/weather_snapshot.dart';
import '../application/weather_snapshot_store.dart';

/// Displays only the last locally persisted BMKG snapshot. It never implies a
/// live refresh or converts weather data into an automatic resident task.
final class WeatherSnapshotCard extends StatefulWidget {
  const WeatherSnapshotCard({
    required this.store,
    required this.communityId,
    this.onRefresh,
    super.key,
  });

  final WeatherSnapshotStore store;
  final String communityId;
  final Future<void> Function()? onRefresh;

  @override
  State<WeatherSnapshotCard> createState() => _WeatherSnapshotCardState();
}

final class _WeatherSnapshotCardState extends State<WeatherSnapshotCard> {
  late Future<WeatherSnapshot?> _snapshotFuture;

  @override
  void initState() {
    super.initState();
    _snapshotFuture = widget.store
        .readLastValid(communityId: widget.communityId)
        .timeout(const Duration(seconds: 4), onTimeout: () => null);
    unawaited(_refreshAndReload());
  }

  @override
  void didUpdateWidget(covariant WeatherSnapshotCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.store != widget.store ||
        oldWidget.communityId != widget.communityId ||
        oldWidget.onRefresh != widget.onRefresh) {
      _snapshotFuture = widget.store
          .readLastValid(communityId: widget.communityId)
          .timeout(const Duration(seconds: 4), onTimeout: () => null);
      unawaited(_refreshAndReload());
    }
  }

  Future<void> _refreshAndReload() async {
    final refresh = widget.onRefresh;
    if (refresh == null) return;
    try {
      // The existing cache is read first and remains visible if the network fails.
      await refresh().timeout(const Duration(seconds: 4), onTimeout: () {});
    } catch (_) {
      // A failed fetch must not erase or hide the last valid cached snapshot.
    }
    if (!mounted) return;
    setState(() {
      _snapshotFuture = widget.store
          .readLastValid(communityId: widget.communityId)
          .timeout(const Duration(seconds: 4), onTimeout: () => null);
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return FutureBuilder<WeatherSnapshot?>(
      future: _snapshotFuture,
      builder: (context, snapshot) {
        final data = snapshot.data;
        final String status;
        final bool isStale;

        if (snapshot.connectionState == ConnectionState.waiting) {
          status = 'Memuat data cuaca tersimpan…';
          isStale = false;
        } else if (snapshot.hasError) {
          status = 'Data cuaca tersimpan tidak dapat dibaca.';
          isStale = true;
        } else if (data == null) {
          status = 'Belum ada snapshot BMKG yang tersimpan di perangkat.';
          isStale = false;
        } else if (data.maximumAgeSeconds == null) {
          status = 'Data tersimpan • kesegaran tidak dapat diverifikasi';
          isStale = true;
        } else if (data.isStaleAt(
          now: DateTime.now(),
          maximumAge: Duration(seconds: data.maximumAgeSeconds!),
        )) {
          status = 'Data tersimpan • sudah usang; periksa pembaruan';
          isStale = true;
        } else {
          status = 'Data tersimpan • tidak diperbarui secara langsung';
          isStale = false;
        }

        final rainfall = data?.rainfallMm ?? 0.0;
        final weatherIcon = rainfall <= 0
            ? Icons.wb_sunny_outlined
            : rainfall < 20
            ? Icons.water_drop_outlined
            : Icons.thunderstorm_outlined;

        return Card(
          key: const Key('weather-snapshot-card'),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: colors.border),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header with icon and title
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: colors.primarySoft,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        weatherIcon,
                        size: 20,
                        color: colors.primaryDark,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Cuaca dari BMKG',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: colors.textPrimary,
                            ),
                      ),
                    ),
                    if (data != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: isStale ? colors.warningBg : colors.successBg,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: isStale
                                ? colors.warning.withValues(alpha: 0.4)
                                : colors.success.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Text(
                          isStale ? 'Data Lama' : 'Aktif',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: isStale
                                ? const Color(0xFFB45309)
                                : colors.success,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),

                // Status chip / banner
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: colors.background,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: colors.border),
                  ),
                  child: Text(
                    status,
                    key: const Key('weather-snapshot-status'),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: colors.textSecondary,
                    ),
                  ),
                ),

                if (data != null) ...[
                  const SizedBox(height: 12),
                  // Curah Hujan Box
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: colors.primarySoft,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: colors.primary.withValues(alpha: 0.2),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.water_drop, color: colors.primary, size: 24),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Data curah hujan: '
                            '${data.rainfallMm.toStringAsFixed(1).replaceAll('.', ',')} mm',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: colors.primaryDark,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  // Timestamp info
                  Text(
                    'Pembaruan sumber: ${_formatDate(data.sourceUpdatedAt)}',
                    style: TextStyle(fontSize: 12, color: colors.textSecondary),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Diterima perangkat: ${_formatDate(data.fetchedAt)}',
                    style: TextStyle(fontSize: 12, color: colors.textSecondary),
                  ),
                ] else ...[
                  const SizedBox(height: 12),
                  // Empty state explanation
                  Row(
                    children: [
                      Icon(
                        Icons.cloud_off_outlined,
                        size: 32,
                        color: colors.textSecondary.withValues(alpha: 0.5),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Data snapshot BMKG akan muncul setelah terhubung dengan wilayah RT Anda.',
                          style: TextStyle(
                            fontSize: 12,
                            color: colors.textSecondary,
                            height: 1.3,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],

                const SizedBox(height: 12),
                Text(
                  'Informasi BMKG adalah konteks cuaca, bukan prediksi banjir '
                  'tingkat RT atau peringatan darurat resmi.',
                  style: TextStyle(
                    fontSize: 11,
                    color: colors.textSecondary,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

String _formatDate(DateTime value) =>
    IndonesianDateFormatter.formatNumeric(value);
