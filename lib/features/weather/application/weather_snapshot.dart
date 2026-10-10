/// A validated, normalized snapshot of rainfall context received from BMKG.
///
/// This value contains source/fetch timestamps so callers can label cached data
/// accurately. It does not imply RT-level flood prediction or an official warning.
final class WeatherSnapshot {
  WeatherSnapshot({
    required this.id,
    required this.sourceUpdatedAt,
    required this.fetchedAt,
    required this.rainfallMm,
  }) {
    if (id.trim().isEmpty) {
      throw ArgumentError.value(id, 'id', 'Must not be empty.');
    }
    if (!rainfallMm.isFinite || rainfallMm < 0) {
      throw ArgumentError.value(
        rainfallMm,
        'rainfallMm',
        'Must be finite and non-negative.',
      );
    }
  }

  static const sourceAttribution = 'BMKG';

  final String id;
  final DateTime sourceUpdatedAt;
  final DateTime fetchedAt;
  final double rainfallMm;

  /// Cached data must be shown as stale when future-dated or beyond [maximumAge].
  bool isStaleAt({required DateTime now, required Duration maximumAge}) {
    if (maximumAge.isNegative) {
      throw ArgumentError.value(
        maximumAge,
        'maximumAge',
        'Must not be negative.',
      );
    }
    final fetchAge = now.difference(fetchedAt);
    final sourceAge = now.difference(sourceUpdatedAt);
    return fetchAge.isNegative ||
        fetchAge > maximumAge ||
        sourceAge.isNegative ||
        sourceAge > maximumAge;
  }

  Map<String, Object> toJson() => {
    'id': id,
    'source': sourceAttribution,
    'sourceUpdatedAt': sourceUpdatedAt.toUtc().toIso8601String(),
    'fetchedAt': fetchedAt.toUtc().toIso8601String(),
    'rainfallMm': rainfallMm,
  };

  factory WeatherSnapshot.fromJson(Map<String, Object?> json) {
    if (json['source'] != sourceAttribution) {
      throw const FormatException('Weather source must be BMKG.');
    }
    final sourceUpdatedAt = DateTime.tryParse(
      json['sourceUpdatedAt'] as String? ?? '',
    );
    final fetchedAt = DateTime.tryParse(json['fetchedAt'] as String? ?? '');
    final rainfallValue = json['rainfallMm'];
    if (sourceUpdatedAt == null || fetchedAt == null || rainfallValue is! num) {
      throw const FormatException('Weather snapshot fields are invalid.');
    }
    return WeatherSnapshot(
      id: json['id'] as String? ?? '',
      sourceUpdatedAt: sourceUpdatedAt,
      fetchedAt: fetchedAt,
      rainfallMm: rainfallValue.toDouble(),
    );
  }
}
