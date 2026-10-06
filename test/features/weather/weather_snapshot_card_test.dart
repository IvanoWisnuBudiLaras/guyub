import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guyub/features/weather/application/weather_snapshot.dart';
import 'package:guyub/features/weather/application/weather_snapshot_store.dart';
import 'package:guyub/features/weather/presentation/weather_snapshot_card.dart';

void main() {
  testWidgets('cached BMKG context shows offline status and both timestamps', (
    tester,
  ) async {
    final store = _FakeWeatherStore(
      WeatherSnapshot(
        id: 'snapshot-test',
        communityId: 'rt-test',
        sourceUpdatedAt: DateTime.utc(2026, 10, 4, 8),
        fetchedAt: DateTime.utc(2026, 10, 4, 8, 5),
        rainfallMm: 12.5,
        maximumAgeSeconds: 604800,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WeatherSnapshotCard(store: store, communityId: 'rt-test'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Data tersimpan • tidak diperbarui secara langsung'),
      findsOneWidget,
    );
    expect(find.textContaining('Data curah hujan: 12,5 mm'), findsOneWidget);
    expect(find.textContaining('Pembaruan sumber:'), findsOneWidget);
    expect(find.textContaining('Diterima perangkat:'), findsOneWidget);
    expect(
      find.textContaining('bukan prediksi banjir tingkat RT'),
      findsOneWidget,
    );
  });

  testWidgets('old cached context is explicitly marked stale', (tester) async {
    final old = DateTime.now().subtract(const Duration(days: 2));
    final store = _FakeWeatherStore(
      WeatherSnapshot(
        id: 'old-snapshot',
        communityId: 'rt-test',
        sourceUpdatedAt: old,
        fetchedAt: old,
        rainfallMm: 12.5,
        maximumAgeSeconds: 60,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WeatherSnapshotCard(store: store, communityId: 'rt-test'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('Data tersimpan • sudah usang; periksa pembaruan'),
      findsOneWidget,
    );
  });

  testWidgets('missing cache does not present weather as current', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: WeatherSnapshotCard(
            store: _EmptyWeatherStore(),
            communityId: 'rt-test',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Belum ada snapshot BMKG yang tersimpan di perangkat.'),
      findsOneWidget,
    );
    expect(find.textContaining('Pembaruan sumber:'), findsNothing);
  });
}

final class _FakeWeatherStore implements WeatherSnapshotStore {
  const _FakeWeatherStore(this.snapshot);

  final WeatherSnapshot? snapshot;

  @override
  Future<WeatherSnapshot?> readLastValid({required String communityId}) async =>
      snapshot?.communityId == communityId ? snapshot : null;
}

final class _EmptyWeatherStore implements WeatherSnapshotStore {
  const _EmptyWeatherStore();

  @override
  Future<WeatherSnapshot?> readLastValid({required String communityId}) async =>
      null;
}
