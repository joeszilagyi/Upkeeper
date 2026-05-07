#!/usr/bin/env bash
set -euo pipefail

# This is intentionally just a visible forever loop around one Upkeeper command.
# It runs Spark-5.3 with xhigh reasoning, sleeps after clean exits, and stops on
# the first non-zero wrapper exit while preserving that exit code.

UPKEEPER_CMD=${UPKEEPER_CMD:-./Upkeeper}
UPKEEPER_LOOP_MODEL=${UPKEEPER_LOOP_MODEL:-gpt-5.3-codex-spark}
UPKEEPER_LOOP_EFFORT=${UPKEEPER_LOOP_EFFORT:-xhigh}
UPKEEPER_LOOP_STOP_PERCENT=${UPKEEPER_LOOP_STOP_PERCENT:-0}
UPKEEPER_LOOP_SLEEP_SECONDS=${UPKEEPER_LOOP_SLEEP_SECONDS:-60}

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
