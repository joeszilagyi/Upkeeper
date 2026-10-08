#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/upkeeper-lattice-tests.XXXXXX")"
export PYTHONDONTWRITEBYTECODE=1
trap 'rm -rf -- "$TMP_ROOT"' EXIT

tests=(
  tests/lattice_test.bash
  tests/lattice_cli_integration_test.bash
  tests/lattice_wrapper_integration_test.bash
  tests/lattice_evidence_test.bash
  tests/lattice_timeout_test.bash
  tests/lattice_finish_retry_test.bash
)
pids=()

cd "$ROOT_DIR"
for index in "${!tests[@]}"; do
  timeout --kill-after=5s 55s bash "${tests[index]}" >"$TMP_ROOT/$index.out" 2>&1 &
  pids[index]="$!"
done

status=0
for index in "${!tests[@]}"; do
  rc=0
  wait "${pids[index]}" || rc="$?"
  cat "$TMP_ROOT/$index.out"
  if [[ "$rc" -ne 0 ]]; then
    printf 'run_lattice_tests: FAIL test=%s rc=%s\n' "${tests[index]}" "$rc" >&2
    status=1
  fi
done

[[ "$status" -eq 0 ]] || exit "$status"
printf 'run_lattice_tests: ok groups=%s\n' "${#tests[@]}"
