# Guyub.id Requirements Traceability

This file reports repository evidence. It does not convert a domain unit test into proof of backend, device, pilot, or production behavior. Statuses are based on the implementation branch, not unmerged remote branches.

## Phase status

| Phase | Status | Verified evidence | Remaining release blockers |
|---|---|---|---|
| 0 — Foundation | COMPLETE_AND_VERIFIED | Flutter app, environment config, `LocalStore`, result/error types, secret-free Firebase build configuration, Auth/Firestore emulator wiring and rules, `./tool/verify.sh`, Android debug build, CI workflow, emulator security test runner. | Device-level UI inspection remains manual. |
| 1 — Role and RT context | PARTIAL | Role selection; Firebase email/password operator sign-in; active `/operators/{uid}` membership check; backend-issued resident RT-code sessions with SHA-256 token-hash storage, seven-day expiry, validation/revocation callables, secure client token storage, idempotent enrollment retries, production App Check enforcement/Android Play Integrity activation, and minimal resident profiles; fail-closed Firestore rules and Auth/Firestore/Functions emulator tests. | Trusted operator provisioning, production RT join-code provisioning, App Check app registration/signing, and an approved per-RT enrollment quota remain external; no device-level UI check. |
| 2 — Safe task catalog/operator creation | PARTIAL | Callable catalog/draft/activation boundary; template content is returned only for enabled, reviewed versions; password operator membership is checked and RT scope is server-derived; activation rechecks the immutable template fingerprint, writes an RT-owned campaign and one audit record transactionally; replay/concurrency, forged content, cross-RT, privacy and widget tests. | No real human-reviewed template content is provisioned; the catalog therefore opens empty until trusted provisioning. No notification/recipient distribution exists. |
| 3 — Resident task loop/RT verification | PARTIAL | Pull-based active task list, locked safety detail, voluntary JOIN/DECLINE, optional bounded completion note, `PENDING_RT_VERIFICATION`, same-RT operator queue/verification, deterministic audit, and response-only recap; Functions/Firestore Emulator and widget/domain tests. Phase 7 adds the scoped offline cache/outbox. | Proxy update, RT-owned history/handover, recipient snapshot, notifications, and device-level validation remain incomplete. |
| 4 — BMKG weather/suggestions | PARTIAL | Normalized timestamped BMKG snapshot, local last-valid cache, configurable threshold model, stale-data exclusion, deterministic suggestion-only evaluator. | No BMKG adapter/fetch schedule, production rules, persisted suggestion, review UI, or human-confirmed task connection. |
| 5 — Distribution/FCM/reminders/escalation | PARTIAL | Active campaigns provide a copy-only, human-readable WhatsApp summary with locked safety text and voluntary-participation copy; no message is sent. An active same-RT campaign can be explicitly cancelled through a callable with one deterministic RT-owned audit event. | No FCM delivery, cancellation/update notification, scheduler, reminder/escalation policy, recipient snapshot, or delivery audit path. |
| 6 — Proposals/assistance | PARTIAL | Callable resident proposal submission, same-RT operator queue, idempotent dismissal/audit, resident form, and review UI; dangerous wording remains proposal-only. | No safe-template draft mapping, official-report route, evidence, assistance/proxy status, or helper assignment. |
| 7 — Offline/emergency mode | PARTIAL | Resident session restores a secure display-only profile on transient outages; authorized active-task snapshots use RT/resident-hashed cache keys; durable JOIN/DECLINE and no-note completion commands replay through callable Functions with conflicts preserved; cached task UI shows stale time/queue state; emergency directory uses a session-scoped callable and revisioned public offline cache; weather card shows the cached snapshot and both timestamps. Flutter unit/widget tests cover parsing, scope, cache, outbox, conflicts, and display; Functions Emulator tests verify session-derived directory scope and deny direct directory reads/writes. | Android airplane-mode/device validation, live BMKG adapter/refresh, trusted verified pilot directory values, and configured official routes remain external/release blockers. |
| 8 — Evidence/data lifecycle | MISSING | — | No image processing, EXIF stripping, storage, expiry/delete job, or data deletion workflow. |
| 9 — History/pilot hardening | MISSING | — | No RT-owned campaign history/handover, pilot configuration, accessibility or stakeholder validation. |

## Acceptance matrix

| ID | Status | Evidence / gap |
|---|---|---|
| AT-001 | PARTIAL | `WeatherRuleEvaluator` only returns deterministic suggestions and never creates campaigns; unit test. No scheduled source or persisted active-task integration. |
| AT-002 | PARTIAL | Callable tests reject arbitrary core/safety text and notes, free-text locations, forged RT/operator fields, unreviewed/disabled/malformed templates, and invalid location categories; activation is callable-only. Real human-reviewed template data is not provisioned, so no production task can be activated yet. |
| AT-003 | PARTIAL | Widget shows locked core/safety instructions; callable drafts snapshot the exact version and activation rejects same-version content mutation; unit, widget, and Functions Emulator replay tests. Real reviewed content remains an external prerequisite. |
| AT-004 | VERIFIED | Resident UI presents balanced JOIN/DECLINE actions and states that decline has no penalty; callable persistence accepts either state and rejects changes; domain, widget, Functions Emulator replay tests. |
| AT-005 | VERIFIED | Completion callable creates only `PENDING_RT_VERIFICATION`; password-authenticated same-RT operator verification is a separate transaction with one audit record. Emulator tests cover replay, concurrency, cross-RT denial, and server-authored verifier/time. |
| AT-006 | PARTIAL | Authorized task snapshots, locked safety text, and scope-isolated offline reads are covered by unit/widget tests. Android airplane-mode reopen/retry testing remains outstanding. |
| AT-007 | PARTIAL | Session-scoped callable, strict revisioned cache, signed-out Darurat route, RT label, last-sync/verification times, and no-seed state are covered by tests. Verified pilot contacts/assembly points and device testing remain external. |
| AT-008 | PARTIAL | The resident-home card shows cached BMKG data plus source-update/fetch timestamps and marks it non-live; widget tests pass. No BMKG fetch adapter or device airplane-mode test exists. |
| AT-009 | VERIFIED | Functions service and emulator tests assert that a resident profile contains only the minimal RT-scoped fields; NIK, full address, and precise GPS fields are absent. |
| AT-010 | MISSING | No image metadata stripping or storage fixture test. |
| AT-011 | MISSING | No evidence retention/deletion. |
| AT-012 | VERIFIED | Functions unit/emulator tests and Flutter form tests show resident submission stays `SUBMITTED`, a risky proposal creates no campaign/ACTIVE task, and RT review can only dismiss. |
| AT-013 | MISSING | No configured official reporting route. |
| AT-014 | MISSING | No proxy update path. |
| AT-015 | MISSING | No RT-owned persistent history/handover path. |
| AT-016 | PARTIAL | Active-only formatter/widget tests verify locked template text, voluntary wording, no internal identifiers, and a copy-boundary call. Android clipboard behavior has not been device-tested; no message is sent. |
| AT-017 | PARTIAL | Callable-only same-RT list/cancellation, hash-only command IDs, deterministic audit, concurrent/same-command replay, cross-RT denial, and canceled-task exclusion pass Functions service/Emulator tests; confirmation/navigation widget tests pass. Physical pilot usability validation remains open. |
| AT-018 | PARTIAL | Offline no-note completion is queued with a stable idempotency key, replayed through the callable, and remains pending until RT verification; unit tests pass. Full emulator/device validation remains open. |
| AT-019 | PARTIAL | Offline completion notes are never stored or queued; typed UI/error and outbox tests cover retry-online behavior. Device validation remains open. |

## Security matrix

| ID | Status | Evidence / gap |
|---|---|---|
| S-01 | PARTIAL | Client reads/writes for templates, campaigns, responses, proposals, and audit remain denied. Emulator tests cover callable-only proposal/review, resident responses, operator membership, and direct proposal/task-response access denial. Other future workflows remain unimplemented. |
| S-02 | PARTIAL | Campaign activation, response verification, and proposal review derive RT from trusted membership; cross-RT proposal review and task access are denied in Functions Emulator tests. Proxy and future workflows remain unimplemented. |
| S-03 | PARTIAL | Resident enrollment, campaign mutations/cancellation, task responses, verification, proposal submission/dismissal, and offline task outbox use stable command IDs/state guards. The 35 Functions service tests and 6 Emulator integration tests pass, including cancellation replay/one-audit verification. Reminder/delivery idempotency remains unimplemented. |
| S-04 | MISSING | No reminders/escalation scheduler. |
| S-05 | VERIFIED | Functions emulator tests show malformed and unknown RT codes return the same generic permission error with no RT/resident disclosure. |
| S-06 | PARTIAL | Resident task/proposal writes derive resident and RT from validated sessions and recheck scope in transactions; operator proposal review derives RT from trusted membership. Proxy and future workflows remain unimplemented. |
| S-07 | PARTIAL | Task responses, completion verification, and cancellation are callable-only; residents cannot set verified state, and same-RT operator verification/cancellation each write one deterministic audit record. Other future state transitions remain out of scope. |
| S-08 | VERIFIED | Emulator test submits a hazardous proposal and confirms it stays `SUBMITTED`, creates no campaign, and cannot be mapped/activated by proposal review. |

## Offline and privacy matrix

| ID | Status | Evidence / gap |
|---|---|---|
| O-01 | PARTIAL | Authorized task snapshots/safety text are locally cached and displayed with last-sync time; airplane-mode device validation remains open. |
| O-02 | PARTIAL | JOIN is durably queued with a stable command ID and replayed by authorized list refresh; unit/widget tests pass, device validation remains. |
| O-03 | PARTIAL | DECLINE is durably queued with a stable command ID and replayed by authorized list refresh; unit/widget tests pass, device validation remains. |
| O-04 | PARTIAL | Audited server cancellation removes the task from operator/resident active results; replay/cross-RT denial/one-audit behavior passes Functions Emulator tests. Queued commands remain and surface typed conflicts in UI tests; physical Android reconnect validation remains open. |
| O-05 | PARTIAL | Last-valid weather cache preserves newer snapshots and the UI shows source/fetch timestamps as non-live context; no real BMKG fetch path is connected. |
| O-06 | PARTIAL | An operator can copy the active task summary for manual WhatsApp sharing. No FCM delivery, delivery failure handling, reminders, or escalation exist. |
| O-07 | PARTIAL | No-note completion is durably queued/replayed once and remains pending RT verification; unit tests pass, device validation remains. |
| O-08 | PARTIAL | Completion notes are never written to the outbox; UI asks the resident to retry online. Unit/widget tests pass, device validation remains. |
| P-01 | VERIFIED | The resident profile contains only nickname, RT scope, assistance marker, creator attribution, and timestamps; unit/emulator tests assert the exact persisted field set. |
| P-02 | MISSING | No evidence pipeline. |
| P-03 | MISSING | No physical evidence deletion. |
| P-04 | MISSING | No same-device resident deletion path. |
| P-05 | MISSING | No RT-assisted deletion process. |
| P-06 | MISSING | No vulnerable-resident presentation. |

## Verification evidence

Commands run on this branch:

- `./tool/verify.sh` — passed: Dart format, `flutter analyze`, all 125 Flutter tests, and `flutter build apk --debug`.
- `./tool/test_firestore_rules.sh` — 5 Auth/Firestore Emulator authorization tests passed using a demo project only.
- `./tool/test_functions.sh` — 35 Functions service tests and 6 Auth/Firestore/Functions Emulator integration tests passed using Node 22, Java 21, and demo projects.
- `npm ci --prefix functions` — completed and reported 0 vulnerabilities.
- No Android device/emulator was available; no device-level visual check is claimed.

## Manual/external validation still required

All eight pilot checks in `docs/TEST_ACCEPTANCE_MATRIX.md` remain MANUAL / EXTERNAL VALIDATION REQUIRED. In particular, a local stakeholder must approve safe templates, the pilot must supply verified emergency/assembly/official-route configuration, operator accounts must be provisioned, and residents/operators must test usability. No production Firebase service was contacted and no billing was enabled. Firebase client options and the tracked Google Services file were removed from source control; runtime production options now require compile-time defines.
