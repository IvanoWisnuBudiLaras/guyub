#!/usr/bin/env bash
# Verifies the callable layer across both runtimes.
#
# 1. The seam and system-flow suites drive the Node HTTP adapter against the
#    Firebase emulator suite: the same journey the app takes, without Cloud
#    Functions.
# 2. The Dart contract test then talks to that running adapter with the real
#    client the app uses.
#
# Neither side is mocked.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

export GCLOUD_PROJECT=demo-guyub-functions
export FIREBASE_AUTH_EMULATOR_HOST=127.0.0.1:9099
export FIRESTORE_EMULATOR_HOST=127.0.0.1:8080
export FIREBASE_STORAGE_EMULATOR_HOST=127.0.0.1:9199
export GUYUB_EVIDENCE_BUCKET=demo-guyub-functions.appspot.com
export GUYUB_ADAPTER_URL=http://127.0.0.1:8787
export FUNCTIONS_EMULATOR=true
export GUYUB_TASK_SECRET=test-task-secret-flow

cat > /tmp/guyub_adapter_suite.sh <<'INNER'
set -e
node functions/server/http_adapter.js > /tmp/guyub_adapter.log 2>&1 &
ADAPTER_PID=$!
trap 'kill $ADAPTER_PID 2>/dev/null || true' EXIT
for i in $(seq 1 30); do
  if curl -s --max-time 2 http://127.0.0.1:8787/health >/dev/null 2>&1; then break; fi
  sleep 1
done
node --test functions/test/http_adapter_seam.test.js \
            functions/test/http_adapter_system_flow.test.js \
            functions/test/app_check_choke_point.test.js
node functions/test/seed_flow_rt.js
flutter test test/core/network/http_adapter_contract_test.dart --tags integration
INNER

npx --yes firebase-tools@15.32.1 emulators:exec \
  --project demo-guyub-functions --only auth,firestore,storage \
  "bash /tmp/guyub_adapter_suite.sh"
