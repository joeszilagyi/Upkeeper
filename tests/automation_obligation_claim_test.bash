#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/upkeeper-obligation-claim.XXXXXX")"
owner_pids=()

cleanup() {
  local pid
  for pid in "${owner_pids[@]:-}"; do
    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
  done
  rm -rf "$TEST_TMP_ROOT"
}
trap cleanup EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

start_owner() {
  sleep 120 &
  STARTED_OWNER_PID="$!"
  owner_pids+=("$STARTED_OWNER_PID")
}

claim_once() {
  local owner_pid="$1"
  ROOT_DIR="$PROJECT_ROOT" \
    UPKEEPER_OBLIGATION_DIR="$TEST_TMP_ROOT/obligations" \
    UPKEEPER_OBLIGATION_CLAIM_OWNER_PID="$owner_pid" \
    UPKEEPER_AUTOMATION_LAUNCHER="claim-test" \
    CYCLE_ID="claim-cycle-$owner_pid" \
    CYCLE_RUN_HASH="claim-run-$owner_pid" \
    bash -c 'source "$1"; automation_claim_open_obligation_json' \
      bash "$PROJECT_ROOT/lib/upkeeper/automation_obligations.bash"
}

mkdir -p "$TEST_TMP_ROOT/obligations/open"
cat >"$TEST_TMP_ROOT/obligations/open/claim-fixture.json" <<JSON
{
  "schema": 1,
  "record_type": "automation_obligation",
  "status": "open",
  "id": "claim-fixture",
  "created_at": "2026-10-09T00:00:00-0700",
  "kind": "blocked",
  "severity": "high",
  "summary": "atomic claim fixture",
  "root": "$PROJECT_ROOT",
  "target_scope": "target",
  "target_file": "Upkeeper",
  "repair_target_file": "Upkeeper",
  "reason": "BLOCKED"
}
JSON

start_owner
owner_one="$STARTED_OWNER_PID"
start_owner
owner_two="$STARTED_OWNER_PID"

claim_once "$owner_one" >"$TEST_TMP_ROOT/selector-one.json" &
selector_one_pid="$!"
claim_once "$owner_two" >"$TEST_TMP_ROOT/selector-two.json" &
selector_two_pid="$!"
wait "$selector_one_pid"
wait "$selector_two_pid"

status_one="$(jq -r '.status' "$TEST_TMP_ROOT/selector-one.json")"
status_two="$(jq -r '.status' "$TEST_TMP_ROOT/selector-two.json")"
[[ "$status_one $status_two" == "ok claimed_deferred" || "$status_one $status_two" == "claimed_deferred ok" ]] ||
  fail "racing selectors did not produce one winner: $status_one / $status_two"

if [[ "$status_one" == "ok" ]]; then
  winner_json="$(<"$TEST_TMP_ROOT/selector-one.json")"
  winner_owner="$owner_one"
else
  winner_json="$(<"$TEST_TMP_ROOT/selector-two.json")"
  winner_owner="$owner_two"
fi
claim_path="$(jq -r '.claim_path' <<<"$winner_json")"
claim_token="$(jq -r '.claim_token' <<<"$winner_json")"
[[ -f "$claim_path" ]] || fail "winning selector did not publish claim sidecar"
[[ -n "$claim_token" && "$claim_token" != "null" ]] || fail "winning selector did not return claim token"
[[ "$(stat -c '%a' "$claim_path")" == "600" ]] || fail "claim sidecar mode is not private"
[[ "$(jq -r '.owner_pid' "$claim_path")" == "$winner_owner" ]] || fail "claim did not retain owner pid"
[[ -n "$(jq -r '.owner_start_ticks' "$claim_path")" ]] || fail "claim did not retain owner process start ticks"
[[ -n "$(jq -r '.owner_cycle_id' "$claim_path")" ]] || fail "claim did not retain owner cycle id"
[[ -n "$(jq -r '.owner_run_hash' "$claim_path")" ]] || fail "claim did not retain owner run hash"
[[ "$(jq -r '.obligation_id' "$claim_path")" == "claim-fixture" ]] || fail "claim lost obligation id"
[[ "$(jq -r '.root' "$claim_path")" == "$PROJECT_ROOT" ]] || fail "claim lost repository root"

wrong_token_json="$(jq '.claim_token = "wrong-token"' <<<"$winner_json")"
if ROOT_DIR="$PROJECT_ROOT" UPKEEPER_OBLIGATION_DIR="$TEST_TMP_ROOT/obligations" \
  bash -c 'source "$1"; automation_record_obligation_attempt_json "$2" blocked 2 "wrong token"' \
    bash "$PROJECT_ROOT/lib/upkeeper/automation_obligations.bash" "$wrong_token_json" >/dev/null; then
  fail "wrong claim token updated obligation attempt"
fi
[[ "$(jq -r '.repair_attempt_count // 0' "$TEST_TMP_ROOT/obligations/open/claim-fixture.json")" == "0" ]] || fail "wrong token mutated attempt count"
[[ -f "$claim_path" ]] || fail "wrong token released active claim"

attempt_json="$({
  ROOT_DIR="$PROJECT_ROOT" \
    UPKEEPER_OBLIGATION_DIR="$TEST_TMP_ROOT/obligations" \
    UPKEEPER_OBLIGATION_RETRY_LIMIT=3 \
    UPKEEPER_OBLIGATION_RETRY_COOLDOWN_SECONDS=60 \
    bash -c 'source "$1"; automation_record_obligation_attempt_json "$2" blocked 2 "blocked fixture"' \
      bash "$PROJECT_ROOT/lib/upkeeper/automation_obligations.bash" "$winner_json"
})"
[[ "$(jq -r '.status' <<<"$attempt_json")" == "updated" ]] || fail "claimed attempt was not updated"
[[ ! -e "$claim_path" ]] || fail "blocked attempt did not release claim"
[[ -f "$TEST_TMP_ROOT/obligations/open/claim-fixture.json" ]] || fail "blocked attempt removed open obligation"

start_owner
stale_owner="$STARTED_OWNER_PID"
stale_selection="$(claim_once "$stale_owner")"
[[ "$(jq -r '.status' <<<"$stale_selection")" == "ok" ]] || fail "released obligation could not be reclaimed"
stale_claim_path="$(jq -r '.claim_path' <<<"$stale_selection")"
kill "$stale_owner"
wait "$stale_owner" 2>/dev/null || true

start_owner
recovery_owner="$STARTED_OWNER_PID"
recovered_selection="$(claim_once "$recovery_owner")"
[[ "$(jq -r '.status' <<<"$recovered_selection")" == "ok" ]] || fail "dead-owner claim was not recovered"
[[ "$(jq -r '.stale_claims_recovered' <<<"$recovered_selection")" == "1" ]] || fail "stale recovery was not reported"
[[ "$(jq -r '.claim_owner_pid' <<<"$recovered_selection")" == "$recovery_owner" ]] || fail "recovered claim has wrong owner"
[[ "$(jq -r '.claim_token' <<<"$recovered_selection")" != "$(jq -r '.claim_token' <<<"$stale_selection")" ]] || fail "recovered claim reused stale token"

ROOT_DIR="$PROJECT_ROOT" UPKEEPER_OBLIGATION_DIR="$TEST_TMP_ROOT/obligations" \
  bash -c 'source "$1"; automation_release_obligation_claim_json "$2" test_complete >/dev/null' \
    bash "$PROJECT_ROOT/lib/upkeeper/automation_obligations.bash" "$recovered_selection"
[[ ! -e "$stale_claim_path" ]] || fail "explicit claim release left sidecar behind"

if ROOT_DIR="$PROJECT_ROOT" UPKEEPER_OBLIGATION_DIR="$TEST_TMP_ROOT/obligations" \
  bash -c 'source "$1"; automation_record_obligation_attempt_json "$2" blocked 2 "released claim"' \
    bash "$PROJECT_ROOT/lib/upkeeper/automation_obligations.bash" "$recovered_selection" >/dev/null; then
  fail "released claim updated obligation attempt"
fi
[[ "$(jq -r '.repair_attempt_count // 0' "$TEST_TMP_ROOT/obligations/open/claim-fixture.json")" == "1" ]] ||
  fail "released claim mutated attempt count"

printf 'automation obligation claim tests passed\n'
