#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

# Required/advisory policy uses complete wrapper dry-runs. It is intentionally
# isolated from core ledger assertions and hard-bounded as an integration test.
timeout --kill-after=5s 30s \
  env UPKEEPER_LATTICE_TEST_GROUP=wrapper-integration \
  bash "$ROOT_DIR/tests/lattice_test.bash"
