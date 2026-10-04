# Feature: Auth & Onboarding

**Status: PARTIAL.** The app has distinct role entry screens and a Firebase Auth email/password path for operators, followed by a server-ruled read of that operator's active RT membership record.

## Implemented
- Role selection, operator login, operator home, and a fail-closed resident entry screen.
- `application/operator_profile.dart` restricts roles to `KETUA_RT_RW` and `PENDAMPING_RT` and holds only UID, RT scope, role, and display name.
- `data/firebase_operator_auth_boundary.dart` authenticates and checks `/operators/{uid}` membership.
- `firestore.rules` permits an active password-authenticated operator to read only their own membership; clients cannot write membership or any unconfigured collection.
- Auth/Firestore emulators are configured for development. `./tool/test_firestore_rules.sh` runs authorization tests.

## Not yet production-operational
- Operator credentials and membership records need trusted pilot provisioning. Each `/operators/{uid}` document must be provisioned outside the app with `rtId`, `role` (`KETUA_RT_RW` or `PENDAMPING_RT`), `displayName`, and `active: true`.
- Production Firebase client options must be supplied through compile-time defines; no project API configuration is committed.
- Resident RT-code entry is intentionally disabled: a code alone is not a scoped session or authorization.
- Operator actions, resident sessions, task data rules, cross-RT data flows, and operator handover are not implemented.
- No real pilot account was used; production Firebase was not contacted.
