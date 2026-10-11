# Feature: Tasks (Tugas Kesiapsiagaan)

**Status: PARTIAL.** Operator catalog, activation/cancellation, and resident response/RT verification use callable Functions. A scoped offline task cache/outbox and read-only stale-state UI are implemented; notification delivery, production template provisioning, and airplane-mode device validation remain incomplete.

## Implemented
- `application/task_template.dart`: versioned catalog template, locked core/safety text, and optional estimated duration.
- `application/task_campaign.dart` and `task_campaign_boundary.dart`: draft/activation model, immutable template snapshots, and stable retry IDs.
- `application/task_location_reference.dart`: controlled coarse-location categories; free-text task notes and locations are disabled to prevent unsafe instructions and personal data.
- `data/firebase_task_campaign_boundary.dart`: callable-only catalog/draft/activation adapter; the client cannot write template, campaign, or audit collections.
- `functions/src/task_campaign_service.js` and `firestore_task_campaign_repository.js`: approved/enabled template validation, password-operator check, RT membership recheck, RT-derived ownership, immutable template fingerprint, deterministic draft ID, explicit activation, audited ACTIVE→CANCELLED transition, same-RT active list, and idempotent cancellation audit.
- Operator catalog/editor/confirmation screens show locked instructions and permit only a future deadline and controlled location category. After activation, the operator can copy a human-readable WhatsApp summary with locked safety text and voluntary-participation copy; this never sends a message. Activation clearly states that automatic notifications are not available.
- `application/task_response_boundary.dart` and `data/firebase_task_response_boundary.dart`: callable-only resident response, RT verification, and recap boundary. The bearer token stays in secure storage and is not exposed to widgets.
- `functions/src/task_response_service.js` and `firestore_task_response_repository.js`: RT-derived active-task listing; voluntary JOINED/DECLINED; optional completion note with server-side privacy checks; pending RT verification; RT-scoped verification and deterministic audit; response-only recap. Resident session/profile scope is rechecked in transactions. Raw tokens and command IDs are not persisted.
- `LocalResidentTaskOfflineStore` uses RT/resident-hashed scope keys. It stores only server-authorized active task snapshots and durable JOIN/DECLINE and no-note completion commands with stable IDs/retry metadata. Tokens and completion notes are never stored in the outbox. Reconnect refresh replays through callable Functions and preserves server conflicts.
- Resident task list/detail screens show locked safety text before action, equal join/decline choices, and `Menunggu Verifikasi RT`. Operator screens show a same-RT verification queue and an aggregate recap without a non-response denominator. Online-only error states are explicit.
- Unit, widget, Firestore rules, and Auth/Firestore/Functions Emulator tests cover the safe empty catalog, locked instructions, controlled locations, voluntary participation, note privacy checks, session/RT scope, direct-access denial, pending and verified transitions, replay/concurrency, and audit idempotency.
## Not yet production-operational
- No real human-reviewed task template is provisioned. Emulator fixtures are test-only; the catalog intentionally stays empty until trusted provisioning.
- No recipient/eligibility snapshot exists. Pull visibility after activation is implemented, but no FCM/WhatsApp message, reminder, or delivery claim exists. Recap counts recorded responses only and cannot count residents who have not responded.
- Offline active-task cache, durable outbox, reconnect reconciliation, and the cancellation UI are implemented with unit/widget coverage. Cancellation replay, same-RT denial, audit, and resident active-list exclusion pass the Functions Emulator suite. Full airplane-mode Android device validation remains a release gate; campaign history/handover and cancellation notification delivery are not implemented.
- Firebase App Check registration/signing, trusted operator/RT provisioning, production deployment, and pilot validation remain external.

## Invariants
- Weather suggestions do not create or activate campaigns (AT-001).
- Catalog content and safety instructions come only from trusted reviewed versions; campaigns snapshot the exact version (AT-002/003).
- Only an authorized operator can activate same-RT drafts or verify same-RT completions; Firestore client access stays denied.
- Participation is voluntary and has no penalty/ranking state (AT-004).
- Resident completion remains pending until operator verification (AT-005); no resident command can set the verified state.
- Offline UI labels cached data and server-confirmed status separately; choice conflicts and no-note completion sync remain pending until server response/RT verification (AT-006, AT-017–AT-019, O-01–O-08). Airplane-mode device testing is still required.
