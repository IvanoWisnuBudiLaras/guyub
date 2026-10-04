# Feature: Tasks (Tugas Kesiapsiagaan)

**Status: PARTIAL.** Operator catalog, draft, and explicit RT-scoped activation now use callable Functions. The resident response lifecycle, offline task cache, and distribution are not implemented.

## Implemented
- `application/task_template.dart`: versioned catalog template, locked core/safety text, and optional estimated duration.
- `application/task_campaign.dart`: domain draft/activation model and immutable template snapshot.
- `application/task_campaign_boundary.dart`: application boundary and stable idempotency keys across retry.
- `data/firebase_task_campaign_boundary.dart`: callable-only adapter; the client cannot write template, campaign, or audit collections.
- `functions/src/task_campaign_service.js` and `firestore_task_campaign_repository.js`: approved/enabled template validation, password-operator check, RT membership recheck in transactions, RT derived from trusted membership, immutable template fingerprint, deterministic draft id, explicit activation and one deterministic audit record.
- Operator catalog/editor/confirmation screens show locked instructions and permit only a future deadline, a general location reference, and a short logistics note (160 characters). The server rejects address/GPS-like location text and any client attempt to author core/safety text. Activation clearly states that automatic messages are not available.
- Unit, widget, Auth/Firestore/Functions Emulator tests cover empty catalog, locked instructions, explicit confirmation, unauthorized/cross-RT activation, review/enabled guards, location privacy, replay, concurrent activation, template mutation, and direct client access denial.

## Not yet production-operational
- No real task template is seeded or marked approved. A human must review real template content before trusted provisioning; emulator fixtures are test-only. The catalog intentionally displays an empty state until then.
- There is no trusted admin template provisioning tool, Functions deployment, recipient roster, resident task list/response backend, FCM/WhatsApp path, or offline cache.
- Firebase App Check registration/signing and production operator/RT provisioning remain external.

## Invariants
- Weather suggestions do not create or activate campaigns (AT-001).
- Catalog content and safety instructions come only from trusted reviewed versions; campaigns snapshot the exact version (AT-002/003).
- Only an authorized operator can activate a same-RT draft; no weather path or client Firestore write can do so.
- Participation is voluntary and has no penalty/ranking state (AT-004).
- Resident completion remains pending until RT verification (AT-005); the persistent backend/UI flow is still missing.
