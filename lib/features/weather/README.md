# Feature: Weather (BMKG Open Data)

**Status: PARTIAL.** The feature contains a normalized BMKG snapshot, timestamp/staleness calculation, a last-valid local cache, configurable rainfall rules, and deterministic suggestion generation.

## Implemented
- `application/weather_snapshot.dart`: source attribution, update/fetch timestamps, validation, and stale calculation.
- `application/weather_rule.dart` and `weather_suggestion.dart`: configuration-only thresholds and suggestion-only evaluation.
- `data/weather_snapshot_cache.dart`: persisted last valid snapshot; older/equal and concurrent stale writes do not replace newer data.
- Unit tests: `test/features/weather/weather_suggestion_test.dart`.

## Not yet production-operational
- No BMKG HTTP adapter, source response normalization, scheduled refresh, production weather rules, or operator review UI exists.
- Staleness is computed in the model but is not presented by a weather screen.
- Suggestions are not persisted or connected to a human confirmation and task catalog flow.
- A cache test does not prove a live BMKG fetch failure path.

## Invariants
- Thresholds have no hidden defaults; they must be configured (FR-WTH-003).
- Stale snapshots do not produce suggestions (AT-008 support).
- Evaluation returns `WeatherSuggestion` values only; it has no campaign activation/distribution operation (AT-001 support).
