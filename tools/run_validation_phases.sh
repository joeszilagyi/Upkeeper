#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

PHASES_CSV="${UPKEEPER_VALIDATION_PHASES:-shell_syntax,unit_tests,public_docs,diff_whitespace,quick_validator}"
PHASE_JOBS="${UPKEEPER_VALIDATION_PHASE_JOBS:-auto}"
PHASE_TIMEOUT_SECONDS="${UPKEEPER_VALIDATION_PHASE_TIMEOUT_SECONDS:-900}"
SHOW_PASS_OUTPUT="${UPKEEPER_VALIDATION_PHASE_SHOW_PASS_OUTPUT:-0}"
RUNNER_TMP_ROOT=""

usage() {
  cat <<'USAGE'
Usage: tools/run_validation_phases.sh [--phases a,b,c] [--jobs N] [--serial]

Run independent local validation phases with bounded parallelism and a timing
table. Supported phases:
  shell_syntax, unit_tests, public_docs, diff_whitespace, quick_validator
USAGE
}

fail() {
  printf 'run_validation_phases: ERROR: %s\n' "$*" >&2
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
    --phases)
      [[ -n "${2:-}" ]] || fail "--phases requires a value"
      PHASES_CSV="$2"
      shift 2
      ;;
    --jobs)
      [[ -n "${2:-}" ]] || fail "--jobs requires a value"
      PHASE_JOBS="$2"
      shift 2
      ;;
    --serial)
      PHASE_JOBS=1
      shift
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

if [[ "$PHASE_JOBS" == "auto" ]]; then
  if command -v nproc >/dev/null 2>&1; then
    PHASE_JOBS="$(nproc)"
  else
    PHASE_JOBS=4
  fi
fi
[[ "$PHASE_JOBS" =~ ^[0-9]+$ && "$PHASE_JOBS" -ge 1 ]] || fail "invalid jobs value: $PHASE_JOBS"
[[ "$PHASE_TIMEOUT_SECONDS" =~ ^[0-9]+$ && "$PHASE_TIMEOUT_SECONDS" -ge 1 ]] || fail "invalid timeout: $PHASE_TIMEOUT_SECONDS"

IFS=, read -r -a RAW_PHASES <<<"$PHASES_CSV"
PHASES=()
for phase in "${RAW_PHASES[@]}"; do
  phase="${phase#"${phase%%[![:space:]]*}"}"
  phase="${phase%"${phase##*[![:space:]]}"}"
  [[ -n "$phase" ]] || continue
  case "$phase" in
    shell_syntax|unit_tests|public_docs|diff_whitespace|quick_validator)
      PHASES+=("$phase")
      ;;
    *)
      fail "unsupported phase: $phase"
      ;;
  esac
done
[[ "${#PHASES[@]}" -gt 0 ]] || fail "no validation phases selected"

RUNNER_TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/upkeeper-validation-phases.XXXXXX")"

phase_command() {
  local phase="$1"

  case "$phase" in
    shell_syntax)
      bash -n Upkeeper ChimneySweep FlameOn Upkeeper.conf configurations/default.conf completions/*.bash lib/upkeeper/*.bash tools/*.sh tests/*.bash testruns/*.sh orchestration/*.sh
      ;;
    unit_tests)
      tools/run_tests.sh
      ;;
    public_docs)
      tools/check_public_docs.sh --quick
      ;;
    diff_whitespace)
      git diff --check
      ;;
    quick_validator)
      tools/validate_upkeeper.sh --quick
      ;;
  esac
}

run_one_phase() {
  local phase="$1"
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
  timeout --kill-after=5s "$PHASE_TIMEOUT_SECONDS" bash -c '
    set -euo pipefail
    cd "$1"
    case "$2" in
      shell_syntax)
        bash -n Upkeeper ChimneySweep FlameOn Upkeeper.conf configurations/default.conf completions/*.bash lib/upkeeper/*.bash tools/*.sh tests/*.bash testruns/*.sh orchestration/*.sh
        ;;
      unit_tests)
        tools/run_tests.sh
        ;;
      public_docs)
        tools/check_public_docs.sh --quick
        ;;
      diff_whitespace)
        git diff --check
        ;;
      quick_validator)
        tools/validate_upkeeper.sh --quick
        ;;
      *)
        printf "unsupported phase: %s\n" "$2" >&2
        exit 64
        ;;
    esac
  ' bash "$ROOT_DIR" "$phase" >"$out_file" 2>&1
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
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$index" "$phase" "$status" "$rc" "$elapsed_us" "$out_file" >"$result_file"
}

wait_for_slot() {
  local running

  while true; do
    running="$(jobs -pr | wc -l | tr -d ' ')"
    if [[ "$running" -lt "$PHASE_JOBS" ]]; then
      return 0
    fi
    wait -n || true
  done
}

printf 'run_validation_phases: start phases=%s jobs=%s timeout=%ss\n' "$PHASES_CSV" "$PHASE_JOBS" "$PHASE_TIMEOUT_SECONDS"

index=0
for phase in "${PHASES[@]}"; do
  index=$((index + 1))
  printf '%s\n' "$phase" >"$RUNNER_TMP_ROOT/$index.phase"
  wait_for_slot
  run_one_phase "$phase" "$index" &
done
wait || true

overall_rc=0
index=0
for phase in "${PHASES[@]}"; do
  index=$((index + 1))
  result_file="$RUNNER_TMP_ROOT/$index.result"
  [[ -f "$result_file" ]] || {
    printf 'PHASE %s status=missing rc=127 elapsed=0.000s\n' "$phase" >&2
    overall_rc=127
    continue
  }
  IFS=$'\t' read -r _ result_phase status rc elapsed_us out_file <"$result_file"
  printf 'PHASE %s status=%s rc=%s elapsed=%d.%03ds\n' \
    "$result_phase" "$status" "$rc" "$((elapsed_us / 1000000))" "$(((elapsed_us % 1000000) / 1000))"
  if [[ "$SHOW_PASS_OUTPUT" == "1" || "$status" != "pass" ]]; then
    sed 's/^/  | /' "$out_file"
  fi
  if [[ "$rc" -ne 0 && "$overall_rc" -eq 0 ]]; then
    overall_rc="$rc"
  fi
done

if [[ "$overall_rc" -eq 0 ]]; then
  printf 'run_validation_phases: ok\n'
else
  printf 'run_validation_phases: failed rc=%s\n' "$overall_rc" >&2
fi
exit "$overall_rc"
