import 'weather_snapshot.dart';
import 'weather_snapshot_store.dart';

/// Callable boundary for an RT-scoped last-valid weather snapshot.
abstract interface class WeatherSnapshotBoundary {
  Future<WeatherSnapshot?> getForOperator();
  Future<WeatherSnapshot?> getForResident({required String sessionToken});
}

/// Reads protected credentials inside the data layer and persists only a
/// validated snapshot for the current RT. The cache stays useful offline.
final class WeatherSnapshotSyncController {
  factory WeatherSnapshotSyncController({
    required WeatherSnapshotBoundary boundary,
    required WritableWeatherSnapshotStore store,
    required Future<String?> Function() readResidentSessionToken,
  }) => WeatherSnapshotSyncController._(
    boundary: boundary,
    store: store,
    readResidentSessionToken: readResidentSessionToken,
  );

  WeatherSnapshotSyncController._({
    required this._boundary,
    required this._store,
    required this._readResidentSessionToken,
  });

  final WeatherSnapshotBoundary _boundary;
  final WritableWeatherSnapshotStore _store;
  final Future<String?> Function() _readResidentSessionToken;

  Future<void> refreshForResident({required String communityId}) async {
    final sessionToken = await _readResidentSessionToken();
    if (sessionToken == null || sessionToken.isEmpty) return;
    final snapshot = await _boundary.getForResident(sessionToken: sessionToken);
    await _saveIfCurrent(snapshot, communityId);
  }

  Future<void> refreshForOperator({required String communityId}) async {
    final snapshot = await _boundary.getForOperator();
    await _saveIfCurrent(snapshot, communityId);
  }

  Future<void> _saveIfCurrent(
    WeatherSnapshot? snapshot,
    String communityId,
  ) async {
    if (snapshot == null) return;
    if (snapshot.communityId != communityId) {
      throw const FormatException('Weather snapshot scope does not match.');
    }
    await _store.saveIfNewer(snapshot);
  }
}
