#!/usr/bin/env bash
set -euo pipefail

./tool/verify.sh
./tool/test_firestore_rules.sh
