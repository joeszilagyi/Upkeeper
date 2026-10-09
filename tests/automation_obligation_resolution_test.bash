#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/upkeeper-obligation-resolution.XXXXXX")"
trap 'rm -rf "$TEST_TMP_ROOT"' EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

shell_quote() {
  printf '%q' "$1"
}

log_line() {
  printf '%s %s\n' "$1" "$2" >>"$TEST_LOG"
}

ROOT_DIR="$TEST_TMP_ROOT/repo"
UPKEEPER_OBLIGATION_DIR="$TEST_TMP_ROOT/obligations"
UPKEEPER_AUTOMATION_LEDGER_DIR="$TEST_TMP_ROOT/ledger"
TEST_LOG="$TEST_TMP_ROOT/automation.log"
TARGET_PATH="repair-target.txt"
OTHER_TARGET_PATH="other-target.txt"
mkdir -p "$ROOT_DIR" "$UPKEEPER_OBLIGATION_DIR/open"
: >"$TEST_LOG"

source "$PROJECT_ROOT/lib/upkeeper/automation_obligations.bash"

write_obligation() {
  local obligation_id="$1"
  python3 - "$UPKEEPER_OBLIGATION_DIR/open/$obligation_id.json" "$obligation_id" "$ROOT_DIR" "$TARGET_PATH" <<'PY'
import json
import sys

path, obligation_id, root, target = sys.argv[1:5]
with open(path, "w", encoding="utf-8") as handle:
    json.dump(
        {
            "schema": 1,
            "record_type": "automation_obligation",
            "status": "open",
            "id": obligation_id,
            "root": root,
            "kind": "blocked",
            "summary": "resolution proof fixture",
            "target_scope": "target",
            "target_file": target,
            "repair_target_file": target,
            "required_resolution": [
                "repair the selected target",
                "run focused deterministic validation",
            ],
        },
        handle,
        separators=(",", ":"),
    )
    handle.write("\n")
PY
  chmod 600 "$UPKEEPER_OBLIGATION_DIR/open/$obligation_id.json"
}

write_resolution_message() {
  local obligation_id="$1"
  local classification="$2"
  local marker_target="$3"
  local evidence="$4"
  local output_path="$5"
  local digest_override="${6:-}"
  python3 - \
    "$UPKEEPER_OBLIGATION_DIR/open/$obligation_id.json" \
    "$classification" \
    "$marker_target" \
    "$evidence" \
    "$output_path" \
    "$digest_override" <<'PY'
import hashlib
import json
import sys

obligation_path, classification, target, evidence, output_path, digest_override = sys.argv[1:7]
with open(obligation_path, "r", encoding="utf-8") as handle:
    obligation = json.load(handle)
required = obligation.get("required_resolution") or []
if not isinstance(required, list):
    required = [str(required)]
required = [str(item) for item in required]
required_digest = hashlib.sha256(
    json.dumps(required, ensure_ascii=True, separators=(",", ":")).encode("utf-8")
).hexdigest()
if digest_override:
    required_digest = digest_override
marker = {
    "id": obligation["id"],
    "classification": classification,
    "target": target,
    "required_resolution_sha256": required_digest,
    "evidence": [evidence],
}
with open(output_path, "w", encoding="utf-8") as handle:
    handle.write("UPKEEPER_OBLIGATION_RESOLUTION: ")
    handle.write(json.dumps(marker, ensure_ascii=True, separators=(",", ":")))
    handle.write("\nUPKEEPER_STATUS: WORK_DONE\n")
PY
}

prepare_attempt() {
  local obligation_id="$1"
  local selected_target="${2:-$TARGET_PATH}"

  CYCLE_ID="cycle-$obligation_id"
  CYCLE_RUN_HASH="run-$obligation_id"
  UPKEEPER_AUTOMATION_WORKFLOW="obligation-repair"
  UPKEEPER_AUTOMATION_OBLIGATION_ID="$obligation_id"
  UPKEEPER_AUTOMATION_OBLIGATION_PATH="$UPKEEPER_OBLIGATION_DIR/open/$obligation_id.json"
  UPKEEPER_AUTOMATION_OBLIGATION_CLAIM_PATH=""
  UPKEEPER_AUTOMATION_OBLIGATION_CLAIM_TOKEN=""
  RUN_SELECTED_REVIEW_PATH="$selected_target"
  RUN_LAST_MESSAGE_FILE="$TEST_TMP_ROOT/$obligation_id.last-message.txt"
  UPKEEPER_AUTOMATION_OBLIGATION_TARGET_BEFORE_STATE=""
  write_obligation "$obligation_id"
}

test_repaired_requires_bound_proof_and_target_change() {
  local obligation_id="repair-success"
  printf 'before\n' >"$ROOT_DIR/$TARGET_PATH"
  prepare_attempt "$obligation_id"
  automation_capture_obligation_resolution_baseline "$TARGET_PATH"
  printf 'after\n' >"$ROOT_DIR/$TARGET_PATH"
  write_resolution_message "$obligation_id" repaired "$TARGET_PATH" "focused validation passed" "$RUN_LAST_MESSAGE_FILE"

  automation_resolve_selected_obligation 0 WORK_DONE WORK_DONE "$TARGET_PATH"

  [[ ! -e "$UPKEEPER_AUTOMATION_OBLIGATION_PATH" ]] || fail "proved repair remained open"
  local resolved="$UPKEEPER_OBLIGATION_DIR/resolved/$obligation_id.json"
  [[ -f "$resolved" ]] || fail "proved repair did not create a resolved record"
  [[ "$(jq -r '.resolution_proof.classification' "$resolved")" == "repaired" ]] || fail "resolved repair lost its classification"
  [[ "$(jq -r '.resolution_proof.target' "$resolved")" == "$TARGET_PATH" ]] || fail "resolved repair lost its target binding"
  [[ "$(jq -r '.resolution_proof.target_before.sha256' "$resolved")" != "$(jq -r '.resolution_proof.target_after.sha256' "$resolved")" ]] || fail "resolved repair did not preserve target delta proof"
}

test_zero_exit_without_marker_stays_open() {
  local obligation_id="missing-proof"
  printf 'unchanged\n' >"$ROOT_DIR/$TARGET_PATH"
  prepare_attempt "$obligation_id"
  automation_capture_obligation_resolution_baseline "$TARGET_PATH"
  printf 'UPKEEPER_STATUS: WORK_DONE\n' >"$RUN_LAST_MESSAGE_FILE"

  automation_resolve_selected_obligation 0 WORK_DONE WORK_DONE "$TARGET_PATH"

  [[ -f "$UPKEEPER_AUTOMATION_OBLIGATION_PATH" ]] || fail "zero-exit no-op without proof resolved the obligation"
  grep -Fq 'proof_reason=missing_resolution_marker' "$TEST_LOG" || fail "missing proof rejection was not logged"
}

test_repaired_marker_without_target_change_stays_open() {
  local obligation_id="no-op-repaired"
  printf 'unchanged\n' >"$ROOT_DIR/$TARGET_PATH"
  prepare_attempt "$obligation_id"
  automation_capture_obligation_resolution_baseline "$TARGET_PATH"
  write_resolution_message "$obligation_id" repaired "$TARGET_PATH" "claimed repair validation" "$RUN_LAST_MESSAGE_FILE"

  automation_resolve_selected_obligation 0 WORK_DONE WORK_DONE "$TARGET_PATH"

  [[ -f "$UPKEEPER_AUTOMATION_OBLIGATION_PATH" ]] || fail "self-asserted repaired marker resolved an unchanged target"
  grep -Fq 'proof_reason=repaired_target_unchanged' "$TEST_LOG" || fail "unchanged repaired target rejection was not logged"
}

test_wrong_target_success_stays_open() {
  local obligation_id="wrong-target"
  printf 'expected\n' >"$ROOT_DIR/$TARGET_PATH"
  printf 'before\n' >"$ROOT_DIR/$OTHER_TARGET_PATH"
  prepare_attempt "$obligation_id" "$OTHER_TARGET_PATH"
  automation_capture_obligation_resolution_baseline "$OTHER_TARGET_PATH"
  printf 'after\n' >"$ROOT_DIR/$OTHER_TARGET_PATH"
  write_resolution_message "$obligation_id" repaired "$TARGET_PATH" "unrelated target changed" "$RUN_LAST_MESSAGE_FILE"

  automation_resolve_selected_obligation 0 WORK_DONE WORK_DONE "$OTHER_TARGET_PATH"

  [[ -f "$UPKEEPER_AUTOMATION_OBLIGATION_PATH" ]] || fail "wrong-target successful run resolved the obligation"
  grep -Fq 'proof_reason=selected_target_mismatch' "$TEST_LOG" || fail "wrong-target rejection was not logged"
}

test_required_resolution_mismatch_stays_open() {
  local obligation_id="required-resolution-mismatch"
  printf 'before\n' >"$ROOT_DIR/$TARGET_PATH"
  prepare_attempt "$obligation_id"
  automation_capture_obligation_resolution_baseline "$TARGET_PATH"
  printf 'after\n' >"$ROOT_DIR/$TARGET_PATH"
  write_resolution_message "$obligation_id" repaired "$TARGET_PATH" "unbound validation claim" "$RUN_LAST_MESSAGE_FILE" "$(printf '0%.0s' {1..64})"

  automation_resolve_selected_obligation 0 WORK_DONE WORK_DONE "$TARGET_PATH"

  [[ -f "$UPKEEPER_AUTOMATION_OBLIGATION_PATH" ]] || fail "mismatched required-resolution proof resolved the obligation"
  grep -Fq 'proof_reason=required_resolution_mismatch' "$TEST_LOG" || fail "required-resolution mismatch was not logged"
}

test_blocked_run_stays_open() {
  local obligation_id="blocked-run"
  printf 'unchanged\n' >"$ROOT_DIR/$TARGET_PATH"
  prepare_attempt "$obligation_id"
  write_resolution_message "$obligation_id" obsolete "$TARGET_PATH" "blocked fixture" "$RUN_LAST_MESSAGE_FILE"

  automation_resolve_selected_obligation 2 BLOCKED BLOCKED "$TARGET_PATH"

  [[ -f "$UPKEEPER_AUTOMATION_OBLIGATION_PATH" ]] || fail "blocked run resolved the obligation"
}

test_explicit_obsolete_proof_resolves_unchanged_target() {
  local obligation_id="obsolete-success"
  printf 'unchanged\n' >"$ROOT_DIR/$TARGET_PATH"
  prepare_attempt "$obligation_id"
  automation_capture_obligation_resolution_baseline "$TARGET_PATH"
  write_resolution_message "$obligation_id" obsolete "$TARGET_PATH" "current deterministic fixture proves the source finding is stale" "$RUN_LAST_MESSAGE_FILE"

  automation_resolve_selected_obligation 0 WORK_DONE WORK_DONE "$TARGET_PATH"

  [[ ! -e "$UPKEEPER_AUTOMATION_OBLIGATION_PATH" ]] || fail "explicit obsolete proof remained open"
  local resolved="$UPKEEPER_OBLIGATION_DIR/resolved/$obligation_id.json"
  [[ "$(jq -r '.resolution_proof.classification' "$resolved")" == "obsolete" ]] || fail "obsolete resolution did not persist classification evidence"
  [[ "$(jq -r '.resolution_proof.evidence[0]' "$resolved")" == "current deterministic fixture proves the source finding is stale" ]] || fail "obsolete resolution did not persist evidence"
}

test_claimed_resolution_requires_token_and_releases_claim() {
  local obligation_id="claimed-obsolete-success" claim_json claim_path claim_token
  find "$UPKEEPER_OBLIGATION_DIR/open" -maxdepth 1 -type f -name '*.json' -delete
  printf 'unchanged\n' >"$ROOT_DIR/$TARGET_PATH"
  prepare_attempt "$obligation_id"
  claim_json="$(UPKEEPER_OBLIGATION_CLAIM_OWNER_PID="${BASHPID:-$$}" automation_claim_open_obligation_json)"
  [[ "$(jq -r '.status' <<<"$claim_json")" == "ok" ]] || fail "resolution fixture could not claim obligation"
  claim_path="$(jq -r '.claim_path' <<<"$claim_json")"
  claim_token="$(jq -r '.claim_token' <<<"$claim_json")"
  UPKEEPER_AUTOMATION_OBLIGATION_CLAIM_PATH="$claim_path"
  UPKEEPER_AUTOMATION_OBLIGATION_CLAIM_TOKEN="wrong-$claim_token"
  automation_capture_obligation_resolution_baseline "$TARGET_PATH"
  write_resolution_message "$obligation_id" obsolete "$TARGET_PATH" "claimed fixture is obsolete" "$RUN_LAST_MESSAGE_FILE"

  if automation_resolve_selected_obligation 0 WORK_DONE WORK_DONE "$TARGET_PATH"; then
    fail "mismatched claim token resolved obligation"
  fi
  [[ -f "$UPKEEPER_AUTOMATION_OBLIGATION_PATH" ]] || fail "mismatched token removed open obligation"
  [[ -f "$claim_path" ]] || fail "mismatched token removed active claim"

  UPKEEPER_AUTOMATION_OBLIGATION_CLAIM_TOKEN="$claim_token"
  automation_resolve_selected_obligation 0 WORK_DONE WORK_DONE "$TARGET_PATH"
  [[ ! -e "$UPKEEPER_AUTOMATION_OBLIGATION_PATH" ]] || fail "valid claimed resolution remained open"
  [[ ! -e "$claim_path" ]] || fail "valid claimed resolution did not release claim"
  [[ -f "$UPKEEPER_OBLIGATION_DIR/resolved/$obligation_id.json" ]] || fail "valid claimed resolution was not retained"
}

test_repaired_requires_bound_proof_and_target_change
test_zero_exit_without_marker_stays_open
test_repaired_marker_without_target_change_stays_open
test_wrong_target_success_stays_open
test_required_resolution_mismatch_stays_open
test_blocked_run_stays_open
test_explicit_obsolete_proof_resolves_unchanged_target
test_claimed_resolution_requires_token_and_releases_claim

printf 'automation obligation resolution tests passed\n'
