#!/usr/bin/env bash
set -euo pipefail

# Firebase CLI 13 supports the repository's Java 17 baseline.
npx --yes firebase-tools@13.35.1 emulators:exec \
  --project demo-guyub-rules \
  --only auth,firestore \
  "python3 tool/firestore_rules_tests/test_firestore_rules.py"
