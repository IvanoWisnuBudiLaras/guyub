# Feature: Weather (BMKG Open Data)

**Status: PARTIAL.** The repository now has a backend BMKG fetch/normalization boundary, RT-scoped last-valid snapshots, reviewed-rule evaluation, deterministic suggestion persistence, and an operator-authenticated read callable. It does not contain pilot sources/rules or a production deployment.

## Implemented
- `application/weather_snapshot.dart`: normalized BMKG attribution, source/fetch timestamps, validation, and stale calculation.
- `application/weather_rule.dart` and `weather_suggestion.dart`: client-domain model with no default rainfall threshold; stale data cannot produce a suggestion.
- `data/weather_snapshot_cache.dart`: local last-valid snapshot cache that does not overwrite a newer snapshot.
- `functions/src/bmkg_forecast_client.js`: HTTPS GET to the allow-listed BMKG public forecast endpoint, redirect rejection, bounded response size, and timeout.
- `functions/src/weather_suggestion_service.js` and `firestore_weather_suggestion_repository.js`: configured source normalization, source-age checks, transactional last-valid server snapshot, reviewed-rule/safe-template checks, deterministic suggestion IDs, and same-RT operator read authorization.
- `syncBmkgWeather` runs on a six-hour schedule when deployed. `listWeatherSuggestions` returns only `SUGGESTED` records to an active password-authenticated operator; it cannot create or activate a campaign.
- Unit tests cover malformed/stale data, last-valid preservation, retries, endpoint boundaries, unreviewed rules, no defaults, and the no-active-campaign invariant. Functions Emulator CI covers persistence and same-RT operator reads.

## Trusted configuration and remaining work
- No `/weather_sources/{rtId}` or `/weather_rules/{rtId}_{ruleId}` documents are seeded. There is no hidden rainfall threshold or pilot location.
- Trusted provisioning must approve the BMKG source, coarse `adm4` area, schema normalization paths, source maximum age, and each versioned rule's threshold, explanation, and reviewed safe-template references. Each template reference binds a SHA-256 fingerprint of normalized approved content; a content change invalidates the rule until a new rule version is reviewed. Suggestions from superseded, disabled, changed, or no-longer-approved rules/templates are hidden. The configured JSON paths must be verified against the current BMKG response schema before pilot use.
- The Android weather card still displays its local cached snapshot; it is not wired to the server pipeline. There is no operator suggestion review UI or explicit suggestion-to-DRAFT action yet.
- Actual BMKG availability, schema mapping, pilot thresholds, local operator review, production Scheduler setup, device offline behavior, and any billing/provider decision remain MANUAL / EXTERNAL. No production function or scheduler is deployed.

## Safety invariants
- Weather is context, not an RT-level flood prediction or official warning.
- A snapshot must be fresh and valid before it can create a suggestion. Failed, malformed, future-dated, or stale data does not replace the last valid snapshot.
- Only explicitly approved rules and enabled, reviewed safe template versions may be recommended.
- Suggestions remain `SUGGESTED`; only a separate authorized human task workflow may create a DRAFT and a further explicit confirmation may activate it.
