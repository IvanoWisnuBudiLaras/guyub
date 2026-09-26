/// Sesuai spec §12.4 `weather_snapshots`. `isStale` wajib dicek UI —
/// AT-008: cached weather harus kelihatan jelas kalau ini data lama.
class WeatherSnapshot {
  const WeatherSnapshot({
    required this.condition,
    required this.temperatureC,
    required this.humidityPercent,
    required this.rainfallMm,
    required this.windKmh,
    required this.observedAt,
    required this.isStale,
  });

  final String condition; // "Hujan Sedang"
  final double temperatureC;
  final int humidityPercent;
  final double rainfallMm;
  final double windKmh;
  final DateTime observedAt;
  final bool isStale;
}
