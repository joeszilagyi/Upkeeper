timestamp_now() {
  date '+%Y-%m-%dT%H:%M:%S%z'
}

epoch_now_fraction() {
  local now
  now="$(date '+%s.%N' 2>/dev/null || true)"
  if [[ "$now" =~ ^[0-9]+\.[0-9]+$ ]]; then
    printf '%.5f\n' "$now"
  else
    date '+%s'
  fi
}

system_boot_id() {
  if [[ -r /proc/sys/kernel/random/boot_id ]]; then
    tr -d '[:space:]' </proc/sys/kernel/random/boot_id
  else
    printf 'unknown'
  fi
}

system_uptime_seconds() {
  if [[ -r /proc/uptime ]]; then
    awk '{ printf "%.2f", $1 }' /proc/uptime
  else
    printf 'unknown'
  fi
}

process_start_fingerprint() {
  local pid="$1"
  local stat_text after_comm
  if [[ -r "/proc/$pid/stat" ]]; then
    IFS= read -r stat_text <"/proc/$pid/stat" || true
    after_comm="${stat_text##*) }"
    set -- $after_comm
    if [[ $# -ge 20 && -n "${20:-}" ]]; then
      printf 'proc_start_ticks=%s' "${20}"
      return 0
    fi
  fi
  printf 'proc_start_ticks=unknown'
}

terminal_mode() {
  local raw="${CODEX_TERMINAL_VERBOSITY:-basic}"
  raw="${raw,,}"
  case "$raw" in
    ''|basic|summary|normal|default)
      printf 'basic'
      ;;
    verbose|1|yes|true)
      printf 'verbose'
      ;;
    debug|debug1)
      printf 'debug1'
      ;;
    quiet)
      printf 'quiet'
      ;;
    silent|none|0|no|false)
      printf 'silent'
      ;;
    full|raw)
      printf 'full'
      ;;
    *)
      printf '%s' "$raw"
      ;;
  esac
}

terminal_wants_full_output() {
  case "$(terminal_mode)" in
    full)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

terminal_wants_quiet_output() {
  case "$(terminal_mode)" in
    quiet)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

terminal_wants_silent_output() {
  case "$(terminal_mode)" in
    silent)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

terminal_wants_verbose_output() {
  case "$(terminal_mode)" in
    verbose|debug1)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

terminal_suppresses_progress() {
  case "$(terminal_mode)" in
    silent)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

terminal_suppresses_heartbeat() {
  case "$(terminal_mode)" in
    quiet|silent|full)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

terminal_emit_progress() {
  local message="$*"
  local mode

  terminal_wants_full_output && return 0
  terminal_suppresses_progress && return 0
  mode="$(terminal_mode)"
  if [[ "$mode" == "quiet" ]]; then
    case "$message" in
      selected\ file*|starting\ Codex*|Codex\ review\ finished*|review\ completed*)
        ;;
      *)
        return 0
        ;;
    esac
  fi
  printf '%s [INFO] Upkeeper: %s\n' "$(timestamp_now)" "$message" >&2
}

terminal_emit_log_line() {
  local level="$1"
  local line="$2"

  if terminal_wants_full_output; then
    printf '%s\n' "$line"
    return 0
  fi
  terminal_wants_silent_output && return 0
  if terminal_wants_quiet_output; then
    case "$level" in
      WARN|ERROR)
        printf '%s\n' "$line" >&2
        ;;
    esac
    return 0
  fi
  case "$level" in
    WARN|ERROR)
      printf '%s\n' "$line" >&2
      ;;
  esac
}

log_line() {
  local level="$1"
  shift
  local ts line
  ts="$(timestamp_now)"
  line="$(printf '%s [%s] cycle=%s run_hash=%s %s' "$ts" "$level" "$CYCLE_ID" "$CYCLE_RUN_HASH" "$*")"
  printf '%s\n' "$line" >>"$LOG_FILE"
  terminal_emit_log_line "$level" "$line"
}

ensure_log_parent() {
  if [[ -n "$LOG_FILE_DIR" && "$LOG_FILE_DIR" != "." ]]; then
    if ! mkdir -p -- "$LOG_FILE_DIR"; then
      printf '%s [ERROR] cycle=%s log.parent_failed path=%s\n' "$(timestamp_now)" "$CYCLE_ID" "$LOG_FILE_DIR" >&2
      exit 3
    fi
  fi
}

ensure_run_tmp_dir() {
  if [[ -n "$RUN_TMP_DIR" ]]; then
    return 0
  fi

  local tmp_base="${TMPDIR:-/tmp}"
  RUN_TMP_DIR="$tmp_base/upkeeper-$CYCLE_RUN_HASH"
  if ! mkdir -p -- "$RUN_TMP_DIR"; then
    die "failed to create run temp directory $RUN_TMP_DIR"
  fi
  chmod 700 "$RUN_TMP_DIR" 2>/dev/null || true
  log_line "INFO" "run.tmp_dir path=$(shell_quote "$RUN_TMP_DIR")" >/dev/null
}

run_mktemp() {
  local label="${1:-tmp}"
  ensure_run_tmp_dir
  mktemp "$RUN_TMP_DIR/${label}.XXXXXX"
}
