#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

TEST_JOBS="${UPKEEPER_TEST_JOBS:-auto}"
TEST_TIMEOUT_SECONDS="${UPKEEPER_TEST_TIMEOUT_SECONDS:-180}"
SLOW_TEST_SECONDS="${UPKEEPER_SLOW_TEST_SECONDS:-15}"
SHOW_PASS_OUTPUT="${UPKEEPER_TEST_SHOW_PASS_OUTPUT:-0}"
SERIAL_ONLY_CSV="${UPKEEPER_TEST_SERIAL_ONLY:-}"
RUNNER_TMP_ROOT=""

usage() {
  cat <<'USAGE'
Usage: tools/run_tests.sh [--serial|--jobs N]

Run tests/*.bash with per-test timing and deterministic failure attribution.
By default tests run in bounded parallel mode. Set UPKEEPER_TEST_JOBS=1 or pass
--serial to retain the old strictly serial debugging path.
USAGE
}

fail() {
  printf 'run_tests: ERROR: %s\n' "$*" >&2
  exit 1
}

cleanup() {
  if [[ -n "$RUNNER_TMP_ROOT" ]]; then
    rm -rf -- "$RUNNER_TMP_ROOT"
  fi
}
trap cleanup EXIT

while [[ $# -gt 0 ]]; do
  case "$1" in
    --serial)
      TEST_JOBS=1
      shift
      ;;
    --jobs)
      [[ -n "${2:-}" ]] || fail "--jobs requires a value"
      TEST_JOBS="$2"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      fail "unknown argument: $1"
      ;;
  esac
done

mapfile -t TESTS < <(find tests -maxdepth 1 -type f -name '*.bash' | sort)
[[ "${#TESTS[@]}" -gt 0 ]] || fail "no tests/*.bash files found"

if [[ "$TEST_JOBS" == "auto" ]]; then
  if command -v nproc >/dev/null 2>&1; then
    TEST_JOBS="$(nproc)"
  else
    TEST_JOBS=4
  fi
fi
[[ "$TEST_JOBS" =~ ^[0-9]+$ && "$TEST_JOBS" -ge 1 ]] || fail "invalid jobs value: $TEST_JOBS"
[[ "$TEST_TIMEOUT_SECONDS" =~ ^[0-9]+$ && "$TEST_TIMEOUT_SECONDS" -ge 1 ]] || fail "invalid timeout: $TEST_TIMEOUT_SECONDS"

RUNNER_TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/upkeeper-test-runner.XXXXXX")"

test_is_serial_only() {
  local test_path="$1"
  local item
  local -a serial_items=()

  if grep -Eq 'UPKEEPER_TEST_SERIAL_ONLY=1|upkeeper-test-serial-only' "$test_path"; then
    return 0
  fi
  IFS=, read -r -a serial_items <<<"$SERIAL_ONLY_CSV"
  for item in "${serial_items[@]:-}"; do
    item="${item#"${item%%[![:space:]]*}"}"
    item="${item%"${item##*[![:space:]]}"}"
    [[ -n "$item" ]] || continue
    [[ "$test_path" == "$item" || "$(basename -- "$test_path")" == "$item" ]] && return 0
  done
  return 1
}

run_one_test() {
  local test_path="$1"
  local index="$2"
  local out_file="$RUNNER_TMP_ROOT/$index.out"
  local result_file="$RUNNER_TMP_ROOT/$index.result"
  local start_us end_us elapsed_us rc=0 status

  start_us="${EPOCHREALTIME:-}"
  if [[ -n "$start_us" ]]; then
    start_us="${start_us/./}"
  else
    start_us="$(date +%s%6N)"
  fi

  set +e
  timeout --kill-after=5s "$TEST_TIMEOUT_SECONDS" bash "$test_path" >"$out_file" 2>&1
  rc=$?
  set -e

  end_us="${EPOCHREALTIME:-}"
  if [[ -n "$end_us" ]]; then
    end_us="${end_us/./}"
  else
    end_us="$(date +%s%6N)"
  fi
  elapsed_us=$((end_us - start_us))
  if [[ "$rc" -eq 0 ]]; then
    status=pass
  elif [[ "$rc" -eq 124 ]]; then
    status=timeout
  else
    status=fail
  fi

  printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$index" "$test_path" "$status" "$rc" "$elapsed_us" "$out_file" >"$result_file"
}

wait_for_slot() {
  local running

  while true; do
    running="$(jobs -pr | wc -l | tr -d ' ')"
    if [[ "$running" -lt "$TEST_JOBS" ]]; then
      return 0
    fi
    wait -n || true
  done
}

parallel_indices=()
serial_indices=()
index=0
for test_path in "${TESTS[@]}"; do
  index=$((index + 1))
  if test_is_serial_only "$test_path"; then
    serial_indices+=("$index")
    printf '%s\n' "$test_path" >"$RUNNER_TMP_ROOT/$index.path"
  else
    parallel_indices+=("$index")
    printf '%s\n' "$test_path" >"$RUNNER_TMP_ROOT/$index.path"
  fi
done

printf 'run_tests: start tests=%s parallel=%s serial=%s jobs=%s timeout=%ss\n' \
  "${#TESTS[@]}" "${#parallel_indices[@]}" "${#serial_indices[@]}" "$TEST_JOBS" "$TEST_TIMEOUT_SECONDS"

for index in "${parallel_indices[@]}"; do
  test_path="$(<"$RUNNER_TMP_ROOT/$index.path")"
  wait_for_slot
  run_one_test "$test_path" "$index" &
done
wait || true

for index in "${serial_indices[@]}"; do
  test_path="$(<"$RUNNER_TMP_ROOT/$index.path")"
  run_one_test "$test_path" "$index"
done

overall_rc=0
index=1
while [[ "$index" -le "${#TESTS[@]}" ]]; do
  result_file="$RUNNER_TMP_ROOT/$index.result"
  [[ -f "$result_file" ]] || {
    printf 'TEST %s status=missing rc=127 elapsed=0.000s\n' "$(<"$RUNNER_TMP_ROOT/$index.path")" >&2
    overall_rc=127
    continue
  }
  IFS=$'\t' read -r _ test_path status rc elapsed_us out_file <"$result_file"
  printf 'TEST %s status=%s rc=%s elapsed=%d.%03ds\n' \
    "$test_path" "$status" "$rc" "$((elapsed_us / 1000000))" "$(((elapsed_us % 1000000) / 1000))"
  if [[ "$SHOW_PASS_OUTPUT" == "1" || "$status" != "pass" ]]; then
    sed 's/^/  | /' "$out_file"
  fi
  if [[ "$status" == "pass" && "$((elapsed_us / 1000000))" -gt "$SLOW_TEST_SECONDS" ]]; then
    printf 'SLOW_TEST %s elapsed=%d.%03ds budget=%ss\n' \
      "$test_path" "$((elapsed_us / 1000000))" "$(((elapsed_us % 1000000) / 1000))" "$SLOW_TEST_SECONDS" >&2
  fi
  if [[ "$rc" -ne 0 && "$overall_rc" -eq 0 ]]; then
    overall_rc="$rc"
  fi
  index=$((index + 1))
done

if [[ "$overall_rc" -eq 0 ]]; then
  printf 'run_tests: ok\n'
else
  printf 'run_tests: failed rc=%s\n' "$overall_rc" >&2
fi
exit "$overall_rc"
