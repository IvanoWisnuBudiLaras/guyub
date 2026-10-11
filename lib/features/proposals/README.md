# Feature: Proposals (Usulan Warga)

**Status: PARTIAL.** Residents submit bounded proposals through a callable. RT operators can review/dismiss them or map one to a safe-template DRAFT. A proposal never activates or distributes a task by itself.

## Implemented
- `application/resident_proposal_boundary.dart`: controlled category/location choices, server-record DTOs, secure-session controller, and retry recovery across controller/app restarts.
- `data/firebase_resident_proposal_boundary.dart`: callable-only submit/list/review adapter; no direct client Firestore access.
- Production retry recovery stores only an opaque request ID and a fingerprint hash in platform secure storage, keyed by a hash of the resident/RT scope. It does not persist proposal text. Server confirmation clears the pending entry; confirmed same-device resident-data deletion clears it too.
- Resident form explains that proposals are not tasks and warns against NIK, phone, address, and GPS content.
- Operator queue shows same-RT proposals. An operator can dismiss a proposal or map it to a reviewed, versioned safe-template DRAFT; activation remains a separate authorized action.

## Open gaps
- `NEEDS_OFFICIAL_REPORT` is in the PRD state model but is not available as a proposal-review decision. Official channels are configured separately; a proposal is not represented as officially handled.
- The optional supporting photo in J-06 is not implemented. Storage policy/configuration, metadata stripping, private review, retention, and deletion must be approved before implementation.
- Resident flagging of a neighbor needing assistance (FR-TWO-003) has no resident report form/RT queue. A target-reference mechanism and report-retention rule need approval; do not expose an RT resident directory or persist third-party report data before those decisions.
- Production proposal review, trusted content, and device-level validation remain open.

## Invariants
- Resident-provided text is proposal-only and never becomes task instructions or an active campaign automatically (AT-012, S-08).
- The server derives resident and RT identity from the validated opaque session. Operator review is server-side and same-RT scoped.
- Location is a controlled coarse category. NIK, full address, and precise GPS are not accepted.
