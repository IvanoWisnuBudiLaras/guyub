#!/usr/bin/env bash
# Runs the operator-flow e2e suite against the Android emulator with the
# Firebase emulator suite seeded behind it.
#
# Needs: a booted Android emulator, the debug APK installed, and the AVD named
# guyub_e2e (pinned in e2e/e2e.config.ts).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

SUITE="${1:-tests/operator-flow.e2e.ts}"

export GCLOUD_PROJECT=demo-guyub-development
export FIREBASE_AUTH_EMULATOR_HOST=127.0.0.1:9099
export FIRESTORE_EMULATOR_HOST=127.0.0.1:8080
export FIREBASE_STORAGE_EMULATOR_HOST=127.0.0.1:9199
export GUYUB_EVIDENCE_BUCKET=demo-guyub-development.appspot.com

cat > /tmp/guyub_e2e_suite.sh <<INNER
set -e
node functions/test/seed_e2e_campaign.js
# Clear stored sessions so the suite starts signed out. Done here, once, rather
# than per test: \`app.clearState()\` mid-run destabilises the emulator.
adb shell pm clear com.guyub.guyub > /dev/null
cd e2e && npx e2e run ${SUITE}
INNER

npx --yes firebase-tools@15.32.1 emulators:exec \
  --project demo-guyub-development --only auth,firestore,functions,storage \
  "bash /tmp/guyub_e2e_suite.sh"
