# Feature: Tasks (Tugas Kesiapsiagaan)

**Status: PARTIAL.** Operator catalog and explicit activation plus the online resident response/RT verification loop use callable Functions. Offline task cache/outbox, notification delivery, and production template provisioning remain incomplete.

## Implemented
- `application/task_template.dart`: versioned catalog template, locked core/safety text, and optional estimated duration.
- `application/task_campaign.dart` and `task_campaign_boundary.dart`: draft/activation model, immutable template snapshots, and stable retry IDs.
- `application/task_location_reference.dart`: controlled coarse-location categories; free-text task notes and locations are disabled to prevent unsafe instructions and personal data.
- `data/firebase_task_campaign_boundary.dart`: callable-only catalog/draft/activation adapter; the client cannot write template, campaign, or audit collections.
- `functions/src/task_campaign_service.js` and `firestore_task_campaign_repository.js`: approved/enabled template validation, password-operator check, RT membership recheck, RT-derived ownership, immutable template fingerprint, deterministic draft ID, explicit activation, and one audit record.
- Operator catalog/editor/confirmation screens show locked instructions and permit only a future deadline and controlled location category. Activation clearly states that automatic messages are not available.
- `application/task_response_boundary.dart` and `data/firebase_task_response_boundary.dart`: callable-only resident response, RT verification, and recap boundary. The bearer token stays in secure storage and is not exposed to widgets.
- `functions/src/task_response_service.js` and `firestore_task_response_repository.js`: RT-derived active-task listing; voluntary JOINED/DECLINED; optional completion note with server-side privacy checks; pending RT verification; RT-scoped verification and deterministic audit; response-only recap. Resident session/profile scope is rechecked in transactions. Raw tokens and command IDs are not persisted.
- Resident task list/detail screens show locked safety text before action, equal join/decline choices, and `Menunggu Verifikasi RT`. Operator screens show a same-RT verification queue and an aggregate recap without a non-response denominator. Online-only error states are explicit.
- Unit, widget, Firestore rules, and Auth/Firestore/Functions Emulator tests cover the safe empty catalog, locked instructions, controlled locations, voluntary participation, note privacy checks, session/RT scope, direct-access denial, pending and verified transitions, replay/concurrency, and audit idempotency.
## Not yet production-operational
- No real human-reviewed task template is provisioned. Emulator fixtures are test-only; the catalog intentionally stays empty until trusted provisioning.
- No recipient/eligibility snapshot exists. Pull visibility after activation is implemented, but no FCM/WhatsApp message, reminder, or delivery claim exists. Recap counts recorded responses only and cannot count residents who have not responded.
- No offline active-task cache, durable command outbox, sync reconciliation, task cancellation/history, or device-level visual validation is implemented here.
- Firebase App Check registration/signing, trusted operator/RT provisioning, production deployment, and pilot validation remain external.

## Invariants
- Weather suggestions do not create or activate campaigns (AT-001).
- Catalog content and safety instructions come only from trusted reviewed versions; campaigns snapshot the exact version (AT-002/003).
- Only an authorized operator can activate same-RT drafts or verify same-RT completions; Firestore client access stays denied.
- Participation is voluntary and has no penalty/ranking state (AT-004).
- Resident completion remains pending until operator verification (AT-005); no resident command can set the verified state.
- Offline acceptance criteria remain open; online-only behavior is shown honestly (AT-006, O-01–O-04).
