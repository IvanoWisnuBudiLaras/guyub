# Guyub.id Firebase Functions

Runtime target: Node.js 22. The local emulator suite runs Auth, Firestore, and Functions under the `demo-guyub-functions` project; it does not contact a production Firebase project.

## Resident session boundary

- `createResidentSession` resolves a high-entropy RT join-code hash, stores a minimal resident profile, and creates an opaque 7-day session.
- Each enrollment attempt carries a random request ID. The raw ID is not persisted; the server stores its SHA-256 hash, a fingerprint derived from the join-code hash and normalized nickname, and only the resident/session references needed for safe retry. Retrying the same attempt reuses the profile and rotates/revokes the previous token.
- Only the SHA-256 token hash is persisted in `/resident_sessions/{tokenHash}`. The raw token is returned once to the app and stored through Android secure storage.
- `validateResidentSession` returns only the token's own RT scope and nickname. An RT ID supplied by a client is never accepted as authority.
- `revokeResidentSession` is idempotent. All three are callable Functions; residents cannot read or write the backing Firestore collections directly.
- Unknown, malformed, disabled, or ambiguous join codes share one generic permission-denied response.
- Callable Functions require App Check outside the emulator. The Android client uses Play Integrity; emulator-only requests disable enforcement. Production enrollment stays unavailable until App Check is registered for the signed Android app in Firebase Console.
- App Check does not replace an approved per-RT enrollment quota; no quota is imposed until pilot owners approve a safe limit.

## Trusted pilot provisioning

An administrator provisions `/rt_communities/{rtId}` outside the resident app with:

```json
{
  "displayName": "<human-approved community display name>",
  "rtLabel": "<human-approved RT label>",
  "joinCodeHash": "<lowercase SHA-256 hex of a generated code>",
  "joinCodeActive": true
}
```

Generate a random 12–32 character uppercase alphanumeric code with a cryptographically secure generator. Store only its SHA-256 hash in Firestore, share the raw code privately with that RT, and revoke by setting `joinCodeActive` to `false`. Do not use a predictable or shared public code. No production community, operator, secret, or real RT code is provisioned by this repository.

## Reviewed task catalog and activation

- `listApprovedTaskTemplates`, `createTaskDraft`, and `activateTaskCampaign` are callable-only operations. Callers must be password-authenticated operators with an active server-provisioned `/operators/{uid}` membership in the supported role set. Every mutation re-reads membership in its Firestore transaction; the stored `rtId` is never accepted from the client.
- Templates live in `/task_templates/{templateId}_v{version}`. A trusted provisioning path must set matching `templateId`/`version`, a controlled category, title, core and safety instructions, optional `estimatedDurationMinutes`, `enabled: true`, `reviewStatus: "approved"`, `reviewedBy`, and `reviewedAt`. Firestore client access remains denied. This repository does not seed or claim human approval for real template content.
- Only the approved version is returned. Draft input is limited to template ID/version, future deadline, one controlled coarse-location category, and a random retry request ID. Free-text task notes and locations are rejected to prevent unsafe instructions or personal data. Activation rechecks the approved version and compares an immutable content fingerprint. Caller-supplied core/safety/category/RT/operator fields are rejected; the location category is separate from the immutable template snapshot.
- Campaign ownership is the server-derived RT. Activation updates the draft and creates one deterministic `/task_audit_events/{campaignId}_activated` record in a transaction. Replays of the same command return the existing activation; a different command cannot reactivate it. No notification is sent by this phase.
- A pilot administrator must obtain human review before provisioning any usable template. Do not copy test fixture instructions into production.


## Active campaign review, cancellation, and closure

- `listActiveTaskCampaigns` requires a password-authenticated active operator and derives its RT from `/operators/{uid}`. It returns only ACTIVE campaigns for that RT, with the immutable template snapshot, deadline, and coarse location; it fails closed above the 200-item bound.
- `cancelTaskCampaign` accepts only `taskId` and an idempotency `commandId`. The repository rechecks operator membership and RT scope, allows only ACTIVE → CANCELLED, hashes the command ID, and writes one deterministic RT-owned audit event. Same actor/command replay succeeds; conflicting commands and foreign/missing IDs do not disclose task existence.
- `closeTaskCampaign` accepts only `taskId` and an idempotency `commandId`. An authorized same-RT operator explicitly closes an ACTIVE campaign; the backend hashes the command ID and atomically writes one deterministic RT-owned audit event. It does not infer closure from a deadline, weather, response count, or resident completion. Closure is not completion verification, and conflicting replays fail closed.
- Cancellation and closure require explicit operator confirmation in the app. Their lifecycle events are created idempotently and can be delivered as generic FCM hints when notifications are enabled; FCM transport may duplicate a delivery. No WhatsApp update is sent. Resident active-task reads exclude closed/cancelled tasks; offline queued resident commands receive the server-authoritative conflict on retry.
- `listRtTaskHistory({pageSize?, cursor?})` uses active operator membership for scope; it never accepts client RT/actor IDs. Pages of 1–50 ACTIVE/CLOSED/CANCELLED campaigns are ordered by activation time and campaign ID, with immutable template snapshots and lifecycle timestamps. `listTaskLifecycleEvents({taskId})` returns only event type and timestamp after same-RT authorization and audit-consistency checks; it never returns actor IDs or raw audit records. Drafts and resident data are excluded. Same-RT replacement operators can read the same records; inactive/foreign operators cannot. The client links each record to the aggregate-only `getTaskResponseRecap`; no self-service operator-transfer flow or offline history cache is added.

## BMKG weather snapshot and suggestion boundary

- `syncBmkgWeather` polls every six hours when deployed. It reads only trusted `/weather_sources/{rtId}` configuration and writes RT-owned server snapshots; Firestore client access stays denied.
- A source document must be explicitly enabled and reviewed. It contains `rtId`, `source: "BMKG"`, reviewer/timestamp, an HTTPS `api.bmkg.go.id/publik/prakiraan-cuaca` URL with one coarse `adm4` code, a reviewed maximum snapshot age, and configured JSON paths for rainfall and source-update time. The path mapping must be checked against the live BMKG response schema by the pilot owner. No location or mapping is seeded.
- `/weather_rules/{rtId}_{ruleId}_v{version}` records are ignored unless enabled and approved. Each rule version has a reviewer/timestamp, explicit `minimumRainfallMm`, bounded explanation, and versioned safe-template references. Each reference includes the SHA-256 `fingerprint` produced by `templateFingerprint` from the normalized approved template content. Sync and reads require an exact match; a changed same-version template invalidates the rule, and only a newly reviewed rule version can restore recommendations. Disabled or superseding rule versions hide old suggestions. No threshold or template recommendation has a production default.
- Valid snapshots are stored with BMKG attribution and both timestamps. Transactional last-valid pointers advance only for newer, fresh snapshots. Fetch, schema, timestamp, or freshness failures leave the last valid value unchanged.
- `task_suggestions` IDs are deterministic per RT/snapshot/rule. Retries do not duplicate a suggestion. `listWeatherSuggestions` is a password-authenticated callable; it derives RT scope from active operator membership and returns only suggestions for that RT. Direct client reads/writes remain denied.
- This slice ends at `SUGGESTED`. It does not create a DRAFT, activate a campaign, or notify residents. The Flutter weather-review screen exists and revalidates suggestion freshness before opening approved catalog templates; defer/ignore do not create a task. The scheduled function is code only; production Scheduler/provider configuration and any billing decision remain external. No source/rule documents are seeded.

## Resident task response and RT verification

- `listResidentActiveTasks` accepts only the opaque resident token. The service derives the resident and RT from the validated session; the repository rechecks session expiry, active state, and resident RT inside the Firestore transaction. The result contains active campaigns and only that resident's response.
- `recordResidentTaskResponse` accepts one voluntary `JOINED` or `DECLINED` choice. A deterministic response document is keyed from the server-derived RT, task, and resident. The first choice wins; an opposite later choice is rejected. No penalty, rank, or leaderboard state exists.
- `submitTaskCompletion` accepts only a joined participant. It stores a bounded optional note and transitions to `PENDING_RT_VERIFICATION`; it cannot set verification fields. The note validator rejects common address/GPS patterns and NIK/mobile digit sequences separated by spaces, dots, hyphens, slashes, or parentheses.
- `listPendingTaskVerifications`, `verifyTaskCompletion`, and `getTaskResponseRecap` require a password-authenticated active operator. Each query/mutation is RT-scoped by the trusted membership. Verification writes the server time, operator UID, and one deterministic audit event transactionally.
- Command IDs are validated and only their SHA-256 hashes are stored. Transactions make repeated and concurrent participation, submission, and verification safe. Raw session tokens are not stored in responses or audit events.
- `/task_responses` and `/task_audit_events` remain unreadable and unwritable from clients. The Android adapter calls Functions only. Firestore composite indexes are declared in `firestore.indexes.json`.
- Active-task lists are capped at 200 items, verification queues at 100, and recap reads at 400 responses. Each response includes `isPartial` when the cap is reached; the UI states that the list/recap may be incomplete. There is not yet cursor pagination.
- Recap counts only recorded responses. It does not claim to count residents who have not responded because no recipient/eligibility snapshot exists.
- Phase 7 adds a resident/RT-scoped local task snapshot and durable outbox for JOIN/DECLINE and no-note completion. Every replay still uses callable Functions and server-derived authorization; conflicts remain queued and visible. Completion stays pending until RT verification. Completion notes and bearer tokens are never stored in the outbox.
- The FCM pipeline provides opt-in, generic lifecycle/reminder/escalation/verification hints; clicks resolve through authorized lists, and terminal cancel/close alerts show read-only status. The pipeline is code-only and disabled/unconfigured for production. No WhatsApp message is sent; physical-device delivery, click-routing, and offline validation remain outstanding.

## Resident proposals and RT review

- `submitResidentProposal` requires the opaque resident session. The service derives resident and RT identity from the validated session and rechecks session, profile, and RT scope in the Firestore transaction.
- Proposal input is limited to bounded title/description, one existing controlled category, an optional coarse location enum, and a stable request ID. Common NIK, mobile-number, coordinate, and address patterns are rejected; free-text location is not accepted.
- New proposals are stored only as `SUBMITTED`, with deterministic IDs and request fingerprints. Even hazardous proposal wording remains review-only text: submission and review never call task creation or activation.
- `listResidentProposals`, `reviewResidentProposal`, and `mapResidentProposalToDraft` require an active password-authenticated operator and derive RT scope from trusted membership. Mapping is a single transaction: it rechecks the SUBMITTED proposal and reviewed/enabled template version, requires explicit deadline/location selection, stores a locked template snapshot in a DRAFT, and writes one deterministic audit event. Stable command IDs are derived from canonical proposal/template/slot inputs so fresh-controller retries replay the same operation. Raw command IDs and proposal text are not written to audit/task instructions. Firestore client access remains denied.
- Mapping never activates or notifies. Activation remains a separate authorized callable. Official-report routing and optional evidence storage are covered below. RT-scoped minimal assistance markers, proxy assistance, and voluntary helper assignment are implemented. Resident flagging/reporting for FR-TWO-003 is not implemented; target-reference and report-retention policies need product approval. PII pattern checks reduce common mistakes but cannot identify every obfuscated string; avoid entering personal details.

## Optional photo evidence and retention

- Residents may select an optional JPEG while submitting task completion. The Flutter client re-encodes it and removes metadata before upload; Cloud Functions applies a second JPEG decode/orientation/resize/re-encode and rejects invalid or oversized files. Stored output is at most 1280 px per edge and 2 MiB.
- The app sends no image bytes through the offline outbox. If photo upload fails, completion continues without evidence. Upload requires the validated resident session, an active campaign, and that resident’s `JOINED` response. The caller cannot choose an RT or resident ID.
- `uploadResidentTaskEvidence` returns only an opaque evidence ID and expiry time. Firestore stores scoped metadata in `task_evidence`; Storage object paths use hashes and contain no resident or RT IDs. No public or signed download URL is created.
- `storage.rules` denies all direct client reads and writes. Firestore client access is also denied. An active, password-authenticated same-RT operator can use `getTaskEvidenceForVerification` only for evidence attached to a pending completion. The callable returns bounded JPEG bytes over the authenticated Firebase Functions channel.
- Evidence expires 30 days after upload. `deleteExpiredTaskEvidence` runs daily, physically deletes Storage objects, clears the response reference, and leaves a minimal deletion record. Failed object deletes stay `DELETE_PENDING` for retry; logs include only an opaque evidence ID and a generic error code. Resident-session deletion follows the same server-verified scope check and is idempotent.
- RT-assisted deletion callable code exists and is RT-scoped/emulator-tested, but request/identity attestations are not backed by a server-verifiable approval artifact. Keep this path out of pilot/production use until the offline identity-verification procedure and its server-verifiable evidence are approved. Same-device resident-data deletion is a separate implemented path. Do not infer or fabricate an identity-verification procedure.
- Emulator runs use `demo-guyub-functions.appspot.com` with the Storage emulator. Production requires a reviewed `GUYUB_EVIDENCE_BUCKET` value and an explicitly approved deployment. Scheduled Cloud Scheduler use may require billing. No production bucket, scheduled job, credential, or billing change is configured here.

## Emergency directory and offline client cache

- `getEmergencyDirectory` accepts only the opaque resident session token. The service derives RT scope from the validated session and the Firestore transaction rechecks the session, resident profile, and RT community before reading `/emergency_directories/{rtId}`.
- Firestore client reads and writes remain denied. The directory is read-only to the app and must be provisioned through a trusted pilot process; this repository contains no emergency phone numbers, assembly locations, or official reporting links as production data.
- The provisioned document uses exact fields `rtId`, `state` (`ACTIVE`/`DISABLED`), positive data `version`, `lastVerifiedAt`, and bounded `emergencyContacts`, `assemblyPoints`, and `officialReportChannels` arrays. Contacts contain a label and phone; assembly points contain a label and public location description; official channels contain a label and HTTPS URL and/or phone. HTTPS routes reject credentials, whitespace/control characters, and non-default ports; telephone values use the bounded phone validator.
- Missing configuration returns `UNCONFIGURED`; an explicit `DISABLED` revision can invalidate an older local cache. The Flutter client keeps only a validated last-known directory with its local sync time, marks it offline/stale, and does not replace it with a missing or failed fetch.
- The Darurat screen shows explicit external-site or dialer actions only for configured, validated per-RT channels. Users must tap to hand off; the app does not submit reports or mark them delivered. Unconfigured, unavailable, and failed-handoff states are shown without fabricated routes.
- No sample/mockup emergency values should be provisioned. Pilot owners must verify contacts, assembly points, official channels, and `lastVerifiedAt` before use.

## Verification

```bash
npm ci --prefix functions
npm test --prefix functions
./tool/test_functions.sh
```

`./tool/test_functions.sh` runs unit tests and starts Auth, Firestore, Functions, and Storage emulators using a demo project. CI runs this after Flutter verification and the Firestore rules suite. Firebase CLI 15 requires Java 21; a Java 17 host can run Functions unit tests but cannot start the emulator suite.

The scheduled cleanup function and production Storage path are code only. No Firebase Functions deployment, scheduled job, production credential, or billing change is part of this package.
