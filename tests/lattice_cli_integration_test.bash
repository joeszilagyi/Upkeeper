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

printf -v lattice_cleanup_command 'env UPKEEPER_LATTICE_TEST_GROUP=cleanup bash %q' \
  "$ROOT_DIR/tests/lattice_test.bash"
cleanup_root_record="$(mktemp "${TMPDIR:-/tmp}/upkeeper-lattice-cleanup-root.XXXXXX")"
trap 'rm -f -- "$cleanup_root_record"' EXIT

# A pseudo-terminal exercises cleanup against a read-only fixture; without the
# non-interactive cleanup flag, rm sees EOF at its confirmation prompt and
# leaves the test root behind.
timeout --kill-after=5s 10s \
  env LATTICE_TEST_CLEANUP_ROOT_RECORD="$cleanup_root_record" \
  script -qfec "$lattice_cleanup_command" /dev/null </dev/null

cleanup_root="$(<"$cleanup_root_record")"
[[ -n "$cleanup_root" && ! -e "$cleanup_root" ]] || {
  printf 'lattice_cli_integration_test: cleanup left read-only fixture root=%s\n' "$cleanup_root" >&2
  exit 1
}
