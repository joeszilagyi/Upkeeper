#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

# This group deliberately retains broad CLI, full-doctor, import/export, and
# failure-exit coverage. Keep it separate and bounded so ordinary ledger tests
# do not serialize behind the intentionally expensive full integration path.
timeout --kill-after=5s 45s \
  env UPKEEPER_LATTICE_TEST_GROUP=cli-integration \
  bash "$ROOT_DIR/tests/lattice_test.bash"
