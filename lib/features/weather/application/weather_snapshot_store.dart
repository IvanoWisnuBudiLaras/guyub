import 'weather_snapshot.dart';

/// Read interface for the last valid normalized weather snapshot in one RT.
abstract interface class WeatherSnapshotStore {
  Future<WeatherSnapshot?> readLastValid({required String communityId});
}

/// Local persistence interface. A refresh may only persist validated snapshots.
abstract interface class WritableWeatherSnapshotStore
    implements WeatherSnapshotStore {
  Future<bool> saveIfNewer(WeatherSnapshot snapshot);
}
