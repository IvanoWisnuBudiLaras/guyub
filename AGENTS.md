# AGENTS.md — Guyub.id

## Mission

Build the Guyub.id Android MVP exactly around the product behavior and safety/privacy boundaries defined in `GUYUB_ID_MASTER_PRD_ENGINEERING_SPEC.md`.

The product is a **community flood-preparedness coordination system**, not an RT-level flood prediction engine or official emergency warning service.

## Required reading order

1. `GUYUB_ID_MASTER_PRD_ENGINEERING_SPEC.md`
2. `IMPLEMENTATION_PLAN.md`
3. `TEST_ACCEPTANCE_MATRIX.md`
4. Existing repository documentation and code

If code conflicts with the Master PRD, stop and surface the conflict.

---

## Non-negotiable invariants

1. **No automatic resident task dispatch from weather thresholds.**
   Weather may produce suggestions only. An authorized RT/RW operator must explicitly approve before distribution.

2. **No arbitrary safety-critical task authoring.**
   Resident-facing preparation tasks come from a controlled safe catalog. Core instruction and safety instruction are locked.

3. **Voluntary participation.**
   Residents can join or decline. No ranking, shaming, penalty, or coercive UX.

4. **No hazardous community tasks.**
   Do not create task templates that require entering drains, approaching dangerous flows, or doing professional emergency-response work.

5. **No forbidden personal data.**
   Do not add NIK, full residential address, or precise resident GPS fields.

6. **Offline-critical content must work.**
   Active synchronized tasks, last weather snapshot with timestamp, emergency contacts, and assembly points remain readable offline.

7. **Photo evidence is optional and temporary.**
   Strip location metadata before persistence. Delete evidence after 30 days.

8. **Resident proposals require RT review.**
   A proposal can never become an active task directly.

9. **Completion requires RT verification.**
   Resident submission is not official completion until an authorized operator verifies.

10. **Official escalation stays official.**
    Guyub.id redirects issues outside community capacity to government/emergency channels; it does not claim to replace them.

---

## Technology baseline from proposal

- Flutter for Android.
- Firebase Firestore.
- Firebase Authentication for Ketua RT/RW and Pendamping RT only.
- Firebase Cloud Functions for automation.
- Firebase Cloud Messaging for notifications.
- BMKG Open Data for weather.
- Local/offline persistence.

Engineering extension allowed by the Master PRD:
- Firebase Cloud Storage for optional evidence images.

Do not substitute the stack merely because another framework is preferred. A change needs explicit human approval.

---

## Architecture rules

### RT is the durable ownership boundary

Preparedness history belongs to the RT/community entity, not an individual operator account.

### Backend is the authorization boundary

Never treat hidden buttons as authorization.

- operator actions are verified server-side;
- resident writes are scoped through the approved resident-session mechanism;
- direct unauthenticated mutation of protected Firestore collections is forbidden.

### Weather rules generate suggestions only

Required transition:

```text
BMKG -> normalized snapshot -> rule evaluation -> suggestion -> human review -> active task
```

### Task templates are versioned

An active/historical task stores an immutable snapshot/version of the task template so later template edits do not rewrite history.

### Commands must be idempotent

Offline retry and scheduled jobs must not:
- duplicate campaigns,
- duplicate reminders,
- duplicate completion transitions,
- duplicate evidence cleanup.

---

## Implementation discipline

For each feature:

1. identify corresponding `FR-*` and `AT-*`;
2. write/adjust test first when practical;
3. implement smallest vertical slice;
4. run focused tests;
5. run broader regression tests;
6. update requirement traceability if behavior changes.

Do not implement speculative multi-disaster support, social feeds, gamification, leaderboards, public maps of residents, or unrelated “smart city” features.

---

## UI rules

- Indonesian is the MVP language.
- Role must remain visually clear.
- Safety instructions must be prominent before action.
- `Menunggu Verifikasi RT` must be explicit.
- Offline/cached weather must show timestamp/staleness.
- Decline action must remain available without punishment.
- Emergency screen must be reachable without a network.
- Values shown in proposal mockups (names, telephone numbers, locations) are demo content and must not be hard-coded as production truth.

---

## Data rules

Allowed resident profile minimum:
- nickname,
- optional house number,
- RT scope,
- assistance marker,
- task status.

Forbidden by default:
- NIK,
- full address,
- precise GPS,
- unnecessary birth date,
- public evidence photo URLs.

When a new field is proposed, ask:
1. Is it required to execute a documented workflow?
2. Can the workflow work with a less identifying field?
3. Does it need server persistence?
4. What is its retention/deletion rule?

---

## Error behavior

Never erase last valid weather data because the newest fetch failed.

Never display stale weather as current.

Never block completion merely because optional photo upload failed.

Never silently resolve an offline state conflict by overwriting a server-authoritative safety/authorization state.

---

## Completion gate

A feature is not “done” if it works only on the happy-path UI.

It must pass:
- domain/state tests,
- authorization tests,
- offline/retry tests when applicable,
- requirement-specific acceptance tests.
