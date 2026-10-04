import 'dart:async';
import 'dart:convert';

import '../../../core/database/local_store.dart';
import '../application/weather_snapshot.dart';
import '../application/weather_snapshot_store.dart';

/// Persists the last valid normalized BMKG snapshot for offline reading.
///
/// A failed refresh must not call [saveIfNewer]. Older/equal refreshes do not
/// overwrite the most recent cached snapshot.
final class WeatherSnapshotCache implements WeatherSnapshotStore {
  WeatherSnapshotCache(this._localStore);

  static const _storageKey = 'guyub.weather.lastValid.v1';
  final LocalStore _localStore;
  Future<void> _writeTail = Future<void>.value();

  @override
  Future<WeatherSnapshot?> readLastValid() async {
    final encoded = await _localStore.read(_storageKey);
    if (encoded == null) return null;
    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! Map<String, dynamic>) return null;
      return WeatherSnapshot.fromJson(decoded);
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    } on ArgumentError {
      return null;
    }
  }

  /// Stores [snapshot] only when it is newer than the cached snapshot.
  ///
  /// Returns `true` if storage changed. Call only after successful source
  /// retrieval and normalization; failed/malformed BMKG data cannot replace it.
  Future<bool> saveIfNewer(WeatherSnapshot snapshot) {
    final result = Completer<bool>();
    _writeTail = _writeTail.then((_) async {
      try {
        final current = await readLastValid();
        if (current != null && !snapshot.fetchedAt.isAfter(current.fetchedAt)) {
          result.complete(false);
          return;
        }
        await _localStore.write(_storageKey, jsonEncode(snapshot.toJson()));
        result.complete(true);
      } catch (error, stackTrace) {
        result.completeError(error, stackTrace);
      }
    });
    return result.future;
  }
}
