#!/usr/bin/env bash
set -euo pipefail

echo "==> 1. Format check"
dart format --output=none --set-exit-if-changed .

echo "==> 2. Static analysis"
flutter analyze

echo "==> 3. Automated tests"
flutter test

echo "==> All test checks passed."
