# Feature: Weather (BMKG Open Data)

**Status: PARTIAL.** The feature contains a normalized BMKG snapshot, timestamp/staleness calculation, a last-valid local cache, configurable rainfall rules, deterministic suggestion generation, and a resident-home card for the cached snapshot.

## Implemented
- `application/weather_snapshot.dart`: source attribution, update/fetch timestamps, validation, and stale calculation.
- `application/weather_rule.dart` and `weather_suggestion.dart`: configuration-only thresholds and suggestion-only evaluation.
- `data/weather_snapshot_cache.dart`: persisted last valid snapshot; older/equal and concurrent stale writes do not replace newer data.
- `presentation/weather_snapshot_card.dart`: displays the cached rainfall context with source-update and device-fetch timestamps and says it is not a live update or official flood warning.
- Unit tests cover rules, cache persistence, and the offline display card.

## Not yet production-operational
- No BMKG HTTP adapter, source response normalization, scheduled refresh, production weather rules, or operator review UI exists.
- The resident-home card displays saved data and timestamps but does not fetch BMKG or determine connectivity; live refresh and full device validation remain open.
- Suggestions are not persisted or connected to a human confirmation and task catalog flow.
- A cache test does not prove a live BMKG fetch failure path.

## Invariants
- Thresholds have no hidden defaults; they must be configured (FR-WTH-003).
- Stale snapshots do not produce suggestions (AT-008 support).
- Evaluation returns `WeatherSuggestion` values only; it has no campaign activation/distribution operation (AT-001 support).
