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
BACKLOG_PR_CHECK_EMPTY_GRACE_SECONDS="${BACKLOG_PR_CHECK_EMPTY_GRACE_SECONDS:-300}"
BACKLOG_PR_CHECK_GATE_BEFORE_NEXT_ISSUE="${BACKLOG_PR_CHECK_GATE_BEFORE_NEXT_ISSUE:-1}"
BACKLOG_PR_CHECK_PROGRESS="${BACKLOG_PR_CHECK_PROGRESS:-1}"
BACKLOG_PR_CHECK_PROGRESS_STEPS="${BACKLOG_PR_CHECK_PROGRESS_STEPS:-1}"
BACKLOG_PER_BUG_VALIDATION_MODE="${BACKLOG_PER_BUG_VALIDATION_MODE:-light}"
BACKLOG_AUTOSHELVE_DIRTY_WORKTREE="${BACKLOG_AUTOSHELVE_DIRTY_WORKTREE:-1}"
BACKLOG_AUTOSHELVE_BRANCH_PREFIX="${BACKLOG_AUTOSHELVE_BRANCH_PREFIX:-wip/backlog-autoshelve/}"
BACKLOG_AUTOSHELVE_PROBE="${BACKLOG_AUTOSHELVE_PROBE:-0}"
BACKLOG_AUTOSHELVE_ACTIVE_VALIDATOR_WAIT_SECONDS="${BACKLOG_AUTOSHELVE_ACTIVE_VALIDATOR_WAIT_SECONDS:-120}"
BACKLOG_AUTOSHELVE_ACTIVE_VALIDATOR_POLL_SECONDS="${BACKLOG_AUTOSHELVE_ACTIVE_VALIDATOR_POLL_SECONDS:-5}"
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
BACKLOG_ANOMALY_CUSTODY="${BACKLOG_ANOMALY_CUSTODY:-1}"
BACKLOG_ANOMALY_CUSTODY_LINES="${BACKLOG_ANOMALY_CUSTODY_LINES:-1200}"
BACKLOG_ANOMALY_CUSTODY_MAX_FINDINGS="${BACKLOG_ANOMALY_CUSTODY_MAX_FINDINGS:-0}"
BACKLOG_OBLIGATION_RECONCILE="${BACKLOG_OBLIGATION_RECONCILE:-1}"
BACKLOG_OBLIGATION_RETRY_LIMIT="${BACKLOG_OBLIGATION_RETRY_LIMIT:-3}"
BACKLOG_OBLIGATION_RETRY_COOLDOWN_SECONDS="${BACKLOG_OBLIGATION_RETRY_COOLDOWN_SECONDS:-21600}"
BACKLOG_OBLIGATION_ISSUE_REPORTS="${BACKLOG_OBLIGATION_ISSUE_REPORTS:-1}"
BACKLOG_OBLIGATION_GITHUB_ISSUE_WRITE="${BACKLOG_OBLIGATION_GITHUB_ISSUE_WRITE:-1}"
BACKLOG_OBLIGATION_GITHUB_ISSUE_LABELS="${BACKLOG_OBLIGATION_GITHUB_ISSUE_LABELS:-bug}"
BACKLOG_ALERT_COLOR="${BACKLOG_ALERT_COLOR:-auto}"
BACKLOG_ALERT_BLINK="${BACKLOG_ALERT_BLINK:-1}"
BACKLOG_VISUAL_BLOCK="${BACKLOG_VISUAL_BLOCK:-█}"
BACKLOG_JOB_SUMMARY="${BACKLOG_JOB_SUMMARY:-1}"
BACKLOG_JOB_SUMMARY_BAR="${BACKLOG_JOB_SUMMARY_BAR:-##### ##### #####}"
BACKLOG_JOB_SUMMARY_SENTINEL_PREFIX="__UPKEEPER_BACKLOG_JOB_SUMMARY__:"
BACKLOG_JOB_SUMMARY_BLANK_SENTINEL="${BACKLOG_JOB_SUMMARY_SENTINEL_PREFIX}blank"
BACKLOG_JOB_SUMMARY_BAR_SENTINEL="${BACKLOG_JOB_SUMMARY_SENTINEL_PREFIX}bar"
BACKLOG_JOB_SUMMARY_LINE_SENTINEL="${BACKLOG_JOB_SUMMARY_SENTINEL_PREFIX}line:"
BACKLOG_OWNER_HEARTBEAT_INTERVAL_SECONDS="${BACKLOG_OWNER_HEARTBEAT_INTERVAL_SECONDS:-120}"
BACKLOG_OWNER_HEARTBEAT_STALE_SECONDS="${BACKLOG_OWNER_HEARTBEAT_STALE_SECONDS:-300}"
BACKLOG_OWNER_CLAIM_LOCK_STALE_SECONDS="${BACKLOG_OWNER_CLAIM_LOCK_STALE_SECONDS:-30}"
BACKLOG_ACTIVE_OWNER_START_TICKS=""
BACKLOG_OWNER_HEARTBEAT_PID=""
BACKLOG_PR_CHECKS_LAST_OUTPUT=""
BACKLOG_PR_CHECKS_PROGRESS_SUMMARY=""
BACKLOG_JOB_START_EPOCH=""
BACKLOG_JOB_START_TIME=""
BACKLOG_JOB_TARGET=""
BACKLOG_JOB_REASON=""
BACKLOG_JOB_EXPECTED=""
BACKLOG_WATCH_CHILD_PID=""
BACKLOG_WATCH_FORMATTER_PID=""
BACKLOG_WATCH_FIFO=""
BACKLOG_WATCH_FIFO_DIR=""
BACKLOG_BATCH_VALIDATION_OBLIGATION_ID=""
BACKLOG_BATCH_VALIDATION_OBLIGATION_PATH=""
BACKLOG_BATCH_VALIDATION_REPEAT_EXIT_CODE=""
BACKLOG_STALE_QUOTA_OBLIGATION_ID=""

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

backlog_payload_is_model_shell_fixture() {
  local payload="$1"

  case "$payload" in
    *"[ERROR] Upkeeper: "*": echo "*|*"[ERROR] Upkeeper: "*": printf "*|*"[WARN] Upkeeper: "*": echo "*|*"[WARN] Upkeeper: "*": printf "*)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

backlog_attention_marker_for_line() {
  local payload="$1"

  case "$payload" in
    *"transcript directory is not private /tmp/upkeeper-transcripts-test"*)
      printf '--FYI--\n'
      return 0
      ;;
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
  esac

  if backlog_payload_is_model_shell_fixture "$payload"; then
    printf 'INFO\n'
    return 0
  fi

  case "$payload" in
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
  local timestamp_style block_style marker_style page_error_style page_payload_style
  local ts_text block_text marker_field marker_text payload_text

  if [[ "$line" == "$BACKLOG_JOB_SUMMARY_BAR" ]]; then
    if backlog_alert_color_enabled; then
      if [[ "$BACKLOG_ALERT_BLINK" == "1" ]]; then
        printf '%s%s%s\n' $'\033[5;1;32m' "$line" $'\033[0m'
      else
        printf '%s%s%s\n' $'\033[1;32m' "$line" $'\033[0m'
      fi
    else
      printf '%s\n' "$line"
    fi
    return 0
  fi

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
  page_error_style=""
  page_payload_style=""
  case "$marker" in
    PAGE)
      timestamp_style=$'\033[97;41m'
      page_payload_style=$'\033[97m'
      if [[ "$BACKLOG_ALERT_BLINK" == "1" ]]; then
        block_style=$'\033[5;1;31m'
        page_error_style=$'\033[5;1;31m'
      else
        block_style=$'\033[1;31m'
        page_error_style=$'\033[1;31m'
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
  payload_text="$payload"
  if [[ -n "$timestamp_style" ]]; then
    ts_text="${timestamp_style}${ts}${reset}"
  fi
  if [[ -n "$block_style" ]]; then
    block_text="${block_style}${BACKLOG_VISUAL_BLOCK}${reset}"
  fi
  if [[ -n "$marker_style" ]]; then
    marker_text="${marker_style}${marker_field}${reset}"
  fi
  if [[ "$marker" == "PAGE" && -n "$page_error_style" && "$payload_text" == *"[ERROR]"* ]]; then
    if [[ -n "$page_payload_style" ]]; then
      payload_text="${payload_text//\[ERROR\]/[${page_error_style}ERROR${reset}${page_payload_style}]}"
    else
      payload_text="${payload_text//\[ERROR\]/[${page_error_style}ERROR${reset}]}"
    fi
  fi
  if [[ "$marker" == "PAGE" && -n "$page_payload_style" && -n "$payload_text" ]]; then
    payload_text="${page_payload_style}${payload_text}${reset}"
  fi
  if [[ -n "$payload_text" ]]; then
    printf '%s %s %s %s\n' "$ts_text" "$block_text" "$marker_text" "$payload_text"
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
    case "$line" in
      "$BACKLOG_JOB_SUMMARY_BLANK_SENTINEL")
        printf '\n'
        continue
        ;;
      "$BACKLOG_JOB_SUMMARY_BAR_SENTINEL")
        printf '%s\n' "$BACKLOG_JOB_SUMMARY_BAR"
        continue
        ;;
      "$BACKLOG_JOB_SUMMARY_LINE_SENTINEL"*)
        printf '%s\n' "${line#"$BACKLOG_JOB_SUMMARY_LINE_SENTINEL"}"
        continue
        ;;
    esac
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

backlog_summary_use_sentinel_stream() {
  [[ "$BACKLOG_STDIO_WATCHED" == "1" || "$BACKLOG_STDIO_AUTODETACHED" == "1" ]]
}

backlog_job_summary_blank_line() {
  if backlog_summary_use_sentinel_stream; then
    printf '%s\n' "$BACKLOG_JOB_SUMMARY_BLANK_SENTINEL" >&2
  else
    printf '\n' >&2
  fi
}

backlog_job_summary_bar_line() {
  if backlog_summary_use_sentinel_stream; then
    printf '%s\n' "$BACKLOG_JOB_SUMMARY_BAR_SENTINEL" >&2
  else
    backlog_color_attention_line "$BACKLOG_JOB_SUMMARY_BAR" >&2
  fi
}

backlog_job_summary_text_line() {
  local message="$1"

  if backlog_summary_use_sentinel_stream; then
    printf '%s%s %s\n' "$BACKLOG_JOB_SUMMARY_LINE_SENTINEL" "$(backlog_timestamp)" "$message" >&2
  else
    printf '%s %s\n' "$(backlog_timestamp)" "$message" >&2
  fi
}

backlog_job_summary_spacer() {
  local i

  for i in 1 2 3 4 5 6; do
    backlog_job_summary_blank_line
  done
}

backlog_job_summary_enabled() {
  case "${BACKLOG_JOB_SUMMARY,,}" in
    never|0|no|false|off)
      return 1
      ;;
    *)
      return 0
      ;;
  esac
}

backlog_emit_job_start_summary() {
  local target="$1"
  local reason="$2"
  local expected="$3"

  backlog_job_summary_enabled || return 0
  BACKLOG_JOB_START_EPOCH="$(backlog_now_epoch 2>/dev/null || date '+%s')"
  BACKLOG_JOB_START_TIME="$(backlog_timestamp)"
  BACKLOG_JOB_TARGET="$target"
  BACKLOG_JOB_REASON="$reason"
  BACKLOG_JOB_EXPECTED="$expected"

  backlog_job_summary_spacer
  backlog_job_summary_bar_line
  backlog_job_summary_blank_line
  backlog_job_summary_text_line "file being worked: $target"
  backlog_job_summary_text_line "why: $reason"
  backlog_job_summary_text_line "expected outcome: $expected"
  backlog_job_summary_blank_line
  backlog_job_summary_bar_line
  backlog_job_summary_spacer
}

backlog_emit_job_finish_summary() {
  local outcome="$1"
  local disposition="$2"
  local end_epoch end_time runtime

  backlog_job_summary_enabled || return 0
  end_epoch="$(backlog_now_epoch 2>/dev/null || date '+%s')"
  end_time="$(backlog_timestamp)"
  if backlog_nonnegative_integer "${BACKLOG_JOB_START_EPOCH:-}" && [[ "$end_epoch" -ge "$BACKLOG_JOB_START_EPOCH" ]]; then
    runtime="$((end_epoch - BACKLOG_JOB_START_EPOCH))s"
  else
    runtime="unknown"
  fi

  backlog_job_summary_spacer
  backlog_job_summary_bar_line
  backlog_job_summary_blank_line
  backlog_job_summary_text_line "file worked: ${BACKLOG_JOB_TARGET:-unknown}"
  backlog_job_summary_text_line "outcome/results: $outcome"
  backlog_job_summary_text_line "start time: ${BACKLOG_JOB_START_TIME:-unknown}"
  backlog_job_summary_text_line "end time: $end_time"
  backlog_job_summary_text_line "run time: $runtime"
  backlog_job_summary_text_line "final disposition: $disposition"
  backlog_job_summary_blank_line
  backlog_job_summary_bar_line
  backlog_job_summary_spacer
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

backlog_format_duration_seconds() {
  local seconds="$1"

  if ! backlog_nonnegative_integer "$seconds"; then
    printf 'unknown'
    return 0
  fi
  if [[ "$seconds" -ge 3600 ]]; then
    printf '%dh%02dm%02ds' "$((seconds / 3600))" "$(((seconds % 3600) / 60))" "$((seconds % 60))"
  elif [[ "$seconds" -ge 60 ]]; then
    printf '%dm%02ds' "$((seconds / 60))" "$((seconds % 60))"
  else
    printf '%ds' "$seconds"
  fi
}

backlog_duration_since_iso() {
  local started_at="$1"
  local now_epoch="$2"
  local start_epoch elapsed

  [[ -n "$started_at" ]] || {
    printf 'unknown'
    return 0
  }
  start_epoch="$(date -d "$started_at" '+%s' 2>/dev/null)" || {
    printf 'unknown'
    return 0
  }
  if ! backlog_nonnegative_integer "$now_epoch" || [[ "$now_epoch" -lt "$start_epoch" ]]; then
    printf 'unknown'
    return 0
  fi
  elapsed=$((now_epoch - start_epoch))
  backlog_format_duration_seconds "$elapsed"
}

backlog_log_value() {
  local value="${1:-}"

  value="${value//$'\r'/ }"
  value="${value//$'\n'/ }"
  value="${value//$'\t'/ }"
  value="${value//\"/\'}"
  if [[ -z "$value" || "$value" == *[[:space:]\;\,]* ]]; then
    printf '"%s"' "$value"
  else
    printf '%s' "$value"
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

backlog_wait_detail_token() {
  local value="${1:-unknown}"

  value="${value//$'\r'/_}"
  value="${value//$'\n'/_}"
  value="${value//$'\t'/_}"
  value="${value// /_}"
  value="${value//;/_}"
  value="${value//,/_}"
  [[ -n "$value" ]] || value="unknown"
  printf '%s\n' "$value"
}

backlog_wait_detail_since() {
  local plane="${1:-unknown}"
  local waiting_for="${2:-unknown}"
  local wait_since_epoch="${3:-}"
  local fragment

  if [[ "$#" -ge 3 ]]; then
    shift 3
  else
    set --
  fi
  if ! backlog_nonnegative_integer "$wait_since_epoch"; then
    wait_since_epoch="$(backlog_now_epoch 2>/dev/null || date '+%s')"
  fi

  printf 'plane=%s waiting_for=%s wait_since_epoch=%s' \
    "$(backlog_wait_detail_token "$plane")" \
    "$(backlog_wait_detail_token "$waiting_for")" \
    "$wait_since_epoch"
  for fragment in "$@"; do
    [[ -n "$fragment" ]] || continue
    printf ' %s' "$(backlog_wait_detail_token "$fragment")"
  done
  printf '\n'
}

backlog_wait_detail() {
  local plane="${1:-unknown}"
  local waiting_for="${2:-unknown}"
  local now_epoch

  if [[ "$#" -ge 2 ]]; then
    shift 2
  else
    set --
  fi
  now_epoch="$(backlog_now_epoch 2>/dev/null || date '+%s')"
  backlog_wait_detail_since "$plane" "$waiting_for" "$now_epoch" "$@"
}

backlog_detail_with_elapsed() {
  local detail="${1:-}"
  local now_epoch wait_since_epoch elapsed

  if [[ "$detail" =~ (^|[[:space:]])wait_since_epoch=([0-9]+)($|[[:space:]]) ]]; then
    wait_since_epoch="${BASH_REMATCH[2]}"
    now_epoch="$(backlog_now_epoch 2>/dev/null || date '+%s')"
    if backlog_nonnegative_integer "$now_epoch" && [[ "$now_epoch" -ge "$wait_since_epoch" ]]; then
      elapsed=$((now_epoch - wait_since_epoch))
      printf '%s wait_elapsed_seconds=%s\n' "$detail" "$elapsed"
      return 0
    fi
  fi

  printf '%s\n' "$detail"
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
  local grace poll max_sleep now_epoch wait_start_epoch wake_epoch wait_seconds chunk
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
  wait_start_epoch="$now_epoch"

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
  backlog_update_active_owner_heartbeat "quota_hibernating" \
    "$(backlog_wait_detail_since quota quota_reset "$wait_start_epoch" "bucket=$blocked_bucket" "wake=$wake_text" "source=$source" "reason=$reason")" \
    "" "quota_wait_until_verified"

  while true; do
    now_epoch="$(backlog_now_epoch)" || return 4
    [[ "$now_epoch" -lt "$wake_epoch" ]] || break
    chunk=$((wake_epoch - now_epoch))
    if [[ "$chunk" -gt "$poll" ]]; then
      chunk="$poll"
    fi
    backlog_update_active_owner_heartbeat "quota_hibernating" \
      "$(backlog_wait_detail_since quota quota_reset "$wait_start_epoch" "bucket=$blocked_bucket" "wake=$wake_text" "sleep=${chunk}s" "source=$source" "reason=$reason")" \
      "" "quota_wait_until_verified"
    backlog_sleep_seconds "$chunk"
  done

  log "quota preflight: quota hibernation complete; next backlog cycle may retry without backend work"
  return 3
}

backlog_open_stale_quota_obligation() {
  local quota_json="$1"
  local primary_decision="$2"
  local secondary_decision="$3"
  local obligation_root open_dir now branch_name payload id path seen_count

  BACKLOG_STALE_QUOTA_OBLIGATION_ID=""
  obligation_root="${BACKLOG_OBLIGATION_DIR:-$ROOT_DIR/runtime/upkeeper-obligations}"
  open_dir="$obligation_root/open"
  mkdir -p -- "$open_dir" || return 1
  chmod 700 "$obligation_root" "$open_dir" 2>/dev/null || true

  now="$(date '+%Y-%m-%dT%H:%M:%S%z')"
  branch_name="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || printf '%s\n' unknown)"
  payload="$(
    python3 - \
      "$ROOT_DIR" \
      "$CODEX_MODEL" \
      "$primary_decision" \
      "$secondary_decision" \
      "$now" \
      "$branch_name" \
      "$quota_json" <<'PY'
import hashlib
import json
import sys

root, model, primary_decision, secondary_decision, now, branch, quota_json = sys.argv[1:8]
quota = json.loads(quota_json)
snapshot = quota.get("snapshot") or {}
projection = quota.get("projection") or {}
source_path = str(snapshot.get("source_path") or "")
source_hash = hashlib.sha256(source_path.encode("utf-8")).hexdigest()[:24] if source_path else ""
fingerprint_basis = {
    "model": model,
    "primary_decision": primary_decision,
    "secondary_decision": secondary_decision,
    "primary_reset_expired": bool(snapshot.get("primary_reset_expired")),
    "secondary_reset_expired": bool(snapshot.get("secondary_reset_expired")),
}
fingerprint = hashlib.sha256(json.dumps(fingerprint_basis, sort_keys=True).encode("utf-8")).hexdigest()[:24]
obligation_id = f"stale-quota-{fingerprint}"
record = {
    "schema": 1,
    "record_type": "automation_obligation",
    "status": "open",
    "id": obligation_id,
    "kind": "stale_quota_evidence",
    "severity": "high",
    "summary": "Backlog quota preflight saw stale quota evidence after reset",
    "root": root,
    "source": "backlog_quota_preflight",
    "source_branch": branch,
    "target_scope": "target",
    "target_file": "orchestration/backlog.sh",
    "repair_target_file": "orchestration/backlog.sh",
    "reason": "STALE_QUOTA_EVIDENCE_AFTER_RESET",
    "fingerprint": f"stale-quota-evidence:{fingerprint}",
    "target_model": model,
    "required_resolution": [
        "inspect the quota preflight stale-evidence path",
        "retire or refresh stale session/marker evidence when safe",
        "keep unresolved stale quota evidence as non-perfect machine health",
        "rerun tests/backlog_stale_quota_obligation_test.bash",
        "rerun tools/validate_upkeeper.sh --quick",
    ],
    "evidence": {
        "target_model": model,
        "primary_decision": primary_decision,
        "secondary_decision": secondary_decision,
        "primary_reset_expired": snapshot.get("primary_reset_expired"),
        "secondary_reset_expired": snapshot.get("secondary_reset_expired"),
        "primary_bucket_current": snapshot.get("primary_bucket_current"),
        "secondary_bucket_current": snapshot.get("secondary_bucket_current"),
        "snapshot_stale_after_reset": snapshot.get("snapshot_stale_after_reset"),
        "snapshot_selection": quota.get("snapshot_selection"),
        "matching_snapshot_count": quota.get("matching_snapshot_count"),
        "primary_reset_age_seconds": snapshot.get("primary_reset_age_seconds"),
        "secondary_reset_age_seconds": snapshot.get("secondary_reset_age_seconds"),
        "projection_basis": projection.get("basis"),
        "source_path_redacted": bool(source_path),
        "source_path_sha256": source_hash,
    },
}
print(json.dumps(record, separators=(",", ":")))
PY
  )" || return 1

  id="$(jq -r '.id' <<<"$payload")"
  path="$open_dir/$id.json"
  if [[ -f "$path" ]]; then
    seen_count="$(jq -r '.seen_count // .occurrence_count // 1' "$path" 2>/dev/null || printf '1')"
    payload="$(
      jq \
        --argjson next_count "$((seen_count + 1))" \
        --arg updated_at "$now" \
        --argjson replacement "$payload" \
        '. as $old
         | $replacement
         | .created_at = ($old.created_at // $updated_at)
         | .updated_at = $updated_at
         | .seen_count = $next_count
         | .occurrence_count = $next_count
         | .first_source_branch = ($old.first_source_branch // $old.source_branch // $replacement.source_branch)
         | .prior_evidence = ($old.evidence // {})' "$path"
    )" || return 1
  else
    payload="$(jq --arg created_at "$now" '.created_at = $created_at | .updated_at = $created_at | .seen_count = 1 | .occurrence_count = 1' <<<"$payload")" || return 1
  fi
  python3 - "$path" "$payload" <<'PY'
import json
import os
import sys

path, payload = sys.argv[1:3]
data = json.loads(payload)
parent = os.path.dirname(path)
os.makedirs(parent, mode=0o700, exist_ok=True)
try:
    os.chmod(parent, 0o700)
except OSError:
    pass
tmp = f"{path}.tmp.{os.getpid()}"
fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
try:
    with os.fdopen(fd, "w", encoding="utf-8") as handle:
        json.dump(data, handle, indent=2, sort_keys=True)
        handle.write("\n")
    os.replace(tmp, path)
    try:
        os.chmod(path, 0o600)
    except OSError:
        pass
except BaseException:
    try:
        os.unlink(tmp)
    except OSError:
        pass
    raise
PY
  BACKLOG_STALE_QUOTA_OBLIGATION_ID="$id"
  log "quota preflight: stale quota evidence after reset recorded as non-perfect health obligation_id=$id action=keep_unresolved_health_blocker"
}

backlog_resolve_stale_quota_obligations() {
  local model="$1"
  local obligation_root open_dir resolved_dir output count

  obligation_root="${BACKLOG_OBLIGATION_DIR:-$ROOT_DIR/runtime/upkeeper-obligations}"
  open_dir="$obligation_root/open"
  [[ -d "$open_dir" ]] || return 0
  resolved_dir="$obligation_root/resolved"
  mkdir -p -- "$resolved_dir" || return 0
  chmod 700 "$obligation_root" "$open_dir" "$resolved_dir" 2>/dev/null || true
  output="$(
    python3 - "$open_dir" "$resolved_dir" "$model" <<'PY'
import json
import os
import pathlib
import sys
from datetime import datetime

open_dir = pathlib.Path(sys.argv[1])
resolved_dir = pathlib.Path(sys.argv[2])
model = sys.argv[3]


def now_local():
    return datetime.now().astimezone().strftime("%Y-%m-%dT%H:%M:%S%z")


def write_json(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(f"{path.name}.tmp.{os.getpid()}")
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            json.dump(data, handle, indent=2, sort_keys=True)
            handle.write("\n")
        os.replace(tmp, path)
        try:
            path.chmod(0o600)
        except OSError:
            pass
    except BaseException:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise


count = 0
resolved_ids = []
for path in sorted(open_dir.glob("*.json")):
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        continue
    if data.get("kind") != "stale_quota_evidence" or data.get("target_model") != model:
        continue
    data["status"] = "resolved"
    data["resolved_at"] = now_local()
    data["resolution"] = "quota preflight observed current non-stale quota evidence"
    destination = resolved_dir / path.name
    write_json(destination, data)
    try:
        path.unlink()
    except OSError:
        pass
    count += 1
    resolved_ids.append(str(data.get("id") or path.stem))
print(json.dumps({"count": count, "ids": resolved_ids}, separators=(",", ":")))
PY
  )" || return 0
  count="$(jq -r '.count // 0' <<<"$output" 2>/dev/null || printf '0')"
  if [[ "$count" -gt 0 ]]; then
    log "quota preflight: stale quota evidence retired count=$count target_model=$model action=resolved_non_perfect_health"
  fi
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
  local owner_file branch log_file log_detail

  backlog_current_process_owns_file || return 0
  owner_file="$(backlog_active_owner_file)"
  branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || backlog_owner_field "$owner_file" branch 2>/dev/null || printf 'unknown')"
  log_file="$(backlog_owner_field "$owner_file" log_file 2>/dev/null || printf '%s/loop.log' "$(backlog_state_root)")"
  backlog_write_owner_record "$owner_file" "$$" "$BACKLOG_ACTIVE_OWNER_START_TICKS" "$branch" "$log_file" "$state" "$detail" "$pr_number" "$check_status" || return 0
  log_detail="$(backlog_detail_with_elapsed "$detail")"
  log "owner heartbeat: state=$state detail=$log_detail check_status=$check_status"
}

backlog_refresh_active_owner_heartbeat() {
  local owner_file state detail pr_number check_status

  backlog_current_process_owns_file || return 0
  owner_file="$(backlog_active_owner_file)"
  state="$(backlog_owner_field "$owner_file" state 2>/dev/null || true)"
  detail="$(backlog_owner_field "$owner_file" detail 2>/dev/null || true)"
  pr_number="$(backlog_owner_field "$owner_file" pr_number 2>/dev/null || true)"
  check_status="$(backlog_owner_field "$owner_file" check_status 2>/dev/null || true)"
  backlog_update_active_owner_heartbeat \
    "${state:-running}" \
    "${detail:-$(backlog_wait_detail local_launcher owner_process_alive)}" \
    "$pr_number" \
    "${check_status:-owner_pid_start_cwd_verified}"
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
  detail="$(backlog_detail_with_elapsed "$detail")"
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

  backlog_write_owner_record "$owner_file" "$$" "$start_ticks" "$branch" "$log_file" "starting" "$(backlog_wait_detail local_launcher owner_claimed)" "" "owner_pid_start_cwd_verified"
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
      backlog_refresh_active_owner_heartbeat || exit 0
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
  detail="$(backlog_detail_with_elapsed "$detail")"
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

backlog_process_is_ancestor() {
  local candidate_pid="$1"
  local current_pid parent_pid

  [[ "$candidate_pid" =~ ^[0-9]+$ ]] || return 1
  current_pid="$$"
  while [[ "$current_pid" =~ ^[0-9]+$ && "$current_pid" -gt 1 ]]; do
    parent_pid="$(ps -o ppid= -p "$current_pid" 2>/dev/null | tr -d ' ')"
    [[ -n "$parent_pid" ]] || return 1
    [[ "$parent_pid" == "$candidate_pid" ]] && return 0
    current_pid="$parent_pid"
  done
  return 1
}

backlog_active_validation_process_pids() {
  local ps_line pid cmd cwd
  local output

  output="$(ps -eo pid=,args= -ww 2>/dev/null | sed 's/^ *//')"
  [[ -n "$output" ]] || return 1

  while IFS= read -r ps_line; do
    [[ -n "$ps_line" ]] || continue
    pid="${ps_line%% *}"
    cmd="${ps_line#* }"
    [[ "$pid" == "$$" ]] && continue
    backlog_process_is_ancestor "$pid" && continue
    [[ "$cmd" == *"validate_upkeeper.sh"* ]] || continue
    if [[ -r "/proc/$pid/cwd" ]]; then
      cwd="$(readlink -f "/proc/$pid/cwd" 2>/dev/null || true)"
      [[ -n "$cwd" ]] || continue
      [[ "${cwd%/}" == "${ROOT_DIR%/}" ]] || continue
    fi
    printf '%s\n' "$pid"
  done <<<"$output"
}

backlog_wait_for_active_validation_readers_for_autoshelve() {
  local wait_seconds poll_seconds start_epoch end_epoch now_epoch active_pids active_count wait_left
  local pids

  wait_seconds="${BACKLOG_AUTOSHELVE_ACTIVE_VALIDATOR_WAIT_SECONDS:-0}"
  poll_seconds="${BACKLOG_AUTOSHELVE_ACTIVE_VALIDATOR_POLL_SECONDS:-5}"
  backlog_nonnegative_integer "$wait_seconds" || wait_seconds=0
  backlog_nonnegative_integer "$poll_seconds" || poll_seconds=5
  [[ "$poll_seconds" -gt 0 ]] || poll_seconds=5
  start_epoch="$(backlog_now_epoch 2>/dev/null || date '+%s')"

  if [[ "$wait_seconds" -eq 0 ]]; then
    pids="$(backlog_active_validation_process_pids || true)"
    if [[ -n "$pids" ]]; then
      active_count="$(wc -l <<<"$pids" | tr -d ' ')"
      log "control-plane autoshelve is blocked by active validation process(es) (${active_count} detected); stopping before stale automation can run"
      log "blocked process ids: ${pids//$'\n'/, }"
      return 4
    fi
    return 0
  fi

  end_epoch="$(( start_epoch + wait_seconds ))"
  while true; do
    pids="$(backlog_active_validation_process_pids || true)"
    if [[ -n "$pids" ]]; then
      active_count="$(wc -l <<<"$pids" | tr -d ' ')"
      now_epoch="$(backlog_now_epoch 2>/dev/null || date '+%s')"
      if [[ "$now_epoch" -ge "$end_epoch" ]]; then
        log "control-plane autoshelve still sees active validation process(es) (${active_count} detected) after ${wait_seconds}s; stopping before stale automation can run"
        log "blocked process ids: ${pids//$'\n'/, }"
        return 4
      fi
      wait_left=$((end_epoch - now_epoch))
      backlog_update_active_owner_heartbeat "waiting_on_local_validation" \
        "$(backlog_wait_detail_since local_validation active_validation_readers "$start_epoch" "active_count=$active_count" "sleep=${poll_seconds}s" "wait_left=${wait_left}s")" \
        "" "validation_readers_active"
      log "control-plane autoshelve is waiting for ${active_count} active validation process(es) to finish; retrying in ${poll_seconds}s (${wait_left}s left)"
      log "blocked process ids: ${pids//$'\n'/, }"
      backlog_sleep_seconds "$poll_seconds"
      continue
    fi
    return 0
  done
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
  if ! backlog_wait_for_active_validation_readers_for_autoshelve; then
    log "autoshelved local changes on $shelve_branch but could not safely apply control-plane remediation while validation readers were active; stopping before stale automation can run"
    exit 4
  fi
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
    "$state_root/obligation-issue-reports" \
    "$state_root/precontact-vault" \
    "$ROOT_DIR/runtime/upkeeper-backlog-lattice"
  chmod 700 "$state_root" "$state_root/logs" "$state_root/tmp" "$state_root/transcripts" "$state_root/postmortems" "$state_root/bug-report-drafts" "$state_root/obligation-issue-reports" "$state_root/precontact-vault" "$ROOT_DIR/runtime/upkeeper-backlog-lattice" 2>/dev/null || true

  export TMPDIR="${BACKLOG_TMPDIR:-$state_root/tmp}"
  export CODEX_LOG_FILE="${BACKLOG_CODEX_LOG_FILE:-$state_root/logs/Upkeeper.log}"
  export CODEX_TRANSCRIPT_DIR="${BACKLOG_CODEX_TRANSCRIPT_DIR:-$state_root/transcripts}"
  export CODEX_POSTMORTEM_DIR="${BACKLOG_CODEX_POSTMORTEM_DIR:-$state_root/postmortems}"
  export UPKEEPER_BUG_REPORT_DRAFT_DIR="${BACKLOG_BUG_REPORT_DRAFT_DIR:-$state_root/bug-report-drafts}"
  export UPKEEPER_OBLIGATION_ISSUE_REPORT_DIR="${BACKLOG_OBLIGATION_ISSUE_REPORT_DIR:-$state_root/obligation-issue-reports}"
  export UPKEEPER_LATTICE_DB="${BACKLOG_LATTICE_DB:-$ROOT_DIR/runtime/upkeeper-backlog-lattice/lattice.sqlite3}"
  export UPKEEPER_OBLIGATION_DIR="${BACKLOG_OBLIGATION_DIR:-$ROOT_DIR/runtime/upkeeper-obligations}"
  export UPKEEPER_PRECONTACT_BACKUP_ROOT="${BACKLOG_PRECONTACT_BACKUP_ROOT:-$state_root/precontact-vault}"
  export CODEX_HOME_DIR="${CODEX_HOME_DIR:-${CODEX_HOME:-$HOME/.codex}}"
  export CODEX_SESSION_SCAN_LIMIT="${CODEX_SESSION_SCAN_LIMIT:-200}"
  export LOG_FILE="${LOG_FILE:-$CODEX_LOG_FILE}"

  if [[ -z "${BACKLOG_CODEX_LOG_FILE+x}" ]]; then
    export CODEX_LOG_FILE_ALLOW_UNSAFE="${BACKLOG_CODEX_LOG_FILE_ALLOW_UNSAFE:-1}"
  else
    export CODEX_LOG_FILE_ALLOW_UNSAFE="${BACKLOG_CODEX_LOG_FILE_ALLOW_UNSAFE:-${CODEX_LOG_FILE_ALLOW_UNSAFE:-0}}"
  fi
  backlog_ensure_transcript_artifact_marker
}

backlog_ensure_transcript_artifact_marker() {
  local transcript_dir marker_path marker_value

  transcript_dir="${CODEX_TRANSCRIPT_DIR:-}"
  [[ -n "$transcript_dir" ]] || return 0
  [[ "$transcript_dir" != "$ROOT_DIR/runtime/upkeeper-transcripts" ]] || return 0
  [[ ! -L "$transcript_dir" ]] || return 0
  mkdir -p -- "$transcript_dir" || return 0
  chmod 700 "$transcript_dir" 2>/dev/null || true

  marker_value="$(
    ROOT_DIR="$ROOT_DIR" \
      bash -c 'set -euo pipefail; source "$1/lib/upkeeper/runtime_foundation.bash"; source "$1/lib/upkeeper/transcript_artifacts.bash"; transcript_artifacts_marker_expected "$2"' \
      bash "$ROOT_DIR" "$transcript_dir" 2>/dev/null
  )" || return 0
  [[ -n "$marker_value" ]] || return 0
  marker_path="$transcript_dir/.upkeeper-transcript-artifacts.marker"
  printf '%s\n' "$marker_value" >"$marker_path" 2>/dev/null || return 0
  chmod 600 "$marker_path" 2>/dev/null || true
}

run_backlog_anomaly_custody_audit() {
  local state_root log_file custody_root obligation_root output rc line

  [[ "$BACKLOG_ANOMALY_CUSTODY" == "1" ]] || return 0
  [[ -x "$ROOT_DIR/tools/upkeeper_anomaly_custody.py" ]] || return 0

  state_root="$(backlog_state_root)"
  log_file="${BACKLOG_LOOP_LOG_FILE:-$state_root/loop.log}"
  [[ -r "$log_file" ]] || return 0
  custody_root="$ROOT_DIR/runtime/upkeeper-anomaly-custody"
  obligation_root="${BACKLOG_OBLIGATION_DIR:-$ROOT_DIR/runtime/upkeeper-obligations}"
  mkdir -p -- "$custody_root" "$obligation_root"
  chmod 700 "$custody_root" "$obligation_root" 2>/dev/null || true

  set +e
  output="$(
    "$ROOT_DIR/tools/upkeeper_anomaly_custody.py" \
      --root "$ROOT_DIR" \
      --loop-log "$log_file" \
      --state-root "$custody_root" \
      --obligation-root "$obligation_root" \
      --recent-lines "$BACKLOG_ANOMALY_CUSTODY_LINES" \
      --max-findings "$BACKLOG_ANOMALY_CUSTODY_MAX_FINDINGS" \
      --write-obligations 2>&1
  )"
  rc="$?"
  set -e
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    log "$line"
  done <<<"$output"
  if [[ "$rc" -ne 0 ]]; then
    log "anomaly custody audit failed with status $rc; stopping before normal issue selection"
    return "$rc"
  fi
  return 0
}

backlog_select_open_obligation_json() {
  ROOT_DIR="$ROOT_DIR" \
    UPKEEPER_OBLIGATION_DIR="${BACKLOG_OBLIGATION_DIR:-$ROOT_DIR/runtime/upkeeper-obligations}" \
    UPKEEPER_AUTOMATION_NOW_EPOCH="${BACKLOG_TEST_NOW_EPOCH:-}" \
    bash -c 'source "$1"; automation_select_open_obligation_json' bash "$ROOT_DIR/lib/upkeeper/automation_obligations.bash"
}

backlog_reconcile_open_obligations() {
  local output status duplicate_count current_before current_after foreign_count groups

  [[ "$BACKLOG_OBLIGATION_RECONCILE" == "1" ]] || return 0
  output="$(
    ROOT_DIR="$ROOT_DIR" \
      UPKEEPER_OBLIGATION_DIR="${BACKLOG_OBLIGATION_DIR:-$ROOT_DIR/runtime/upkeeper-obligations}" \
      bash -c 'source "$1"; automation_reconcile_open_obligations_json' bash "$ROOT_DIR/lib/upkeeper/automation_obligations.bash"
  )" || return $?
  status="$(jq -r '.status // "unknown"' <<<"$output")"
  duplicate_count="$(jq -r '.duplicates_resolved // 0' <<<"$output")"
  current_before="$(jq -r '.current_root_open_before // 0' <<<"$output")"
  current_after="$(jq -r '.current_root_open_after // 0' <<<"$output")"
  foreign_count="$(jq -r '.deferred_foreign_root_count // 0' <<<"$output")"
  groups="$(jq -r '.duplicate_groups // 0' <<<"$output")"
  if [[ "$status" == "reconciled" || "$foreign_count" != "0" ]]; then
    log "automation obligation reconciliation: status=$status current_open_before=$current_before current_open_after=$current_after duplicate_groups=$groups duplicates_resolved=$duplicate_count foreign_deferred=$foreign_count"
  fi
  return 0
}

backlog_sync_obligation_issue_reports() {
  local output status current_open drafted updated github_created github_existing github_failed report_dir umbrella_unlinked

  [[ "$BACKLOG_OBLIGATION_ISSUE_REPORTS" == "1" ]] || return 0
  prepare_backlog_runtime_env
  output="$(
    ROOT_DIR="$ROOT_DIR" \
      UPKEEPER_OBLIGATION_DIR="${BACKLOG_OBLIGATION_DIR:-$ROOT_DIR/runtime/upkeeper-obligations}" \
      UPKEEPER_OBLIGATION_ISSUE_REPORT_DIR="$UPKEEPER_OBLIGATION_ISSUE_REPORT_DIR" \
      UPKEEPER_OBLIGATION_GITHUB_ISSUE_WRITE="$BACKLOG_OBLIGATION_GITHUB_ISSUE_WRITE" \
      UPKEEPER_OBLIGATION_GITHUB_ISSUE_LABELS="$BACKLOG_OBLIGATION_GITHUB_ISSUE_LABELS" \
      bash -c 'source "$1"; automation_sync_obligation_issue_reports_json' bash "$ROOT_DIR/lib/upkeeper/automation_obligations.bash"
  )" || return $?
  status="$(jq -r '.status // "unknown"' <<<"$output")"
  current_open="$(jq -r '.current_root_open // 0' <<<"$output")"
  drafted="$(jq -r '.drafted // 0' <<<"$output")"
  updated="$(jq -r '.updated_records // 0' <<<"$output")"
  github_created="$(jq -r '.github_created // 0' <<<"$output")"
  github_existing="$(jq -r '.github_existing // 0' <<<"$output")"
  github_failed="$(jq -r '.github_failed // 0' <<<"$output")"
  umbrella_unlinked="$(jq -r '.umbrella_unlinked // 0' <<<"$output")"
  report_dir="$(jq -r '.report_dir // ""' <<<"$output")"
  if [[ "$current_open" != "0" || "$github_failed" != "0" ]]; then
    log "automation obligation issue reports: status=$status current_open=$current_open drafted=$drafted records_updated=$updated github_created=$github_created github_existing=$github_existing github_failed=$github_failed umbrella_unlinked=$umbrella_unlinked report_dir=$report_dir"
  fi
  if [[ "$BACKLOG_OBLIGATION_GITHUB_ISSUE_WRITE" == "1" && "$github_failed" != "0" ]]; then
    log "automation obligation GitHub issue creation had failures; stopping before normal issue selection"
    return 1
  fi
  return 0
}

backlog_prepare_obligation_prompt_file() {
  local obligation_json="$1"

  ROOT_DIR="$ROOT_DIR" \
    UPKEEPER_OBLIGATION_DIR="${BACKLOG_OBLIGATION_DIR:-$ROOT_DIR/runtime/upkeeper-obligations}" \
    bash -c 'source "$1"; automation_prepare_obligation_prompt_file "$2"' bash "$ROOT_DIR/lib/upkeeper/automation_obligations.bash" "$obligation_json"
}

backlog_record_obligation_attempt() {
  local obligation_json="$1"
  local attempt_status="$2"
  local exit_status="${3:-}"
  local result_summary="${4:-}"

  ROOT_DIR="$ROOT_DIR" \
    UPKEEPER_OBLIGATION_DIR="${BACKLOG_OBLIGATION_DIR:-$ROOT_DIR/runtime/upkeeper-obligations}" \
    UPKEEPER_OBLIGATION_RETRY_LIMIT="$BACKLOG_OBLIGATION_RETRY_LIMIT" \
    UPKEEPER_OBLIGATION_RETRY_COOLDOWN_SECONDS="$BACKLOG_OBLIGATION_RETRY_COOLDOWN_SECONDS" \
    UPKEEPER_AUTOMATION_NOW_EPOCH="${BACKLOG_TEST_NOW_EPOCH:-}" \
    bash -c 'source "$1"; automation_record_obligation_attempt_json "$2" "$3" "$4" "$5"' \
      bash "$ROOT_DIR/lib/upkeeper/automation_obligations.bash" "$obligation_json" "$attempt_status" "$exit_status" "$result_summary"
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

  if marker_path="$(latest_active_primary_quota_block_marker "$CODEX_MODEL" 2>/dev/null)"; then
    marker_epoch="$(backlog_marker_field "$marker_path" "blocked_until_epoch")"
    marker_bucket="$(backlog_marker_field "$marker_path" "blocked_bucket")"
    marker_reason="$(backlog_marker_field "$marker_path" "reason")"
    if [[ "$BACKLOG_QUOTA_COOLDOWN_BYPASS" != "1" || "$marker_bucket" == "backend_usage_limit" || "$marker_reason" == "backend_usage_limit" ]]; then
      backlog_hibernate_until_epoch "$marker_epoch" "${marker_bucket:-primary}" "${marker_reason:-active quota marker}" "quota_marker" || return "$?"
    fi
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

  if [[ "$snapshot_stale_after_reset" == "true" && ( "$primary_decision" == "defer" || "$secondary_decision" == "defer" ) ]]; then
    if ! backlog_open_stale_quota_obligation "$quota_json" "$primary_decision" "$secondary_decision"; then
      log "quota preflight: stale quota evidence after reset could not be recorded as non-perfect health; failing closed"
      return 4
    fi
  else
    backlog_resolve_stale_quota_obligations "$CODEX_MODEL"
  fi

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
        log "quota preflight: burn bypass continuing despite stale quota evidence after reset; recorded_non_perfect_health=1 obligation_id=${BACKLOG_STALE_QUOTA_OBLIGATION_ID:-unknown} primary=$primary_decision secondary=$secondary_decision primary_reset_expired=$primary_reset_expired secondary_reset_expired=$secondary_reset_expired"
      else
        log "quota preflight: burn bypass continuing despite stale quota evidence (primary=$primary_decision secondary=$secondary_decision)"
      fi
      return 0
    fi

    if [[ "$snapshot_stale_after_reset" == "true" && "$primary_decision" == "defer" && "$secondary_decision" == "defer" ]]; then
      log "quota preflight: stale quota evidence after reset recorded as non-perfect health obligation_id=${BACKLOG_STALE_QUOTA_OBLIGATION_ID:-unknown}; retrying guarded run this cycle to refresh quota state (primary=$primary_decision secondary=$secondary_decision primary_reset_expired=$primary_reset_expired secondary_reset_expired=$secondary_reset_expired)"
      return 0
    fi
    if [[ "$snapshot_stale_after_reset" == "true" ]]; then
      log "quota preflight: deferring backlog run this cycle after recording stale quota evidence as non-perfect health obligation_id=${BACKLOG_STALE_QUOTA_OBLIGATION_ID:-unknown} (primary=$primary_decision secondary=$secondary_decision)"
    else
      log "quota preflight: deferring backlog run this cycle (primary=$primary_decision secondary=$secondary_decision)"
    fi
    return 3
  fi
  return 0
}

current_backlog_pr() {
  gh pr list --state open --json number,title,headRefName \
    --jq '.[] | select(.headRefName | startswith("'"$BACKLOG_BRANCH_PREFIX"'")) | [.number, .headRefName] | @tsv' \
    | sed -n '1p'
}

backlog_log_pr_watch_hint() {
  local pr_number="${1:-}"

  [[ -n "$pr_number" ]] || return 0
  log "PR #$pr_number checks may be pending; watch with: ./orchestration/watch-pr.sh $pr_number"
}

checkout_backlog_branch() {
  local branch="$1"

  log "branch sync: plane=git waiting_for=checkout_or_fetch branch=$branch"
  if git show-ref --verify --quiet "refs/heads/$branch"; then
    git checkout "$branch" >/dev/null
    git pull --ff-only origin "$branch"
  else
    git fetch origin "$branch"
    git checkout -b "$branch" "origin/$branch" >/dev/null
  fi
}

backlog_ensure_local_branch_pushed() {
  local pr_number="$1"
  local branch="$2"
  local context="${3:-pr_checks}"
  local current_branch counts remote_ahead local_ahead status_output

  [[ -n "$branch" ]] || return 0
  case "$branch" in
    "$BACKLOG_BRANCH_PREFIX"*) ;;
    *) return 0 ;;
  esac

  current_branch="$(git rev-parse --abbrev-ref HEAD)"
  if [[ "$current_branch" != "$branch" ]]; then
    log "local branch push guard blocked branch=$branch current_branch=$current_branch context=$context reason=wrong_branch action=stop_before_pr_checks"
    return 1
  fi

  if ! git fetch origin "$branch" >/dev/null; then
    log "local branch push guard blocked branch=$branch context=$context reason=fetch_failed action=stop_before_pr_checks"
    return 1
  fi
  if ! git show-ref --verify --quiet "refs/remotes/origin/$branch"; then
    log "local branch push guard blocked branch=$branch context=$context reason=missing_remote_ref action=stop_before_pr_checks"
    return 1
  fi

  counts="$(git rev-list --left-right --count "origin/$branch...HEAD")" || {
    log "local branch push guard blocked branch=$branch context=$context reason=compare_failed action=stop_before_pr_checks"
    return 1
  }
  read -r remote_ahead local_ahead <<<"$counts"
  remote_ahead="${remote_ahead:-0}"
  local_ahead="${local_ahead:-0}"

  if [[ "$local_ahead" == "0" && "$remote_ahead" == "0" ]]; then
    return 0
  fi

  if [[ "$remote_ahead" != "0" ]]; then
    log "local branch push guard blocked branch=$branch pr=$pr_number local_ahead=$local_ahead remote_ahead=$remote_ahead context=$context reason=diverged_or_behind action=manual_reconcile"
    return 1
  fi

  status_output="$(git status --short)"
  if [[ -n "$status_output" ]]; then
    log "local branch push guard blocked branch=$branch pr=$pr_number local_ahead=$local_ahead context=$context reason=dirty_worktree action=stop_before_pr_checks"
    return 1
  fi

  log "local branch push guard branch=$branch pr=$pr_number local_ahead=$local_ahead context=$context action=push_before_pr_checks"
  if ! git push origin "HEAD:$branch" >/dev/null; then
    log "local branch push guard blocked branch=$branch pr=$pr_number local_ahead=$local_ahead context=$context reason=push_failed action=stop_before_pr_checks"
    return 1
  fi
  log "local branch push guard branch=$branch pr=$pr_number local_ahead=$local_ahead context=$context action=pushed_wait_for_fresh_checks"
  backlog_log_pr_watch_hint "$pr_number"
  return 0
}

open_backlog_pr() {
  local branch pr_number

  log "new backlog PR setup: plane=git waiting_for=sync_main"
  git checkout main >/dev/null
  git pull --ff-only origin main >/dev/null

  branch="${BACKLOG_BRANCH_PREFIX}$(date +%Y%m%d-%H%M%S)"
  log "new backlog PR setup: plane=git waiting_for=create_branch branch=$branch"
  git checkout -b "$branch" >/dev/null
  git commit --allow-empty -m "Start backlog issue batch" >/dev/null
  log "new backlog PR setup: plane=git waiting_for=push_branch branch=$branch"
  git push -u origin "$branch" >/dev/null
  log "new backlog PR setup: plane=github waiting_for=create_pull_request branch=$branch"
  gh pr create \
    --base main \
    --head "$branch" \
    --title "$BACKLOG_PR_TITLE" \
    --body "Backlog wrench batch.

Target: up to ${BACKLOG_BATCH_LIMIT} bug or data-protection fixes, newest non-feature/non-research issue first.

Validation: script-local quick validation plus required PR checks before merge." >/dev/null

  pr_number="$(gh pr view --json number --jq '.number')"
  backlog_log_pr_watch_hint "$pr_number"
  printf '%s\t%s\n' "$pr_number" "$branch"
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
  local target_hint="${2:-}"
  local upkeeper_args=()
  local upkeeper_status=0

  prepare_backlog_runtime_env

  if [[ -n "$issue_number" ]]; then
    if [[ "$BACKLOG_IGNORE_FAILURE_QUEUE" == "1" ]]; then
      upkeeper_args+=(--ignore-failure-queue)
    fi
    if [[ -n "$target_hint" ]]; then
      upkeeper_args+=(--target-file="$target_hint")
    fi
    upkeeper_args+=(--fix-issue="$issue_number")
    log "running Upkeeper for issue #$issue_number with $CODEX_MODEL/$CODEX_REASONING_EFFORT target=${target_hint:-wrapper-inferred}"
    backlog_update_active_owner_heartbeat "running_upkeeper" \
      "$(backlog_wait_detail llm codex_issue_repair "issue=$issue_number" "target=${target_hint:-wrapper-inferred}" "model=$CODEX_MODEL" "effort=$CODEX_REASONING_EFFORT" "expected=patch_or_status")" \
      "" "owner_pid_start_cwd_verified"
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
    backlog_update_active_owner_heartbeat "running_upkeeper" \
      "$(backlog_wait_detail llm codex_file_review "selection_order=newest" "model=$CODEX_MODEL" "effort=$CODEX_REASONING_EFFORT" "expected=review_or_status")" \
      "" "owner_pid_start_cwd_verified"
    ./Upkeeper --selection-order=newest
  fi
}

run_upkeeper_for_obligation() {
  local obligation_json="$1"
  local obligation_id obligation_path obligation_kind obligation_summary target_hint prompt_file prompt_root
  local upkeeper_status=0

  prepare_backlog_runtime_env
  obligation_id="$(jq -r '.id // ""' <<<"$obligation_json")"
  obligation_path="$(jq -r '.path // ""' <<<"$obligation_json")"
  obligation_kind="$(jq -r '.kind // "prior_run_anomaly"' <<<"$obligation_json")"
  obligation_summary="$(jq -r '.summary // "automation obligation"' <<<"$obligation_json")"
  target_hint="$(jq -r '.repair_target_file // .target_file // "Upkeeper"' <<<"$obligation_json")"
  [[ -n "$target_hint" && "$target_hint" != "null" ]] || target_hint="Upkeeper"
  prompt_file="$(backlog_prepare_obligation_prompt_file "$obligation_json")"
  prompt_root="$(dirname -- "$prompt_file")"

  log "running Upkeeper for automation obligation $obligation_id kind=$obligation_kind target=$target_hint"
  backlog_update_active_owner_heartbeat "running_upkeeper" \
    "$(backlog_wait_detail llm codex_obligation_repair "obligation=$obligation_id" "kind=$obligation_kind" "target=$target_hint" "model=$CODEX_MODEL" "effort=$CODEX_REASONING_EFFORT" "expected=repair_or_preserve")" \
    "" "owner_pid_start_cwd_verified"
  UPKEEPER_AUTOMATION_LAUNCHER="backlog" \
    UPKEEPER_AUTOMATION_VARIANT="issue-batch" \
    UPKEEPER_AUTOMATION_POLICY="pre-issue-health" \
    UPKEEPER_AUTOMATION_WORKFLOW="obligation-repair" \
    UPKEEPER_AUTOMATION_OBLIGATION_ID="$obligation_id" \
    UPKEEPER_AUTOMATION_OBLIGATION_PATH="$obligation_path" \
    UPKEEPER_PROMPT_TRUST_ROOT="$prompt_root" \
    ./Upkeeper --ignore-failure-queue --target-file="$target_hint" --prompt-file "$prompt_file"
  upkeeper_status="$?"
  if [[ "$upkeeper_status" -ne 0 ]]; then
    if [[ "$upkeeper_status" -eq 2 ]]; then
      return 2
    fi
    return "$upkeeper_status"
  fi
  log "automation obligation $obligation_id completed: $obligation_summary"
}

has_worktree_changes() {
  [[ -n "$(git status --short)" ]]
}

backlog_git_path_changed() {
  local path="$1"

  git diff --name-only --diff-filter=ACMR -- "$path" | grep -Fxq "$path"
}

run_changed_python_compile_validation() {
  local -a python_files=()
  local python_file

  while IFS= read -r -d '' python_file; do
    [[ -n "$python_file" ]] || continue
    python_files+=("$python_file")
  done < <(git diff --name-only -z --diff-filter=ACMR -- '*.py')

  [[ "${#python_files[@]}" -gt 0 ]] || return 0
  require_command python3 || return $?
  log "per-bug validation: python compile (${#python_files[@]} changed file(s))"
  python3 -m py_compile "${python_files[@]}" || return $?
}

run_focused_issue_validation() {
  local issue_number="${1:-}"
  local target_hint="${2:-}"

  [[ -n "$issue_number" ]] || return 0
  if [[ "$target_hint" == "tools/upkeeper_lattice.py" ]] || backlog_git_path_changed "tools/upkeeper_lattice.py"; then
    if backlog_git_path_changed "tools/upkeeper_lattice.py"; then
      require_command python3 || return $?
      log "per-bug validation: lattice focused coverage (tests/lattice_test.bash)"
      python3 -m py_compile tools/upkeeper_lattice.py || return $?
      bash tests/lattice_test.bash || return $?
    fi
  fi
}

run_changed_source_contract_validation() {
  local changed_count=0
  local changed_path

  while IFS= read -r -d '' changed_path; do
    [[ -n "$changed_path" ]] || continue
    changed_count=$((changed_count + 1))
  done < <(
    git diff --name-only -z --diff-filter=ACMR -- \
      Upkeeper \
      lib/upkeeper \
      tools \
      tests
  )

  [[ "$changed_count" -gt 0 ]] || return 0
  log "per-bug validation: source contracts (${changed_count} changed file(s))"
  tools/validate_upkeeper.sh --source-contracts || return $?
}

backlog_batch_validation_owner_hint() {
  local phase="${1:-}"
  local command_text="${2:-}"
  local output_file="${3:-}"
  local output_text

  output_text=""
  if [[ -n "$output_file" && -r "$output_file" ]]; then
    output_text="$(tail -n 80 -- "$output_file" 2>/dev/null || true)"
  fi

  case "$command_text $output_text" in
    *"tools/validate_upkeeper.sh"*|*"validate_upkeeper:"*)
      case "$output_text" in
        *"backlog launcher"*|*"orchestration/backlog.sh"*)
          printf '%s\n' "orchestration/backlog.sh"
          return 0
          ;;
      esac
      printf '%s\n' "tools/validate_upkeeper.sh"
      return 0
      ;;
    *"tools/check_public_docs.sh"*|*"check_public_docs:"*)
      printf '%s\n' "tools/check_public_docs.sh"
      return 0
      ;;
    *"git diff --check"*|*"trailing whitespace"*|*"new blank line at EOF"*)
      printf '%s\n' "Upkeeper"
      return 0
      ;;
    *"tests/"*".bash"*)
      python3 - "$output_text" <<'PY'
import re
import sys

text = sys.argv[1]
match = re.search(r"(tests/[A-Za-z0-9_.-]+\.bash)", text)
print(match.group(1) if match else "tests")
PY
      return 0
      ;;
  esac

  case "$phase" in
    batch_validation.bash_syntax)
      printf '%s\n' "orchestration/backlog.sh"
      ;;
    batch_validation.unit_tests)
      printf '%s\n' "tests"
      ;;
    batch_validation.docs_quick)
      printf '%s\n' "tools/check_public_docs.sh"
      ;;
    batch_validation.diff_whitespace)
      printf '%s\n' "Upkeeper"
      ;;
    batch_validation.quick_validator)
      printf '%s\n' "tools/validate_upkeeper.sh"
      ;;
    *)
      printf '%s\n' "orchestration/backlog.sh"
      ;;
  esac
}

backlog_open_batch_validation_obligation() {
  local phase="$1"
  local exit_code="$2"
  local output_file="$3"
  local owner_hint="$4"
  shift 4
  local -a command_args=("$@")
  local obligation_root open_dir command_text now payload id path seen_count

  BACKLOG_BATCH_VALIDATION_OBLIGATION_ID=""
  BACKLOG_BATCH_VALIDATION_OBLIGATION_PATH=""

  obligation_root="${BACKLOG_OBLIGATION_DIR:-$ROOT_DIR/runtime/upkeeper-obligations}"
  open_dir="$obligation_root/open"
  mkdir -p -- "$open_dir" || return 1
  chmod 700 "$obligation_root" "$open_dir" 2>/dev/null || true

  command_text="$(printf '%q ' "${command_args[@]}")"
  command_text="${command_text% }"
  now="$(date '+%Y-%m-%dT%H:%M:%S%z')"
  payload="$(
    python3 - \
      "$ROOT_DIR" \
      "$phase" \
      "$exit_code" \
      "$owner_hint" \
      "$output_file" \
      "$now" \
      "${pr_number:-}" \
      "${branch:-}" \
      "$command_text" \
      "${command_args[@]}" <<'PY'
import hashlib
import json
import pathlib
import re
import sys

root, phase, exit_code, owner_hint, output_file, now, pr_number, branch, command_text, *command = sys.argv[1:]
try:
    raw_text = pathlib.Path(output_file).read_text(encoding="utf-8", errors="replace")
except OSError:
    raw_text = ""

tail_lines = raw_text.splitlines()[-80:]
tail_text = "\n".join(tail_lines)

def normalize(value: str) -> str:
    value = value.replace(root, "<repo-root>")
    value = re.sub(r"/tmp/upkeeper[-A-Za-z0-9_./]*", "/tmp/upkeeper-<tmp>", value)
    value = re.sub(r"/home/[^/\s]+/\.local/state/upkeeper/[^\s]+", "<upkeeper-state>", value)
    value = re.sub(r"20[0-9]{2}-[0-9]{2}-[0-9]{2}T[0-9:+-]+", "<timestamp>", value)
    return value

normalized_tail = normalize(tail_text)
fingerprint = hashlib.sha256(
    f"backlog-batch-validation\0{phase}\0{exit_code}\0{command_text}\0{normalized_tail}".encode("utf-8")
).hexdigest()[:24]
obligation_id = f"batch-validation-{fingerprint}"
required = [
    f"repair the failing local batch validation phase: {phase}",
    f"rerun the failing command: {command_text}",
    "rerun tools/validate_upkeeper.sh --quick",
]
record = {
    "schema": 1,
    "record_type": "automation_obligation",
    "status": "open",
    "id": obligation_id,
    "kind": "local_validation_failure",
    "severity": "high",
    "summary": f"Backlog batch validation failed during {phase}",
    "root": root,
    "source": "backlog_batch_validation",
    "source_pr_number": pr_number,
    "source_branch": branch,
    "failed_phase": phase,
    "command": command,
    "command_text": command_text,
    "exit_code": str(exit_code),
    "fingerprint": f"backlog-batch-validation:{fingerprint}",
    "target_scope": "target",
    "target_file": owner_hint,
    "repair_target_file": owner_hint,
    "reason": "BATCH_VALIDATION_FAILED",
    "required_resolution": required,
    "evidence": {
        "source": "batch_validation_output",
        "tail_line_count": len(tail_lines),
        "tail": tail_lines,
        "normalized_tail": normalized_tail,
    },
}
print(json.dumps(record, separators=(",", ":")))
PY
  )" || return 1

  id="$(jq -r '.id' <<<"$payload")"
  path="$open_dir/$id.json"
  if [[ -f "$path" ]]; then
    seen_count="$(jq -r '.seen_count // .occurrence_count // 1' "$path" 2>/dev/null || printf '1')"
    payload="$(
      jq \
        --argjson next_count "$((seen_count + 1))" \
        --arg updated_at "$now" \
        --argjson replacement "$payload" \
        '. as $old
         | $replacement
         | .created_at = ($old.created_at // $updated_at)
         | .updated_at = $updated_at
         | .seen_count = $next_count
         | .occurrence_count = $next_count
         | .first_source_pr_number = ($old.first_source_pr_number // $old.source_pr_number // $replacement.source_pr_number)
         | .prior_evidence_tail = ($old.evidence.tail // [])' "$path"
    )" || return 1
  else
    payload="$(jq --arg created_at "$now" '.created_at = $created_at | .updated_at = $created_at | .seen_count = 1 | .occurrence_count = 1' <<<"$payload")" || return 1
  fi
  python3 - "$path" "$payload" <<'PY'
import json
import os
import sys

path, payload = sys.argv[1:3]
data = json.loads(payload)
parent = os.path.dirname(path)
os.makedirs(parent, mode=0o700, exist_ok=True)
try:
    os.chmod(parent, 0o700)
except OSError:
    pass
tmp = f"{path}.tmp.{os.getpid()}"
fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
try:
    with os.fdopen(fd, "w", encoding="utf-8") as handle:
        json.dump(data, handle, indent=2, sort_keys=True)
        handle.write("\n")
    os.replace(tmp, path)
    try:
        os.chmod(path, 0o600)
    except OSError:
        pass
except BaseException:
    try:
        os.unlink(tmp)
    except OSError:
        pass
    raise
PY
  BACKLOG_BATCH_VALIDATION_OBLIGATION_ID="$id"
  BACKLOG_BATCH_VALIDATION_OBLIGATION_PATH="$path"
  log "automation obligation opened for batch validation failure id=$id phase=$phase target=$owner_hint path=$path"
}

backlog_batch_validation_retry_key() {
  local phase="${1:-}"

  printf '%s\n' "$phase" | tr '/: ' '___' | tr -cd '[:alnum:]_.-'
}

backlog_batch_validation_retry_path() {
  local phase="${1:-}"
  local state_root retry_dir

  state_root="$(backlog_state_root)"
  retry_dir="$state_root/batch-validation-retry"
  printf '%s/%s.%s.json\n' "$retry_dir" "$(backlog_branch_key)" "$(backlog_batch_validation_retry_key "$phase")"
}

backlog_batch_validation_retry_fingerprint() {
  local phase="${1:-}"
  local command_text="${2:-}"
  local branch="${3:-}"
  local head="${4:-}"

  python3 - "$phase" "$command_text" "$branch" "$head" <<'PY'
import hashlib
import sys

phase, command_text, branch, head = sys.argv[1:5]
print(hashlib.sha256(f"backlog-batch-validation-retry\0{branch}\0{head}\0{phase}\0{command_text}".encode("utf-8")).hexdigest()[:24])
PY
}

backlog_touch_batch_validation_obligation_retry() {
  local obligation_path="${1:-}"
  local now tmp

  [[ -n "$obligation_path" && -f "$obligation_path" ]] || return 0
  now="$(date '+%Y-%m-%dT%H:%M:%S%z')"
  tmp="$(mktemp "${TMPDIR:-/tmp}/upkeeper-batch-validation-obligation.XXXXXX")" || return 0
  if jq \
    --arg updated_at "$now" \
    '.updated_at = $updated_at
     | .seen_count = ((.seen_count // .occurrence_count // 1) + 1)
     | .occurrence_count = .seen_count
     | .retry_guard_repeated = true' "$obligation_path" >"$tmp"; then
    mv "$tmp" "$obligation_path"
    chmod 600 "$obligation_path" 2>/dev/null || true
  else
    rm -f -- "$tmp"
  fi
}

backlog_record_batch_validation_retry_marker() {
  local phase="$1"
  local exit_code="$2"
  local command_text="$3"
  local owner_hint="$4"
  local marker_path marker_dir now branch_name head fingerprint head_short

  marker_path="$(backlog_batch_validation_retry_path "$phase")"
  marker_dir="$(dirname -- "$marker_path")"
  mkdir -p -- "$marker_dir" || return 0
  chmod 700 "$marker_dir" 2>/dev/null || true
  now="$(date '+%Y-%m-%dT%H:%M:%S%z')"
  branch_name="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || printf '%s\n' unknown)"
  head="$(git rev-parse --verify HEAD 2>/dev/null || printf '%s\n' unknown)"
  fingerprint="$(backlog_batch_validation_retry_fingerprint "$phase" "$command_text" "$branch_name" "$head")"
  python3 - \
    "$marker_path" \
    "$now" \
    "$branch_name" \
    "$head" \
    "$phase" \
    "$command_text" \
    "$exit_code" \
    "$owner_hint" \
    "$fingerprint" \
    "$BACKLOG_BATCH_VALIDATION_OBLIGATION_ID" \
    "$BACKLOG_BATCH_VALIDATION_OBLIGATION_PATH" <<'PY'
import json
import os
import sys

(
    path,
    now,
    branch,
    head,
    phase,
    command_text,
    exit_code,
    owner_hint,
    fingerprint,
    obligation_id,
    obligation_path,
) = sys.argv[1:12]
record = {
    "schema": 1,
    "record_type": "backlog_batch_validation_retry_marker",
    "created_at": now,
    "updated_at": now,
    "branch": branch,
    "head": head,
    "phase": phase,
    "command_text": command_text,
    "exit_code": str(exit_code),
    "owner_hint": owner_hint,
    "fingerprint": f"backlog-batch-validation-retry:{fingerprint}",
    "obligation_id": obligation_id,
    "obligation_path": obligation_path,
}
parent = os.path.dirname(path)
os.makedirs(parent, mode=0o700, exist_ok=True)
tmp = f"{path}.tmp.{os.getpid()}"
fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
try:
    with os.fdopen(fd, "w", encoding="utf-8") as handle:
        json.dump(record, handle, indent=2, sort_keys=True)
        handle.write("\n")
    os.replace(tmp, path)
    try:
        os.chmod(path, 0o600)
    except OSError:
        pass
except BaseException:
    try:
        os.unlink(tmp)
    except OSError:
        pass
    raise
PY
  head_short="${head:0:12}"
  log "batch validation retry guard recorded fingerprint=backlog-batch-validation-retry:$fingerprint phase=$phase branch=$branch_name head=$head_short action=route_next_retry_to_obligation"
}

backlog_batch_validation_repeated_failure() {
  local phase="$1"
  local command_text="$2"
  local marker_path branch_name head marker_branch marker_head marker_command exit_code fingerprint obligation_path head_short

  BACKLOG_BATCH_VALIDATION_REPEAT_EXIT_CODE=""
  marker_path="$(backlog_batch_validation_retry_path "$phase")"
  [[ -f "$marker_path" ]] || return 1
  branch_name="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || printf '%s\n' unknown)"
  head="$(git rev-parse --verify HEAD 2>/dev/null || printf '%s\n' unknown)"
  marker_branch="$(jq -r '.branch // ""' "$marker_path" 2>/dev/null || printf '\n')"
  marker_head="$(jq -r '.head // ""' "$marker_path" 2>/dev/null || printf '\n')"
  marker_command="$(jq -r '.command_text // ""' "$marker_path" 2>/dev/null || printf '\n')"
  if [[ "$marker_branch" != "$branch_name" || "$marker_head" != "$head" || "$marker_command" != "$command_text" ]]; then
    rm -f -- "$marker_path"
    return 1
  fi
  exit_code="$(jq -r '.exit_code // "1"' "$marker_path" 2>/dev/null || printf '1')"
  if [[ ! "$exit_code" =~ ^[0-9]+$ || "$exit_code" -lt 1 || "$exit_code" -gt 255 ]]; then
    exit_code=1
  fi
  fingerprint="$(jq -r '.fingerprint // ""' "$marker_path" 2>/dev/null || printf '\n')"
  if [[ -z "$fingerprint" ]]; then
    fingerprint="backlog-batch-validation-retry:$(backlog_batch_validation_retry_fingerprint "$phase" "$command_text" "$branch_name" "$head")"
  fi
  obligation_path="$(jq -r '.obligation_path // ""' "$marker_path" 2>/dev/null || printf '\n')"
  backlog_touch_batch_validation_obligation_retry "$obligation_path"
  head_short="${head:0:12}"
  log "batch validation retry guard repeated_failure fingerprint=$fingerprint phase=$phase branch=$branch_name head=$head_short exit_code=$exit_code action=skip_validation_route_to_obligation"
  BACKLOG_BATCH_VALIDATION_REPEAT_EXIT_CODE="$exit_code"
  return 0
}

backlog_clear_batch_validation_retry_marker() {
  local phase="$1"
  local command_text="$2"
  local marker_path branch_name head marker_branch marker_head marker_command

  marker_path="$(backlog_batch_validation_retry_path "$phase")"
  [[ -f "$marker_path" ]] || return 0
  branch_name="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || printf '%s\n' unknown)"
  head="$(git rev-parse --verify HEAD 2>/dev/null || printf '%s\n' unknown)"
  marker_branch="$(jq -r '.branch // ""' "$marker_path" 2>/dev/null || printf '\n')"
  marker_head="$(jq -r '.head // ""' "$marker_path" 2>/dev/null || printf '\n')"
  marker_command="$(jq -r '.command_text // ""' "$marker_path" 2>/dev/null || printf '\n')"
  if [[ "$marker_branch" != "$branch_name" || "$marker_head" != "$head" || "$marker_command" != "$command_text" ]]; then
    rm -f -- "$marker_path"
  fi
}

run_batch_validation_phase() {
  local phase="$1"
  local label="$2"
  shift 2
  local output_file rc owner_hint command_text

  command_text="$(printf '%q ' "$@")"
  command_text="${command_text% }"
  if backlog_batch_validation_repeated_failure "$phase" "$command_text"; then
    log "batch validation: $label skipped because identical prior failure is already under obligation custody"
    return "$BACKLOG_BATCH_VALIDATION_REPEAT_EXIT_CODE"
  fi
  output_file="$(mktemp "${TMPDIR:-/tmp}/upkeeper-backlog-validation.XXXXXX")"
  log "batch validation: $label"
  set +e
  "$@" 2>&1 | tee "$output_file"
  rc="${PIPESTATUS[0]}"
  set -e
  if [[ "$rc" -ne 0 ]]; then
    owner_hint="$(backlog_batch_validation_owner_hint "$phase" "$command_text" "$output_file")"
    backlog_open_batch_validation_obligation "$phase" "$rc" "$output_file" "$owner_hint" "$@" || true
    if [[ -n "$BACKLOG_BATCH_VALIDATION_OBLIGATION_PATH" ]]; then
      backlog_record_batch_validation_retry_marker "$phase" "$rc" "$command_text" "$owner_hint" || true
    fi
    rm -f -- "$output_file"
    return "$rc"
  fi
  backlog_clear_batch_validation_retry_marker "$phase" "$command_text"
  rm -f -- "$output_file"
  return 0
}

run_per_bug_validation() {
  local issue_number="${1:-}"
  local target_hint="${2:-}"
  local validation_start

  [[ "${BACKLOG_SKIP_LOCAL_VALIDATION:-0}" == "1" ]] && return 0

  validation_start="$SECONDS"
  backlog_update_active_owner_heartbeat "validating" \
    "$(backlog_wait_detail local_validation per_bug_validation "issue=${issue_number:-none}" "target=${target_hint:-none}" "expected=syntax_compile_source_contract_diff_checks")" \
    "" "owner_pid_start_cwd_verified"
  log "per-bug validation: bash syntax"
  bash -n Upkeeper ChimneySweep FlameOn lib/upkeeper/*.bash tools/*.sh tests/*.bash testruns/*.sh Upkeeper.conf configurations/default.conf orchestration/backlog.sh || return $?
  run_changed_python_compile_validation || return $?
  run_focused_issue_validation "$issue_number" "$target_hint" || return $?
  run_changed_source_contract_validation || return $?
  log "per-bug validation: diff whitespace"
  git diff --check || return $?
  log "per-bug validation: complete in $((SECONDS - validation_start))s"
}

run_batch_validation() {
  local validation_start

  [[ "${BACKLOG_SKIP_LOCAL_VALIDATION:-0}" == "1" ]] && return 0

  validation_start="$SECONDS"
  backlog_update_active_owner_heartbeat "validating" \
    "$(backlog_wait_detail local_validation batch_validation "expected=syntax_tests_docs_diff_quick_validator")" \
    "" "owner_pid_start_cwd_verified"
  run_batch_validation_phase "batch_validation.bash_syntax" "bash syntax" \
    bash -n Upkeeper ChimneySweep FlameOn lib/upkeeper/*.bash tools/*.sh tests/*.bash testruns/*.sh Upkeeper.conf configurations/default.conf orchestration/backlog.sh || return $?
  run_batch_validation_phase "batch_validation.unit_tests" "unit tests" \
    bash -c 'set -euo pipefail; for test_script in tests/*.bash; do bash "$test_script"; done' || return $?
  run_batch_validation_phase "batch_validation.docs_quick" "docs quick checks" \
    tools/check_public_docs.sh --quick || return $?
  run_batch_validation_phase "batch_validation.diff_whitespace" "diff whitespace" \
    git diff --check || return $?
  run_batch_validation_phase "batch_validation.quick_validator" "quick validator" \
    tools/validate_upkeeper.sh --quick || return $?
  log "batch validation: complete in $((SECONDS - validation_start))s"
}

commit_and_push_changes() {
  local issue_number="${1:-}"
  local commit_message="${2:-}"
  local target_hint="${3:-}"
  local message

  cleanup_ephemeral_artifacts || return $?
  has_worktree_changes || return 1
  case "$BACKLOG_PER_BUG_VALIDATION_MODE" in
    none)
      log "per-bug validation: skipped by BACKLOG_PER_BUG_VALIDATION_MODE=none"
      ;;
    light)
      run_per_bug_validation "$issue_number" "$target_hint" || return $?
      ;;
    full)
      run_batch_validation || return $?
      ;;
    *)
      fail "unsupported BACKLOG_PER_BUG_VALIDATION_MODE: $BACKLOG_PER_BUG_VALIDATION_MODE"
      ;;
  esac
  cleanup_ephemeral_artifacts || return $?
  log "staging tracked changes"
  git add --all || return $?
  git diff --cached --check || return $?
  if [[ -n "$commit_message" ]]; then
    message="$commit_message"
  elif [[ -n "$issue_number" ]]; then
    message="Fix backlog issue #$issue_number"
  else
    message="Apply backlog Upkeeper pass"
  fi
  log "committing: $message plane=git waiting_for=commit"
  git commit -m "$message" || return $?
  log "pushing branch updates plane=git waiting_for=push"
  git push || return $?
  backlog_log_pr_watch_hint "${pr_number:-}"
  return 0
}

backlog_partial_commit_message() {
  local obligation_selected="${1:-0}"
  local obligation_id="${2:-}"
  local issue_number="${3:-}"

  if [[ "$obligation_selected" == "1" ]]; then
    if [[ -n "$obligation_id" && "$obligation_id" != "unknown" ]]; then
      printf 'Preserve partial backlog work for obligation %s' "$obligation_id"
    else
      printf 'Preserve partial backlog work for automation obligation'
    fi
    return 0
  fi
  if [[ -n "$issue_number" ]]; then
    printf 'Preserve partial backlog work for issue #%s' "$issue_number"
  else
    printf 'Preserve partial backlog work for wrapper-selected Upkeeper pass'
  fi
}

backlog_pr_check_progress_enabled() {
  case "${BACKLOG_PR_CHECK_PROGRESS,,}" in
    never|0|no|false|off)
      return 1
      ;;
    *)
      return 0
      ;;
  esac
}

backlog_pr_check_progress_steps_enabled() {
  case "${BACKLOG_PR_CHECK_PROGRESS_STEPS,,}" in
    never|0|no|false|off)
      return 1
      ;;
    *)
      return 0
      ;;
  esac
}

backlog_github_actions_current_step() {
  local link="$1"
  local run_id="" job_id="" run_json rc step

  backlog_pr_check_progress_steps_enabled || return 1
  if [[ "$link" =~ /actions/runs/([0-9]+) ]]; then
    run_id="${BASH_REMATCH[1]}"
  else
    return 1
  fi
  if [[ "$link" =~ /job/([0-9]+) ]]; then
    job_id="${BASH_REMATCH[1]}"
  fi

  set +e
  run_json="$(gh run view "$run_id" --json jobs 2>/dev/null)"
  rc="$?"
  set -e
  [[ "$rc" -eq 0 && -n "$run_json" ]] || return 1

  step="$(jq -r --arg link "$link" --arg job_id "$job_id" '
    def wanted_job:
      if $job_id != "" then
        ((.url // "") | contains("/job/" + $job_id))
      else
        ((.url // "") == $link)
      end;
    ([.jobs[]? | select(wanted_job)][0]) as $job
    | if $job == null then
        empty
      else
        ([$job.steps[]? | select((.status // "") == "in_progress") | .name][0]
         // [$job.steps[]? | select((.status // "") == "queued") | .name][0]
         // [$job.steps[]? | select((.status // "") != "completed") | .name][0]
         // empty)
      end
  ' <<<"$run_json" 2>/dev/null)" || return 1
  [[ -n "$step" && "$step" != "null" ]] || return 1
  printf '%s\n' "$step"
}

backlog_pr_checks_progress_summary() {
  local pr_number="$1"
  local checks_json rc aggregate active_lines now_epoch summary
  local name workflow bucket state started_at link duration step rendered count

  backlog_pr_check_progress_enabled || return 1

  set +e
  checks_json="$(gh pr checks "$pr_number" --watch=false --json name,state,startedAt,completedAt,link,workflow,bucket 2>/dev/null)"
  rc="$?"
  set -e
  [[ "$rc" -eq 0 || -n "$checks_json" ]] || return 1
  [[ -n "$checks_json" ]] || return 1

  aggregate="$(jq -r '
    def bucket_name: ((.bucket // "unknown") | ascii_downcase);
    def count_bucket($name): [.[] | select(bucket_name == $name)] | length;
    def other_count:
      [.[] | select((bucket_name != "pass") and (bucket_name != "pending") and (bucket_name != "fail") and (bucket_name != "skipping"))] | length;
    "checks total=\(length) pass=\(count_bucket("pass")) pending=\(count_bucket("pending")) fail=\(count_bucket("fail")) other=\(other_count)"
  ' <<<"$checks_json" 2>/dev/null)" || return 1
  summary="$aggregate"

  active_lines="$(jq -r '
    def bucket_name: ((.bucket // "unknown") | ascii_downcase);
    def sort_key:
      if bucket_name == "pending" then 0
      elif bucket_name == "fail" then 1
      else 2
      end;
    [.[] | select(bucket_name != "pass") | . + {sort_key: sort_key}]
    | sort_by(.sort_key, (.name // ""))
    | .[0:3][]
    | [(.name // "unnamed check"), (.workflow // ""), (.bucket // "unknown"), (.state // "unknown"), (.startedAt // ""), (.link // "")]
    | @tsv
  ' <<<"$checks_json" 2>/dev/null)" || active_lines=""

  if [[ -n "$active_lines" ]]; then
    now_epoch="$(backlog_now_epoch 2>/dev/null || date '+%s')"
    count=0
    while IFS=$'\t' read -r name workflow bucket state started_at link; do
      [[ -n "$name" ]] || continue
      count=$((count + 1))
      duration="$(backlog_duration_since_iso "$started_at" "$now_epoch")"
      rendered="active=$(backlog_log_value "$name") state=$(backlog_log_value "$state") bucket=$(backlog_log_value "$bucket") duration=$duration"
      if [[ -n "$workflow" ]]; then
        rendered="$rendered workflow=$(backlog_log_value "$workflow")"
      fi
      if step="$(backlog_github_actions_current_step "$link" 2>/dev/null)"; then
        rendered="$rendered step=$(backlog_log_value "$step")"
      fi
      if [[ -n "$link" ]]; then
        rendered="$rendered url=$link"
      fi
      summary="$summary; $rendered"
    done <<<"$active_lines"
    if [[ "$count" -ge 3 ]]; then
      summary="$summary; active_list_truncated=1"
    fi
  fi

  printf '%s\n' "$summary"
}

wait_for_pr_checks() {
  local pr_number="$1"
  local interval timeout_seconds empty_grace_seconds start_epoch now_epoch elapsed status output status_rc progress

  log "waiting for PR #$pr_number checks"
  interval="$(backlog_positive_integer_or_default "$BACKLOG_PR_CHECK_INTERVAL_SECONDS" 60)"
  timeout_seconds="${BACKLOG_PR_CHECK_TIMEOUT_SECONDS:-0}"
  backlog_nonnegative_integer "$timeout_seconds" || timeout_seconds=0
  empty_grace_seconds="${BACKLOG_PR_CHECK_EMPTY_GRACE_SECONDS:-300}"
  backlog_nonnegative_integer "$empty_grace_seconds" || empty_grace_seconds=300
  start_epoch="$(backlog_now_epoch)" || start_epoch=0

  while true; do
    backlog_update_active_owner_heartbeat "waiting_on_pr_checks" \
      "$(backlog_wait_detail_since github pr_checks "$start_epoch" "pr=$pr_number" "phase=polling")" \
      "$pr_number" "polling"
    if backlog_pr_checks_once "$pr_number"; then
      status_rc=0
    else
      status_rc="$?"
    fi
    output="$BACKLOG_PR_CHECKS_LAST_OUTPUT"
    status="$(sed -n '1p' <<<"$output")"
    case "$status_rc" in
      0)
        backlog_update_active_owner_heartbeat "waiting_on_pr_checks" \
          "$(backlog_wait_detail_since github pr_checks "$start_epoch" "pr=$pr_number" "phase=checks_passed")" \
          "$pr_number" "pass"
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
        backlog_update_active_owner_heartbeat "waiting_on_pr_checks" \
          "$(backlog_wait_detail_since github pr_checks "$start_epoch" "pr=$pr_number" "phase=checks_pending" "elapsed=${elapsed}s" "next_check=${interval}s")" \
          "$pr_number" "pending"
        progress="$BACKLOG_PR_CHECKS_PROGRESS_SUMMARY"
        if [[ -n "$progress" ]]; then
          log "PR #$pr_number checks pending; holding owner lease; progress: $progress; checking again in ${interval}s"
        else
          log "PR #$pr_number checks pending; holding owner lease and checking again in ${interval}s"
        fi
        backlog_sleep_seconds "$interval"
        ;;
      3)
        now_epoch="$(backlog_now_epoch)" || now_epoch="$start_epoch"
        elapsed=$((now_epoch - start_epoch))
        [[ "$elapsed" -ge 0 ]] || elapsed=0
        if [[ "$empty_grace_seconds" -le 0 || "$elapsed" -ge "$empty_grace_seconds" ]]; then
          backlog_update_active_owner_heartbeat "waiting_on_pr_checks" \
            "$(backlog_wait_detail_since github pr_checks "$start_epoch" "pr=$pr_number" "phase=checks_absent_timeout" "elapsed=${elapsed}s")" \
            "$pr_number" "fail"
          log "PR #$pr_number checks were not reported after ${elapsed}s; configured empty-check grace is ${empty_grace_seconds}s"
          printf '%s\n' "$output" >&2
          return 1
        fi
        backlog_update_active_owner_heartbeat "waiting_on_pr_checks" \
          "$(backlog_wait_detail_since github pr_checks "$start_epoch" "pr=$pr_number" "phase=checks_settling" "elapsed=${elapsed}s" "next_check=${interval}s")" \
          "$pr_number" "pending"
        progress="$BACKLOG_PR_CHECKS_PROGRESS_SUMMARY"
        if [[ -n "$progress" ]]; then
          log "PR #$pr_number checks not reported yet; treating as pending/settling for up to ${empty_grace_seconds}s; progress: $progress; checking again in ${interval}s"
        else
          log "PR #$pr_number checks not reported yet; treating as pending/settling for up to ${empty_grace_seconds}s; checking again in ${interval}s"
        fi
        backlog_sleep_seconds "$interval"
        ;;
      *)
        backlog_update_active_owner_heartbeat "waiting_on_pr_checks" \
          "$(backlog_wait_detail_since github pr_checks "$start_epoch" "pr=$pr_number" "phase=checks_failed")" \
          "$pr_number" "fail"
        printf '%s\n' "$output" >&2
        return 1
        ;;
    esac
  done
}

backlog_pr_checks_once() {
  local pr_number="$1"
  local next_status rest output rc progress

  BACKLOG_PR_CHECKS_PROGRESS_SUMMARY=""
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
        BACKLOG_PR_CHECKS_PROGRESS_SUMMARY="checks total=1 pass=1 pending=0 fail=0 other=0"
        return 0
        ;;
      pending|wait|waiting|queued|in_progress)
        BACKLOG_PR_CHECKS_LAST_OUTPUT="pending"
        BACKLOG_PR_CHECKS_PROGRESS_SUMMARY='checks total=1 pass=0 pending=1 fail=0 other=0; active="fake PR check" state=pending bucket=pending duration=unknown source=local-test'
        return 2
        ;;
      empty|none|no_checks|no-checks|not_reported|not-reported)
        BACKLOG_PR_CHECKS_LAST_OUTPUT="$(printf 'settling\nno checks reported on the fake branch yet\n')"
        BACKLOG_PR_CHECKS_PROGRESS_SUMMARY="checks total=0 pass=0 pending=0 fail=0 other=0; status=no_checks_reported_yet source=local-test"
        return 3
        ;;
      fail|failed|failure|error)
        BACKLOG_PR_CHECKS_LAST_OUTPUT="fail"
        BACKLOG_PR_CHECKS_PROGRESS_SUMMARY="checks total=1 pass=0 pending=0 fail=1 other=0"
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
    if progress="$(backlog_pr_checks_progress_summary "$pr_number" 2>/dev/null)"; then
      BACKLOG_PR_CHECKS_PROGRESS_SUMMARY="$progress"
    fi
    return 0
  fi
  if grep -Eiq 'pending|queued|in.?progress|waiting' <<<"$output"; then
    BACKLOG_PR_CHECKS_LAST_OUTPUT="$(printf 'pending\n%s\n' "$output")"
    if progress="$(backlog_pr_checks_progress_summary "$pr_number" 2>/dev/null)"; then
      BACKLOG_PR_CHECKS_PROGRESS_SUMMARY="$progress"
    fi
    return 2
  fi
  if grep -Eiq 'no checks reported|no check runs|no statuses reported|no checks? found' <<<"$output"; then
    BACKLOG_PR_CHECKS_LAST_OUTPUT="$(printf 'settling\n%s\n' "$output")"
    if progress="$(backlog_pr_checks_progress_summary "$pr_number" 2>/dev/null)"; then
      BACKLOG_PR_CHECKS_PROGRESS_SUMMARY="$progress"
    else
      BACKLOG_PR_CHECKS_PROGRESS_SUMMARY="checks total=0 pass=0 pending=0 fail=0 other=0; status=no_checks_reported_yet"
    fi
    return 3
  fi

  BACKLOG_PR_CHECKS_LAST_OUTPUT="$(printf 'fail\n%s\n' "$output")"
  if progress="$(backlog_pr_checks_progress_summary "$pr_number" 2>/dev/null)"; then
    BACKLOG_PR_CHECKS_PROGRESS_SUMMARY="$progress"
  fi
  return 1
}

backlog_ensure_pr_checks_allow_next_issue() {
  local pr_number="$1"
  local count="$2"
  local status

  [[ "$BACKLOG_PR_CHECK_GATE_BEFORE_NEXT_ISSUE" == "1" ]] || return 0
  [[ "$count" -gt 0 ]] || return 0

  log "checking PR #$pr_number checks before selecting another issue"
  if wait_for_pr_checks "$pr_number"; then
    return 0
  else
    status="$?"
  fi
  if [[ "$status" -eq 2 ]]; then
    log "PR #$pr_number checks are still pending; no new issue selected this cycle"
    return 2
  fi
  log "PR #$pr_number checks failed; stopping before selecting another issue"
  return "$status"
}

merge_and_clean() {
  local pr_number="$1"
  local branch="$2"

  run_batch_validation || return $?
  backlog_ensure_local_branch_pushed "$pr_number" "$branch" "pre_batch_merge" || return $?
  wait_for_pr_checks "$pr_number" || {
    local status="$?"
    [[ "$status" -eq 2 ]] && return 2
    return "$status"
  }
  log "merging PR #$pr_number: plane=github waiting_for=merge branch=$branch"
  CODEX_ALLOW_PR_MERGE="$pr_number" gh pr merge "$pr_number" --merge --delete-branch
  log "syncing local main after PR #$pr_number: plane=git waiting_for=checkout_pull_prune"
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
  local pr_info pr_number branch issue_info issue_number issue_title target_hint count run_status
  local job_target job_reason job_expected commit_result final_disposition status partial_commit_message
  local obligation_json obligation_status obligation_id obligation_issue_number obligation_issue_title
  local obligation_summary obligation_target obligation_selected
  local attempt_json
  local issue_deferred_after_noop
  local quota_status
  commit_result="uninitialized backlog outcome"
  obligation_selected=0

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
    log "opening new backlog PR plane=github waiting_for=create_pull_request"
    pr_info="$(open_backlog_pr)"
  fi

  pr_number="$(awk -F '\t' '{print $1}' <<<"$pr_info")"
  branch="$(awk -F '\t' '{print $2}' <<<"$pr_info")"
  checkout_backlog_branch "$branch"
  backlog_ensure_local_branch_pushed "$pr_number" "$branch" "post_branch_sync" || exit $?

  if ! run_backlog_anomaly_custody_audit; then
    status="$?"
    exit "$status"
  fi
  if ! backlog_reconcile_open_obligations; then
    status="$?"
    log "automation obligation reconciliation failed with status $status; stopping before normal issue selection"
    exit "$status"
  fi
  if ! backlog_sync_obligation_issue_reports; then
    status="$?"
    log "automation obligation issue report sync failed with status $status; stopping before normal issue selection"
    exit "$status"
  fi

  obligation_json="$(backlog_select_open_obligation_json)"
  obligation_status="$(jq -r '.status // "clean"' <<<"$obligation_json")"
  if [[ "$obligation_status" == "foreign_root_deferred" ]]; then
    log "automation obligations from other roots are deferred for their owning checkout: count=$(jq -r '.deferred_foreign_root_count // 0' <<<"$obligation_json")"
  fi
  if [[ "$obligation_status" == "operator_action_required" ]]; then
    obligation_id="$(jq -r '.id // "unknown"' <<<"$obligation_json")"
    obligation_summary="$(jq -r '.summary // "machine-local automation obligation"' <<<"$obligation_json")"
    log "automation obligation $obligation_id requires operator action before normal issue work: $obligation_summary"
    exit 0
  fi
  if [[ "$obligation_status" == "cooldown_deferred" ]]; then
    log "automation obligations are cooling down after repeated blocked repair attempts: count=$(jq -r '.cooldown_deferred_count // 0' <<<"$obligation_json") next_retry_epoch=$(jq -r '.next_retry_epoch // 0' <<<"$obligation_json")"
    exit 0
  fi

  if [[ "$obligation_status" == "ok" ]]; then
    obligation_selected=1
    obligation_id="$(jq -r '.id // "unknown"' <<<"$obligation_json")"
    obligation_summary="$(jq -r '.summary // "automation obligation"' <<<"$obligation_json")"
    obligation_target="$(jq -r '.repair_target_file // .target_file // "Upkeeper"' <<<"$obligation_json")"
    obligation_issue_number="$(jq -r '.issue_number // ""' <<<"$obligation_json")"
    obligation_issue_title="$(jq -r '.issue_title // ""' <<<"$obligation_json")"
    issue_number="$obligation_issue_number"
    issue_title="$obligation_issue_title"
    target_hint="$obligation_target"
  else
    count="$(fix_count "$pr_number")"
    if [[ "$count" -ge "$BACKLOG_BATCH_LIMIT" ]]; then
      log "PR #$pr_number has $count recorded fixes; merging batch"
      backlog_emit_job_start_summary \
        "PR #$pr_number batch merge" \
        "batch limit reached with $count recorded fixes on $branch" \
        "run local batch validation, wait for PR checks, merge, and clean local main"
      if merge_and_clean "$pr_number" "$branch"; then
        backlog_emit_job_finish_summary \
          "batch validation, PR checks, and merge completed" \
          "merged PR #$pr_number and returned to clean main"
      else
        status="$?"
        backlog_emit_job_finish_summary \
          "batch merge path stopped with status $status" \
          "launcher exiting with status $status"
        [[ "$status" -eq 2 ]] && exit 0
        exit "$status"
      fi
      exit 0
    fi

    if backlog_ensure_pr_checks_allow_next_issue "$pr_number" "$count"; then
      :
    else
      status="$?"
      [[ "$status" -eq 2 ]] && exit 0
      exit "$status"
    fi

    issue_info="$(selected_issue "$pr_number")"
    issue_number="$(awk -F '\t' '{print $1}' <<<"$issue_info")"
    issue_title="$(awk -F '\t' '{print $2}' <<<"$issue_info")"
    target_hint="$(target_hint_for_issue "$issue_number")"
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

  issue_deferred_after_noop=0
  if [[ "$obligation_selected" == "1" ]]; then
    job_target="$target_hint"
    job_reason="automation obligation $obligation_id: $obligation_summary"
    job_expected="repair or classify prior-run anomaly custody before normal issue work"
  elif [[ -n "$issue_number" ]]; then
    job_target="${target_hint:-wrapper-inferred target for issue #$issue_number}"
    job_reason="issue #$issue_number${issue_title:+: $issue_title}"
    job_expected="fix issue #$issue_number, validate locally, commit and push tracked changes"
  else
    job_target="wrapper-selected newest eligible file"
    job_reason="no eligible backlog issue found"
    job_expected="run a normal newest-file Upkeeper pass and commit tracked changes if produced"
  fi
  backlog_emit_job_start_summary "$job_target" "$job_reason" "$job_expected"

  if [[ "$obligation_selected" == "1" ]]; then
    if run_upkeeper_for_obligation "$obligation_json"; then
      run_status=0
    else
      run_status="$?"
    fi
  elif run_upkeeper_for_one_target "$issue_number" "$target_hint"; then
    run_status=0
  else
    run_status="$?"
  fi

  if [[ "$run_status" -eq 2 ]]; then
    commit_result="blocked with no partial tracked changes"
    if has_worktree_changes; then
      partial_commit_message="$(backlog_partial_commit_message "$obligation_selected" "$obligation_id" "$issue_number")"
      if commit_and_push_changes "" "$partial_commit_message" "$target_hint"; then
        if [[ "$obligation_selected" == "1" ]]; then
          log "preserved partial work for automation obligation $obligation_id"
        else
          log "preserved partial work for blocked issue #$issue_number"
        fi
        commit_result="blocked; partial work committed and pushed"
      else
        commit_result="blocked; partial work present but no commit was produced"
      fi
    fi
    if [[ "$obligation_selected" == "1" ]]; then
      attempt_json="$(backlog_record_obligation_attempt "$obligation_json" "blocked" "$run_status" "$commit_result" || true)"
      if [[ -n "${attempt_json:-}" && "$(jq -r '.cooldown_applied // false' <<<"$attempt_json" 2>/dev/null || printf false)" == "true" ]]; then
        log "automation obligation $obligation_id reached repeated-blocked retry limit; next retry epoch=$(jq -r '.next_retry_epoch // 0' <<<"$attempt_json")"
      fi
      log "automation obligation $obligation_id blocked and remains open"
      backlog_emit_job_finish_summary "$commit_result" "automation obligation $obligation_id remains open"
    else
      defer_issue "$issue_number"
      log "deferred blocked issue #$issue_number for this backlog branch"
      backlog_emit_job_finish_summary "$commit_result" "deferred issue #$issue_number for this backlog branch"
    fi
    exit 0
  elif [[ "$run_status" -eq 7 ]]; then
    backlog_emit_job_finish_summary "Upkeeper deferred on quota or backend usage limit" "quota cooldown marker recorded; outer loop may sleep before the next preflight"
    exit 0
  elif [[ "$run_status" -ne 0 ]]; then
    if [[ "$obligation_selected" == "1" ]]; then
      backlog_record_obligation_attempt "$obligation_json" "failed" "$run_status" "Upkeeper exited with status $run_status" >/dev/null || true
    fi
    backlog_emit_job_finish_summary "Upkeeper exited with status $run_status" "launcher exiting with status $run_status"
    exit "$run_status"
  fi

  commit_result="no tracked changes produced"
  if commit_and_push_changes "$issue_number" "" "$target_hint"; then
    commit_result="tracked changes committed and pushed"
    if [[ -n "$issue_number" ]]; then
      append_pr_fix_line "$pr_number" "$issue_number"
    fi
  else
    log "Upkeeper produced no tracked changes"
    commit_result="no tracked changes produced"
    if [[ "$obligation_selected" == "1" ]]; then
      log "automation obligation $obligation_id produced no tracked changes; obligation resolution state was left to Upkeeper"
    elif [[ -n "$issue_number" ]]; then
      defer_issue "$issue_number"
      log "deferred no-change issue #$issue_number for this backlog branch"
      commit_result="no tracked changes produced; deferred issue #$issue_number for this backlog branch"
      issue_deferred_after_noop=1
    fi
  fi

  count="$(fix_count "$pr_number")"
  if [[ "$count" -ge "$BACKLOG_BATCH_LIMIT" ]]; then
    log "PR #$pr_number reached $count fixes; merging batch"
    if merge_and_clean "$pr_number" "$branch"; then
      backlog_emit_job_finish_summary \
        "$commit_result; batch validation, PR checks, and merge completed" \
        "merged PR #$pr_number and returned to clean main"
    else
      status="$?"
      backlog_emit_job_finish_summary \
        "$commit_result; merge path stopped with status $status" \
        "launcher exiting with status $status"
      [[ "$status" -eq 2 ]] && exit 0
      exit "$status"
    fi
  else
    log "PR #$pr_number now has $count/$BACKLOG_BATCH_LIMIT recorded fixes"
    if [[ "$issue_deferred_after_noop" == "1" ]]; then
      final_disposition="deferred issue #$issue_number after no tracked changes; PR #$pr_number has $count/$BACKLOG_BATCH_LIMIT recorded fixes; outer loop may sleep before next invocation"
    else
      final_disposition="PR #$pr_number has $count/$BACKLOG_BATCH_LIMIT recorded fixes; outer loop may sleep before next invocation"
    fi
    backlog_emit_job_finish_summary "$commit_result" "$final_disposition"
  fi
}

if [[ "${BACKLOG_SOURCE_ONLY:-0}" != "1" ]]; then
  main "$@"
fi
