# Feature: Auth & Onboarding

**Status: PARTIAL.** Operators sign in with Firebase email/password and read only their own active RT membership. Residents create short-lived, RT-scoped sessions through callable Functions. On a temporary network outage, a secure display-only session snapshot can reopen the resident home; it never authorizes a backend call.

## Implemented
- Role selection and separate operator/resident paths.
- `data/firebase_operator_auth_boundary.dart` authenticates operators and checks `/operators/{uid}` membership; Firestore rules prevent membership writes and cross-operator reads.
- `functions/src/resident_session_service.js` accepts only a high-entropy 12–32 character RT code and a nickname. Invalid/malformed/disabled codes return the same generic denial.
- Callable Functions issue a cryptographically random 7-day participant token. Firestore stores only its SHA-256 hash. The session profile stores only RT scope, nickname, assistance marker, origin, and timestamps.
- A secure, random per-attempt request ID makes enrollment retries reuse one profile; a retry rotates the token and revokes the older session. The raw request ID is kept in platform secure storage only while enrollment is pending.
- Production callable access requires Firebase App Check. Android uses Play Integrity; the demo emulator bypasses App Check enforcement. Production enrollment fails closed until the signed app is registered in Firebase Console.
- `ResidentSessionController` keeps the bearer token out of UI models. `FlutterSecureResidentSessionVault` uses platform secure storage. A temporary network error preserves the saved token and may restore a minimal display-only profile snapshot; revoked/expired sessions clear both. Offline metadata never authorizes a backend call.
- All direct client reads/writes to resident and other protected collections remain denied. Mutations in this slice are Admin-SDK-only through callable Functions.
- Tests: Dart controller/widget tests, Node service tests, and Functions/Firestore emulator integration tests in `./tool/test_functions.sh`; Firestore rules tests in `./tool/test_firestore_rules.sh`.

## Provisioning and limitations
- A trusted administrator must provision `/rt_communities/{rtId}` with a display name, RT label, `joinCodeHash` (SHA-256 of a random uppercase alphanumeric code, 12–32 characters), and `joinCodeActive: true`. The raw join code must be shared privately with that RT. The app never reads this document.
- Operator Firebase Auth users and `/operators/{uid}` membership records also require trusted provisioning. No credentials or project IDs are included in the repository.
- Task participation, completion submission, and proposals use callable Functions with server-validated session scope. The offline task queue stores no bearer token or completion note and is replayed only through those callables; offline proposals remain unavailable. Do not add direct Firestore client writes.
- Production Functions are not deployed. Billing/provider activation, App Check registration, and real pilot provisioning remain external decisions. No per-RT enrollment quota is set without a stakeholder-approved limit. Emulator tests use a demo project only.
