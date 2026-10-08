#!/usr/bin/env bash
set -euo pipefail

npm ci --prefix functions
npm test --prefix functions

# Emulator fixtures share a demo project; run integration files serially.
GUYUB_EVIDENCE_BUCKET=demo-guyub-functions.appspot.com \
FIREBASE_STORAGE_EMULATOR_HOST=127.0.0.1:9199 \
npx --yes firebase-tools@15.32.1 emulators:exec \
  --project demo-guyub-functions \
  --only auth,firestore,functions,storage \
  "node --test --test-concurrency=1 functions/test/task_evidence_emulator.test.js functions/test/emergency_directory_emulator.test.js functions/test/resident_proposal_emulator.test.js functions/test/resident_session_emulator.test.js functions/test/task_campaign_emulator.test.js functions/test/task_response_emulator.test.js functions/test/task_notification_emulator.test.js functions/test/proxy_resident_emulator.test.js functions/test/weather_suggestion_emulator.test.js"
