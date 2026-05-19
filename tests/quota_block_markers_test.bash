#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck source=/dev/null
source "$ROOT_DIR/lib/upkeeper/runtime_foundation.bash"
# shellcheck source=/dev/null
source "$ROOT_DIR/lib/upkeeper/quota_state.bash"
# shellcheck source=/dev/null
source "$ROOT_DIR/lib/upkeeper/quota_block_markers.bash"

TEST_TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/upkeeper-quota-block-markers.XXXXXX")"
trap 'rm -rf "$TEST_TMP_ROOT"' EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

timestamp_now() {
  printf '2026-05-07T00:00:00-0700'
}

format_epoch_local() {
  printf 'formatted:%s' "$1"
}

quota_identity_changed_flag() {
  printf '0'
}

shell_quote() {
  printf '%q' "$1"
}

log_line() {
  return 0
}

test_latest_active_primary_quota_block_marker_rejects_nonfinite_epoch() {
  local tmp_dir bad_dir good_dir private_root output good_marker expected_marker err_file future_epoch

  tmp_dir="$TEST_TMP_ROOT/read"
  bad_dir="$tmp_dir/bad"
  good_dir="$tmp_dir/good"
  private_root="$tmp_dir/private"
  mkdir -p "$bad_dir" "$good_dir" "$private_root"

  cat >"$bad_dir/primary-quota-blocked-until.txt" <<'EOF'
primary_model: gpt-test
blocked_until_epoch: 1e999
EOF

  future_epoch="$(($(date '+%s') + 3600))"
  good_marker="$good_dir/primary-quota-blocked-until.txt"
  cat >"$good_marker" <<EOF
primary_model: gpt-test
blocked_until_epoch: $future_epoch
EOF
  mkdir -p "$private_root/good"
  cp "$good_marker" "$private_root/good/primary-quota-blocked-until.txt"
  expected_marker="$private_root/good/primary-quota-blocked-until.txt"

  CODEX_POSTMORTEM_DIR="$tmp_dir"
  UPKEEPER_QUOTA_PRIMARY_BLOCK_MARKER_DIR="$private_root"
  err_file="$tmp_dir/stderr.txt"
  output="$(latest_active_primary_quota_block_marker "gpt-test" 2>"$err_file")" ||
    fail "latest active marker lookup failed"

  [[ "$output" == "$expected_marker" ]] ||
    fail "expected $expected_marker, got ${output:-<empty>}"
  [[ "$output" != "$good_marker" ]] || fail "public marker was incorrectly selected"
  [[ ! -s "$err_file" ]] ||
    fail "malformed marker produced stderr: $(tr '\n' ' ' <"$err_file")"
}

test_write_primary_quota_blocked_marker_writes_final_marker() {
  local tmp_dir public_root private_root marker_path private_marker_path temp_paths now_epoch

  tmp_dir="$TEST_TMP_ROOT/write"
  public_root="$tmp_dir/public"
  private_root="$tmp_dir/private"
  mkdir -p "$public_root"
  now_epoch="$(date '+%s')"

  CODEX_POSTMORTEM_DIR="$public_root"
  UPKEEPER_QUOTA_PRIMARY_BLOCK_MARKER_DIR="$private_root"
  CYCLE_ID="20260507T000000-0700-test"
  CODEX_MODEL="gpt-test"
  primary_guardrail_decision="stop"
  secondary_guardrail_decision="defer"
  primary_reset="$((now_epoch + 3600))"
  secondary_reset=""
  primary_used="99.0"
  primary_left="1.0"
  secondary_used="20.0"
  secondary_left="80.0"
  before_primary_bucket_current="current"
  before_secondary_bucket_current="current"
  primary_projected_left="0.5"
  secondary_projected_left="79.5"
  five_hour_threshold="5"
  week_threshold="15"

  write_primary_quota_blocked_marker "test quota stop"

  marker_path="$public_root/$CYCLE_ID/primary-quota-blocked-until.txt"
  private_marker_path="$private_root/$CYCLE_ID/primary-quota-blocked-until.txt"
  [[ -s "$marker_path" ]] || fail "public marker was not written"
  [[ -s "$private_marker_path" ]] || fail "private marker was not written"
  grep -qx 'primary_model: gpt-test' "$marker_path" ||
    fail "marker primary_model field missing"
  grep -qx 'blocked_bucket: primary' "$marker_path" ||
    fail "marker blocked_bucket field missing"
  grep -qx 'quota_identity_changed: 0' "$marker_path" ||
    fail "marker quota_identity_changed field missing"
  grep -qx 'primary_model: gpt-test' "$private_marker_path" ||
    fail "private marker primary_model field missing"
  if grep -q '^before_limit_id:' "$marker_path"; then
    fail "marker retained raw limit id"
  fi
  if grep -q '^primary_used:' "$marker_path"; then
    fail "marker retained detailed quota usage"
  fi

  shopt -s nullglob
  temp_paths=("$marker_path".tmp.*)
  shopt -u nullglob
  [[ "${#temp_paths[@]}" -eq 0 ]] ||
    fail "temporary marker path left behind"
}

test_latest_active_primary_quota_block_marker_ignores_postmortem_only_marker() {
  local tmp_dir public_root private_root legacy_cycle output err_file future_epoch

  tmp_dir="$TEST_TMP_ROOT/legacy-only"
  public_root="$tmp_dir/public"
  private_root="$tmp_dir/private"
  mkdir -p "$public_root"

  future_epoch="$(($(date '+%s') + 3600))"
  legacy_cycle="legacy-cycle"
  mkdir -p "$public_root/$legacy_cycle"
  cat >"$public_root/$legacy_cycle/primary-quota-blocked-until.txt" <<EOF
primary_model: gpt-test
blocked_until_epoch: $future_epoch
EOF

  CODEX_POSTMORTEM_DIR="$public_root"
  UPKEEPER_QUOTA_PRIMARY_BLOCK_MARKER_DIR="$private_root"
  err_file="$tmp_dir/stderr.txt"
  if output="$(latest_active_primary_quota_block_marker "gpt-test" 2>"$err_file")"; then
    fail "latest active marker lookup incorrectly accepted public-only marker"
  fi
  [[ -z "${output:-}" ]] || fail "latest active marker lookup should have returned no marker"
  if [[ -s "$err_file" ]]; then
    fail "latest active marker lookup printed unexpected stderr: $(tr '\n' ' ' <"$err_file")"
  fi
}

test_write_primary_usage_limit_block_marker_writes_hard_marker() {
  local tmp_dir public_root private_root marker_path private_marker_path now_epoch

  tmp_dir="$TEST_TMP_ROOT/usage-limit"
  public_root="$tmp_dir/public"
  private_root="$tmp_dir/private"
  mkdir -p "$public_root"
  now_epoch="$(date '+%s')"

  CODEX_POSTMORTEM_DIR="$public_root"
  UPKEEPER_QUOTA_PRIMARY_BLOCK_MARKER_DIR="$private_root"
  CYCLE_ID="20260507T001000-0700-test"
  CODEX_MODEL="gpt-test"

  write_primary_usage_limit_block_marker "$((now_epoch + 3600))" "May 7, 2026 1:00 AM" "after_run" ||
    fail "usage-limit marker writer returned failure"

  marker_path="$public_root/$CYCLE_ID/primary-quota-blocked-until.txt"
  private_marker_path="$private_root/$CYCLE_ID/primary-quota-blocked-until.txt"
  [[ -s "$marker_path" ]] || fail "usage-limit public marker was not written"
  [[ -s "$private_marker_path" ]] || fail "usage-limit private marker was not written"
  grep -qx 'blocked_bucket: backend_usage_limit' "$marker_path" ||
    fail "usage-limit marker hard bucket missing"
  grep -qx 'reason: backend_usage_limit' "$marker_path" ||
    fail "usage-limit marker reason missing"
  grep -qx 'hard_block: 1' "$marker_path" ||
    fail "usage-limit marker hard_block missing"
  grep -qx 'primary_model: gpt-test' "$private_marker_path" ||
    fail "usage-limit private marker primary_model missing"
}

test_latest_active_primary_quota_block_marker_rejects_nonfinite_epoch
test_write_primary_quota_blocked_marker_writes_final_marker
test_latest_active_primary_quota_block_marker_ignores_postmortem_only_marker
test_write_primary_usage_limit_block_marker_writes_hard_marker
printf 'ok - quota_block_markers\n'
