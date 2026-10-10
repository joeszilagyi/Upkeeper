#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/upkeeper-obligation-retry-state.XXXXXX")"
trap 'rm -rf "$TEST_TMP_ROOT"' EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

fixture_root="$TEST_TMP_ROOT/repository"
obligation_root="$TEST_TMP_ROOT/obligations"
mkdir -p "$fixture_root/lib/upkeeper" "$obligation_root/open"
ln -s "$PROJECT_ROOT/lib/upkeeper/automation_obligation_retry_state.py" \
  "$fixture_root/lib/upkeeper/automation_obligation_retry_state.py"
git -C "$fixture_root" init -q
git -C "$fixture_root" config user.email 'upkeeper-test@example.invalid'
git -C "$fixture_root" config user.name 'Upkeeper test'
printf 'one\n' >"$fixture_root/target-one.txt"
printf 'two\n' >"$fixture_root/target-two.txt"
git -C "$fixture_root" add target-one.txt target-two.txt
git -C "$fixture_root" commit -qm baseline

cat >"$obligation_root/open/retry-fixture.json" <<JSON
{"schema":1,"record_type":"automation_obligation","status":"open","id":"retry-fixture","created_at":"2026-10-10T01:00:00-0700","kind":"prior_run_anomaly","severity":"high","summary":"retry state fixture","root":"$fixture_root","target_scope":"target","target_file":"target-one.txt","repair_target_file":"target-one.txt","reason":"PRIOR_RUN_ANOMALY","fingerprint":"failure-fixture","issue_number":"716","issue_title":"Retry cooldown","evidence":{"source":"fixture","digest":"one"},"required_resolution":["repair fixture"]}
JSON

ROOT_DIR="$fixture_root"
UPKEEPER_OBLIGATION_DIR="$obligation_root"
source "$PROJECT_ROOT/lib/upkeeper/automation_obligations.bash"

select_at() {
  local now="$1"
  shift
  env "$@" ROOT_DIR="$fixture_root" UPKEEPER_OBLIGATION_DIR="$obligation_root" \
    UPKEEPER_AUTOMATION_NOW_EPOCH="$now" \
    bash -c 'source "$1"; automation_select_open_obligation_json' \
    bash "$PROJECT_ROOT/lib/upkeeper/automation_obligations.bash"
}

record_blocked_at() {
  local now="$1"
  local selected="$2"
  ROOT_DIR="$fixture_root" UPKEEPER_OBLIGATION_DIR="$obligation_root" \
    UPKEEPER_OBLIGATION_RETRY_LIMIT=1 UPKEEPER_OBLIGATION_RETRY_COOLDOWN_SECONDS=600 \
    UPKEEPER_AUTOMATION_NOW_EPOCH="$now" \
    bash -c 'source "$1"; automation_record_obligation_attempt_json "$2" blocked 2 "blocked fixture"' \
      bash "$PROJECT_ROOT/lib/upkeeper/automation_obligations.bash" "$selected"
}

selected="$(select_at 100)"
[[ "$(jq -r '.status' <<<"$selected")" == "ok" ]] || fail "fresh obligation was not selected"
recorded="$(record_blocked_at 100 "$selected")"
[[ "$(jq -r '.cooldown_applied' <<<"$recorded")" == "true" ]] || fail "fixture cooldown was not recorded"
[[ -n "$(jq -r '.cooldown_retry_state_fingerprint' <<<"$recorded")" ]] || fail "cooldown did not store retry state"

deferred="$(select_at 101)"
[[ "$(jq -r '.status' <<<"$deferred")" == "cooldown_deferred" ]] || fail "unchanged retry state bypassed cooldown"
[[ "$(jq -r '.cooldown_remaining_seconds' <<<"$deferred")" == "599" ]] || fail "cooldown did not report remaining wait"
[[ "$(jq -r '.cooldown_failure_fingerprint' <<<"$deferred")" == "failure-fixture" ]] || fail "cooldown did not report failure fingerprint"
[[ "$(jq -r '.cooldown_retry_hint' <<<"$deferred")" == *'UPKEEPER_OBLIGATION_RETRY_OVERRIDE=1'* ]] || fail "cooldown did not explain override"

jq '.target_file="target-two.txt" | .repair_target_file="target-two.txt"' \
  "$obligation_root/open/retry-fixture.json" >"$TEST_TMP_ROOT/changed-target.json"
mv "$TEST_TMP_ROOT/changed-target.json" "$obligation_root/open/retry-fixture.json"
selected="$(select_at 102)"
[[ "$(jq -r '.status' <<<"$selected")" == "ok" ]] || fail "changed target did not lift cooldown"
[[ "$(jq -r '.cooldown_bypass_reason' <<<"$selected")" == "retry_state_changed" ]] || fail "changed target had wrong cooldown reason"
[[ "$(jq -r '.cooldown_state_changes | join(",")' <<<"$selected")" == *'target file'* ]] || fail "changed target was not identified"
record_blocked_at 102 "$selected" >/dev/null

git -C "$fixture_root" checkout -qb retry-state-branch
selected="$(select_at 103)"
[[ "$(jq -r '.status' <<<"$selected")" == "ok" ]] || fail "changed branch did not lift cooldown"
[[ "$(jq -r '.cooldown_state_changes | join(",")' <<<"$selected")" == *'checkout branch'* ]] || fail "changed branch was not identified"
record_blocked_at 103 "$selected" >/dev/null

printf 'unrelated checkout change\n' >"$fixture_root/context.txt"
git -C "$fixture_root" add context.txt
git -C "$fixture_root" commit -qm 'change checkout head'
selected="$(select_at 104)"
[[ "$(jq -r '.status' <<<"$selected")" == "ok" ]] || fail "changed HEAD did not lift cooldown"
[[ "$(jq -r '.cooldown_state_changes | join(",")' <<<"$selected")" == *'checkout HEAD'* ]] || fail "changed HEAD was not identified"
record_blocked_at 104 "$selected" >/dev/null

jq '.evidence.digest="two"' "$obligation_root/open/retry-fixture.json" >"$TEST_TMP_ROOT/changed-evidence.json"
mv "$TEST_TMP_ROOT/changed-evidence.json" "$obligation_root/open/retry-fixture.json"
selected="$(select_at 105)"
[[ "$(jq -r '.status' <<<"$selected")" == "ok" ]] || fail "changed evidence did not lift cooldown"
[[ "$(jq -r '.cooldown_state_changes | join(",")' <<<"$selected")" == *'repair evidence'* ]] || fail "changed evidence was not identified"
record_blocked_at 105 "$selected" >/dev/null

overridden="$(select_at 106 UPKEEPER_OBLIGATION_RETRY_OVERRIDE=1)"
[[ "$(jq -r '.status' <<<"$overridden")" == "ok" ]] || fail "manual override did not lift cooldown"
[[ "$(jq -r '.cooldown_bypass_reason' <<<"$overridden")" == "operator_override" ]] || fail "manual override had wrong reason"

expired="$(select_at 706)"
[[ "$(jq -r '.status' <<<"$expired")" == "ok" ]] || fail "expired cooldown did not select obligation"
[[ "$(jq -r '.cooldown_bypass_reason' <<<"$expired")" == "expired" ]] || fail "expired cooldown had wrong selection reason"
[[ "$(jq -r '.blocked_attempt_count' "$obligation_root/open/retry-fixture.json")" == "5" ]] || fail "state retry reset blocked-attempt custody"

printf 'automation obligation retry-state tests passed\n'
