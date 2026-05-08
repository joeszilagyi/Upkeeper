#!/usr/bin/env bash
set -euo pipefail

# This is intentionally just a visible forever loop around one Upkeeper command.
# It runs Spark-5.3 with xhigh reasoning, sleeps after clean exits, and stops on
# the first non-zero wrapper exit while preserving that exit code.
#
# Documentation: launcher_examples/README.md
# When changing launcher behavior, update that paired doc if examples or safety
# expectations change.

UPKEEPER_CMD=${UPKEEPER_CMD:-./Upkeeper}
UPKEEPER_LOOP_MODEL=${UPKEEPER_LOOP_MODEL:-gpt-5.3-codex-spark}
UPKEEPER_LOOP_EFFORT=${UPKEEPER_LOOP_EFFORT:-xhigh}
UPKEEPER_LOOP_STOP_PERCENT=${UPKEEPER_LOOP_STOP_PERCENT:-0}
UPKEEPER_LOOP_SLEEP_SECONDS=${UPKEEPER_LOOP_SLEEP_SECONDS:-60}

usage() {
  cat <<EOF
Usage: ${0##*/} [--help]

Run Upkeeper in a forever loop with Spark-5.3 Codex xhigh defaults.
The loop stops on the first non-zero Upkeeper exit and preserves that exit code.

Environment:
  UPKEEPER_CMD                    Command to run (default: ./Upkeeper)
  UPKEEPER_LOOP_MODEL             Codex model (default: gpt-5.3-codex-spark)
  UPKEEPER_LOOP_EFFORT            Reasoning effort (default: xhigh)
  UPKEEPER_LOOP_STOP_PERCENT      Spark 5-hour stop threshold, 0-100 (default: 0)
  UPKEEPER_LOOP_SLEEP_SECONDS     Sleep after clean exits, in seconds (default: 60)
  UPKEEPER_LOOP_DRY_RUN           Set to 1 to print resolved settings and exit
EOF
}

validate_percent_threshold() {
  local name="$1"
  local value="$2"

  if ! awk -v value="$value" '
    function is_number(raw) {
      return raw ~ /^[-+]?([0-9]+([.][0-9]*)?|[.][0-9]+)$/
    }
    BEGIN {
      if (!is_number(value) || value + 0 < 0 || value + 0 > 100) {
        exit 1
      }
    }
  '; then
    echo "$name must be a number from 0 through 100: $value" >&2
    exit 64
  fi
}

if [[ "$#" -gt 1 ]]; then
  echo "Unexpected arguments: $*" >&2
  usage >&2
  exit 64
fi

case "${1:-}" in
  -h|--help)
    usage
    exit 0
    ;;
  '')
    ;;
  *)
    echo "Unexpected argument: $1" >&2
    usage >&2
    exit 64
    ;;
esac

if [[ ! -x "$UPKEEPER_CMD" ]]; then
  echo "Upkeeper command is not executable: $UPKEEPER_CMD" >&2
  exit 127
fi

case "$UPKEEPER_LOOP_SLEEP_SECONDS" in
  ''|*[!0-9]*)
    echo "UPKEEPER_LOOP_SLEEP_SECONDS must be a non-negative integer: $UPKEEPER_LOOP_SLEEP_SECONDS" >&2
    exit 64
    ;;
esac

validate_percent_threshold UPKEEPER_LOOP_STOP_PERCENT "$UPKEEPER_LOOP_STOP_PERCENT"

if [[ "${UPKEEPER_LOOP_DRY_RUN:-0}" == "1" ]]; then
  cat <<EOF
Dry-run: ${UPKEEPER_CMD} would be executed repeatedly with:
  CODEX_MODEL=$UPKEEPER_LOOP_MODEL
  CODEX_REASONING_EFFORT=$UPKEEPER_LOOP_EFFORT
  CODEX_SPARK_5H_STOP_PERCENT=$UPKEEPER_LOOP_STOP_PERCENT
  sleep=${UPKEEPER_LOOP_SLEEP_SECONDS}s between cycles
EOF
  exit 0
fi

iteration=0
while true; do
  iteration=$((iteration + 1))
  echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] starting cycle $iteration"

  if CODEX_MODEL="$UPKEEPER_LOOP_MODEL" \
    CODEX_REASONING_EFFORT="$UPKEEPER_LOOP_EFFORT" \
    CODEX_SPARK_5H_STOP_PERCENT="$UPKEEPER_LOOP_STOP_PERCENT" \
    "$UPKEEPER_CMD"; then
    :
  else
    status=$?
    echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] Upkeeper exited with code $status; stopping." >&2
    exit "$status"
  fi

  echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] completed cycle $iteration; sleeping ${UPKEEPER_LOOP_SLEEP_SECONDS}s"
  sleep "$UPKEEPER_LOOP_SLEEP_SECONDS"
done
