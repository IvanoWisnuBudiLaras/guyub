import '../../features/weather/presentation/weather_snapshot_card.dart';

export '../../features/weather/presentation/weather_snapshot_card.dart'
    show WeatherSnapshotCard;

/// General shared alias for [WeatherSnapshotCard] displaying BMKG snapshot,
/// rainfall, staleness timestamp, and offline/empty states.
typedef WeatherSummaryCard = WeatherSnapshotCard;
