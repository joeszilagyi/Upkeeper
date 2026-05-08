#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

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
  local tmp_dir bad_dir good_dir err_file output good_marker future_epoch

  tmp_dir="$TEST_TMP_ROOT/read"
  bad_dir="$tmp_dir/bad"
  good_dir="$tmp_dir/good"
  mkdir -p "$bad_dir" "$good_dir"

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

  CODEX_POSTMORTEM_DIR="$tmp_dir"
  err_file="$tmp_dir/stderr.txt"
  output="$(latest_active_primary_quota_block_marker "gpt-test" 2>"$err_file")" ||
    fail "latest active marker lookup failed"

  [[ "$output" == "$good_marker" ]] ||
    fail "expected $good_marker, got ${output:-<empty>}"
  [[ ! -s "$err_file" ]] ||
    fail "malformed marker produced stderr: $(tr '\n' ' ' <"$err_file")"
}

test_write_primary_quota_blocked_marker_writes_final_marker() {
  local tmp_dir marker_path temp_paths now_epoch

  tmp_dir="$TEST_TMP_ROOT/write"
  mkdir -p "$tmp_dir"
  now_epoch="$(date '+%s')"

  CODEX_POSTMORTEM_DIR="$tmp_dir"
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

  marker_path="$tmp_dir/$CYCLE_ID/primary-quota-blocked-until.txt"
  [[ -s "$marker_path" ]] || fail "marker was not written"
  grep -qx 'primary_model: gpt-test' "$marker_path" ||
    fail "marker primary_model field missing"
  grep -qx 'blocked_bucket: primary' "$marker_path" ||
    fail "marker blocked_bucket field missing"

  shopt -s nullglob
  temp_paths=("$marker_path".tmp.*)
  shopt -u nullglob
  [[ "${#temp_paths[@]}" -eq 0 ]] ||
    fail "temporary marker path left behind"
}

test_latest_active_primary_quota_block_marker_rejects_nonfinite_epoch
test_write_primary_quota_blocked_marker_writes_final_marker
printf 'ok - quota_block_markers\n'
