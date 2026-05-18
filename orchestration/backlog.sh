#!/usr/bin/env bash
set -euo pipefail

SCRIPT_SOURCE="${BASH_SOURCE[0]}"
SCRIPT_DIR="$(cd -- "$(dirname -- "$SCRIPT_SOURCE")" && pwd)"
SCRIPT_PATH="$SCRIPT_DIR/$(basename -- "$SCRIPT_SOURCE")"
ROOT_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT_DIR"

BACKLOG_BRANCH_PREFIX="${BACKLOG_BRANCH_PREFIX:-backlog/}"
BACKLOG_PR_TITLE="${BACKLOG_PR_TITLE:-[backlog] Upkeeper issue batch}"
BACKLOG_BATCH_LIMIT="${BACKLOG_BATCH_LIMIT:-10}"
BACKLOG_ISSUE_LIMIT="${BACKLOG_ISSUE_LIMIT:-200}"
BACKLOG_EXCLUDED_LABELS="${BACKLOG_EXCLUDED_LABELS:-feature,features,enhancement,research,r&d,r-and-d,documentation,docs,in-progress,blocked,duplicate,wontfix,invalid,needs-info,done,merged,has-pr}"
BACKLOG_CODEX_MODEL="${BACKLOG_CODEX_MODEL:-gpt-5.3-codex-spark}"
BACKLOG_CODEX_REASONING_EFFORT="${BACKLOG_CODEX_REASONING_EFFORT:-xhigh}"
BACKLOG_IGNORE_FAILURE_QUEUE="${BACKLOG_IGNORE_FAILURE_QUEUE:-1}"
BACKLOG_PR_CHECK_TIMEOUT_SECONDS="${BACKLOG_PR_CHECK_TIMEOUT_SECONDS:-0}"
BACKLOG_PR_CHECK_INTERVAL_SECONDS="${BACKLOG_PR_CHECK_INTERVAL_SECONDS:-60}"
BACKLOG_PER_BUG_VALIDATION_MODE="${BACKLOG_PER_BUG_VALIDATION_MODE:-light}"
BACKLOG_AUTOSHELVE_DIRTY_WORKTREE="${BACKLOG_AUTOSHELVE_DIRTY_WORKTREE:-1}"
BACKLOG_AUTOSHELVE_BRANCH_PREFIX="${BACKLOG_AUTOSHELVE_BRANCH_PREFIX:-wip/backlog-autoshelve/}"
BACKLOG_AUTOSHELVE_PROBE="${BACKLOG_AUTOSHELVE_PROBE:-0}"
BACKLOG_ALLOW_INTERACTIVE_STDIN="${BACKLOG_ALLOW_INTERACTIVE_STDIN:-0}"
BACKLOG_ALLOW_INTERACTIVE_STDIO="${BACKLOG_ALLOW_INTERACTIVE_STDIO:-$BACKLOG_ALLOW_INTERACTIVE_STDIN}"
BACKLOG_INTERACTIVE_MODE="${BACKLOG_INTERACTIVE_MODE:-watch}"
BACKLOG_DUPLICATE_MODE="${BACKLOG_DUPLICATE_MODE:-exit}"
BACKLOG_ACTIVE_ATTACH_LINES="${BACKLOG_ACTIVE_ATTACH_LINES:-20}"
BACKLOG_STDIO_AUTODETACHED="${BACKLOG_STDIO_AUTODETACHED:-0}"
BACKLOG_STDIO_WATCHED="${BACKLOG_STDIO_WATCHED:-0}"
BACKLOG_QUOTA_HIBERNATE="${BACKLOG_QUOTA_HIBERNATE:-1}"
BACKLOG_QUOTA_HIBERNATE_GRACE_SECONDS="${BACKLOG_QUOTA_HIBERNATE_GRACE_SECONDS:-60}"
BACKLOG_QUOTA_HIBERNATE_POLL_SECONDS="${BACKLOG_QUOTA_HIBERNATE_POLL_SECONDS:-60}"
BACKLOG_QUOTA_HIBERNATE_MAX_SECONDS="${BACKLOG_QUOTA_HIBERNATE_MAX_SECONDS:-0}"
BACKLOG_QUOTA_GUARDRAIL_BYPASS="${BACKLOG_QUOTA_GUARDRAIL_BYPASS:-1}"
BACKLOG_QUOTA_COOLDOWN_BYPASS="${BACKLOG_QUOTA_COOLDOWN_BYPASS:-1}"
BACKLOG_ALERT_COLOR="${BACKLOG_ALERT_COLOR:-auto}"
BACKLOG_ALERT_BLINK="${BACKLOG_ALERT_BLINK:-1}"
BACKLOG_VISUAL_BLOCK="${BACKLOG_VISUAL_BLOCK:-█}"
BACKLOG_OWNER_HEARTBEAT_INTERVAL_SECONDS="${BACKLOG_OWNER_HEARTBEAT_INTERVAL_SECONDS:-120}"
BACKLOG_OWNER_HEARTBEAT_STALE_SECONDS="${BACKLOG_OWNER_HEARTBEAT_STALE_SECONDS:-300}"
BACKLOG_OWNER_CLAIM_LOCK_STALE_SECONDS="${BACKLOG_OWNER_CLAIM_LOCK_STALE_SECONDS:-30}"
BACKLOG_ACTIVE_OWNER_START_TICKS=""
BACKLOG_OWNER_HEARTBEAT_PID=""
BACKLOG_PR_CHECKS_LAST_OUTPUT=""
BACKLOG_WATCH_CHILD_PID=""
BACKLOG_WATCH_FORMATTER_PID=""
BACKLOG_WATCH_FIFO=""
BACKLOG_WATCH_FIFO_DIR=""

backlog_timestamp() {
  date '+%Y-%m-%dT%H:%M:%S'
}

backlog_line_starts_with_timestamp() {
  local line="$1"

  case "$line" in
    [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]*)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

backlog_display_timestamp() {
  local ts="$1"

  if [[ "$ts" =~ ^([0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9])([+-][0-9][0-9][0-9][0-9])$ ]]; then
    printf '%s\n' "${BASH_REMATCH[1]}"
    return 0
  fi
  printf '%s\n' "$ts"
}

backlog_trim_leading_ws() {
  local value="${1:-}"
  value="${value#"${value%%[![:space:]]*}"}"
  printf '%s\n' "$value"
}

backlog_attention_marker_known() {
  case "${1:-}" in
    PAGE|--FYI--|WORKER|ACTION|WAIT|HEALTH|OK|RUN|INFO)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

backlog_attention_marker_payload() {
  local rest="$1"
  local first after_block marker payload

  [[ -n "$rest" ]] || return 1
  first="${rest%% *}"
  if backlog_attention_marker_known "$first"; then
    payload="${rest#"$first"}"
    payload="$(backlog_trim_leading_ws "$payload")"
    printf '%s\t%s\n' "$first" "$payload"
    return 0
  fi

  if [[ "$first" == "$BACKLOG_VISUAL_BLOCK" && "$rest" != "$first" ]]; then
    after_block="${rest#"$first"}"
    after_block="$(backlog_trim_leading_ws "$after_block")"
    [[ -n "$after_block" ]] || return 1
    marker="${after_block%% *}"
    if backlog_attention_marker_known "$marker"; then
      payload="${after_block#"$marker"}"
      payload="$(backlog_trim_leading_ws "$payload")"
      printf '%s\t%s\n' "$marker" "$payload"
      return 0
    fi
  fi

  return 1
}

backlog_emit_attention_line() {
  local ts="$1"
  local marker="$2"
  local payload="${3:-}"

  if [[ -n "$payload" ]]; then
    printf '%s %s %-7s %s\n' "$ts" "$BACKLOG_VISUAL_BLOCK" "$marker" "$payload"
  else
    printf '%s %s %-7s\n' "$ts" "$BACKLOG_VISUAL_BLOCK" "$marker"
  fi
}

backlog_normalize_attention_line_timestamp() {
  local line="$1"
  local original_ts ts rest marker payload

  backlog_line_starts_with_timestamp "$line" || {
    printf '%s\n' "$line"
    return 0
  }
  original_ts="${line%% *}"
  ts="$(backlog_display_timestamp "$original_ts")"
  if [[ "$line" == "$original_ts" ]]; then
    printf '%s\n' "$ts"
  else
    rest="${line#* }"
    if backlog_attention_marker_payload "$rest" >/dev/null; then
      IFS=$'\t' read -r marker payload < <(backlog_attention_marker_payload "$rest")
      backlog_emit_attention_line "$ts" "$marker" "$payload"
    else
      printf '%s %s\n' "$ts" "$rest"
    fi
  fi
}

backlog_line_has_attention_marker() {
  local line="$1"
  local first rest

  backlog_line_starts_with_timestamp "$line" || return 1
  first="${line%% *}"
  [[ "$line" != "$first" ]] || return 1
  rest="${line#* }"
  backlog_attention_marker_payload "$rest" >/dev/null
}

backlog_attention_marker_for_line() {
  local payload="$1"

  case "$payload" in
    *"Upkeeper: "*" cmd#"*" failed:"*|*"Upkeeper: "*" cmd#"*" exited nonzero:"*)
      printf 'WORKER\n'
      return 0
      ;;
    *"quota preflight:"*|*"quota.stop "*|*"quota guardrail tripped"*|*"quota hibernation complete"*|*"quota.blocked_marker "*|*"sent SIGTERM to parent_pid="*)
      printf 'WAIT\n'
      return 0
      ;;
    *"UPKEEPER_STATUS: BLOCKED"*|*"automation.obligation.open"*|*"cycle.exit exit_code=2 reason=BLOCKED"*|*"review completed outcome=unknown"*|*"status_marker=BLOCKED"*|*"deferred blocked issue #"*|*"preserved partial work for blocked issue #"*|*"tool_failure_queue.open "*)
      printf 'ACTION\n'
      return 0
      ;;
    *"[ERROR] Upkeeper: "*"primary: echo "*|*"[ERROR] Upkeeper: "*"secondary: echo "*|*"[ERROR] Upkeeper: "*"validation: echo "*)
      printf 'INFO\n'
      return 0
      ;;
    *"backlog: ERROR:"*|*"[ERROR]"*)
      printf 'PAGE\n'
      return 0
      ;;
    *"previous_run.anomaly"*|*"startup_anomaly.gate"*|*"machine health"*|*"active_lock."*)
      printf '%s\n' '--FYI--'
      return 0
      ;;
    *"backlog: running Upkeeper"*|*"selected file "*|*"starting Codex review"*|*"opening new backlog PR"*|*"running normal newest-file Upkeeper pass"*)
      printf 'RUN\n'
      return 0
      ;;
    *"UPKEEPER_STATUS: WORK_DONE"*|*"checks passed"*|*"Already up to date."*|*"per-bug validation: complete"*|*"batch validation: complete"*|*"committing:"*|*"pushing branch updates"*|*"merged PR #"*|*"PR #"*" now has "*|*"PR #"*" reached "*)
      printf 'OK\n'
      return 0
      ;;
    *)
      printf 'INFO\n'
      return 0
      ;;
  esac
}

backlog_format_attention_line() {
  local line="$1"
  local original_ts ts rest marker payload

  if backlog_line_has_attention_marker "$line"; then
    backlog_normalize_attention_line_timestamp "$line"
    return 0
  fi

  if backlog_line_starts_with_timestamp "$line"; then
    original_ts="${line%% *}"
    ts="$(backlog_display_timestamp "$original_ts")"
    if [[ "$line" == "$original_ts" ]]; then
      rest=""
    else
      rest="${line#* }"
    fi
  else
    ts="$(backlog_timestamp)"
    rest="$line"
  fi

  marker="$(backlog_attention_marker_for_line "$rest")"
  payload="$rest"
  backlog_emit_attention_line "$ts" "$marker" "$payload"
}

backlog_alert_color_enabled() {
  local mode="${BACKLOG_ALERT_COLOR,,}"

  case "$mode" in
    never|0|no|false|off)
      return 1
      ;;
    always|1|yes|true|on)
      return 0
      ;;
    auto|'')
      [[ -z "${NO_COLOR:-}" && -t 1 ]]
      ;;
    *)
      [[ -z "${NO_COLOR:-}" && -t 1 ]]
      ;;
  esac
}

backlog_color_attention_line() {
  local line="$1"
  local ts rest marker payload reset
  local timestamp_style block_style marker_style ts_text block_text marker_field marker_text

  if ! backlog_alert_color_enabled || ! backlog_line_has_attention_marker "$line"; then
    printf '%s\n' "$line"
    return 0
  fi

  ts="${line%% *}"
  rest="${line#* }"
  IFS=$'\t' read -r marker payload < <(backlog_attention_marker_payload "$rest")
  timestamp_style=""
  block_style=""
  marker_style=""
  case "$marker" in
    PAGE)
      timestamp_style=$'\033[31m'
      if [[ "$BACKLOG_ALERT_BLINK" == "1" ]]; then
        block_style=$'\033[5;1;31m'
      else
        block_style=$'\033[1;31m'
      fi
      marker_style="$block_style"
      ;;
    OK)
      block_style=$'\033[1;32m'
      ;;
    INFO)
      block_style=$'\033[37m'
      ;;
    --FYI--)
      timestamp_style=$'\033[38;5;208m'
      block_style=$'\033[1;38;5;208m'
      marker_style="$block_style"
      ;;
    RUN)
      block_style=$'\033[1;36m'
      ;;
    ACTION)
      block_style=$'\033[1;35m'
      ;;
    WAIT|HEALTH)
      block_style=$'\033[1;33m'
      ;;
    WORKER)
      block_style=$'\033[1;34m'
      ;;
  esac
  reset=$'\033[0m'
  ts_text="$ts"
  block_text="$BACKLOG_VISUAL_BLOCK"
  printf -v marker_field '%-7s' "$marker"
  marker_text="$marker_field"
  if [[ -n "$timestamp_style" ]]; then
    ts_text="${timestamp_style}${ts}${reset}"
  fi
  if [[ -n "$block_style" ]]; then
    block_text="${block_style}${BACKLOG_VISUAL_BLOCK}${reset}"
  fi
  if [[ -n "$marker_style" ]]; then
    marker_text="${marker_style}${marker_field}${reset}"
  fi
  if [[ -n "$payload" ]]; then
    printf '%s %s %s %s\n' "$ts_text" "$block_text" "$marker_text" "$payload"
  else
    printf '%s %s %s\n' "$ts_text" "$block_text" "$marker_text"
  fi
}

backlog_color_attention_stream() {
  local line

  while IFS= read -r line || [[ -n "$line" ]]; do
    backlog_color_attention_line "$line"
  done
}

backlog_timestamp_stream() {
  local line

  while IFS= read -r line || [[ -n "$line" ]]; do
    backlog_format_attention_line "$line"
  done
}

backlog_cleanup_owned_watch_pipeline() {
  local pid

  for pid in "${BACKLOG_WATCH_CHILD_PID:-}" "${BACKLOG_WATCH_FORMATTER_PID:-}"; do
    if [[ -n "$pid" ]]; then
      kill "$pid" 2>/dev/null || true
      wait "$pid" 2>/dev/null || true
    fi
  done
  BACKLOG_WATCH_CHILD_PID=""
  BACKLOG_WATCH_FORMATTER_PID=""
  if [[ -n "${BACKLOG_WATCH_FIFO:-}" ]]; then
    rm -f -- "$BACKLOG_WATCH_FIFO"
    BACKLOG_WATCH_FIFO=""
  fi
  if [[ -n "${BACKLOG_WATCH_FIFO_DIR:-}" ]]; then
    rmdir -- "$BACKLOG_WATCH_FIFO_DIR" 2>/dev/null || true
    BACKLOG_WATCH_FIFO_DIR=""
  fi
}

backlog_abort_owned_watch_pipeline() {
  local status="${1:-130}"

  backlog_cleanup_owned_watch_pipeline
  exit "$status"
}

backlog_run_owned_watch_pipeline() {
  local log_file="$1"
  local fifo_parent status formatter_status had_errexit
  shift
  had_errexit=0
  case "$-" in
    *e*)
      had_errexit=1
      ;;
  esac

  fifo_parent="$(dirname -- "$log_file")"
  BACKLOG_WATCH_FIFO_DIR="$(mktemp -d "$fifo_parent/backlog-watch.XXXXXX")"
  chmod 700 "$BACKLOG_WATCH_FIFO_DIR" 2>/dev/null || true
  BACKLOG_WATCH_FIFO="$BACKLOG_WATCH_FIFO_DIR/output.fifo"
  mkfifo -- "$BACKLOG_WATCH_FIFO"
  chmod 600 "$BACKLOG_WATCH_FIFO" 2>/dev/null || true

  (
    backlog_timestamp_stream <"$BACKLOG_WATCH_FIFO" |
      tee -a "$log_file" |
      backlog_color_attention_stream
  ) &
  BACKLOG_WATCH_FORMATTER_PID="$!"

  trap 'backlog_abort_owned_watch_pipeline 130' INT
  trap 'backlog_abort_owned_watch_pipeline 143' TERM
  trap 'backlog_cleanup_owned_watch_pipeline' EXIT

  BACKLOG_STDIO_WATCHED=1 "$SCRIPT_PATH" "$@" </dev/null >"$BACKLOG_WATCH_FIFO" 2>&1 &
  BACKLOG_WATCH_CHILD_PID="$!"

  set +e
  wait "$BACKLOG_WATCH_CHILD_PID"
  status="$?"
  BACKLOG_WATCH_CHILD_PID=""
  wait "$BACKLOG_WATCH_FORMATTER_PID"
  formatter_status="$?"
  BACKLOG_WATCH_FORMATTER_PID=""
  if [[ "$had_errexit" == "1" ]]; then
    set -e
  else
    set +e
  fi

  rm -f -- "$BACKLOG_WATCH_FIFO"
  BACKLOG_WATCH_FIFO=""
  rmdir -- "$BACKLOG_WATCH_FIFO_DIR" 2>/dev/null || true
  BACKLOG_WATCH_FIFO_DIR=""
  trap - INT TERM EXIT

  if [[ "$status" -eq 0 && "$formatter_status" -ne 0 ]]; then
    return "$formatter_status"
  fi
  return "$status"
}

log() {
  backlog_color_attention_line "$(backlog_format_attention_line "$(backlog_timestamp) backlog: $*")" >&2
}

fail() {
  backlog_color_attention_line "$(backlog_format_attention_line "$(backlog_timestamp) backlog: ERROR: $*")" >&2
  exit 1
}

backlog_notice() {
  backlog_color_attention_line "$(backlog_format_attention_line "$(backlog_timestamp) # backlog: $*")" >&2
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "required command missing: $1"
}

backlog_nonnegative_integer() {
  [[ "${1:-}" =~ ^[0-9]+$ ]]
}

backlog_positive_integer_or_default() {
  local value="$1"
  local default_value="$2"

  if backlog_nonnegative_integer "$value" && [[ "$value" -gt 0 ]]; then
    printf '%s\n' "$value"
  else
    printf '%s\n' "$default_value"
  fi
}

backlog_now_epoch() {
  if [[ -n "${BACKLOG_TEST_NOW_EPOCH:-}" ]]; then
    backlog_nonnegative_integer "$BACKLOG_TEST_NOW_EPOCH" || return 1
    printf '%s\n' "$BACKLOG_TEST_NOW_EPOCH"
    return 0
  fi
  date '+%s'
}

backlog_format_epoch() {
  local epoch="$1"

  if backlog_nonnegative_integer "$epoch"; then
    date -d "@$epoch" '+%Y-%m-%dT%H:%M:%S%z' 2>/dev/null && return 0
  fi
  printf 'unknown'
}

backlog_sleep_seconds() {
  local seconds="$1"

  backlog_nonnegative_integer "$seconds" || return 1
  [[ "$seconds" -gt 0 ]] || return 0

  if [[ "${BACKLOG_TEST_FAKE_SLEEP:-0}" == "1" ]]; then
    if [[ -n "${BACKLOG_TEST_SLEEP_LOG:-}" ]]; then
      printf '%s\n' "$seconds" >>"$BACKLOG_TEST_SLEEP_LOG"
    fi
    if [[ -n "${BACKLOG_TEST_NOW_EPOCH:-}" ]]; then
      BACKLOG_TEST_NOW_EPOCH=$((BACKLOG_TEST_NOW_EPOCH + seconds))
      export BACKLOG_TEST_NOW_EPOCH
    fi
    return 0
  fi

  sleep "$seconds"
}

backlog_marker_field() {
  local path="$1"
  local key="$2"

  [[ -r "$path" ]] || return 0
  awk -v key="$key" '
    index($0, key ":") == 1 {
      sub("^[^:]*:[[:space:]]*", "")
      print
      exit
    }
  ' "$path" 2>/dev/null || return 0
}

backlog_hibernate_until_epoch() {
  local blocked_until_epoch="$1"
  local blocked_bucket="$2"
  local reason="$3"
  local source="$4"
  local grace poll max_sleep now_epoch wake_epoch wait_seconds chunk
  local blocked_until_text wake_text
  local branch summary log_file

  if [[ "$BACKLOG_QUOTA_HIBERNATE" != "1" ]]; then
    log "quota preflight: quota blocked bucket=$blocked_bucket; hibernation disabled; deferring this cycle"
    return 3
  fi
  if ! backlog_nonnegative_integer "$blocked_until_epoch" || [[ "$blocked_until_epoch" -le 0 ]]; then
    log "quota preflight: hibernation unavailable; invalid blocked_until_epoch=${blocked_until_epoch:-missing} source=$source"
    return 4
  fi
  if ! now_epoch="$(backlog_now_epoch)"; then
    log "quota preflight: hibernation unavailable; invalid current time source=$source"
    return 4
  fi

  grace="$(backlog_positive_integer_or_default "$BACKLOG_QUOTA_HIBERNATE_GRACE_SECONDS" 60)"
  poll="$(backlog_positive_integer_or_default "$BACKLOG_QUOTA_HIBERNATE_POLL_SECONDS" 60)"
  max_sleep="${BACKLOG_QUOTA_HIBERNATE_MAX_SECONDS:-0}"
  backlog_nonnegative_integer "$max_sleep" || max_sleep=0
  wake_epoch=$((blocked_until_epoch + grace))

  if [[ "$wake_epoch" -le "$now_epoch" ]]; then
    log "quota preflight: quota block already expired bucket=$blocked_bucket wake=$(backlog_format_epoch "$wake_epoch"); retrying this cycle"
    return 0
  fi

  wait_seconds=$((wake_epoch - now_epoch))
  if [[ "$max_sleep" -gt 0 && "$wait_seconds" -gt "$max_sleep" ]]; then
    log "quota preflight: hibernation unavailable; wait_seconds=$wait_seconds exceeds max=$max_sleep bucket=$blocked_bucket source=$source"
    return 4
  fi

  blocked_until_text="$(backlog_format_epoch "$blocked_until_epoch")"
  wake_text="$(backlog_format_epoch "$wake_epoch")"
  branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || printf 'unknown')"
  log_file="${BACKLOG_LOOP_LOG_FILE:-$(backlog_state_root)/loop.log}"
  summary="$(backlog_recent_log_summary "$log_file" 2>/dev/null || true)"
  if [[ -n "$summary" ]]; then
    log "quota preflight: quota blocked bucket=$blocked_bucket until=$blocked_until_text wake=$wake_text wait_seconds=$wait_seconds branch=$branch recent_activity=$summary source=$source reason=$reason"
  else
    log "quota preflight: quota blocked bucket=$blocked_bucket until=$blocked_until_text wake=$wake_text wait_seconds=$wait_seconds branch=$branch source=$source reason=$reason"
  fi
  backlog_update_active_owner_heartbeat "quota_hibernating" "bucket=$blocked_bucket wake=$wake_text source=$source" "" "quota_wait_until_verified"

  while true; do
    now_epoch="$(backlog_now_epoch)" || return 4
    [[ "$now_epoch" -lt "$wake_epoch" ]] || break
    chunk=$((wake_epoch - now_epoch))
    if [[ "$chunk" -gt "$poll" ]]; then
      chunk="$poll"
    fi
    backlog_update_active_owner_heartbeat "quota_hibernating" "bucket=$blocked_bucket wake=$wake_text sleep=${chunk}s" "" "quota_wait_until_verified"
    backlog_sleep_seconds "$chunk"
  done

  log "quota preflight: quota hibernation complete; next backlog cycle may retry without backend work"
  return 3
}

require_clean_worktree() {
  local status
  status="$(git status --short)"
  [[ -z "$status" ]] || fail "working tree is not clean; finish or stash local changes before running backlog.sh"
}

dirty_worktree_status() {
  git status --short
}

backlog_state_root() {
  printf '%s\n' "${BACKLOG_STATE_ROOT:-${XDG_STATE_HOME:-$HOME/.local/state}/upkeeper/backlog}"
}

backlog_repo_key() {
  printf '%s\n' "$ROOT_DIR" | tr '/: ' '___' | tr -cd '[:alnum:]_.-'
}

backlog_active_owner_file() {
  local state_root
  state_root="$(backlog_state_root)"
  mkdir -p "$state_root"
  chmod 700 "$state_root" 2>/dev/null || true
  printf '%s/active-owner.%s.tsv\n' "$state_root" "$(backlog_repo_key)"
}

backlog_active_owner_lock_dir() {
  printf '%s.lock\n' "$(backlog_active_owner_file)"
}

backlog_owner_sanitize_value() {
  printf '%s' "${1:-}" | tr '\t\r\n' '   '
}

backlog_recent_log_summary() {
  local log_file="$1"

  [[ -f "$log_file" ]] || return 0
  awk '
    {
      candidate=$0
      sub(/^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]([+-][0-9][0-9][0-9][0-9])? /, "", candidate)
      if (candidate ~ /^[^[:space:]]+[[:space:]]+([A-Z][A-Z]+|--FYI--)[[:space:]]+/) {
        sub(/^[^[:space:]]+[[:space:]]+/, "", candidate)
      }
      sub(/^([A-Z][A-Z]+|--FYI--)[[:space:]]+/, "", candidate)
      if (candidate ~ /^backlog: running Upkeeper for issue #[0-9]+/) {
        line=candidate
      }
    }
    END {
      if (line != "") {
        sub(/^backlog: /, "", line)
        print line
      }
    }
  ' "$log_file"
}

backlog_process_start_ticks() {
  local pid="$1"

  [[ -r "/proc/$pid/stat" ]] || return 1
  awk '{print $22}' "/proc/$pid/stat"
}

backlog_owner_field() {
  local owner_file="$1"
  local key="$2"

  [[ -f "$owner_file" ]] || return 1
  awk -F '\t' -v key="$key" '$1 == key { print substr($0, index($0, "\t") + 1); exit }' "$owner_file"
}

backlog_pid_matches_owner() {
  local pid="$1"
  local expected_start_ticks="$2"
  local cmdline cwd current_start_ticks

  if [[ "${BACKLOG_TEST_OWNER_MATCH:-0}" == "1" ]]; then
    [[ -n "$pid" && -n "$expected_start_ticks" ]]
    return "$?"
  fi

  [[ -n "$pid" && -r "/proc/$pid/cmdline" ]] || return 1
  cmdline="$(tr '\0' ' ' <"/proc/$pid/cmdline" 2>/dev/null || true)"
  [[ "$cmdline" == *"orchestration/backlog.sh"* ]] || return 1
  cwd="$(readlink -f "/proc/$pid/cwd" 2>/dev/null || true)"
  [[ "$cwd" == "$ROOT_DIR" ]] || return 1
  current_start_ticks="$(backlog_process_start_ticks "$pid" 2>/dev/null || true)"
  [[ -n "$current_start_ticks" && "$current_start_ticks" == "$expected_start_ticks" ]] || return 1
  return 0
}

backlog_write_owner_record() {
  local owner_file="$1"
  local pid="$2"
  local start_ticks="$3"
  local branch="$4"
  local log_file="$5"
  local state="$6"
  local detail="$7"
  local pr_number="${8:-}"
  local check_status="${9:-}"
  local now_epoch tmp_file

  now_epoch="$(backlog_now_epoch)" || return 1
  tmp_file="$(mktemp "${owner_file}.tmp.XXXXXX")"
  {
    printf 'pid\t%s\n' "$(backlog_owner_sanitize_value "$pid")"
    printf 'start_ticks\t%s\n' "$(backlog_owner_sanitize_value "$start_ticks")"
    printf 'branch\t%s\n' "$(backlog_owner_sanitize_value "$branch")"
    printf 'log_file\t%s\n' "$(backlog_owner_sanitize_value "$log_file")"
    printf 'state\t%s\n' "$(backlog_owner_sanitize_value "$state")"
    printf 'detail\t%s\n' "$(backlog_owner_sanitize_value "$detail")"
    printf 'pr_number\t%s\n' "$(backlog_owner_sanitize_value "$pr_number")"
    printf 'check_status\t%s\n' "$(backlog_owner_sanitize_value "$check_status")"
    printf 'heartbeat_epoch\t%s\n' "$now_epoch"
    printf 'updated_at\t%s\n' "$(backlog_format_epoch "$now_epoch")"
  } >"$tmp_file"
  chmod 600 "$tmp_file" 2>/dev/null || true
  mv -f -- "$tmp_file" "$owner_file"
}

backlog_current_process_owns_file() {
  local owner_file owner_pid owner_start_ticks

  owner_file="$(backlog_active_owner_file)"
  [[ -f "$owner_file" ]] || return 1
  owner_pid="$(backlog_owner_field "$owner_file" pid 2>/dev/null || true)"
  owner_start_ticks="$(backlog_owner_field "$owner_file" start_ticks 2>/dev/null || true)"
  [[ "$owner_pid" == "$$" ]] || return 1
  [[ -n "$BACKLOG_ACTIVE_OWNER_START_TICKS" && "$owner_start_ticks" == "$BACKLOG_ACTIVE_OWNER_START_TICKS" ]] || return 1
  backlog_pid_matches_owner "$owner_pid" "$owner_start_ticks"
}

backlog_update_active_owner_heartbeat() {
  local state="${1:-running}"
  local detail="${2:-process_alive}"
  local pr_number="${3:-}"
  local check_status="${4:-owner_pid_start_cwd_verified}"
  local owner_file branch log_file

  backlog_current_process_owns_file || return 0
  owner_file="$(backlog_active_owner_file)"
  branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || backlog_owner_field "$owner_file" branch 2>/dev/null || printf 'unknown')"
  log_file="$(backlog_owner_field "$owner_file" log_file 2>/dev/null || printf '%s/loop.log' "$(backlog_state_root)")"
  backlog_write_owner_record "$owner_file" "$$" "$BACKLOG_ACTIVE_OWNER_START_TICKS" "$branch" "$log_file" "$state" "$detail" "$pr_number" "$check_status" || return 0
  log "owner heartbeat: state=$state detail=$detail check_status=$check_status"
}

backlog_owner_health_status() {
  local owner_file="${1:-$(backlog_active_owner_file)}"
  local pid start_ticks heartbeat_epoch now_epoch age stale_after state detail branch

  [[ -f "$owner_file" ]] || {
    printf 'missing_owner_file\n'
    return 1
  }

  pid="$(backlog_owner_field "$owner_file" pid 2>/dev/null || true)"
  start_ticks="$(backlog_owner_field "$owner_file" start_ticks 2>/dev/null || true)"
  if ! backlog_pid_matches_owner "$pid" "$start_ticks"; then
    printf 'stale_process pid=%s\n' "${pid:-unknown}"
    return 2
  fi

  heartbeat_epoch="$(backlog_owner_field "$owner_file" heartbeat_epoch 2>/dev/null || true)"
  if ! backlog_nonnegative_integer "$heartbeat_epoch"; then
    printf 'healthy_legacy_no_heartbeat pid=%s\n' "$pid"
    return 0
  fi

  now_epoch="$(backlog_now_epoch)" || {
    printf 'unknown_current_time pid=%s\n' "$pid"
    return 2
  }
  age=$((now_epoch - heartbeat_epoch))
  [[ "$age" -ge 0 ]] || age=0
  stale_after="$(backlog_positive_integer_or_default "$BACKLOG_OWNER_HEARTBEAT_STALE_SECONDS" 300)"
  state="$(backlog_owner_field "$owner_file" state 2>/dev/null || true)"
  detail="$(backlog_owner_field "$owner_file" detail 2>/dev/null || true)"
  branch="$(backlog_owner_field "$owner_file" branch 2>/dev/null || true)"

  if [[ "$age" -gt "$stale_after" ]]; then
    printf 'stale_heartbeat pid=%s age=%s stale_after=%s state=%s detail=%s branch=%s\n' "$pid" "$age" "$stale_after" "${state:-unknown}" "${detail:-unknown}" "${branch:-unknown}"
    return 2
  fi

  printf 'healthy pid=%s age=%s state=%s detail=%s branch=%s\n' "$pid" "$age" "${state:-unknown}" "${detail:-unknown}" "${branch:-unknown}"
  return 0
}

backlog_active_owner_pid() {
  local owner_file pid health_status

  owner_file="$(backlog_active_owner_file)"
  [[ -f "$owner_file" ]] || return 1
  if health_status="$(backlog_owner_health_status "$owner_file")"; then
    pid="$(backlog_owner_field "$owner_file" pid)"
    printf '%s\n' "$pid"
    return 0
  fi

  log "active owner is stale; reclaiming checkout ownership: $health_status"
  rm -f -- "$owner_file"
  return 1
}

write_backlog_active_owner() {
  local owner_file log_file branch start_ticks

  owner_file="$(backlog_active_owner_file)"
  log_file="${BACKLOG_LOOP_LOG_FILE:-$(backlog_state_root)/loop.log}"
  branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || printf 'unknown')"
  start_ticks="$(backlog_process_start_ticks "$$")"
  BACKLOG_ACTIVE_OWNER_START_TICKS="$start_ticks"

  backlog_write_owner_record "$owner_file" "$$" "$start_ticks" "$branch" "$log_file" "starting" "owner_claimed" "" "owner_pid_start_cwd_verified"
}

clear_backlog_active_owner() {
  local owner_file owner_pid owner_start_ticks

  owner_file="$(backlog_active_owner_file)"
  [[ -f "$owner_file" ]] || return 0
  owner_pid="$(backlog_owner_field "$owner_file" pid)"
  owner_start_ticks="$(backlog_owner_field "$owner_file" start_ticks)"
  if [[ "$owner_pid" == "$$" && -n "$BACKLOG_ACTIVE_OWNER_START_TICKS" && "$owner_start_ticks" == "$BACKLOG_ACTIVE_OWNER_START_TICKS" ]]; then
    rm -f -- "$owner_file"
  fi
}

start_backlog_owner_heartbeat() {
  local interval

  [[ -z "${BACKLOG_OWNER_HEARTBEAT_PID:-}" ]] || return 0
  [[ "${BACKLOG_TEST_FAKE_SLEEP:-0}" == "1" ]] && return 0
  interval="$(backlog_positive_integer_or_default "$BACKLOG_OWNER_HEARTBEAT_INTERVAL_SECONDS" 120)"
  (
    sleep_pid=""
    trap 'if [[ -n "${sleep_pid:-}" ]]; then kill "$sleep_pid" 2>/dev/null || true; fi; exit 0' TERM INT EXIT
    while true; do
      sleep "$interval" &
      sleep_pid="$!"
      wait "$sleep_pid" || exit 0
      sleep_pid=""
      backlog_update_active_owner_heartbeat "running" "owner_process_alive" "" "owner_pid_start_cwd_verified" || exit 0
    done
  ) &
  BACKLOG_OWNER_HEARTBEAT_PID="$!"
}

stop_backlog_owner_heartbeat() {
  if [[ -n "${BACKLOG_OWNER_HEARTBEAT_PID:-}" ]]; then
    kill "$BACKLOG_OWNER_HEARTBEAT_PID" 2>/dev/null || true
    wait "$BACKLOG_OWNER_HEARTBEAT_PID" 2>/dev/null || true
    BACKLOG_OWNER_HEARTBEAT_PID=""
  fi
}

backlog_acquire_owner_claim_lock() {
  local lock_dir stale_after now_epoch lock_mtime age attempts

  lock_dir="$(backlog_active_owner_lock_dir)"
  stale_after="$(backlog_positive_integer_or_default "$BACKLOG_OWNER_CLAIM_LOCK_STALE_SECONDS" 30)"
  attempts=0
  while ! mkdir "$lock_dir" 2>/dev/null; do
    now_epoch="$(backlog_now_epoch 2>/dev/null || date '+%s')"
    lock_mtime="$(stat -c '%Y' "$lock_dir" 2>/dev/null || printf '0')"
    if backlog_nonnegative_integer "$lock_mtime" && [[ "$lock_mtime" -gt 0 ]]; then
      age=$((now_epoch - lock_mtime))
      if [[ "$age" -gt "$stale_after" ]]; then
        rm -rf -- "$lock_dir" 2>/dev/null || true
        continue
      fi
    fi
    attempts=$((attempts + 1))
    if [[ "$attempts" -gt "$stale_after" ]]; then
      fail "could not acquire backlog owner claim lock after ${stale_after}s"
    fi
    sleep 1
  done
}

backlog_release_owner_claim_lock() {
  rmdir "$(backlog_active_owner_lock_dir)" 2>/dev/null || true
}

print_stdio_watch_notice() {
  local log_file="$1"
  local branch summary

  branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || printf 'unknown')"
  summary="$(backlog_recent_log_summary "$log_file")"

  backlog_notice "interactive stdin detected; keeping output in this terminal and mirroring to $log_file"
  backlog_notice "current branch: $branch"
  if [[ -n "$summary" ]]; then
    backlog_notice "recent activity: $summary"
  fi
  backlog_notice "follow progress with: tail -f $log_file"
}

print_stdio_detach_notice() {
  local log_file="$1"
  local branch summary

  branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || printf 'unknown')"
  summary="$(backlog_recent_log_summary "$log_file")"

  backlog_notice "interactive stdio detected; redirecting this run to $log_file"
  backlog_notice "current branch: $branch"
  if [[ -n "$summary" ]]; then
    backlog_notice "recent activity: $summary"
  fi
  backlog_notice "follow progress with: tail -f $log_file"
}

describe_active_backlog_owner() {
  local pid="$1"
  local log_file="$2"
  local summary owner_file owner_branch state detail check_status health_status

  owner_file="$(backlog_active_owner_file)"
  owner_branch="$(backlog_owner_field "$owner_file" branch 2>/dev/null || true)"
  state="$(backlog_owner_field "$owner_file" state 2>/dev/null || true)"
  detail="$(backlog_owner_field "$owner_file" detail 2>/dev/null || true)"
  check_status="$(backlog_owner_field "$owner_file" check_status 2>/dev/null || true)"
  health_status="$(backlog_owner_health_status "$owner_file" 2>/dev/null || true)"

  summary="$(backlog_recent_log_summary "$log_file")"
  backlog_notice "another backlog run already owns this checkout (pid=$pid)"
  if [[ -n "$owner_branch" ]]; then
    backlog_notice "active branch: $owner_branch"
  fi
  if [[ -n "$state" ]]; then
    backlog_notice "owner heartbeat: state=$state detail=${detail:-none} check=${check_status:-unknown} health=${health_status:-unknown}"
  fi
  if [[ -n "$summary" ]]; then
    backlog_notice "current activity: $summary"
  fi
}

follow_active_backlog_output() {
  local pid="$1"
  local log_file="$2"

  describe_active_backlog_owner "$pid" "$log_file"
  backlog_notice "attaching to $log_file until pid $pid exits"
  if [[ -f "$log_file" ]]; then
    tail -n "$BACKLOG_ACTIVE_ATTACH_LINES" -f --pid="$pid" "$log_file" | backlog_color_attention_stream || true
  else
    while kill -0 "$pid" 2>/dev/null; do
      sleep 1
    done
  fi
}

handle_healthy_active_backlog_owner() {
  local active_pid="$1"
  local log_file="$2"

  case "$BACKLOG_DUPLICATE_MODE" in
    attach)
      follow_active_backlog_output "$active_pid" "$log_file"
      ;;
    exit)
      describe_active_backlog_owner "$active_pid" "$log_file"
      backlog_notice "duplicate invocation not needed; primary owner is healthy; exiting 0"
      ;;
    *)
      fail "unsupported BACKLOG_DUPLICATE_MODE: $BACKLOG_DUPLICATE_MODE"
      ;;
  esac
}

claim_backlog_active_owner_or_exit() {
  local owner_file health_status health_rc active_pid log_file

  backlog_acquire_owner_claim_lock
  owner_file="$(backlog_active_owner_file)"
  if [[ -f "$owner_file" ]]; then
    set +e
    health_status="$(backlog_owner_health_status "$owner_file")"
    health_rc="$?"
    set -e
    if [[ "$health_rc" -eq 0 ]]; then
      active_pid="$(backlog_owner_field "$owner_file" pid 2>/dev/null || true)"
      log_file="$(backlog_owner_field "$owner_file" log_file 2>/dev/null || printf '%s/loop.log' "$(backlog_state_root)")"
      backlog_release_owner_claim_lock
      handle_healthy_active_backlog_owner "$active_pid" "$log_file"
      exit 0
    fi
    log "active owner is stale; taking over checkout ownership: $health_status"
    rm -f -- "$owner_file"
  fi
  write_backlog_active_owner
  backlog_release_owner_claim_lock
  start_backlog_owner_heartbeat
}
redirect_interactive_stdio() {
  local state_root log_file active_pid status

  [[ "$BACKLOG_ALLOW_INTERACTIVE_STDIO" == "1" ]] && return 0
  [[ ! -t 0 && ! -t 1 && ! -t 2 ]] && return 0

  if [[ "$BACKLOG_STDIO_WATCHED" == "1" ]]; then
    if [[ -t 0 ]]; then
      log "ERROR: interactive stdin remained attached after backlog watch-mode reexec"
      exit 64
    fi
    return 0
  fi

  if [[ "$BACKLOG_STDIO_AUTODETACHED" == "1" ]]; then
    log "ERROR: interactive stdio remained attached after backlog auto-detach"
    exit 64
  fi

  state_root="$(backlog_state_root)"
  log_file="${BACKLOG_LOOP_LOG_FILE:-$state_root/loop.log}"
  mkdir -p -- "$state_root" "$(dirname -- "$log_file")"
  chmod 700 "$state_root" "$(dirname -- "$log_file")" 2>/dev/null || true

  if [[ "${BACKLOG_STDIO_AUTODETACH_PROBE:-0}" == "1" ]]; then
    if [[ "$BACKLOG_INTERACTIVE_MODE" == "detach" ]]; then
      print_stdio_detach_notice "$log_file"
    else
      print_stdio_watch_notice "$log_file"
    fi
    exit 0
  fi

  active_pid="$(backlog_active_owner_pid || true)"
  if [[ -n "$active_pid" ]]; then
    log_file="$(backlog_owner_field "$(backlog_active_owner_file)" log_file 2>/dev/null || printf '%s' "$log_file")"
    handle_healthy_active_backlog_owner "$active_pid" "$log_file"
    exit 0
  fi

  case "$BACKLOG_INTERACTIVE_MODE" in
    watch)
      print_stdio_watch_notice "$log_file"
      set +e
      backlog_run_owned_watch_pipeline "$log_file" "$@"
      status="$?"
      set -e
      exit "$status"
      ;;
    detach)
      print_stdio_detach_notice "$log_file"
      export BACKLOG_STDIO_AUTODETACHED=1
      exec "$SCRIPT_PATH" "$@" </dev/null > >(backlog_timestamp_stream >>"$log_file") 2>&1
      ;;
    *)
      fail "unsupported BACKLOG_INTERACTIVE_MODE: $BACKLOG_INTERACTIVE_MODE"
      ;;
  esac

  log "ERROR: failed to activate interactive backlog stdio mode for $log_file"
  exit 64
}

backlog_branch_key() {
  git rev-parse --abbrev-ref HEAD | tr '/:' '__'
}

deferred_issue_file() {
  local state_root
  state_root="$(backlog_state_root)"
  mkdir -p "$state_root"
  chmod 700 "$state_root" 2>/dev/null || true
  printf '%s/deferred-issues.%s.txt\n' "$state_root" "$(backlog_branch_key)"
}

cleanup_ephemeral_artifacts() {
  find "$ROOT_DIR" -type d -name '__pycache__' -prune -exec rm -rf -- {} + 2>/dev/null || true
  find "$ROOT_DIR" -type f \( -name '*.pyc' -o -name '*.pyo' \) -delete 2>/dev/null || true
  rm -f -- "$ROOT_DIR/\$db" "$ROOT_DIR/\$db-shm" "$ROOT_DIR/\$db-wal" 2>/dev/null || true
}

autoshelve_next_branch_name() {
  local base candidate suffix

  base="${BACKLOG_AUTOSHELVE_BRANCH_PREFIX}$(date +%Y%m%d-%H%M%S)"
  candidate="$base"
  suffix=2
  while git show-ref --verify --quiet "refs/heads/$candidate"; do
    candidate="${base}-${suffix}"
    suffix=$((suffix + 1))
  done
  printf '%s\n' "$candidate"
}

autoshelve_dirty_paths() {
  local entry status path extra

  while IFS= read -r -d '' entry; do
    [[ "${#entry}" -ge 4 ]] || continue
    status="${entry:0:2}"
    path="${entry:3}"
    [[ -n "$path" ]] && printf '%s\0' "${path#./}"
    case "$status" in
      R*|C*)
        if IFS= read -r -d '' extra; then
          [[ -n "$extra" ]] && printf '%s\0' "${extra#./}"
        fi
        ;;
    esac
  done < <(git status --porcelain=v1 -z --untracked-files=all)
}

autoshelve_is_control_plane_trigger_path() {
  local path="${1#./}"

  case "$path" in
    Upkeeper|ChimneySweep|FlameOn|Upkeeper.conf)
      return 0
      ;;
    configurations/*|lib/upkeeper/*|orchestration/*|prompts/*|testruns/*|tests/*|tools/*)
      return 0
      ;;
  esac
  return 1
}

autoshelve_is_remediation_bundle_path() {
  local path="${1#./}"

  if autoshelve_is_control_plane_trigger_path "$path"; then
    return 0
  fi
  case "$path" in
    AGENTS.md|PLANS.md|change_notes_[0-9][0-9][0-9][0-9].md|docs/*)
      return 0
      ;;
  esac
  return 1
}

autoshelve_apply_control_plane_from_shelve() {
  local current_head="$1"
  local shelved_commit="$2"
  local shelve_branch="$3"
  local current_branch="$4"
  local promoted_summary
  local -a promote_paths=()
  shift 4
  promote_paths=("$@")

  if [[ "${#promote_paths[@]}" -eq 0 ]]; then
    log "autoshelved local changes on $shelve_branch but found no remediation bundle paths to apply; backlog will continue on clean branch $current_branch"
    return 0
  fi

  log "autoshelved local changes on $shelve_branch; applying ${#promote_paths[@]} Upkeeper remediation path(s) to $current_branch before issue work"
  if ! git diff --binary "$current_head" "$shelved_commit" -- "${promote_paths[@]}" | git apply --index --whitespace=nowarn; then
    git reset --hard "$current_head" >/dev/null 2>&1 || true
    log "autoshelved local changes on $shelve_branch but could not apply Upkeeper control-plane remediation cleanly; stopping before stale automation can run"
    exit 4
  fi
  git diff --cached --check
  if git diff --cached --quiet; then
    log "autoshelved local changes on $shelve_branch but no control-plane diff remained after cleanup; backlog will continue on clean branch $current_branch"
    return 0
  fi
  git commit -m "Apply autoshelved Upkeeper control-plane changes from ${shelve_branch}" >/dev/null
  promoted_summary="$(git rev-parse --short HEAD 2>/dev/null || printf 'unknown')"
  require_clean_worktree
  log "applied autoshelved Upkeeper control-plane changes from $shelve_branch onto $current_branch at $promoted_summary; backlog will continue with local remediation"
}

autoshelve_dirty_worktree_if_enabled() {
  local status current_branch current_head shelve_branch shelved_commit shelved_summary
  local path has_control_plane
  local -a dirty_paths=()
  local -a promote_paths=()

  status="$(dirty_worktree_status)"
  [[ -n "$status" ]] || return 0
  [[ "$BACKLOG_AUTOSHELVE_DIRTY_WORKTREE" == "1" ]] || return 0

  cleanup_ephemeral_artifacts
  status="$(dirty_worktree_status)"
  [[ -n "$status" ]] || return 0
  mapfile -d '' -t dirty_paths < <(autoshelve_dirty_paths)
  has_control_plane=0
  for path in "${dirty_paths[@]}"; do
    if autoshelve_is_control_plane_trigger_path "$path"; then
      has_control_plane=1
    fi
    if autoshelve_is_remediation_bundle_path "$path"; then
      promote_paths+=("$path")
    fi
  done

  current_branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || printf 'unknown')"
  current_head="$(git rev-parse HEAD 2>/dev/null || printf '')"
  [[ -n "$current_head" ]] || fail "cannot autoshelve dirty worktree without a current HEAD"
  shelve_branch="$(autoshelve_next_branch_name)"

  log "dirty worktree detected; autoshelving local changes to $shelve_branch before backlog issue work"
  git checkout -b "$shelve_branch" >/dev/null
  git add --all
  git diff --cached --check
  git commit -m "Preserve dirty backlog launcher worktree from ${current_branch}" >/dev/null
  shelved_commit="$(git rev-parse HEAD)"
  shelved_summary="$(git rev-parse --short HEAD 2>/dev/null || printf 'unknown')"
  git checkout "$current_branch" >/dev/null
  git reset --hard "$current_head" >/dev/null
  require_clean_worktree
  if [[ "$has_control_plane" == "1" ]]; then
    autoshelve_apply_control_plane_from_shelve "$current_head" "$shelved_commit" "$shelve_branch" "$current_branch" "${promote_paths[@]}"
  else
    log "autoshelved local changes on $shelve_branch at $shelved_summary; backlog will continue on clean branch $current_branch"
  fi

  if [[ "$BACKLOG_AUTOSHELVE_PROBE" == "1" ]]; then
    exit 0
  fi
}

prepare_backlog_runtime_env() {
  local state_root

  export CODEX_MODEL="$BACKLOG_CODEX_MODEL"
  export CODEX_REASONING_EFFORT="$BACKLOG_CODEX_REASONING_EFFORT"
  export CODEX_FALLBACK_ENABLED="${BACKLOG_CODEX_FALLBACK_ENABLED:-0}"
  export CODEX_FALLBACK_SCREEN_ENABLED="${BACKLOG_CODEX_FALLBACK_SCREEN_ENABLED:-0}"
  export CODEX_POSTMORTEM_ENABLED="${BACKLOG_CODEX_POSTMORTEM_ENABLED:-0}"
  export CODEX_5H_STOP_PERCENT="${BACKLOG_5H_STOP_PERCENT:-0}"
  export CODEX_WEEK_STOP_PERCENT="${BACKLOG_WEEK_STOP_PERCENT:-0}"
  export CODEX_WEEK_STOP_BUFFER_PERCENT="${BACKLOG_WEEK_STOP_BUFFER_PERCENT:-0}"
  export CODEX_SPARK_5H_STOP_PERCENT="${BACKLOG_SPARK_5H_STOP_PERCENT:-0}"
  export CODEX_SPARK_WEEK_STOP_BUFFER_PERCENT="${BACKLOG_SPARK_WEEK_STOP_BUFFER_PERCENT:-0}"
  export CODEX_QUOTA_GUARDRAIL_BYPASS="$BACKLOG_QUOTA_GUARDRAIL_BYPASS"
  export CODEX_QUOTA_COOLDOWN_BYPASS="$BACKLOG_QUOTA_COOLDOWN_BYPASS"
  export UPKEEPER_ALLOW_PRIVATE_ISSUE_BODY_TO_MODEL="${BACKLOG_ALLOW_PRIVATE_ISSUE_BODY_TO_MODEL:-1}"
  export CODEX_TERMINAL_VERBOSITY="${BACKLOG_CODEX_TERMINAL_VERBOSITY:-${CODEX_TERMINAL_VERBOSITY:-quiet}}"
  export PYTHONDONTWRITEBYTECODE=1

  state_root="$(backlog_state_root)"
  mkdir -p \
    "$state_root/logs" \
    "$state_root/tmp" \
    "$state_root/transcripts" \
    "$state_root/postmortems" \
    "$state_root/bug-report-drafts" \
    "$state_root/precontact-vault" \
    "$ROOT_DIR/runtime/upkeeper-backlog-lattice"
  chmod 700 "$state_root" "$state_root/logs" "$state_root/tmp" "$state_root/transcripts" "$state_root/postmortems" "$state_root/bug-report-drafts" "$state_root/precontact-vault" "$ROOT_DIR/runtime/upkeeper-backlog-lattice" 2>/dev/null || true

  export TMPDIR="${BACKLOG_TMPDIR:-$state_root/tmp}"
  export CODEX_LOG_FILE="${BACKLOG_CODEX_LOG_FILE:-$state_root/logs/Upkeeper.log}"
  export CODEX_TRANSCRIPT_DIR="${BACKLOG_CODEX_TRANSCRIPT_DIR:-$state_root/transcripts}"
  export CODEX_POSTMORTEM_DIR="${BACKLOG_CODEX_POSTMORTEM_DIR:-$state_root/postmortems}"
  export UPKEEPER_BUG_REPORT_DRAFT_DIR="${BACKLOG_BUG_REPORT_DRAFT_DIR:-$state_root/bug-report-drafts}"
  export UPKEEPER_LATTICE_DB="${BACKLOG_LATTICE_DB:-$ROOT_DIR/runtime/upkeeper-backlog-lattice/lattice.sqlite3}"
  export UPKEEPER_PRECONTACT_BACKUP_ROOT="${BACKLOG_PRECONTACT_BACKUP_ROOT:-$state_root/precontact-vault}"
  export CODEX_HOME_DIR="${CODEX_HOME_DIR:-${CODEX_HOME:-$HOME/.codex}}"
  export CODEX_SESSION_SCAN_LIMIT="${CODEX_SESSION_SCAN_LIMIT:-200}"
  export LOG_FILE="${LOG_FILE:-$CODEX_LOG_FILE}"
}

quota_preflight_allows_backlog_run() {
  local quota_json primary_bucket_current secondary_bucket_current
  local primary_projected_left secondary_projected_left
  local primary_decision secondary_decision
  local marker_path marker_epoch marker_bucket marker_reason
  local blocked_bucket blocked_until_epoch
  local primary_reset
  local secondary_reset
  local primary_reset_expired secondary_reset_expired snapshot_stale_after_reset

  prepare_backlog_runtime_env
  source "$ROOT_DIR/lib/upkeeper/config_validation.bash"
  source "$ROOT_DIR/lib/upkeeper/quota_state.bash"
  source "$ROOT_DIR/lib/upkeeper/quota_guardrails.bash"
  source "$ROOT_DIR/lib/upkeeper/quota_block_markers.bash"

  if [[ "$BACKLOG_QUOTA_COOLDOWN_BYPASS" != "1" ]] && marker_path="$(latest_active_primary_quota_block_marker "$CODEX_MODEL" 2>/dev/null)"; then
    marker_epoch="$(backlog_marker_field "$marker_path" "blocked_until_epoch")"
    marker_bucket="$(backlog_marker_field "$marker_path" "blocked_bucket")"
    marker_reason="$(backlog_marker_field "$marker_path" "reason")"
    backlog_hibernate_until_epoch "$marker_epoch" "${marker_bucket:-primary}" "${marker_reason:-active quota marker}" "quota_marker" || return "$?"
  fi

  quota_json="$(quota_state_json "$CODEX_MODEL")" || return 0
  [[ -n "$quota_json" ]] || return 0
  if jq -e '.error? != null' >/dev/null 2>&1 <<<"$quota_json"; then
    return 0
  fi

  primary_bucket_current="$(jq -r '.snapshot.primary_bucket_current // "false"' <<<"$quota_json")"
  secondary_bucket_current="$(jq -r '.snapshot.secondary_bucket_current // "false"' <<<"$quota_json")"
  snapshot_stale_after_reset="$(jq -r '.snapshot.snapshot_stale_after_reset // "false"' <<<"$quota_json")"
  primary_reset_expired="$(jq -r '.snapshot.primary_reset_expired // "false"' <<<"$quota_json")"
  secondary_reset_expired="$(jq -r '.snapshot.secondary_reset_expired // "false"' <<<"$quota_json")"
  primary_projected_left="$(jq -r '100 - ((.snapshot.primary_used_percent // 0) + (.projection.primary_delta // 0))' <<<"$quota_json")"
  secondary_projected_left="$(jq -r '100 - ((.snapshot.secondary_used_percent // 0) + (.projection.secondary_delta // 0))' <<<"$quota_json")"
  primary_decision="$(quota_bucket_decision "$primary_bucket_current" "$primary_projected_left" "$(quota_5h_stop_percent_for_model "$CODEX_MODEL")")"
  secondary_decision="$(quota_bucket_decision "$secondary_bucket_current" "$secondary_projected_left" "$(quota_week_stop_percent_for_model "$CODEX_MODEL")")"

  if [[ "$primary_decision" == "stop" || "$secondary_decision" == "stop" ]]; then
    if [[ "$BACKLOG_QUOTA_GUARDRAIL_BYPASS" == "1" ]]; then
      log "quota preflight: burn bypass continuing despite stop decision (primary=$primary_decision secondary=$secondary_decision)"
      return 0
    fi
    blocked_bucket=""
    blocked_until_epoch=0
    if [[ "$primary_decision" == "stop" ]]; then
      blocked_bucket="${blocked_bucket:+$blocked_bucket,}primary"
      primary_reset="$(jq -r '.snapshot.primary_resets_at // 0' <<<"$quota_json")"
      if backlog_nonnegative_integer "$primary_reset" && [[ "$primary_reset" -gt "$blocked_until_epoch" ]]; then
        blocked_until_epoch="$primary_reset"
      fi
    fi
    if [[ "$secondary_decision" == "stop" ]]; then
      blocked_bucket="${blocked_bucket:+$blocked_bucket,}secondary"
      secondary_reset="$(jq -r '.snapshot.secondary_resets_at // 0' <<<"$quota_json")"
      if backlog_nonnegative_integer "$secondary_reset" && [[ "$secondary_reset" -gt "$blocked_until_epoch" ]]; then
        blocked_until_epoch="$secondary_reset"
      fi
    fi
    backlog_hibernate_until_epoch "$blocked_until_epoch" "$blocked_bucket" "primary=$primary_decision projected_left=${primary_projected_left} secondary=$secondary_decision projected_left=${secondary_projected_left}" "quota_snapshot" || return "$?"
  fi

  if [[ "$primary_decision" == "defer" || "$secondary_decision" == "defer" ]]; then
    if [[ "$BACKLOG_QUOTA_GUARDRAIL_BYPASS" == "1" ]]; then
      if [[ "$snapshot_stale_after_reset" == "true" ]]; then
        log "quota preflight: burn bypass continuing despite stale quota evidence after reset (primary=$primary_decision secondary=$secondary_decision primary_reset_expired=$primary_reset_expired secondary_reset_expired=$secondary_reset_expired)"
      else
        log "quota preflight: burn bypass continuing despite stale quota evidence (primary=$primary_decision secondary=$secondary_decision)"
      fi
      return 0
    fi

    if [[ "$snapshot_stale_after_reset" == "true" && "$primary_decision" == "defer" && "$secondary_decision" == "defer" ]]; then
      log "quota preflight: stale quota evidence after reset; retrying guarded run this cycle to refresh quota state (primary=$primary_decision secondary=$secondary_decision primary_reset_expired=$primary_reset_expired secondary_reset_expired=$secondary_reset_expired)"
      return 0
    fi
    log "quota preflight: deferring backlog run this cycle (primary=$primary_decision secondary=$secondary_decision)"
    return 3
  fi
  return 0
}

current_backlog_pr() {
  gh pr list --state open --json number,title,headRefName \
    --jq '.[] | select(.headRefName | startswith("'"$BACKLOG_BRANCH_PREFIX"'")) | [.number, .headRefName] | @tsv' \
    | sed -n '1p'
}

checkout_backlog_branch() {
  local branch="$1"

  if git show-ref --verify --quiet "refs/heads/$branch"; then
    git checkout "$branch" >/dev/null
    git pull --ff-only origin "$branch"
  else
    git fetch origin "$branch"
    git checkout -b "$branch" "origin/$branch" >/dev/null
  fi
}

open_backlog_pr() {
  local branch

  git checkout main >/dev/null
  git pull --ff-only origin main >/dev/null

  branch="${BACKLOG_BRANCH_PREFIX}$(date +%Y%m%d-%H%M%S)"
  git checkout -b "$branch" >/dev/null
  git commit --allow-empty -m "Start backlog issue batch" >/dev/null
  git push -u origin "$branch" >/dev/null
  gh pr create \
    --base main \
    --head "$branch" \
    --title "$BACKLOG_PR_TITLE" \
    --body "Backlog wrench batch.

Target: up to ${BACKLOG_BATCH_LIMIT} bug or data-protection fixes, newest non-feature/non-research issue first.

Validation: script-local quick validation plus required PR checks before merge." >/dev/null

  printf '%s\t%s\n' "$(gh pr view --json number --jq '.number')" "$branch"
}

pr_body() {
  local pr_number="$1"
  gh pr view "$pr_number" --json body --jq '.body // ""'
}

fixed_issue_numbers() {
  local pr_number="$1"
  pr_body "$pr_number" | rg -o '^Fixes #[0-9]+' -r '$0' | sed 's/^Fixes #//' || true
}

deferred_issue_numbers() {
  local deferred_file

  deferred_file="$(deferred_issue_file)"
  [[ -f "$deferred_file" ]] || return 0
  sed -n '/^[0-9][0-9]*$/p' "$deferred_file"
}

defer_issue() {
  local issue_number="$1"
  local deferred_file

  [[ -n "$issue_number" ]] || return 0
  deferred_file="$(deferred_issue_file)"
  touch "$deferred_file"
  chmod 600 "$deferred_file" 2>/dev/null || true
  grep -Fxq "$issue_number" "$deferred_file" || printf '%s\n' "$issue_number" >>"$deferred_file"
}

clear_deferred_issues() {
  local deferred_file

  deferred_file="$(deferred_issue_file)"
  [[ -f "$deferred_file" ]] && rm -f "$deferred_file"
}

fix_count() {
  local pr_number="$1"
  fixed_issue_numbers "$pr_number" | sed '/^$/d' | wc -l | tr -d ' '
}

append_pr_fix_line() {
  local pr_number="$1"
  local issue_number="$2"
  local body_file

  pr_body "$pr_number" | grep -Fq "Fixes #$issue_number" && return 0
  body_file="$(mktemp "${TMPDIR:-/tmp}/upkeeper-backlog-pr-body.XXXXXX")"
  {
    pr_body "$pr_number"
    printf '\nFixes #%s\n' "$issue_number"
  } >"$body_file"
  gh pr edit "$pr_number" --body-file "$body_file"
  rm -f "$body_file"
}

selected_issue() {
  local pr_number="$1"
  local fixed_csv
  local deferred_csv

  fixed_csv="$(fixed_issue_numbers "$pr_number" | paste -sd, -)"
  deferred_csv="$(deferred_issue_numbers | paste -sd, -)"
  gh issue list --state open --limit "$BACKLOG_ISSUE_LIMIT" --json number,title,createdAt,labels \
    | jq -r \
      --arg excluded "$BACKLOG_EXCLUDED_LABELS" \
      --arg fixed ",$fixed_csv," \
      --arg deferred ",$deferred_csv," '
        def label_names: [.labels[]?.name | ascii_downcase];
        def excluded_labels: ($excluded | split(",") | map(ascii_downcase | gsub("^ +| +$"; "")) | map(select(length > 0)));
        def label_matches($label; $needle):
          $label == $needle
          or ($needle == "feature" and ($label | contains("feature")))
          or ($needle == "research" and ($label | contains("research")));
        def excluded_by_title:
          (.title // "" | ascii_downcase) as $title
          | ($title | contains("feature:"))
            or ($title | contains("enhancement:"))
            or ($title | contains("research:"))
            or ($title | contains("r&d:"))
            or ($title | contains("r-and-d:"));
        def excluded_by_label:
          label_names as $labels
          | any(excluded_labels[]; . as $needle | any($labels[]; label_matches(.; $needle)));
        map(select((.number | tostring) as $number | (excluded_by_label | not) and (excluded_by_title | not) and (($fixed | contains("," + $number + ",")) | not) and (($deferred | contains("," + $number + ",")) | not)))
        | sort_by(.createdAt)
        | reverse
        | .[0]
        | if . then [.number, .title] | @tsv else empty end
      ' \
    | sed -n '1p'
}

target_hint_for_issue() {
  local issue_number="$1"
  local issue_text

  [[ -n "$issue_number" ]] || return 0
  issue_text="$(gh issue view "$issue_number" --json title,body --jq '((.title // "") + "\n" + (.body // "")) | ascii_downcase')"
  case "$issue_text" in
    *log\ rotation*|*rotated\ log*|*plaintext\ archive*|*plaintext\ archives*|*retained\ archive*|*zip\ archive*|*upkeeper.log.*.zip*|*upkeeper.log*)
      [[ -f lib/upkeeper/log_rotation.bash ]] && printf '%s\n' "lib/upkeeper/log_rotation.bash"
      ;;
    *startup_anomaly.gate_violation*|*startup-anomaly.gate-violation*|*changed_path*|*before_hash*|*after_hash*|*review.preselect*|*worktree\ hash*)
      [[ -f lib/upkeeper/worktree_state.bash ]] && printf '%s\n' "lib/upkeeper/worktree_state.bash"
      ;;
    *startup\ anomaly\ state*|*unresolved\ startup\ anomaly*|*previous_cycle*|*previous_run_hash*|*unresolved\ anomaly*)
      [[ -f lib/upkeeper/startup_anomaly_state.bash ]] && printf '%s\n' "lib/upkeeper/startup_anomaly_state.bash"
      ;;
    *prompt_file*|*run.start*|*prompt\ file*)
      [[ -f Upkeeper ]] && printf '%s\n' "Upkeeper"
      ;;
    *runtime/upkeeper-file-manifest.json*|*upkeeper-file-manifest.json*|*file\ manifest*|*manifest\ refresh*|*manifest\ selection*)
      [[ -f lib/upkeeper/file_manifest.bash ]] && printf '%s\n' "lib/upkeeper/file_manifest.bash"
      ;;
    *cycle.start*|*record-cycle-start*|*verbose\ metadata*|*operator\ and\ config\ metadata*|*config\ file*|*issue\ labels*|*include/exclude\ globs*)
      [[ -f Upkeeper ]] && printf '%s\n' "Upkeeper"
      ;;
    *lattice*|*pass_result*|*pass-result*)
      [[ -f tools/upkeeper_lattice.py ]] && printf '%s\n' "tools/upkeeper_lattice.py"
      ;;
    *bug-report-only*|*source_mutation_guard*|*source\ mutation\ fingerprint*|*dirty-state\ fingerprint*|*dirty\ worktree*|*untracked\ path*)
      [[ -f lib/upkeeper/codex_io.bash ]] && printf '%s\n' "lib/upkeeper/codex_io.bash"
      ;;
  esac
}

run_upkeeper_for_one_target() {
  local issue_number="${1:-}"
  local target_hint=""
  local upkeeper_args=()
  local upkeeper_status=0

  prepare_backlog_runtime_env

  if [[ -n "$issue_number" ]]; then
    if [[ "$BACKLOG_IGNORE_FAILURE_QUEUE" == "1" ]]; then
      upkeeper_args+=(--ignore-failure-queue)
    fi
    target_hint="$(target_hint_for_issue "$issue_number")"
    if [[ -n "$target_hint" ]]; then
      upkeeper_args+=(--target-file="$target_hint")
    fi
    upkeeper_args+=(--fix-issue="$issue_number")
    log "running Upkeeper for issue #$issue_number with $CODEX_MODEL/$CODEX_REASONING_EFFORT target=${target_hint:-wrapper-inferred}"
    backlog_update_active_owner_heartbeat "running_upkeeper" "issue=$issue_number target=${target_hint:-wrapper-inferred}" "" "owner_pid_start_cwd_verified"
    ./Upkeeper "${upkeeper_args[@]}"
    upkeeper_status="$?"
    if [[ "$upkeeper_status" -ne 0 ]]; then
      if [[ "$upkeeper_status" -eq 2 ]]; then
        return 2
      fi
      return "$upkeeper_status"
    fi
  else
    log "no eligible issue found; running normal newest-file Upkeeper pass with $CODEX_MODEL/$CODEX_REASONING_EFFORT"
    backlog_update_active_owner_heartbeat "running_upkeeper" "normal_newest_file_pass" "" "owner_pid_start_cwd_verified"
    ./Upkeeper --selection-order=newest
  fi
}

has_worktree_changes() {
  [[ -n "$(git status --short)" ]]
}

run_per_bug_validation() {
  local validation_start

  [[ "${BACKLOG_SKIP_LOCAL_VALIDATION:-0}" == "1" ]] && return 0

  validation_start="$SECONDS"
  backlog_update_active_owner_heartbeat "validating" "per_bug_validation" "" "owner_pid_start_cwd_verified"
  log "per-bug validation: bash syntax"
  bash -n Upkeeper ChimneySweep FlameOn lib/upkeeper/*.bash tools/*.sh tests/*.bash testruns/*.sh Upkeeper.conf configurations/default.conf orchestration/backlog.sh
  log "per-bug validation: diff whitespace"
  git diff --check
  log "per-bug validation: complete in $((SECONDS - validation_start))s"
}

run_batch_validation() {
  local validation_start

  [[ "${BACKLOG_SKIP_LOCAL_VALIDATION:-0}" == "1" ]] && return 0

  validation_start="$SECONDS"
  backlog_update_active_owner_heartbeat "validating" "batch_validation" "" "owner_pid_start_cwd_verified"
  log "batch validation: bash syntax"
  bash -n Upkeeper ChimneySweep FlameOn lib/upkeeper/*.bash tools/*.sh tests/*.bash testruns/*.sh Upkeeper.conf configurations/default.conf orchestration/backlog.sh
  log "batch validation: unit tests"
  for test_script in tests/*.bash; do
    bash "$test_script"
  done
  log "batch validation: docs quick checks"
  tools/check_public_docs.sh --quick
  log "batch validation: diff whitespace"
  git diff --check
  log "batch validation: quick validator"
  tools/validate_upkeeper.sh --quick
  log "batch validation: complete in $((SECONDS - validation_start))s"
}

commit_and_push_changes() {
  local issue_number="${1:-}"
  local commit_message="${2:-}"
  local message

  cleanup_ephemeral_artifacts
  has_worktree_changes || return 1
  case "$BACKLOG_PER_BUG_VALIDATION_MODE" in
    none)
      log "per-bug validation: skipped by BACKLOG_PER_BUG_VALIDATION_MODE=none"
      ;;
    light)
      run_per_bug_validation
      ;;
    full)
      run_batch_validation
      ;;
    *)
      fail "unsupported BACKLOG_PER_BUG_VALIDATION_MODE: $BACKLOG_PER_BUG_VALIDATION_MODE"
      ;;
  esac
  cleanup_ephemeral_artifacts
  log "staging tracked changes"
  git add --all
  git diff --cached --check
  if [[ -n "$commit_message" ]]; then
    message="$commit_message"
  elif [[ -n "$issue_number" ]]; then
    message="Fix backlog issue #$issue_number"
  else
    message="Apply backlog Upkeeper pass"
  fi
  log "committing: $message"
  git commit -m "$message"
  log "pushing branch updates"
  git push
  return 0
}

wait_for_pr_checks() {
  local pr_number="$1"
  local interval timeout_seconds start_epoch now_epoch elapsed status output status_rc

  log "waiting for PR #$pr_number checks"
  interval="$(backlog_positive_integer_or_default "$BACKLOG_PR_CHECK_INTERVAL_SECONDS" 60)"
  timeout_seconds="${BACKLOG_PR_CHECK_TIMEOUT_SECONDS:-0}"
  backlog_nonnegative_integer "$timeout_seconds" || timeout_seconds=0
  start_epoch="$(backlog_now_epoch)" || start_epoch=0

  while true; do
    backlog_update_active_owner_heartbeat "waiting_on_pr_checks" "pr=$pr_number polling_checks" "$pr_number" "polling"
    if backlog_pr_checks_once "$pr_number"; then
      status_rc=0
    else
      status_rc="$?"
    fi
    output="$BACKLOG_PR_CHECKS_LAST_OUTPUT"
    status="$(sed -n '1p' <<<"$output")"
    case "$status_rc" in
      0)
        backlog_update_active_owner_heartbeat "waiting_on_pr_checks" "pr=$pr_number checks_passed" "$pr_number" "pass"
        log "PR #$pr_number checks passed"
        return 0
        ;;
      2)
        now_epoch="$(backlog_now_epoch)" || now_epoch="$start_epoch"
        elapsed=$((now_epoch - start_epoch))
        [[ "$elapsed" -ge 0 ]] || elapsed=0
        if [[ "$timeout_seconds" -gt 0 && "$elapsed" -ge "$timeout_seconds" ]]; then
          log "PR #$pr_number checks still pending after ${elapsed}s; owner remains healthy but configured timeout is ${timeout_seconds}s"
          return 2
        fi
        backlog_update_active_owner_heartbeat "waiting_on_pr_checks" "pr=$pr_number checks_pending elapsed=${elapsed}s next_check=${interval}s" "$pr_number" "pending"
        log "PR #$pr_number checks pending; holding owner lease and checking again in ${interval}s"
        backlog_sleep_seconds "$interval"
        ;;
      *)
        backlog_update_active_owner_heartbeat "waiting_on_pr_checks" "pr=$pr_number checks_failed" "$pr_number" "fail"
        printf '%s\n' "$output" >&2
        return 1
        ;;
    esac
  done
}

backlog_pr_checks_once() {
  local pr_number="$1"
  local next_status rest output rc

  if [[ -n "${BACKLOG_TEST_PR_CHECK_STATUS_SEQUENCE:-}" ]]; then
    next_status="${BACKLOG_TEST_PR_CHECK_STATUS_SEQUENCE%%,*}"
    if [[ "$BACKLOG_TEST_PR_CHECK_STATUS_SEQUENCE" == *","* ]]; then
      rest="${BACKLOG_TEST_PR_CHECK_STATUS_SEQUENCE#*,}"
    else
      rest="$next_status"
    fi
    BACKLOG_TEST_PR_CHECK_STATUS_SEQUENCE="$rest"
    export BACKLOG_TEST_PR_CHECK_STATUS_SEQUENCE
    case "$next_status" in
      pass|passed|success|ok)
        BACKLOG_PR_CHECKS_LAST_OUTPUT="pass"
        return 0
        ;;
      pending|wait|waiting|queued|in_progress)
        BACKLOG_PR_CHECKS_LAST_OUTPUT="pending"
        return 2
        ;;
      fail|failed|failure|error)
        BACKLOG_PR_CHECKS_LAST_OUTPUT="fail"
        return 1
        ;;
      *)
        BACKLOG_PR_CHECKS_LAST_OUTPUT="$(printf 'fail\nunknown fake PR check status: %s\n' "$next_status")"
        return 1
        ;;
    esac
  fi

  set +e
  output="$(gh pr checks "$pr_number" --watch=false 2>&1)"
  rc="$?"
  set -e

  if [[ "$rc" -eq 0 ]]; then
    BACKLOG_PR_CHECKS_LAST_OUTPUT="$(printf 'pass\n%s\n' "$output")"
    return 0
  fi
  if grep -Eiq 'pending|queued|in.?progress|waiting' <<<"$output"; then
    BACKLOG_PR_CHECKS_LAST_OUTPUT="$(printf 'pending\n%s\n' "$output")"
    return 2
  fi

  BACKLOG_PR_CHECKS_LAST_OUTPUT="$(printf 'fail\n%s\n' "$output")"
  return 1
}

merge_and_clean() {
  local pr_number="$1"
  local branch="$2"

  run_batch_validation
  wait_for_pr_checks "$pr_number" || {
    local status="$?"
    [[ "$status" -eq 2 ]] && return 2
    return "$status"
  }
  CODEX_ALLOW_PR_MERGE="$pr_number" gh pr merge "$pr_number" --merge --delete-branch
  git checkout main >/dev/null
  git pull --ff-only origin main
  git fetch --prune origin
  clear_deferred_issues
  if git show-ref --verify --quiet "refs/heads/$branch"; then
    git branch -d "$branch" >/dev/null || true
  fi
  require_clean_worktree
  log "merged PR #$pr_number and returned to clean main"
}

main() {
  local pr_info pr_number branch issue_info issue_number count run_status

  redirect_interactive_stdio "$@"
  claim_backlog_active_owner_or_exit
  trap 'stop_backlog_owner_heartbeat; clear_backlog_active_owner' EXIT

  require_command git
  autoshelve_dirty_worktree_if_enabled
  require_clean_worktree

  require_command gh
  require_command jq
  require_command rg

  pr_info="$(current_backlog_pr)"
  if [[ -z "$pr_info" ]]; then
    log "opening new backlog PR"
    pr_info="$(open_backlog_pr)"
  fi

  pr_number="$(awk -F '\t' '{print $1}' <<<"$pr_info")"
  branch="$(awk -F '\t' '{print $2}' <<<"$pr_info")"
  checkout_backlog_branch "$branch"

  count="$(fix_count "$pr_number")"
  if [[ "$count" -ge "$BACKLOG_BATCH_LIMIT" ]]; then
    log "PR #$pr_number has $count recorded fixes; merging batch"
    merge_and_clean "$pr_number" "$branch" || {
      local status="$?"
      [[ "$status" -eq 2 ]] && exit 0
      exit "$status"
    }
    exit 0
  fi

  if quota_preflight_allows_backlog_run; then
    quota_status=0
  else
    quota_status="$?"
  fi
  if [[ "$quota_status" -ne 0 ]]; then
    [[ "$quota_status" -eq 3 ]] && exit 0
    exit "$quota_status"
  fi

  issue_info="$(selected_issue "$pr_number")"
  issue_number="$(awk -F '\t' '{print $1}' <<<"$issue_info")"

  if run_upkeeper_for_one_target "$issue_number"; then
    run_status=0
  else
    run_status="$?"
  fi

  if [[ "$run_status" -eq 2 ]]; then
    if has_worktree_changes; then
      if commit_and_push_changes "" "Preserve partial backlog work for issue #$issue_number"; then
        log "preserved partial work for blocked issue #$issue_number"
      fi
    fi
    defer_issue "$issue_number"
    log "deferred blocked issue #$issue_number for this backlog branch"
    exit 0
  elif [[ "$run_status" -ne 0 ]]; then
    exit "$run_status"
  fi

  if commit_and_push_changes "$issue_number"; then
    if [[ -n "$issue_number" ]]; then
      append_pr_fix_line "$pr_number" "$issue_number"
    fi
  else
    log "Upkeeper produced no tracked changes"
  fi

  count="$(fix_count "$pr_number")"
  if [[ "$count" -ge "$BACKLOG_BATCH_LIMIT" ]]; then
    log "PR #$pr_number reached $count fixes; merging batch"
    merge_and_clean "$pr_number" "$branch" || {
      local status="$?"
      [[ "$status" -eq 2 ]] && exit 0
      exit "$status"
    }
  else
    log "PR #$pr_number now has $count/$BACKLOG_BATCH_LIMIT recorded fixes"
  fi
}

if [[ "${BACKLOG_SOURCE_ONLY:-0}" != "1" ]]; then
  main "$@"
fi
