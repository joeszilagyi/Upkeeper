#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

# upkeeper-test-serial-only
# This group deliberately retains broad CLI, full-doctor, import/export, and
# failure-exit coverage. Run it after the parallel test set: concurrent
# Lattice-heavy fixtures can consume its bounded in-process response budget on
# constrained CI runners. The marker keeps ordinary ledger tests parallel
# while retaining deterministic timeout diagnostics for genuine hangs.
timeout --kill-after=5s 45s \
  env UPKEEPER_LATTICE_TEST_GROUP=cli-integration \
  bash "$ROOT_DIR/tests/lattice_test.bash"
