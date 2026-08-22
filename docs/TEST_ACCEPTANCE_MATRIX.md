# Guyub.id — Test & Acceptance Matrix

This matrix maps implementation behavior back to the Master PRD. It is intended to prevent an AI coding agent from finishing only the visible UI while missing safety, authorization, or offline requirements.

| ID | Requirement | Minimum verification | Layer | Release blocking |
|---|---|---|---|---|
| AT-001 | Weather threshold cannot auto-send | Trigger rule; assert suggestion exists and ACTIVE task does not | Integration | Yes |
| AT-002 | Unsafe/free-form task blocked | Attempt activation without safe template | Backend integration | Yes |
| AT-003 | Safety text immutable | Edit allowed task slots; compare safety snapshot | Unit + widget | Yes |
| AT-004 | Resident can decline voluntarily | Choose decline; assert valid state and no penalty state | Widget + integration | Yes |
| AT-005 | Completion requires RT verification | Submit completion; assert pending until operator verifies | Integration | Yes |
| AT-006 | Active task readable offline | Sync task, disable network, reopen/view task | E2E/manual/device | Yes |
| AT-007 | Emergency info readable offline | Sync directory, disable network, open Darurat | E2E/manual/device | Yes |
| AT-008 | Cached weather marked stale/timestamped | Disable network; inspect weather UI | Widget + E2E | Yes |
| AT-009 | Forbidden PII absent | Schema/input audit for NIK/full address/GPS | Static/review | Yes |
| AT-010 | Evidence location metadata stripped | Upload geotagged fixture, inspect stored file metadata | Integration | Yes |
| AT-011 | Evidence expires after 30 days | Seed expired evidence; run cleanup; assert object deleted | Backend integration | Yes |
| AT-012 | Resident proposal cannot activate | Submit proposal; assert no ACTIVE task without RT flow | Integration | Yes |
| AT-013 | Official escalation route exists | Classify outside-capacity problem; assert configured official action | Widget/integration | Yes |
| AT-014 | Proxy status supported | Authorized operator updates non-app resident status | Integration | Yes |
| AT-015 | RT history survives operator change | Create history, replace operator, verify history | Integration/E2E | Yes |

---

## Additional security matrix

| SEC | Scenario | Expected |
|---|---|---|
| S-01 | Resident attempts direct protected Firestore write | Denied |
| S-02 | Operator A tries RT B task activation | Denied |
| S-03 | Replayed task activation command | No duplicate task |
| S-04 | Replayed reminder scheduler run | No duplicate reminder for same policy window |
| S-05 | Invalid RT code enumeration attempt | Generic failure; no RT/resident disclosure |
| S-06 | Resident token used for another RT | Denied |
| S-07 | Resident attempts to verify own completion | Denied |
| S-08 | Resident proposal contains arbitrary risky instructions | Stored as proposal only; never executable directly |

---

## Offline/reconciliation matrix

| OFF | Scenario | Expected |
|---|---|---|
| O-01 | App offline after task was synchronized | Task + safety instruction visible |
| O-02 | Resident joins task offline | Local pending state; single server transition after reconnect |
| O-03 | Resident declines offline | Local pending state; single server transition after reconnect |
| O-04 | Server task cancelled before queued completion sync | Client surfaces conflict; does not silently restore task |
| O-05 | BMKG fetch fails | Last valid snapshot retained with timestamp |
| O-06 | FCM fails | Task remains available through app/WhatsApp copy path |

---

## Privacy/data-lifecycle matrix

| PRV | Scenario | Expected |
|---|---|---|
| P-01 | New resident profile | Only minimal documented fields persisted |
| P-02 | Evidence photo contains EXIF GPS | Stored object has location metadata removed |
| P-03 | Evidence becomes >30 days old | Scheduled deletion physically removes object |
| P-04 | Same-device resident deletion | Only own scoped data can be requested/deleted |
| P-05 | Lost device resident asks deletion | Authorized RT-assisted process available |
| P-06 | UI shows vulnerable resident | No unnecessary public sensitive detail |

---

## Manual pilot checks

Some proposal goals require human validation and cannot be proven by automated tests alone:

1. Can a resident understand a preparation task without additional explanation?
2. Can an elderly/less technical participant identify “Ikut”, “Tidak Ikut”, and “Darurat”?
3. Does the RT operator understand that BMKG information is forecast context, not an RT-level flood prediction?
4. Does the operator notice and understand the confirmation screen before sending?
5. Are safe task templates locally appropriate?
6. Are official reporting routes correct for the pilot location?
7. Are emergency contacts and assembly points current and verified?
8. Can an RT handover preserve preparedness history without relying on the old leader’s phone?

A pilot finding may change configuration and wording, but must not weaken the safety/privacy invariants without an explicit product decision.
