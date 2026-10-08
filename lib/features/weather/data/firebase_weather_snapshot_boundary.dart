import 'package:cloud_functions/cloud_functions.dart';

import '../application/weather_snapshot.dart';
import '../application/weather_snapshot_boundary.dart';

/// Firebase Callable adapter; Firestore weather collections stay server-only.
final class FirebaseWeatherSnapshotBoundary implements WeatherSnapshotBoundary {
  FirebaseWeatherSnapshotBoundary(this._functions);

  final FirebaseFunctions _functions;

  @override
  Future<WeatherSnapshot?> getForOperator() => _fetch(const {});

  @override
  Future<WeatherSnapshot?> getForResident({required String sessionToken}) =>
      _fetch({'sessionToken': sessionToken});

  Future<WeatherSnapshot?> _fetch(Map<String, Object?> data) async {
    final response = await _functions
        .httpsCallable('getLastValidWeatherSnapshot')
        .call<Object?>(data);
    final envelope = _asMap(response.data);
    if (envelope.length != 1 || !envelope.containsKey('snapshot')) {
      throw const FormatException('Invalid weather snapshot response.');
    }
    final rawSnapshot = envelope['snapshot'];
    if (rawSnapshot == null) return null;
    final wire = _asMap(rawSnapshot);
    const expectedKeys = {
      'id',
      'source',
      'communityId',
      'sourceUpdatedAt',
      'fetchedAt',
      'rainfallMm',
      'maximumAgeSeconds',
    };
    if (wire.keys.toSet().difference(expectedKeys).isNotEmpty ||
        wire.keys.toSet().length != expectedKeys.length) {
      throw const FormatException('Invalid weather snapshot response.');
    }
    return WeatherSnapshot.fromJson(wire);
  }
}

Map<String, Object?> _asMap(Object? value) {
  if (value is! Map) {
    throw const FormatException('Invalid weather snapshot response.');
  }
  final result = <String, Object?>{};
  for (final entry in value.entries) {
    if (entry.key is! String) {
      throw const FormatException('Invalid weather snapshot response.');
    }
    result[entry.key as String] = entry.value;
  }
  return result;
}
