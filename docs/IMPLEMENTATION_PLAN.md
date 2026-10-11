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
- Define configurable `weather_rules`.
- Implement scheduled evaluator.
- Generate idempotent `task_suggestions`.
- Build operator suggestion review UI.

## Required tests
- fetch failure preserves last valid snapshot;
- malformed payload does not replace valid data;
- same weather/rule interval does not create duplicate suggestions;
- threshold evaluator never creates ACTIVE task.

## Acceptance linkage
AT-001, AT-008.

---

# Phase 5 — Distribution, FCM, reminders, escalation

## Deliverable
Active tasks notify residents, reminders run automatically, and administrative escalation reaches Pendamping RT.

## Work items
- register/update FCM tokens,
- send active-task notification,
- implement audited same-RT campaign cancellation;
- defer task cancellation/update notifications until FCM and recipient/privacy rules are implemented and reviewed,
- implement reminder scheduler,
- implement configurable escalation policy,
- notify Pendamping RT for non-response,
- implement WhatsApp copy-text action,
- audit delivery workflow without storing unnecessary content.

## Required tests
- retries do not duplicate reminders;
- escalation does not change resident participation status;
- notification content does not claim official flood warning;
- task remains accessible if push delivery fails.

## Acceptance linkage
AT-016 (copy-only summary) and AT-017 (authorized, audited cancellation).

---

# Phase 6 — Two-way proposals and assistance

## Deliverable
Residents can propose tasks/conditions, and RT can manage vulnerable-resident assistance.

## Work items
- [x] implement resident proposal form and same-RT review queue,
- [x] map a SUBMITTED proposal only to a DRAFT created from an approved, versioned safe template; proposal text is context only,
- [ ] optional supporting evidence reference and temporary image retention (requires approved storage policy/configuration),
- [ ] implement vulnerable-resident records,
- [ ] implement voluntary helper assignment,
- [ ] implement consent-defined proxy status update.

## Required tests
- proposal cannot activate task directly;
- proposal cannot overwrite template safety text;
- helper assignment is voluntary;
- proxy status requires authorized operator.

## Acceptance linkage
AT-012, AT-014.

---

# Phase 7 — Emergency/offline mode

## Deliverable
Core preparedness information remains useful without internet.

## Work items
- cache active tasks and template safety text,
- cache emergency directory,
- cache assembly points,
- cache last valid weather snapshot,
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

**Current status: PARTIAL.** Client and server JPEG sanitization, private RT-scoped storage/review, same-device deletion, and 30-day physical cleanup are implemented with unit and emulator coverage. The local Storage/Functions emulator suite still needs Java 21; production bucket, scheduled job, and billing are not configured. RT-assisted deletion remains blocked on the pilot identity-verification policy.

## Work items
- [x] Strip EXIF/location metadata on the client and re-encode again on the server.
- [x] Resize to at most 1280 px and bound stored JPEGs to 2 MiB.
- [x] Store bytes in a private Cloud Storage object; deny direct client reads and writes.
- [x] Store only a scoped, opaque Firestore reference; never return a public or signed URL.
- [x] Set `expiresAt` to 30 days after upload and implement scheduled physical deletion.
- [x] Retry failed deletion and log only the opaque evidence ID and generic failure code.
- [x] Allow the resident session to delete its own evidence; remove the completion reference.
- [ ] Add RT-assisted deletion after stakeholders define the required offline identity check.
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

**Current status: PARTIAL.** The read-only RT-scoped history list, aggregate completion recap, and same-RT operator replacement emulator test are implemented. Operator membership provisioning remains trusted-admin work; no self-service transfer flow is added. Pilot configuration, accessibility, usability, and release validation remain open.

## Work items
- historical task/event view,
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
