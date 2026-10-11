import 'dart:async';
import 'dart:convert';

import '../../../core/database/local_store.dart';
import '../application/weather_snapshot.dart';
import '../application/weather_snapshot_store.dart';

/// Persists the last valid normalized BMKG snapshot for offline reading.
///
/// A failed refresh must not call [saveIfNewer]. Older/equal refreshes do not
/// overwrite the most recent cached snapshot.
final class WeatherSnapshotCache implements WritableWeatherSnapshotStore {
  WeatherSnapshotCache(this._localStore);

  static String _storageKey(String communityId) =>
      'guyub.weather.lastValid.v1.$communityId';
  final LocalStore _localStore;
  Future<void> _writeTail = Future<void>.value();

  @override
  Future<WeatherSnapshot?> readLastValid({required String communityId}) async {
    if (!RegExp(r'^[A-Za-z0-9_-]{1,64}$').hasMatch(communityId)) return null;
    final encoded = await _localStore.read(_storageKey(communityId));
    if (encoded == null) return null;
    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! Map<String, dynamic>) return null;
      final snapshot = WeatherSnapshot.fromJson(decoded);
      return snapshot.communityId == communityId ? snapshot : null;
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
  @override
  Future<bool> saveIfNewer(WeatherSnapshot snapshot) {
    final result = Completer<bool>();
    _writeTail = _writeTail.then((_) async {
      try {
        final current = await readLastValid(communityId: snapshot.communityId);
        if (current != null && !snapshot.fetchedAt.isAfter(current.fetchedAt)) {
          result.complete(false);
          return;
        }
        await _localStore.write(
          _storageKey(snapshot.communityId),
          jsonEncode(snapshot.toJson()),
        );
        result.complete(true);
      } catch (error, stackTrace) {
        result.completeError(error, stackTrace);
      }
    });
    return result.future;
  }
}
