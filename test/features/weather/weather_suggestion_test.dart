import 'package:flutter_test/flutter_test.dart';
import 'package:guyub/features/weather/application/weather_rule.dart';
import 'package:guyub/features/weather/application/weather_snapshot.dart';
import 'package:guyub/features/weather/application/weather_suggestion.dart';
import 'package:guyub/features/weather/data/weather_snapshot_cache.dart';
import 'package:guyub/core/database/in_memory_local_store.dart';

void main() {
  final now = DateTime.utc(2026, 1, 1, 8);
  WeatherSnapshot snapshot({
    String id = 'bmkg-1',
    String communityId = 'rt-a',
    DateTime? fetchedAt,
    DateTime? sourceUpdatedAt,
    double rainfallMm = 16,
    int? maximumAgeSeconds = 3600,
  }) => WeatherSnapshot(
    id: id,
    communityId: communityId,
    sourceUpdatedAt:
        sourceUpdatedAt ?? now.subtract(const Duration(minutes: 15)),
    fetchedAt: fetchedAt ?? now.subtract(const Duration(minutes: 5)),
    rainfallMm: rainfallMm,
    maximumAgeSeconds: maximumAgeSeconds,
  );

  group('WeatherRuleEvaluator', () {
    test(
      'configured threshold produces suggestions only and is replay safe',
      () {
        final rule = WeatherRule(
          id: 'rain-rule-1',
          minimumRainfallMm: 10,
          suggestedTemplateIds: ['reviewed-template-1'],
          enabled: true,
        );
        final evaluator = WeatherRuleEvaluator();

        final suggestions = evaluator.evaluate(
          snapshot: snapshot(),
          rules: [rule],
          evaluatedAt: now,
          maximumSnapshotAge: const Duration(hours: 1),
        );
        final retry = evaluator.evaluate(
          snapshot: snapshot(),
          rules: [rule],
          evaluatedAt: now,
          maximumSnapshotAge: const Duration(hours: 1),
        );

        expect(suggestions, hasLength(1));
        expect(suggestions.single.state, WeatherSuggestionState.suggested);
        expect(suggestions.single.recommendedTemplateIds, [
          'reviewed-template-1',
        ]);
        expect(suggestions.single.id, retry.single.id);
        expect(suggestions.single.source, 'BMKG');
      },
    );

    test('below-threshold, disabled, and stale data do not suggest tasks', () {
      final rule = WeatherRule(
        id: 'rain-rule-1',
        minimumRainfallMm: 20,
        suggestedTemplateIds: ['reviewed-template-1'],
        enabled: true,
      );
      final evaluator = WeatherRuleEvaluator();

      expect(
        evaluator.evaluate(
          snapshot: snapshot(rainfallMm: 19.9),
          rules: [rule],
          evaluatedAt: now,
          maximumSnapshotAge: const Duration(hours: 1),
        ),
        isEmpty,
      );
      expect(
        evaluator.evaluate(
          snapshot: snapshot(),
          rules: [
            WeatherRule(
              id: 'disabled',
              minimumRainfallMm: 0,
              suggestedTemplateIds: ['reviewed-template-1'],
              enabled: false,
            ),
          ],
          evaluatedAt: now,
          maximumSnapshotAge: const Duration(hours: 1),
        ),
        isEmpty,
      );
      expect(
        evaluator.evaluate(
          snapshot: snapshot(fetchedAt: now.subtract(const Duration(hours: 3))),
          rules: [rule],
          evaluatedAt: now,
          maximumSnapshotAge: const Duration(hours: 1),
        ),
        isEmpty,
      );
      expect(
        evaluator.evaluate(
          snapshot: snapshot(
            sourceUpdatedAt: now.subtract(const Duration(hours: 3)),
          ),
          rules: [rule],
          evaluatedAt: now,
          maximumSnapshotAge: const Duration(hours: 1),
        ),
        isEmpty,
      );
    });

    test('thresholds and suggested template references are validated', () {
      expect(
        () => WeatherRule(
          id: 'bad',
          minimumRainfallMm: -1,
          suggestedTemplateIds: ['template-1'],
          enabled: true,
        ),
        throwsArgumentError,
      );
      expect(
        () => WeatherRule(
          id: 'bad',
          minimumRainfallMm: 1,
          suggestedTemplateIds: const [],
          enabled: true,
        ),
        throwsArgumentError,
      );
    });
  });

  group('WeatherSnapshotCache', () {
    test(
      'last valid snapshot remains available and is not replaced by older data',
      () async {
        final localStore = InMemoryLocalStore();
        final cache = WeatherSnapshotCache(localStore);
        final latest = snapshot(id: 'latest');
        final older = snapshot(
          id: 'older',
          fetchedAt: now.subtract(const Duration(hours: 1)),
        );

        expect(await cache.saveIfNewer(latest), isTrue);
        expect(await cache.saveIfNewer(latest), isFalse);
        expect(await cache.saveIfNewer(older), isFalse);
        expect((await cache.readLastValid(communityId: 'rt-a'))?.id, 'latest');
        expect(
          (await cache.readLastValid(communityId: 'rt-a'))?.isStaleAt(
            now: now.add(const Duration(hours: 2)),
            maximumAge: const Duration(hours: 1),
          ),
          isTrue,
        );
        await localStore.close();
      },
    );

    test(
      'snapshots are isolated by RT when one device changes communities',
      () async {
        final localStore = InMemoryLocalStore();
        final cache = WeatherSnapshotCache(localStore);
        final rtA = snapshot(id: 'snapshot-a', communityId: 'rt-a');
        final rtB = snapshot(id: 'snapshot-b', communityId: 'rt-b');

        expect(await cache.saveIfNewer(rtA), isTrue);
        expect(await cache.saveIfNewer(rtB), isTrue);
        expect(
          (await cache.readLastValid(communityId: 'rt-a'))?.id,
          'snapshot-a',
        );
        expect(
          (await cache.readLastValid(communityId: 'rt-b'))?.id,
          'snapshot-b',
        );
        expect(await cache.readLastValid(communityId: 'rt-c'), isNull);
        await localStore.close();
      },
    );

    test(
      'concurrent refreshes cannot replace a newer snapshot with an older one',
      () async {
        final localStore = InMemoryLocalStore();
        final cache = WeatherSnapshotCache(localStore);
        final latest = snapshot(id: 'latest');
        final older = snapshot(
          id: 'older',
          fetchedAt: now.subtract(const Duration(hours: 1)),
        );

        final saved = await Future.wait([
          cache.saveIfNewer(latest),
          cache.saveIfNewer(older),
        ]);

        expect(saved, [isTrue, isFalse]);
        expect((await cache.readLastValid(communityId: 'rt-a'))?.id, 'latest');
        await localStore.close();
      },
    );
  });
}
