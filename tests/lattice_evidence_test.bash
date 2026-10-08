#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

timeout --kill-after=5s 30s \
  env UPKEEPER_LATTICE_TEST_GROUP=evidence \
  bash "$ROOT_DIR/tests/lattice_test.bash"
