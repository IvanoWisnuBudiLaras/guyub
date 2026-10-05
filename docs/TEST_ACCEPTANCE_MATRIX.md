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
| AT-010 | Evidence location metadata stripped | Server re-encodes a synthetic geotagged fixture; emulator inspects stored bytes and verifies direct resident read/write and Firestore metadata access are denied | Functions service + Storage emulator | Yes |
| AT-011 | Evidence expires after 30 days | Seed an expired Firestore record and Storage object; run cleanup and assert physical deletion; inject a storage delete failure and assert retry-pending state; overlap resident deletion with a pending upload and assert deletion waits, then succeeds after upload completion with failed object cleanup retained for retry | Functions service + Storage emulator | Yes |
| AT-012 | Proposal maps only to a reviewed-template DRAFT | Submit hazardous proposal; RT selects an approved template and explicit slots; assert draft snapshot contains only template instructions, remains absent from resident active tasks, and requires a separate authorized activation | Functions emulator + Flutter | Yes |
| AT-013 | Official escalation route exists | Configured per-RT HTTPS/telephone routes launch only after a tap; unconfigured, load-error, invalid-URI, and failed-handoff states expose no unsafe action | Flutter widget + Functions validation | Yes |
| AT-014 | RT proxy status and profile recovery are safe | Same-RT operators can update proxy or self-enrolled profiles only after consent; conflicting resident choices are preserved; completion stays pending; uncertain proxy creation replays one persisted request; a 200-row cap is disclosed; incomplete deletion remains visible for retry | Functions Emulator + Flutter | Yes |
| AT-015 | RT history and lifecycle events survive operator change | Create, activate, then explicitly close a task; replace the operator; verify CLOSED history and only event types/timestamps; confirm closure does not verify completion | Functions Emulator + Flutter | Yes |
| AT-016 | WhatsApp summary is copy-only and active-only | Draft has no copy action; active copy contains locked safety/voluntary text and sends no message | Unit + widget | Yes |
| AT-017 | Active campaign cancellation is authorized and audited | Same-RT operator cancels; exactly one audit event; replay is idempotent; resident list excludes it | Functions Emulator + widget | Yes |
| AT-018 | Offline completion replays without a note | No-note completion is queued once, replayed idempotently, and remains pending RT verification | Unit + Functions Emulator | Yes |
| AT-019 | Offline completion note is never queued | Nonempty note is rejected offline and absent from persistent outbox | Unit + widget | Yes |
| AT-020 | Helper assignment is opt-in, private, and voluntary | Resident opts in; same-RT operator offers a pairing only to an opted-in helper; helper response hides household identity; decline/withdrawal is allowed; cross-RT and replay cases remain scoped/idempotent | Functions Emulator + Flutter | Yes |
| AT-021 | RT-assisted resident-data deletion is scoped and retryable | Require same-RT operator, resident-request and pilot identity attestations; delete sessions/profile/responses/proposals/assignments/evidence; retain only privacy-safe audit and a minimal enrollment replay tombstone without resident/session identifiers; active upload leases block completion until expiry, then cleanup retries without reopening resident writes | Functions Emulator + Storage Emulator + Flutter | Yes |
| AT-022 | Uncertain proxy creation is RT-bound and safely reconcilable | Cross-RT retry is blocked before the payload is shown; backend cancellation tombstones a missing create; concurrent create/cancel cannot both commit; confirmed creation clears only the local retry payload and leaves server data intact | Functions Emulator + Flutter | Yes |

---

## Additional security matrix

| SEC | Scenario | Expected |
|---|---|---|
| S-01 | Resident attempts direct protected Firestore write | Denied |
| S-02 | Operator A tries RT B task activation, close, or lifecycle-event read | Denied |
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
| O-04 | Server task cancelled or closed before queued participation/completion sync | Client surfaces conflict; does not silently restore task or completion state |
| O-05 | BMKG fetch fails | Last valid snapshot retained with timestamp |
| O-06 | FCM fails | Task remains available through app/WhatsApp copy path |
| O-07 | Resident submits completion offline without a note | One durable idempotent command replays after reconnect; server still requires RT verification |
| O-08 | Resident enters a completion note while offline | Note is never persisted or queued; UI asks resident to retry online |

---

## Privacy/data-lifecycle matrix

| PRV | Scenario | Expected |
|---|---|---|
| P-01 | New resident profile | Only minimal documented fields persisted, including an opt-in helper willingness flag; no sensitive details |
| P-02 | Evidence photo contains EXIF GPS | Stored object has location metadata removed |
| P-03 | Evidence becomes >30 days old | Scheduled deletion physically removes object |
| P-04 | Same-device resident deletion | Only own scoped data can be requested/deleted; full same-device profile/response/proposal deletion remains open |
| P-05 | Lost device resident asks deletion | Same-RT RT-assisted server deletion requires resident-request and pilot-defined offline identity-check attestations; pilot procedure must be approved |
| P-06 | UI shows vulnerable resident | RT-only profile display uses nickname/optional house number/assistance marker; no diagnosis or public household details |

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

Phase 8 evidence emulator coverage is included in `functions/test/task_evidence_emulator.test.js`; this Java 17 host cannot run the Firebase CLI 15 emulator suite, which requires Java 21. CI uses Java 21. No production bucket, scheduled job, or billing change is configured.
