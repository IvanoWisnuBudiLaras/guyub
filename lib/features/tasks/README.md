# Feature: Tasks (Tugas Kesiapsiagaan)

**Status: PARTIAL.** The application layer now models controlled-template snapshots, draft/activation state, voluntary response, pending RT verification, bounded operator parameters, and retry-safe domain transitions.

## Implemented
- `application/task_template.dart`: immutable versioned template copy and required safety/core text.
- `application/task_campaign.dart`: draft creation from a template, deadline/location parameters, explicit activation method, same-community guard, and command replay handling. Free-text resident-facing notes are disabled until a reviewed safety mechanism exists.
- `application/task_response.dart`: JOIN/DECLINE and completion pending until operator verification.
- Unit tests: `test/features/tasks/task_workflow_test.dart`.

## Not yet production-operational
- There is no approved catalog data or catalog backend. A valid Dart object is not proof of human safety review.
- Campaign and resident response operations are not connected to Firestore. Domain checks are not server authorization.
- There is no task UI, resident session, RT verification queue, active-task offline cache, audit log, notification, or distribution.
- Operator/resident writes remain denied by Firestore rules until explicit RT-scoped rules and emulator tests are added.

## Invariants
- Weather suggestions do not activate campaigns (AT-001).
- Core and safety instructions are snapshotted; arbitrary free-text notes are not accepted (AT-002/003 partial).
- Participation has no penalty/ranking state (AT-004).
- Resident completion remains `pendingRtVerification` until a domain verification transition (AT-005).
- Backend authorization is still required before persistence or distribution.
