# Feature: Proposals (Usulan Warga)

**Status: PARTIAL.** Residents can submit a bounded proposal through a callable and operators can review proposals scoped to their RT. A proposal remains `SUBMITTED` until the operator closes it as `DISMISSED`; neither action creates or activates a task.

## Implemented
- `application/resident_proposal_boundary.dart`: controlled category/location choices, server-record DTOs, secure-session controller, and stable retry IDs.
- `data/firebase_resident_proposal_boundary.dart`: callable-only submit/list/review adapter; no direct client Firestore access.
- Resident form explains that proposals are not tasks and warns against NIK, phone, address, and GPS content.
- Operator queue shows same-RT proposals and can close them. The UI offers no task activation action.

## Not yet implemented
- Mapping an approved proposal to a safe-template draft; an operator must use the existing catalog separately.
- `NEEDS_OFFICIAL_REPORT` handling, evidence upload, photo metadata stripping/retention, and assistance/helper assignment.
- Production proposal review, trusted content, and device-level validation.

## Invariants
- Resident-provided text is proposal-only and never becomes task instructions or an active campaign automatically (AT-012, S-08).
- The server derives resident and RT identity from the validated opaque session. Operator review is server-side and same-RT scoped.
- Location is a controlled coarse category. NIK, full address, and precise GPS are not accepted.
