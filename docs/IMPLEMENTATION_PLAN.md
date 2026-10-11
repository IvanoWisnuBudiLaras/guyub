# Guyub.id Implementation Plan

> **For agentic workers:** Execute task-by-task. Each phase must leave the application in a testable state. Do not start a later phase to hide a broken earlier phase.

**Goal:** Deliver the Android Guyub.id MVP described in `GUYUB_ID_MASTER_PRD_ENGINEERING_SPEC.md`.

**Architecture:** Flutter Android client backed by Firebase services. RT/RW operators authenticate formally; residents use a scoped RT-code/participant-session path without formal accounts. Weather automation generates suggestions, while activation of resident tasks always requires explicit operator confirmation.

**Tech Stack:** Flutter, Firebase Firestore, Firebase Authentication, Firebase Cloud Functions, Firebase Cloud Messaging, BMKG Open Data, local persistence; Firebase Cloud Storage is the default engineering extension for temporary photo evidence.

**Spec:** `GUYUB_ID_MASTER_PRD_ENGINEERING_SPEC.md`

---

## Global constraints

- Android APK only for MVP.
- Flood/rain-related inundation only.
- Human confirmation before task distribution.
- Safe locked templates only.
- Voluntary resident participation.
- No NIK, full address, or precise resident GPS.
- Evidence photo metadata stripped and evidence deleted after 30 days.
- Active tasks, last weather snapshot, emergency directory available offline.
- Preparedness history persists at RT level.

---

# Phase 0 — Foundation

## Deliverable
A buildable Flutter Android app connected to development Firebase environment with automated test/static-analysis baseline.

## Work items
- Initialize project structure.
- Separate app configuration by environment.
- Add local persistence abstraction.
- Add Firebase emulator support for development tests.
- Add CI command(s) for format, analyze, unit/widget tests.
- Define domain error/result conventions.
- Create requirements traceability file or test tags referencing `AT-*`.

## Exit criteria
- Clean APK debug build.
- Test command runs from one documented entry point.
- No production secrets in repository.

---

# Phase 1 — Role and RT context

## Deliverable
Role selection, operator authentication, and resident RT-code entry.

## Work items
- Implement splash and role selection screens from proposal.
- Implement Firebase Auth email/password operator path.
- Implement operator RT membership lookup.
- Implement backend RT-code validation endpoint.
- Implement opaque resident participant session stored on device.
- Deny broad unauthenticated Firestore writes.
- Implement role-specific navigation shell.

## Required tests
- invalid/expired RT code does not leak RT data;
- operator cannot access another RT;
- resident session is scoped to one RT;
- resident cannot call operator endpoints.

## Acceptance linkage
AT-009 plus security requirements.

---

# Phase 2 — Safe task catalog and operator task creation

## Deliverable
RT operator can create a draft from a locked safe template and explicitly activate it.

## Work items
- Define versioned `task_templates`.
- Seed reviewed safe templates.
- Implement catalog screen.
- Implement editable deadline/location/note slots.
- Implement backend validation.
- Implement confirmation screen.
- Implement audit event on activation.
- Persist immutable template snapshot on campaign.

## Required tests
- free-form core task cannot activate;
- missing safety text blocks activation;
- operator edit cannot alter safety/core content;
- activation requires authorized operator;
- repeated activation request is idempotent.

## Acceptance linkage
AT-002, AT-003.

---

# Phase 3 — Resident task loop and RT verification

## Deliverable
Active tasks are visible to residents; residents may join/decline; completion requires RT verification.

## Work items
- Build resident home and task list.
- Implement task detail/safety view.
- Implement `JOINED` and `DECLINED`.
- Implement completion screen.
- Implement optional note.
- Implement pending-verification state.
- Build RT verification queue.
- Implement verified-complete transition.
- Build basic task recap.

## Required tests
- decline is a valid terminal participation state;
- no leaderboard/penalty state exists;
- completion is not verified automatically;
- resident can modify only their scoped response;
- operator verification is RT-scoped.

## Acceptance linkage
AT-004, AT-005.

---

# Phase 4 — BMKG weather and suggestions

## Deliverable
Official forecast is synchronized, cached, shown with timestamp, and may produce suggestions.

## Work items
- Build BMKG adapter and normalization boundary.
- Persist last valid snapshot.
- Build weather card.
- Add explicit stale/offline state.
- Fetch last-valid snapshots through resident-session or operator-membership callables.
- Cache snapshots under RT-scoped local keys; show cached content before background refresh and retain it on failure.
- Define configurable `weather_rules`.
- Implement scheduled evaluator.
- Generate idempotent `task_suggestions`.
- Build same-RT operator suggestion review UI with accept/review, postpone, and ignore actions; only matching approved catalog versions open, ignored decisions are RT-scoped/idempotent, and task draft/activation remains a separate operator flow.

## Required tests
- fetch failure preserves last valid snapshot;
- malformed payload does not replace valid data;
- same weather/rule interval does not create duplicate suggestions;
- operator and resident snapshot reads derive scope from trusted membership/session; forged RT scope is rejected;
- direct client reads of weather config/snapshots/suggestions are denied;
- an RT-keyed offline cache never displays another RT's snapshot, keeps a newer snapshot after fetch failure, and marks unknown/expired freshness safely;
- suggestions are revalidated at the action boundary; expired or superseded trigger snapshots cannot open the recommended task catalog, and failed freshness checks fail closed;
- postpone leaves a suggestion available; ignore is an authorized, idempotent RT-scoped state change that never creates a task;
- threshold evaluator never creates DRAFT or ACTIVE tasks.

## Acceptance linkage
AT-001, AT-008.

---

# Phase 5 — Distribution, FCM, reminders, escalation

## Deliverable
Provide the CF-07 reminder and CF-08 escalation backend with validated per-RT policy, transactional outbox/audit, replay-safe delivery attempts, and same-RT Pendamping RT targeting. Keep task access independent of push delivery.

## Current status
**Backend and Android client slices are implemented; rollout remains disabled and unconfigured.** `rt_communities.reminderPolicyId` points to a server-provisioned document in `task_reminder_policies`. A policy must be enabled, reviewed, versioned, RT-scoped, and valid. It defines reminder windows/cohorts, escalation window/cohort/minimum cohort size, and retry delays. Campaign activation snapshots the policy document ID, version, and fingerprint. Missing or invalid policy never blocks activation; it disables configured reminders/escalation.

`sendTaskReminders` and `escalateUnrespondedTasks` scan configured policies every minute so the scheduler cadence matches the shortest supported one-minute policy offset. Lifecycle notification events remain on a five-minute scan. Idempotent outbox events and privacy-safe audit markers cover those windows. Campaign activation, cancellation, and closure create lifecycle notices transactionally. Resident completion submission creates a separate idempotent verification-needed notice in the same transaction as the pending report. Delivery rechecks live resident session/task state or active same-RT `PENDAMPING_RT` membership. Declined residents are excluded from reminders. Protected policy, event, audit, and token collections remain unavailable to direct clients.

Android push permission is requested only after an explicit resident or Pendamping RT opt-in. The client registers and refreshes scoped tokens through callable Functions, revokes tokens on opt-out/session revocation and attempts operator-token removal before sign-out, handles foreground/opened/cold-start messages, and resolves resident task IDs through the authorized active-task list. Pendamping verification notices open the server-backed verification queue; escalation notices open the active-task list. Push stays an optional hint; task access and WhatsApp copy-text remain separate. Generic FCM copy contains no resident details and never claims an official warning.

The outbox retries configured failures with stable logical event IDs. FCM acceptance followed by worker failure can still cause a transport duplicate; event creation is idempotent, not provider-level exactly-once. `GUYUB_NOTIFICATIONS_ENABLED` defaults off. No pilot policy values, production token setup, scheduler deployment, or real FCM delivery has been configured or verified.

## Remaining work / decisions
- Provision reviewed per-RT policy values only after product-owner approval; do not add pilot timing, thresholds, or recipients as defaults.
- Complete Android device validation for consent, token refresh/revocation, background/cold-start click routing, and failed/offline delivery.
- Confirm WhatsApp copy-text fallback on a device. Keep it copy-only; do not add automatic sending.
- Production FCM, Scheduler, and notification policy configuration remain disabled until explicit approval.

## Required tests
- the minimum one-minute policy window is scanned at a matching cadence; replay creates one event per policy window and a later configured window is distinct;
- retry after delivery failure creates no second logical reminder;
- escalation replay is idempotent and does not alter participation/completion state;
- declined residents receive no reminder;
- cross-RT operator cannot read campaign notification audit or receive its escalation;
- FCM failure leaves the active task available in the app;
- payload/copy and audit contain no sensitive resident details and never claim an official flood warning;
- clients cannot directly read/write policy, outbox, audit, or push-token collections.

## Acceptance linkage
AT-016 (copy-only summary), AT-017 (authorized, audited cancellation), AT-023 (configured reminders/escalation), AT-024 (opt-in push delivery and click routing), and AT-025 (same-device resident-data deletion).

---

# Phase 6 — Two-way proposals and assistance

## Deliverable
Residents can propose tasks/conditions, and RT can manage vulnerable-resident assistance.

## Work items
- [x] implement resident proposal form and same-RT review queue,
- [x] map a SUBMITTED proposal only to a DRAFT created from an approved, versioned safe template; proposal text is context only,
- [ ] optional supporting evidence reference and temporary image retention (requires approved storage policy/configuration),
- [x] implement RT-scoped resident profiles and minimal assistance markers,
- [x] implement voluntary helper opt-in, private same-RT assignment, and helper accept/decline/withdrawal,
- [x] implement consent-attested RT status updates for proxy and self-enrolled profiles; preserve conflicting resident choices and pending RT verification,
- [x] persist proxy-create retries by RT scope and support server-confirmed cancellation/reconciliation with replay tombstones.

## Required tests
- proposal cannot activate task directly;
- proposal cannot overwrite template safety text;
- helper assignment is voluntary;
- proxy status requires authorized operator.

## Acceptance linkage
AT-012, AT-014, AT-020.

---

# Phase 7 — Emergency/offline mode

## Deliverable
Core preparedness information remains useful without internet.

## Work items
- cache active tasks and template safety text,
- cache emergency directory,
- cache assembly points,
- cache last valid weather snapshot per RT; refresh through callable after rendering the cached value,
- build offline banner/state,
- implement local command queue,
- add idempotency keys,
- implement reconnect reconciliation.

## Required tests
- airplane-mode active task read;
- airplane-mode emergency screen;
- stale weather timestamp visible;
- queued join/decline syncs once;
- server-authoritative conflicts are surfaced, not silently overwritten.

## Acceptance linkage
AT-006, AT-007, AT-008, AT-018, AT-019 and offline/reconciliation scenarios O-01–O-08.

---

# Phase 8 — Photo evidence and data lifecycle

## Deliverable
Optional evidence works without expanding permanent resident data.

**Current status: PARTIAL.** Client and server JPEG sanitization, private RT-scoped storage/review, same-device evidence deletion, RT-assisted and same-device full server-data deletion, retryable evidence cleanup, and 30-day physical cleanup have unit and emulator coverage. Same-device deletion uses the validated participant session, creates a replay-safe deletion job, removes resident-owned server data, and clears the local task cache/outbox, session, and push-token state only after server confirmation. A bounded upload lease makes deletion reject during an active write and keeps cleanup retryable after the upload callable timeout; failed object deletion retains metadata. Completed deletion retains only minimal enrollment/profile replay tombstones, with no nickname, resident ID, or session token; a retryable job temporarily keeps the scoped resident ID and a hashed session binding only while cleanup is incomplete. The RT-assisted fallback requires explicit resident-request and pilot identity-check attestations; the pilot procedure remains external. Production bucket, scheduled jobs, and billing are not configured.

## Work items
- [x] Strip EXIF/location metadata on the client and re-encode again on the server.
- [x] Resize to at most 1280 px and bound stored JPEGs to 2 MiB.
- [x] Store bytes in a private Cloud Storage object; deny direct client reads and writes.
- [x] Store only a scoped, opaque Firestore reference; never return a public or signed URL.
- [x] Set `expiresAt` to 30 days after upload and implement scheduled physical deletion.
- [x] Retry failed deletion and log only the opaque evidence ID and generic failure code.
- [x] Allow the resident session to delete its own evidence; remove the completion reference.
- [x] Add same-RT RT-assisted server-data deletion with explicit resident-request/identity-check attestations, retryable cleanup, private audit, and evidence-object deletion. Pilot identity-check procedure still requires stakeholder definition.
- [x] Add same-device resident self-deletion through the validated participant session; remove server-owned profile data and evidence, preserve shared RT history, support replay/retry, and clear local task cache/outbox/session/push state only after server confirmation.
- [ ] Configure a production bucket and deploy/observe cleanup only after explicit billing and deployment approval.

## Required tests
- Evidence is optional; upload failure does not block completion and image bytes are never queued offline.
- A synthetic geotagged JPEG has no EXIF/GPS metadata after server processing and storage.
- Resident and operator direct Storage/Firestore access is denied; only a same-RT authenticated operator can request review bytes.
- The emulator cleanup physically removes an expired object; a failed delete remains pending for retry.
- Same-device deletion cannot target another resident’s evidence and clears stale task references.

## Acceptance linkage
AT-010, AT-011.

---

# Phase 9 — History and pilot hardening

## Deliverable
RT history survives operator changes and the app is ready for controlled pilot.

**Current status: PARTIAL.** The RT-scoped paginated history, aggregate completion recap, explicit audited ACTIVE → CLOSED transition, privacy-safe lifecycle event timeline, and same-RT operator replacement emulator coverage are implemented. Closure never implies resident completion or RT verification. Operator membership provisioning remains trusted-admin work; no self-service transfer flow is added. Pilot configuration, device accessibility/usability, and release validation remain open.

## Work items
- [x] historical task/event view with audited explicit close;
- confirm RT-owned persistence,
- operator replacement/handover test,
- [x] add safe explicit HTTPS/telephone actions for trusted RT-configured official channels; pilot route provisioning and verification remain external,
- configure pilot emergency numbers and assembly points,
- configure pilot weather rules with human-reviewed values,
- review all safe templates with local stakeholders,
- usability test role entry/task completion,
- accessibility pass,
- release APK.

## Required tests
- replacing operator account does not erase RT history;
- mockup names/numbers/locations are not production constants;
- every `AT-*` has automated or documented manual evidence.

## Acceptance linkage
AT-015 plus full regression.

---

# Final release gate

Before producing the competition/pilot APK:

- all hard invariants pass;
- no unresolved security rule allows cross-RT access;
- all Cloud Functions used by offline retry are idempotent;
- evidence cleanup is enabled;
- BMKG attribution/timestamp are visible;
- emergency directory works in offline test;
- resident decline flow is usable;
- official-reporting links are configured for pilot region;
- safe template set has human approval.
