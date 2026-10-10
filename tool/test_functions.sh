#!/usr/bin/env bash
set -euo pipefail

npm ci --prefix functions
npm test --prefix functions

# Emulator fixtures share a demo project; run integration files serially.
npx --yes firebase-tools@15.32.1 emulators:exec \
  --project demo-guyub-functions \
  --only auth,firestore,functions \
  "node --test --test-concurrency=1 functions/test/resident_session_emulator.test.js functions/test/task_campaign_emulator.test.js functions/test/task_response_emulator.test.js"
