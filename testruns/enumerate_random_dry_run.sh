#!/usr/bin/env bash
set -euo pipefail

# Local selector smoke test: bypass the manifest and choose a random target.

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

UPKEEPER_CMD="${UPKEEPER_CMD:-./Upkeeper}"
UPKEEPER_TEST_MODEL="${UPKEEPER_TEST_MODEL:-gpt-5.5}"
UPKEEPER_TEST_EFFORT="${UPKEEPER_TEST_EFFORT:-xhigh}"
UPKEEPER_TEST_TERMINAL_VERBOSITY="${UPKEEPER_TEST_TERMINAL_VERBOSITY:-basic}"

UPKEEPER_DRY_RUN=1 \
  CODEX_MODEL="$UPKEEPER_TEST_MODEL" \
  CODEX_REASONING_EFFORT="$UPKEEPER_TEST_EFFORT" \
  CODEX_TERMINAL_VERBOSITY="$UPKEEPER_TEST_TERMINAL_VERBOSITY" \
  "$UPKEEPER_CMD" --selection-source=enumerate --random-target "$@"
