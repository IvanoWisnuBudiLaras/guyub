#!/usr/bin/env bash
set -euo pipefail

echo "========================================================"
echo " Guyub.id — Unified Verification Gate (Phase 0 Baseline)"
echo "========================================================"

echo ""
echo "==> 1/4 Memeriksa format kode (dart format)..."
dart format --output=none --set-exit-if-changed .

echo ""
echo "==> 2/4 Menjalankan static analysis (flutter analyze)..."
flutter analyze

echo ""
echo "==> 3/4 Menjalankan automated test baseline (flutter test)..."
flutter test

echo ""
echo "==> 4/4 Memverifikasi build Android (flutter build apk --debug)..."
flutter build apk --debug

echo ""
echo "========================================================"
echo " ✓ SELURUH GERBANG VERIFIKASI LOLOS DENGAN SUKSES."
echo "========================================================"
