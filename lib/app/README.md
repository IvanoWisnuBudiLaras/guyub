# App Layer — Guyub.id

This layer assembles the `MaterialApp`, runtime configuration, role-aware routing, and Firebase boundaries.

- `app.dart` is the presentation root and injects the operator auth boundary.
- `router.dart` routes to role selection, operator login, and the fail-closed resident entry placeholder.
- `bootstrap.dart` initializes Firebase and connects Auth/Firestore to emulators for development. If setup fails, it does not inject an operator backend and does not fall back from emulator to production.

Firebase SDK access stays in data/infrastructure adapters; feature screens depend on application contracts.
