# Guyub.id Requirements Traceability

This file reports repository evidence. It does not convert a domain unit test into proof of backend, device, pilot, or production behavior. Statuses are based on the implementation branch, not unmerged remote branches.

## Phase status

| Phase | Status | Verified evidence | Remaining release blockers |
|---|---|---|---|
| 0 — Foundation | COMPLETE_AND_VERIFIED | Flutter app, environment config, `LocalStore`, result/error types, secret-free Firebase build configuration, Auth/Firestore emulator wiring and rules, `./tool/verify.sh`, Android debug build, CI workflow, emulator security test runner. | Device-level UI inspection remains manual. |
| 1 — Role and RT context | PARTIAL | Role selection; Firebase email/password operator sign-in; active `/operators/{uid}` membership check; backend-issued resident RT-code sessions with SHA-256 token-hash storage, seven-day expiry, validation/revocation callables, secure client token storage, idempotent enrollment retries, production App Check enforcement/Android Play Integrity activation, and minimal resident profiles; fail-closed Firestore rules and Auth/Firestore/Functions emulator tests. | Trusted operator provisioning, production RT join-code provisioning, App Check app registration/signing, and an approved per-RT enrollment quota remain external; no device-level UI check. |
| 2 — Safe task catalog/operator creation | PARTIAL | Callable catalog/draft/activation boundary; template content is returned only for enabled, reviewed versions; password operator membership is checked and RT scope is server-derived; activation rechecks the immutable template fingerprint, writes an RT-owned campaign and one audit record transactionally; replay/concurrency, forged content, cross-RT, privacy and widget tests. | No real human-reviewed template content is provisioned; the catalog therefore opens empty until trusted provisioning. No notification/recipient distribution exists. |
| 3 — Resident task loop/RT verification | PARTIAL | Pull-based active task list, locked safety detail, voluntary JOIN/DECLINE, optional bounded completion note, `PENDING_RT_VERIFICATION`, same-RT operator queue/verification, deterministic audit, and response-only recap; Functions/Firestore Emulator and widget/domain tests. | Online-only; no durable offline outbox/cache/reconciliation, proxy update, campaign cancellation/history, recipient snapshot, or device-level validation. |
| 4 — BMKG weather/suggestions | PARTIAL | Normalized timestamped BMKG snapshot, local last-valid cache, configurable threshold model, stale-data exclusion, deterministic suggestion-only evaluator. | No BMKG adapter/fetch schedule, production rules, persisted suggestion, review UI, or human-confirmed task connection. |
| 5 — Distribution/FCM/reminders/escalation | MISSING | Resident-session callable Functions exist, but no notification/delivery Functions are implemented. | No FCM, scheduler, reminder/escalation policy or audit delivery path. |
| 6 — Proposals/assistance | MISSING | — | No proposal review/catalog mapping, vulnerable-resident/helper flow, or proxy status. |
| 7 — Offline/emergency mode | PARTIAL | Local weather snapshot cache survives refresh failures by not overwriting on older/equal input; stale timestamp calculation is tested. | No active-task cache/queue/reconciliation, emergency directory, assembly-point UI, offline UI state or official route. |
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
| AT-006 | MISSING | No synchronized active-task cache or rendered offline task. |
| AT-007 | MISSING | No emergency contacts/assembly-points directory or offline screen. |
| AT-008 | PARTIAL | Snapshot calculates stale state; no weather UI currently presents timestamp/staleness. |
| AT-009 | VERIFIED | Functions service and emulator tests assert that a resident profile contains only the minimal RT-scoped fields; NIK, full address, and precise GPS fields are absent. |
| AT-010 | MISSING | No image metadata stripping or storage fixture test. |
| AT-011 | MISSING | No evidence retention/deletion. |
| AT-012 | MISSING | Proposal workflow is absent. |
| AT-013 | MISSING | No configured official reporting route. |
| AT-014 | MISSING | No proxy update path. |
| AT-015 | MISSING | No RT-owned persistent history/handover path. |

## Security matrix

| ID | Status | Evidence / gap |
|---|---|---|
| S-01 | PARTIAL | Client reads/writes for templates, campaigns, responses, and audit remain denied. Emulator tests cover callable-only resident responses, password Auth/active membership for operator verification, session tokens, and direct task-response access denial. Other future workflows remain unimplemented. |
| S-02 | PARTIAL | Campaign activation and response verification derive RT from trusted membership; resident task list/response and operator verification reject cross-RT access in Functions Emulator tests. Proposal, proxy, and future task endpoints remain unimplemented. |
| S-03 | PARTIAL | Resident enrollment, campaign draft/activation, participation, completion submission, and verification use hashed IDs/state guards; emulator tests cover concurrent choice/completion/verification and one audit. Offline outbox, reminders, and delivery idempotency remain unimplemented. |
| S-04 | MISSING | No reminders/escalation scheduler. |
| S-05 | VERIFIED | Functions emulator tests show malformed and unknown RT codes return the same generic permission error with no RT/resident disclosure. |
| S-06 | PARTIAL | Resident task reads/writes derive resident and RT from validated session records and recheck scope in transactions; activation/verification derive RT from trusted operator membership. Other future task/proposal flows remain unimplemented. |
| S-07 | PARTIAL | Task responses and completion verification are callable-only; residents cannot set verified state, and same-RT operator verification writes one deterministic audit record. Other future state transitions remain out of scope. |
| S-08 | MISSING | Proposal workflow is absent. |

## Offline and privacy matrix

| ID | Status | Evidence / gap |
|---|---|---|
| O-01 | MISSING | Active task + safety instruction offline read is not implemented. |
| O-02 | MISSING | No offline JOIN queue. |
| O-03 | MISSING | No offline DECLINE queue. |
| O-04 | MISSING | No cancellation/reconciliation conflict handling. |
| O-05 | PARTIAL | Cache preserves the newer valid snapshot and tests older/concurrent writes; live fetch-failure behavior is not connected. |
| O-06 | MISSING | FCM/WhatsApp distribution is not implemented. |
| P-01 | VERIFIED | The resident profile contains only nickname, RT scope, assistance marker, creator attribution, and timestamps; unit/emulator tests assert the exact persisted field set. |
| P-02 | MISSING | No evidence pipeline. |
| P-03 | MISSING | No physical evidence deletion. |
| P-04 | MISSING | No same-device resident deletion path. |
| P-05 | MISSING | No RT-assisted deletion process. |
| P-06 | MISSING | No vulnerable-resident presentation. |

## Verification evidence

Commands run on this branch:

- `./tool/verify.sh` — passed: Dart format, `flutter analyze`, all 68 Flutter tests, and `flutter build apk --debug`.
- `./tool/test_firestore_rules.sh` — 5 Auth/Firestore Emulator authorization tests passed using a demo project only.
- `./tool/test_functions.sh` — 19 Functions service tests and 4 Auth/Firestore/Functions Emulator integration tests passed using Node 22, Java 21, and demo projects.
- `npm ci --prefix functions` — completed and reported 0 vulnerabilities.
- No Android device/emulator was available; no device-level visual check is claimed.

## Manual/external validation still required

All eight pilot checks in `docs/TEST_ACCEPTANCE_MATRIX.md` remain MANUAL / EXTERNAL VALIDATION REQUIRED. In particular, a local stakeholder must approve safe templates, the pilot must supply verified emergency/assembly/official-route configuration, operator accounts must be provisioned, and residents/operators must test usability. No production Firebase service was contacted and no billing was enabled. Firebase client options and the tracked Google Services file were removed from source control; runtime production options now require compile-time defines.
