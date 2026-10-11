import 'package:flutter_test/flutter_test.dart';
import 'package:guyub/features/weather/application/weather_snapshot.dart';
import 'package:guyub/features/weather/application/weather_snapshot_boundary.dart';
import 'package:guyub/features/weather/application/weather_snapshot_store.dart';

void main() {
  final updatedAt = DateTime.utc(2026, 10, 5, 8);

  WeatherSnapshot snapshot({
    String communityId = 'rt-a',
    String id = 'snapshot-a',
  }) => WeatherSnapshot(
    id: id,
    communityId: communityId,
    sourceUpdatedAt: updatedAt,
    fetchedAt: updatedAt,
    rainfallMm: 12.5,
  );

  test(
    'resident refresh reads token in the boundary and stores only same-RT data',
    () async {
      final boundary = _FakeBoundary(residentSnapshot: snapshot());
      final store = _FakeStore();
      final controller = WeatherSnapshotSyncController(
        boundary: boundary,
        store: store,
        readResidentSessionToken: () async => 'secret-session-token',
      );

      await controller.refreshForResident(communityId: 'rt-a');

      expect(boundary.residentToken, 'secret-session-token');
      expect(store.snapshots['rt-a']?.id, 'snapshot-a');
    },
  );

  test(
    'resident refresh skips without session token and rejects a different RT',
    () async {
      final boundary = _FakeBoundary(
        residentSnapshot: snapshot(communityId: 'rt-b'),
      );
      final store = _FakeStore()..snapshots['rt-a'] = snapshot(id: 'cached-a');
      final noSession = WeatherSnapshotSyncController(
        boundary: boundary,
        store: store,
        readResidentSessionToken: () async => null,
      );
      await noSession.refreshForResident(communityId: 'rt-a');
      expect(boundary.residentToken, isNull);
      expect(store.snapshots['rt-a']?.id, 'cached-a');

      final controller = WeatherSnapshotSyncController(
        boundary: boundary,
        store: store,
        readResidentSessionToken: () async => 'secret-session-token',
      );
      await expectLater(
        controller.refreshForResident(communityId: 'rt-a'),
        throwsFormatException,
      );
      expect(store.snapshots['rt-a']?.id, 'cached-a');
    },
  );

  test('operator refresh also validates the RT before saving', () async {
    final boundary = _FakeBoundary(operatorSnapshot: snapshot());
    final store = _FakeStore();
    final controller = WeatherSnapshotSyncController(
      boundary: boundary,
      store: store,
      readResidentSessionToken: () async => null,
    );
    await controller.refreshForOperator(communityId: 'rt-a');
    expect(boundary.operatorReads, 1);
    expect(store.snapshots['rt-a']?.id, 'snapshot-a');
  });
}

final class _FakeBoundary implements WeatherSnapshotBoundary {
  _FakeBoundary({this.residentSnapshot, this.operatorSnapshot});

  final WeatherSnapshot? residentSnapshot;
  final WeatherSnapshot? operatorSnapshot;
  String? residentToken;
  int operatorReads = 0;

  @override
  Future<WeatherSnapshot?> getForOperator() async {
    operatorReads += 1;
    return operatorSnapshot;
  }

  @override
  Future<WeatherSnapshot?> getForResident({
    required String sessionToken,
  }) async {
    residentToken = sessionToken;
    return residentSnapshot;
  }
}

final class _FakeStore implements WritableWeatherSnapshotStore {
  final Map<String, WeatherSnapshot> snapshots = {};

  @override
  Future<WeatherSnapshot?> readLastValid({required String communityId}) async =>
      snapshots[communityId];

  @override
  Future<bool> saveIfNewer(WeatherSnapshot snapshot) async {
    final current = snapshots[snapshot.communityId];
    if (current != null && !snapshot.fetchedAt.isAfter(current.fetchedAt)) {
      return false;
    }
    snapshots[snapshot.communityId] = snapshot;
    return true;
  }
}
