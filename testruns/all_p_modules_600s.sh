#!/usr/bin/env bash
set -euo pipefail

# Quota-respecting watch loop for full Upkeeper review coverage.
# Runs P1-P23 with --prompt-pass=all and appends P24-P30.

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

UPKEEPER_CMD="${UPKEEPER_CMD:-./Upkeeper}"
UPKEEPER_TEST_MODEL="${UPKEEPER_TEST_MODEL:-gpt-5.5}"
UPKEEPER_TEST_EFFORT="${UPKEEPER_TEST_EFFORT:-xhigh}"
UPKEEPER_TEST_5H_STOP_PERCENT="${UPKEEPER_TEST_5H_STOP_PERCENT:-5}"
UPKEEPER_TEST_WEEK_STOP_PERCENT="${UPKEEPER_TEST_WEEK_STOP_PERCENT:-15}"
UPKEEPER_TEST_TERMINAL_VERBOSITY="${UPKEEPER_TEST_TERMINAL_VERBOSITY:-basic}"
UPKEEPER_TEST_SLEEP_SECONDS="${UPKEEPER_TEST_SLEEP_SECONDS:-600}"

case "$UPKEEPER_TEST_SLEEP_SECONDS" in
  ''|*[!0-9]*)
    echo "UPKEEPER_TEST_SLEEP_SECONDS must be a non-negative integer: $UPKEEPER_TEST_SLEEP_SECONDS" >&2
    exit 64
    ;;
esac

if [[ ! -x "$UPKEEPER_CMD" ]]; then
  echo "Upkeeper command is not executable: $UPKEEPER_CMD" >&2
  exit 127
fi

iteration=0
while true; do
  iteration=$((iteration + 1))
  echo "[$(date '+%Y-%m-%dT%H:%M:%S%z')] testrun all_p_modules_600s cycle=$iteration start"

  set +e
  CODEX_MODEL="$UPKEEPER_TEST_MODEL" \
    CODEX_REASONING_EFFORT="$UPKEEPER_TEST_EFFORT" \
    CODEX_5H_STOP_PERCENT="$UPKEEPER_TEST_5H_STOP_PERCENT" \
    CODEX_WEEK_STOP_PERCENT="$UPKEEPER_TEST_WEEK_STOP_PERCENT" \
    CODEX_TERMINAL_VERBOSITY="$UPKEEPER_TEST_TERMINAL_VERBOSITY" \
    "$UPKEEPER_CMD" --prompt-pass=all --review-modules=p24,p25,p26,p27,p28,p29,p30 "$@"
  rc=$?
  set -e

  echo "[$(date '+%Y-%m-%dT%H:%M:%S%z')] testrun all_p_modules_600s cycle=$iteration rc=$rc"
  case "$rc" in
    0)
      sleep "$UPKEEPER_TEST_SLEEP_SECONDS"
      ;;
    75)
      echo "[$(date '+%Y-%m-%dT%H:%M:%S%z')] stopping loop on quota/parent-stop guardrail rc=75" >&2
      exit "$rc"
      ;;
    *)
      echo "[$(date '+%Y-%m-%dT%H:%M:%S%z')] stopping loop on rc=$rc" >&2
      exit "$rc"
      ;;
  esac
done
