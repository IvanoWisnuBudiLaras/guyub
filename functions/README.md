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

## Verification

```bash
npm ci --prefix functions
npm test --prefix functions
./tool/test_functions.sh
```

`./tool/test_functions.sh` runs unit tests and starts only Firebase emulators using a demo project. CI runs this after Flutter verification and the Firestore rules suite.

No Firebase Functions deployment, scheduled job, production credential, or billing change is part of this package.
