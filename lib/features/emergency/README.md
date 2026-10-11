# Feature: Emergency & Escalation (Darurat)

**Status: PARTIAL.** The callable-only emergency directory, strict client parser, revision-aware cache, signed-out offline route, and resident-session refresh are implemented. The directory stays visibly unconfigured until trusted pilot data is provisioned and verified.

## Implemented
- `application/`: Session-scoped callable and cache boundaries, response models, and controller state.
- `data/`: Firebase callable adapter and RT/resident-scoped local cache. A separate public latest copy supports signed-out offline access and always carries the RT scope label.
- `presentation/`: Darurat screen shows contacts, assembly points, official channels, last sync/verification timestamps, offline state, and a clear official-service disclaimer.
- Flutter tests cover strict schema/bounds, corrupt/older/conflicting revisions, disabled-revision invalidation, RT isolation, no-session display, and direct client Firestore denial in the Functions Emulator suite.

## Provisioning and release blockers
- No phone numbers, assembly locations, official reporting routes, or trusted directory documents are seeded in this repository.
- A local stakeholder must provide and verify all pilot values and `lastVerifiedAt`; production directory provisioning is not implemented in the client.
- Android airplane-mode/device validation remains open. Guyub.id does not replace SAR, BPBD, or other official emergency services (AT-007, AT-013).
