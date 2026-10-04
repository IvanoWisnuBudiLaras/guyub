#!/usr/bin/env bash
set -euo pipefail

npm ci --prefix functions
npm test --prefix functions

npx --yes firebase-tools@15.32.1 emulators:exec \
  --project demo-guyub-functions \
  --only auth,firestore,functions \
  "node --test functions/test/resident_session_emulator.test.js"
