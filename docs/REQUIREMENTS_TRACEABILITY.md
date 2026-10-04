# Guyub.id Requirements Traceability

This file reports repository evidence. It does not convert a domain unit test into proof of backend, device, pilot, or production behavior. Statuses are based on the implementation branch, not unmerged remote branches.

## Phase status

| Phase | Status | Verified evidence | Remaining release blockers |
|---|---|---|---|
| 0 — Foundation | COMPLETE_AND_VERIFIED | Flutter app, environment config, `LocalStore`, result/error types, secret-free Firebase build configuration, Auth/Firestore emulator wiring and rules, `./tool/verify.sh`, Android debug build, CI workflow, emulator security test runner. | Device-level UI inspection remains manual. |
| 1 — Role and RT context | PARTIAL | Role selection; Firebase email/password operator sign-in; active `/operators/{uid}` membership check; backend-issued resident RT-code sessions with SHA-256 token-hash storage, seven-day expiry, validation/revocation callables, secure client token storage, idempotent enrollment retries, production App Check enforcement/Android Play Integrity activation, and minimal resident profiles; fail-closed Firestore rules and Auth/Firestore/Functions emulator tests. | Trusted operator provisioning, production RT join-code provisioning, App Check app registration/signing, and an approved per-RT enrollment quota remain external; no device-level UI check. |
| 2 — Safe task catalog/operator creation | PARTIAL | Immutable task template snapshot, limited draft parameters, explicit activation transition, basic validation and replay test. | No human-approved catalog data, catalog boundary implementation, task UI, Firestore campaign path, server-side activation authorization, or audit event. Editable additional notes remain disabled pending a reviewed mechanism. |
| 3 — Resident task loop/RT verification | PARTIAL | Voluntary JOIN/DECLINE domain model and pending-verification/RT-scope transition tests; resident session admission now exists. | No resident task UI, persisted response, task backend authorization, verification queue, or recap. |
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
| AT-002 | PARTIAL | Draft requires a `TaskTemplate` and rejects disabled/invalid content; no trusted catalog or backend validation exists, so this is not proof against a client bypass. |
| AT-003 | PARTIAL | Template fields are final and campaigns preserve a versioned snapshot; domain test. No operator UI/backend test. |
| AT-004 | PARTIAL | Decline is a valid domain state with no penalty/ranking state; widget/backend path is not present. |
| AT-005 | PARTIAL | Submission becomes `pendingRtVerification` and only the domain verification method makes it complete; no authenticated backend transition exists. |
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
| S-01 | PARTIAL | Firestore rules deny client access to protected collections; Functions emulator tests prove unauthenticated direct resident-profile reads/writes are denied while callable session operations work. Task-specific protected operations are not implemented yet. |
| S-02 | PARTIAL | Rules and emulator test deny reading another operator's membership. No RT-scoped task operation exists yet. |
| S-03 | PARTIAL | Enrollment retries use a random secure idempotency key and reuse the profile/rotate the session transactionally; unit and Functions emulator replay tests. Domain activation also uses an idempotency command ID. Persisted campaign commands are not implemented yet. |
| S-04 | MISSING | No reminders/escalation scheduler. |
| S-05 | VERIFIED | Functions emulator tests show malformed and unknown RT codes return the same generic permission error with no RT/resident disclosure. |
| S-06 | PARTIAL | Session tokens are opaque and server-bound to their stored RT; a caller-supplied alternate community ID cannot change the validated RT. No task/read/write endpoint exists yet to test cross-RT access denial. |
| S-07 | PARTIAL | All unconfigured resident writes are denied; there is no completion-verification backend command to test. |
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

- `./tool/verify.sh` — passed: Dart format, `flutter analyze`, full Flutter test suite, and `flutter build apk --debug`.
- `./tool/test_firestore_rules.sh` — 5 Auth/Firestore Emulator authorization tests passed using a demo project only.
- `./tool/test_functions.sh` — 8 service tests and 2 Functions/Firestore Emulator integration tests passed using Node 22, Java 21, and demo projects.
- `npm audit --prefix functions --omit=dev` — passed; 0 vulnerabilities.
- No Android device/emulator was available; no device-level visual check is claimed.

## Manual/external validation still required

All eight pilot checks in `docs/TEST_ACCEPTANCE_MATRIX.md` remain MANUAL / EXTERNAL VALIDATION REQUIRED. In particular, a local stakeholder must approve safe templates, the pilot must supply verified emergency/assembly/official-route configuration, operator accounts must be provisioned, and residents/operators must test usability. No production Firebase service was contacted and no billing was enabled. Firebase client options and the tracked Google Services file were removed from source control; runtime production options now require compile-time defines.
