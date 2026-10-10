#!/usr/bin/env bash
set -euo pipefail

# Firebase CLI 15 / Firestore emulator use the Node 22 and Java 21 CI baseline.
npx --yes firebase-tools@15.32.1 emulators:exec \
  --project demo-guyub-rules \
  --only auth,firestore \
  "python3 tool/firestore_rules_tests/test_firestore_rules.py"
