import 'weather_snapshot.dart';

/// Read interface for the last valid normalized weather snapshot.
abstract interface class WeatherSnapshotStore {
  Future<WeatherSnapshot?> readLastValid();
}
