# Local log hygiene.
#
# Rotation is based on the oldest entry inside the log, not file mtime. The log
# is continuously appended during operator work, so mtime would never age out in
# the scenario where rotation is most useful.
sanitize_nonnegative_integer() {
  local raw_value="$1"
  local fallback="$2"

  case "$raw_value" in
    ''|*[!0-9]*)
      printf '%s' "$fallback"
      ;;
    *)
      printf '%s' "$raw_value"
      ;;
  esac
}

sanitize_positive_integer() {
  local raw_value="$1"
  local fallback="$2"
  local min_value="$3"

  awk -v raw="$raw_value" -v fallback="$fallback" -v min_value="$min_value" '
    function is_uint(value) {
      return value ~ /^[0-9]+$/
    }
    BEGIN {
      minimum = is_uint(min_value) ? min_value + 0 : 1
      fallback_value = is_uint(fallback) ? fallback + 0 : minimum
      if (fallback_value < minimum) {
        fallback_value = minimum
      }
      if (!is_uint(raw)) {
        print fallback_value
      } else if (raw + 0 < minimum) {
        print minimum
      } else {
        print raw + 0
      }
    }
  ' 2>/dev/null || printf '%s' "$fallback"
}

sanitize_percent_threshold() {
  local raw_value="$1"
  local fallback="$2"

  awk -v raw="$raw_value" -v fallback="$fallback" '
    function is_number(value) {
      return value ~ /^[-+]?([0-9]+([.][0-9]*)?|[.][0-9]+)$/
    }
    function emit(value, out) {
      if (value < 0) {
        value = 0
      } else if (value > 100) {
        value = 100
      }
      if (value == int(value)) {
        printf "%d", value
      } else {
        out = sprintf("%.10f", value)
        sub(/0+$/, "", out)
        sub(/[.]$/, "", out)
        printf "%s", out
      }
    }
    BEGIN {
      if (is_number(raw)) {
        emit(raw + 0)
      } else if (is_number(fallback)) {
        emit(fallback + 0)
      } else {
        emit(0)
      }
    }
  ' 2>/dev/null || printf '%s' "$fallback"
}

sum_percent_thresholds() {
  local first="$1"
  local second="$2"

  awk -v first="$first" -v second="$second" '
    function is_number(value) {
      return value ~ /^[-+]?([0-9]+([.][0-9]*)?|[.][0-9]+)$/
    }
    function emit(value, out) {
      if (value < 0) {
        value = 0
      } else if (value > 100) {
        value = 100
      }
      if (value == int(value)) {
        printf "%d", value
      } else {
        out = sprintf("%.10f", value)
        sub(/0+$/, "", out)
        sub(/[.]$/, "", out)
        printf "%s", out
      }
    }
    BEGIN {
      if (!is_number(first) || !is_number(second)) {
        printf "%s", first
      } else {
        emit(first + second)
      }
    }
  ' 2>/dev/null || printf '%s' "$first"
}

normalize_guardrail_thresholds() {
  CODEX_5H_STOP_PERCENT="$(sanitize_percent_threshold "${CODEX_5H_STOP_PERCENT}" 5)"
  CODEX_SPARK_5H_STOP_PERCENT="$(sanitize_percent_threshold "${CODEX_SPARK_5H_STOP_PERCENT}" 0)"
  CODEX_WEEK_STOP_PERCENT="$(sanitize_percent_threshold "${CODEX_WEEK_STOP_PERCENT}" 15)"
  CODEX_WEEK_STOP_BUFFER_PERCENT="$(sanitize_percent_threshold "${CODEX_WEEK_STOP_BUFFER_PERCENT}" 0)"
  CODEX_SPARK_WEEK_STOP_BUFFER_PERCENT="$(sanitize_percent_threshold "${CODEX_SPARK_WEEK_STOP_BUFFER_PERCENT}" 5)"
  CODEX_FALLBACK_SCREEN_POLL_SECONDS="$(sanitize_nonnegative_integer "${CODEX_FALLBACK_SCREEN_POLL_SECONDS}" 60)"
  CODEX_UPKEEPER_SELF_REVIEW_AFTER_DAYS="$(sanitize_nonnegative_integer "${CODEX_UPKEEPER_SELF_REVIEW_AFTER_DAYS}" 7)"
  CODEX_MARK_INTERVAL_SECONDS="$(sanitize_nonnegative_integer "${CODEX_MARK_INTERVAL_SECONDS}" 60)"
  CODEX_PREVIOUS_RUN_SCAN_MINUTES="$(sanitize_nonnegative_integer "${CODEX_PREVIOUS_RUN_SCAN_MINUTES}" 240)"
  CODEX_DISK_MIN_FREE_PERCENT="$(sanitize_percent_threshold "${CODEX_DISK_MIN_FREE_PERCENT}" 10)"
  CODEX_STARTUP_ANOMALY_FORCE_UPKEEPER="$(sanitize_nonnegative_integer "${CODEX_STARTUP_ANOMALY_FORCE_UPKEEPER}" 1)"
  CODEX_SESSION_SCAN_LIMIT="$(sanitize_positive_integer "${CODEX_SESSION_SCAN_LIMIT}" 200 1)"
  CODEX_LOOP_STOP_GRACE_SECONDS="$(sanitize_nonnegative_integer "${CODEX_LOOP_STOP_GRACE_SECONDS}" 5)"
  if [[ "$CODEX_FALLBACK_SCREEN_POLL_SECONDS" -lt 1 ]]; then
    CODEX_FALLBACK_SCREEN_POLL_SECONDS=1
  fi
}

is_spark_model() {
  local target_model="$1"
  case "$target_model" in
    *spark* | *Spark* | *SPARK*)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

quota_5h_stop_percent_for_model() {
  local target_model="$1"
  if is_spark_model "$target_model"; then
    printf '%s' "$CODEX_SPARK_5H_STOP_PERCENT"
  else
    printf '%s' "$CODEX_5H_STOP_PERCENT"
  fi
}

quota_week_stop_buffer_percent_for_model() {
  local target_model="$1"
  if is_spark_model "$target_model"; then
    printf '%s' "$CODEX_SPARK_WEEK_STOP_BUFFER_PERCENT"
  else
    printf '%s' "$CODEX_WEEK_STOP_BUFFER_PERCENT"
  fi
}

quota_week_stop_percent_for_model() {
  local target_model="$1"
  local buffer
  buffer="$(quota_week_stop_buffer_percent_for_model "$target_model")"
  sum_percent_thresholds "$CODEX_WEEK_STOP_PERCENT" "$buffer"
}

quota_expected_identity_for_model() {
  printf 'exact_model_snapshot'
}

quota_identity_status_for_model() {
  local target_model="$1"
  local limit_id="${2:-unknown}"
  local limit_name="${3:-unknown}"

  [[ -n "$limit_id" && "$limit_id" != "null" ]] || limit_id="unknown"
  [[ -n "$limit_name" && "$limit_name" != "null" ]] || limit_name="unknown"

  if is_spark_model "$target_model"; then
    if [[ "$limit_id" == codex_* || "$limit_name" == *spark* || "$limit_name" == *Spark* || "$limit_name" == *SPARK* ]]; then
      printf 'model_specific'
    elif [[ "$limit_id" == "unknown" && "$limit_name" == "unknown" ]]; then
      printf 'unknown'
    elif [[ "$limit_id" == "codex" && "$limit_name" == "unknown" ]]; then
      printf 'generic_unknown'
    else
      printf 'generic_named'
    fi
  elif [[ "$limit_id" == "unknown" && "$limit_name" == "unknown" ]]; then
    printf 'unknown'
  elif [[ "$limit_name" == "unknown" ]]; then
    printf 'generic_unknown'
  else
    printf 'accepted'
  fi
}

quota_identity_allows_pre_run() {
  local target_model="$1"
  local limit_id="${2:-unknown}"
  local limit_name="${3:-unknown}"
  [[ "$(quota_identity_status_for_model "$target_model" "$limit_id" "$limit_name")" != "conflicting_generic" ]]
}

quota_reset_epoch_delta_seconds() {
  local before="$1"
  local after="$2"
  [[ "$before" =~ ^[0-9]+$ && "$after" =~ ^[0-9]+$ ]] || {
    printf 'unknown'
    return 1
  }

  local delta=$(( after - before ))
  if (( delta < 0 )); then
    delta=$(( -delta ))
  fi
  printf '%s' "$delta"
}

quota_reset_same_window() {
  local before="$1"
  local after="$2"
  local tolerance_seconds="${3:-2}"
  local delta

  delta="$(quota_reset_epoch_delta_seconds "$before" "$after")" || return 1
  (( delta <= tolerance_seconds ))
}

quota_bucket_decision() {
  local bucket_current="${1:-false}"
  local projected_left="${2:-}"
  local threshold="${3:-}"

  if [[ "$bucket_current" != "true" || -z "$projected_left" || -z "$threshold" ]]; then
    printf 'defer'
    return 0
  fi
  if awk -v value="$projected_left" -v threshold="$threshold" 'BEGIN { exit !(value <= threshold) }'; then
    printf 'stop'
  else
    printf 'allow'
  fi
}

quota_transition_fields() {
  local before_primary_used="${1:-unknown}"
  local before_primary_left="${2:-unknown}"
  local before_secondary_used="${3:-unknown}"
  local before_secondary_left="${4:-unknown}"
  local after_primary_used="${5:-unknown}"
  local after_primary_left="${6:-unknown}"
  local after_secondary_used="${7:-unknown}"
  local after_secondary_left="${8:-unknown}"

  [[ -n "$before_primary_used" ]] || before_primary_used="unknown"
  [[ -n "$before_primary_left" ]] || before_primary_left="unknown"
  [[ -n "$before_secondary_used" ]] || before_secondary_used="unknown"
  [[ -n "$before_secondary_left" ]] || before_secondary_left="unknown"
  [[ -n "$after_primary_used" ]] || after_primary_used="unknown"
  [[ -n "$after_primary_left" ]] || after_primary_left="unknown"
  [[ -n "$after_secondary_used" ]] || after_secondary_used="unknown"
  [[ -n "$after_secondary_left" ]] || after_secondary_left="unknown"

  printf 'before_primary_used=%s%% before_primary_left=%s%% before_secondary_used=%s%% before_secondary_left=%s%% after_primary_used=%s%% after_primary_left=%s%% after_secondary_used=%s%% after_secondary_left=%s%%' \
    "$before_primary_used" \
    "$before_primary_left" \
    "$before_secondary_used" \
    "$before_secondary_left" \
    "$after_primary_used" \
    "$after_primary_left" \
    "$after_secondary_used" \
    "$after_secondary_left"
}

quota_identity_changed_flag() {
  local before_id="${1:-unknown}"
  local before_name="${2:-unknown}"
  local after_id="${3:-unknown}"
  local after_name="${4:-unknown}"
  local comparable=0
  local changed=0

  [[ -n "$before_id" ]] || before_id="unknown"
  [[ -n "$before_name" ]] || before_name="unknown"
  [[ -n "$after_id" ]] || after_id="unknown"
  [[ -n "$after_name" ]] || after_name="unknown"

  if [[ "$before_id" != "unknown" && "$after_id" != "unknown" ]]; then
    comparable=1
    [[ "$before_id" == "$after_id" ]] || changed=1
  fi
  if [[ "$before_name" != "unknown" && "$after_name" != "unknown" ]]; then
    comparable=1
    [[ "$before_name" == "$after_name" ]] || changed=1
  fi

  if [[ "$comparable" -eq 0 ]]; then
    printf 'unknown'
  else
    printf '%s' "$changed"
  fi
}

codex_session_store_write_check() {
  local marker_dir="$CODEX_HOME_DIR/sessions"
  local marker_path
  local err_file

  if ! err_file="$(mktemp)"; then
    printf 'mktemp_failed'
    return 1
  fi

  if ! mkdir -p "$marker_dir" 2>"$err_file"; then
    printf 'mkdir_failed:%s' "$(tr '\n' ' ' <"$err_file")"
    rm -f "$err_file"
    return 1
  fi

  marker_path="$marker_dir/.upkeeper-write-test.$$"
  if ! ( : >"$marker_path" ) 2>"$err_file"; then
    printf 'write_failed:%s' "$(tr '\n' ' ' <"$err_file")"
    rm -f "$err_file"
    return 1
  fi

  if ! rm -f "$marker_path" 2>"$err_file"; then
    printf 'cleanup_failed:%s' "$(tr '\n' ' ' <"$err_file")"
    rm -f "$err_file"
    return 1
  fi

  rm -f "$err_file"
  printf 'ok'
  return 0
}

ensure_codex_session_store_writable_or_exit() {
  local phase="$1"
  local codex_exec_started="$2"
  local detail detail_q code_home_q session_store_q

  detail="$(codex_session_store_write_check | compact_process_args || true)"
  if [[ "$detail" == "ok" ]]; then
    return 0
  fi

  detail_q="$(shell_quote "$detail")"
  code_home_q="$(shell_quote "$CODEX_HOME_DIR")"
  session_store_q="$(shell_quote "$CODEX_HOME_DIR/sessions")"
  log_line "ERROR" "codex.session_store_unwritable phase=$phase code_home=$code_home_q session_store=$session_store_q detail=$detail_q"
  finish_cycle 3 CODEX_SESSION_STORE_UNWRITABLE ERROR "phase=$phase codex_exec_started=$codex_exec_started code_home=$code_home_q session_store=$session_store_q detail=$detail_q"
}

codex_bwrap_tmp_write_check() {
  local registry_root="$CODEX_BWRAP_TMP_ROOT"
  local lock_path="$registry_root/lock"
  local probe_dir=""
  local probe_file
  local err_file

  if [[ "$CODEX_BWRAP_TMP_PREFLIGHT" != "1" ]]; then
    printf 'ok'
    return 0
  fi

  if ! err_file="$(mktemp)"; then
    printf 'mktemp_failed'
    return 1
  fi

  if [[ -e "$registry_root" && ! -d "$registry_root" ]]; then
    printf 'not_directory:%s' "$registry_root"
    rm -f "$err_file"
    return 1
  fi

  if ! mkdir -p "$registry_root" 2>"$err_file"; then
    printf 'mkdir_failed:%s' "$(tr '\n' ' ' <"$err_file")"
    rm -f "$err_file"
    return 1
  fi

  if ! ( : >>"$lock_path" ) 2>"$err_file"; then
    printf 'lock_write_failed:%s' "$(tr '\n' ' ' <"$err_file")"
    rm -f "$err_file"
    return 1
  fi

  if ! probe_dir="$(mktemp -d "$registry_root/.upkeeper-write-test.XXXXXX" 2>"$err_file")"; then
    printf 'probe_dir_failed:%s' "$(tr '\n' ' ' <"$err_file")"
    rm -f "$err_file"
    return 1
  fi

  probe_file="$probe_dir/probe"
  if ! ( : >"$probe_file" ) 2>"$err_file"; then
    printf 'probe_write_failed:%s' "$(tr '\n' ' ' <"$err_file")"
    rmdir "$probe_dir" >/dev/null 2>&1 || true
    rm -f "$err_file"
    return 1
  fi

  if ! rm -f "$probe_file" 2>"$err_file"; then
    printf 'probe_file_cleanup_failed:%s' "$(tr '\n' ' ' <"$err_file")"
    rmdir "$probe_dir" >/dev/null 2>&1 || true
    rm -f "$err_file"
    return 1
  fi

  if ! rmdir "$probe_dir" 2>"$err_file"; then
    printf 'probe_dir_cleanup_failed:%s' "$(tr '\n' ' ' <"$err_file")"
    rm -f "$err_file"
    return 1
  fi

  rm -f "$err_file"
  printf 'ok'
  return 0
}

ensure_codex_bwrap_tmp_writable_or_exit() {
  local phase="$1"
  local codex_exec_started="$2"
  local detail detail_q registry_root_q

  detail="$(codex_bwrap_tmp_write_check | compact_process_args || true)"
  if [[ "$detail" == "ok" ]]; then
    return 0
  fi

  detail_q="$(shell_quote "$detail")"
  registry_root_q="$(shell_quote "$CODEX_BWRAP_TMP_ROOT")"
  log_line "ERROR" "codex.bwrap_tmp_unwritable phase=$phase registry_root=$registry_root_q detail=$detail_q"
  finish_cycle 3 CODEX_BWRAP_TMP_UNWRITABLE ERROR "phase=$phase codex_exec_started=$codex_exec_started registry_root=$registry_root_q detail=$detail_q"
}

remove_flat_codex_arg0_dir() {
  local dir="$1"
  local err_file="$2"

  # Codex arg0 dirs are flat symlink shims plus a .lock file. Do not recurse:
  # if a future Codex version writes nested state, quarantine the directory
  # instead of deleting unknown content.
  if ! find "$dir" -mindepth 1 -maxdepth 1 -exec rm -f -- {} + 2>"$err_file"; then
    return 1
  fi
  if ! rmdir "$dir" 2>"$err_file"; then
    return 1
  fi
}

codex_arg0_tmp_cleanup_check() {
  local arg0_root="$CODEX_ARG0_TMP_ROOT"
  local quarantine_root="$CODEX_ARG0_TMP_QUARANTINE_ROOT"
  local stale_minutes="$CODEX_ARG0_TMP_STALE_MINUTES"
  local err_file
  local candidate base quarantine detail
  local rotated_root
  local removed=0
  local quarantined=0
  local blocked=()
  local quarantines=()
  local candidates=()

  if [[ "$CODEX_ARG0_TMP_PREFLIGHT" != "1" ]]; then
    printf 'ok'
    return 0
  fi

  case "$stale_minutes" in ''|*[!0-9]*) stale_minutes=60 ;; esac

  if ! err_file="$(mktemp)"; then
    printf 'mktemp_failed'
    return 1
  fi

  if [[ -e "$arg0_root" && ! -d "$arg0_root" ]]; then
    printf 'not_directory:%s' "$arg0_root"
    rm -f "$err_file"
    return 1
  fi

  if ! mkdir -p "$arg0_root" 2>"$err_file"; then
    printf 'mkdir_failed:%s' "$(tr '\n' ' ' <"$err_file")"
    rm -f "$err_file"
    return 1
  fi

  if [[ ! -w "$arg0_root" || ! -x "$arg0_root" ]]; then
    printf 'root_not_writable:%s' "$arg0_root"
    rm -f "$err_file"
    return 1
  fi

  mapfile -d '' candidates < <(find "$arg0_root" -mindepth 1 -maxdepth 1 -type d -mmin "+$stale_minutes" -print0 2>"$err_file")
  if [[ -s "$err_file" ]]; then
    printf 'find_failed:%s' "$(tr '\n' ' ' <"$err_file")"
    rm -f "$err_file"
    return 1
  fi

  for candidate in "${candidates[@]}"; do
    [[ -d "$candidate" && ! -L "$candidate" ]] || continue
    : >"$err_file"
    if remove_flat_codex_arg0_dir "$candidate" "$err_file"; then
      removed=$((removed + 1))
      continue
    fi

    if ! mkdir -p "$quarantine_root" 2>"$err_file"; then
      detail="$(tr '\n' ' ' <"$err_file")"
      blocked+=("$candidate:quarantine_mkdir_failed:${detail:-unknown_error}")
      continue
    fi

    base="$(basename -- "$candidate")"
    quarantine="$quarantine_root/${base}-$(date '+%Y%m%dT%H%M%S%z')-$$"
    : >"$err_file"
    if mv -- "$candidate" "$quarantine" 2>"$err_file"; then
      quarantined=$((quarantined + 1))
      quarantines+=("$candidate->$quarantine")
      continue
    fi

    detail="$(tr '\n' ' ' <"$err_file")"
    blocked+=("$candidate:${detail:-unknown_error}")
  done

  rm -f "$err_file"

  if [[ "${#blocked[@]}" -gt 0 ]]; then
    if [[ "$CODEX_ARG0_TMP_ROTATE_ON_BLOCKED" == "1" ]]; then
      rotated_root="${CODEX_HOME_DIR}/tmp/arg0-rotated-$(date '+%Y%m%dT%H%M%S%z')-$$"
      if mv -- "$arg0_root" "$rotated_root" >/dev/null 2>&1 && mkdir -p "$arg0_root" >/dev/null 2>&1 && chmod 700 "$arg0_root" >/dev/null 2>&1; then
        printf 'ok removed=%s quarantined=%s rotated=1 rotated_root=%s blocked_entries=%s' \
          "$removed" \
          "$quarantined" \
          "$rotated_root" \
          "$(IFS=';'; printf '%s' "${blocked[*]}")"
        return 0
      fi
    fi
    printf 'blocked:%s' "$(IFS=';'; printf '%s' "${blocked[*]}")"
    return 1
  fi

  if [[ "$removed" -gt 0 || "$quarantined" -gt 0 ]]; then
    printf 'ok removed=%s quarantined=%s' "$removed" "$quarantined"
    if [[ "${#quarantines[@]}" -gt 0 ]]; then
      printf ' quarantine_paths=%s' "$(IFS=';'; printf '%s' "${quarantines[*]}")"
    fi
    return 0
  fi

  printf 'ok'
}

ensure_codex_arg0_tmp_clean_or_exit() {
  local phase="$1"
  local codex_exec_started="$2"
  local detail detail_q arg0_root_q

  detail="$(codex_arg0_tmp_cleanup_check | compact_process_args || true)"
  if [[ "$detail" == "ok" ]]; then
    return 0
  fi

  detail_q="$(shell_quote "$detail")"
  arg0_root_q="$(shell_quote "$CODEX_ARG0_TMP_ROOT")"
  if [[ "$detail" == ok\ * ]]; then
    log_line "INFO" "codex.arg0_tmp_cleanup phase=$phase arg0_root=$arg0_root_q detail=$detail_q"
    return 0
  fi

  log_line "ERROR" "codex.arg0_tmp_uncleanable phase=$phase arg0_root=$arg0_root_q detail=$detail_q"
  finish_cycle 3 CODEX_ARG0_TMP_UNCLEANABLE ERROR "phase=$phase codex_exec_started=$codex_exec_started arg0_root=$arg0_root_q detail=$detail_q"
}

compact_process_args() {
  sed 's/[[:space:]]\+/ /g; s/^[[:space:]]*//; s/[[:space:]]*$//'
}

truncate_process_args() {
  local value="$1"
  local max_chars

  max_chars="$(sanitize_nonnegative_integer "$CODEX_PROCESS_ARGS_MAX_CHARS" "600")"
  if [[ "$max_chars" -eq 0 || "${#value}" -le "$max_chars" ]]; then
    printf '%s' "$value"
    return 0
  fi

  printf '%s...<truncated:%s chars>' "${value:0:max_chars}" "${#value}"
}

oldest_wrapper_log_epoch() {
  if [[ ! -s "$LOG_FILE" ]]; then
    return 1
  fi

  python3 - "$LOG_FILE" <<'PY'
from datetime import datetime
from pathlib import Path
import sys

path = Path(sys.argv[1])
try:
    first_line = path.open("r", encoding="utf-8", errors="ignore").readline()
except OSError:
    raise SystemExit(1)

timestamp = first_line.split(" ", 1)[0].strip()
if timestamp:
    try:
        print(int(datetime.strptime(timestamp, "%Y-%m-%dT%H:%M:%S%z").timestamp()))
        raise SystemExit(0)
    except ValueError:
        pass

try:
    print(int(path.stat().st_mtime))
except OSError:
    raise SystemExit(1)
PY
}

prune_wrapper_log_archives() {
  local keep_hours keep_minutes

  keep_hours="$(sanitize_nonnegative_integer "$CODEX_LOG_ROTATE_KEEP_HOURS" "144")"
  keep_minutes=$((keep_hours * 60))

  python3 - "$LOG_FILE_DIR" "$LOG_ARCHIVE_GLOB" "$keep_minutes" <<'PY' || true
from pathlib import Path
import fnmatch
import sys
import time

root = Path(sys.argv[1])
pattern = sys.argv[2]
keep_minutes = int(sys.argv[3])
cutoff = time.time() - (keep_minutes * 60)

try:
    entries = list(root.iterdir())
except OSError:
    raise SystemExit(0)

for path in entries:
    try:
        if path.is_file() and fnmatch.fnmatch(path.name, pattern) and path.stat().st_mtime < cutoff:
            path.unlink()
    except OSError:
        pass
PY
}

rotate_wrapper_log_if_needed() {
  local rotate_after_hours keep_hours rotate_after_seconds now_epoch oldest_epoch
  local archive_path archive_timestamp

  prune_wrapper_log_archives

  if [[ ! -s "$LOG_FILE" ]]; then
    return 0
  fi

  rotate_after_hours="$(sanitize_nonnegative_integer "$CODEX_LOG_ROTATE_AFTER_HOURS" "72")"
  keep_hours="$(sanitize_nonnegative_integer "$CODEX_LOG_ROTATE_KEEP_HOURS" "144")"

  if [[ "$rotate_after_hours" -eq 0 ]]; then
    return 0
  fi

  oldest_epoch="$(oldest_wrapper_log_epoch || true)"
  if [[ -z "$oldest_epoch" || ! "$oldest_epoch" =~ ^[0-9]+$ ]]; then
    return 0
  fi

  rotate_after_seconds=$((rotate_after_hours * 3600))
  now_epoch="$(date '+%s')"
  if (( now_epoch - oldest_epoch < rotate_after_seconds )); then
    return 0
  fi

  archive_timestamp="$(date '+%Y%m%dT%H%M%S%z')"
  archive_path="$LOG_FILE.$archive_timestamp.zip"
  if zip -qjm "$archive_path" "$LOG_FILE" >/dev/null 2>&1; then
    : >"$LOG_FILE"
    printf '%s [INFO] cycle=%s run_hash=%s log.rotate live=%s archive=%s rotate_after_hours=%s keep_hours=%s oldest_entry_epoch=%s\n' \
      "$(timestamp_now)" "$CYCLE_ID" "$CYCLE_RUN_HASH" "$LOG_FILE" "$archive_path" "$rotate_after_hours" "$keep_hours" "$oldest_epoch" | tee -a "$LOG_FILE"
  else
    rm -f "$archive_path"
    printf '%s [WARN] cycle=%s run_hash=%s log.rotate_failed live=%s attempted_archive=%s reason=zip_failed\n' \
      "$(timestamp_now)" "$CYCLE_ID" "$CYCLE_RUN_HASH" "$LOG_FILE" "$archive_path" | tee -a "$LOG_FILE"
  fi

  prune_wrapper_log_archives
}

disk_preflight_path_specs() {
  printf 'root\t%s\n' "$ROOT_DIR"
  printf 'log_dir\t%s\n' "$LOG_FILE_DIR"
  printf 'codex_home\t%s\n' "$CODEX_HOME_DIR"
  printf 'codex_sessions\t%s\n' "$CODEX_HOME_DIR/sessions"
  printf 'tmp\t%s\n' "${TMPDIR:-/tmp}"
  printf 'bwrap_tmp\t%s\n' "$CODEX_BWRAP_TMP_ROOT"
  printf 'arg0_tmp\t%s\n' "$CODEX_ARG0_TMP_ROOT"
  printf 'runtime\t%s\n' "$ROOT_DIR/runtime"
}

existing_df_probe_path() {
  local path="$1"

  case "$path" in
    "~")
      path="$HOME"
      ;;
    "~/"*)
      path="$HOME/${path#~/}"
      ;;
  esac

  if [[ "$path" != /* ]]; then
    path="$PWD/$path"
  fi
  path="${path%/}"
  [[ -n "$path" ]] || path="/"

  while [[ ! -e "$path" && "$path" != "/" ]]; do
    path="${path%/*}"
    [[ -n "$path" ]] || path="/"
  done

  if [[ -e "$path" ]]; then
    printf '%s' "$path"
  fi
}

disk_space_fields() {
  local label="$1"
  local path="$2"
  local probe_path

  probe_path="$(existing_df_probe_path "$path")"
  [[ -n "$probe_path" ]] || return 1
  df -Pk "$probe_path" 2>/dev/null | awk -v label="$label" -v path="$path" -v probe="$probe_path" 'NR == 2 {
    used = $5
    gsub("%", "", used)
    free = 100 - used
    printf "label=%s size_kb=%s used_kb=%s avail_kb=%s used_percent=%s free_percent=%s mount=%s path=%s probe_path=%s", label, $2, $3, $4, used, free, $6, path, probe
  }'
}

check_disk_space_preflight() {
  local label path fields free_percent threshold decision
  local unavailable_count=0 warn_count=0 checked_count=0
  local notes=""

  threshold="$CODEX_DISK_MIN_FREE_PERCENT"
  while IFS=$'\t' read -r label path; do
    [[ -n "$label" && -n "$path" ]] || continue
    checked_count=$((checked_count + 1))
    fields="$(disk_space_fields "$label" "$path" || true)"
    if [[ -z "$fields" ]]; then
      unavailable_count=$((unavailable_count + 1))
      log_line "WARN" "disk.preflight status=unavailable label=$label path=$(shell_quote "$path")"
      notes+="- disk.preflight unavailable label=$label path=$path"$'\n'
      continue
    fi

    free_percent="$(sed -n 's/.*free_percent=\([0-9.]*\).*/\1/p' <<<"$fields")"
    decision="$(awk -v free="$free_percent" -v threshold="$threshold" 'BEGIN { if (free < threshold) print "warn"; else print "allow" }')"
    if [[ "$decision" == "warn" ]]; then
      warn_count=$((warn_count + 1))
      log_line "WARN" "disk.preflight status=$decision min_free_percent=$threshold $fields"
      notes+="- disk.preflight low_space min_free_percent=$threshold $fields"$'\n'
    else
      log_line "INFO" "disk.preflight status=$decision min_free_percent=$threshold $fields"
    fi
  done < <(disk_preflight_path_specs)

  if [[ "$unavailable_count" -gt 0 ]]; then
    append_startup_anomaly_reason "disk_preflight_unavailable"
  fi
  if [[ "$warn_count" -gt 0 ]]; then
    append_startup_anomaly_reason "disk_preflight_low_space"
  fi
  if [[ "$unavailable_count" -gt 0 || "$warn_count" -gt 0 ]]; then
    STARTUP_ANOMALY_GATE="1"
    DISK_SPACE_PROMPT_NOTE="${notes%$'\n'}"
  else
    DISK_SPACE_PROMPT_NOTE=""
  fi
  log_line "INFO" "disk.preflight.summary checked=$checked_count unavailable=$unavailable_count low_space=$warn_count min_free_percent=$threshold"
}

previous_run_anomaly_lines() {
  if [[ ! -s "$LOG_FILE" ]]; then
    return 0
  fi

  python3 - "$LOG_FILE" "$CYCLE_ID" "$CODEX_PREVIOUS_RUN_SCAN_MINUTES" "$(system_boot_id)" <<'PY'
import datetime as dt
import re
import sys
import time

log_path, current_cycle, minutes_raw, current_boot_id = sys.argv[1:5]
try:
    scan_minutes = max(0, int(minutes_raw))
except ValueError:
    scan_minutes = 240
cutoff = time.time() - (scan_minutes * 60)
cycle_re = re.compile(r"\bcycle=([^ ]+)")
run_hash_re = re.compile(r"\brun_hash=([^ ]+)")
boot_id_re = re.compile(r"\bboot_id=([^ ]+)")
cycles = {}
latest_previous_run_ack_epoch = None

def parsed_epoch(line):
    stamp = line.split(" ", 1)[0]
    try:
        return dt.datetime.strptime(stamp, "%Y-%m-%dT%H:%M:%S%z").timestamp()
    except ValueError:
        return None

try:
    handle = open(log_path, "r", encoding="utf-8", errors="replace")
except OSError:
    raise SystemExit(0)

with handle:
    for line in handle:
        epoch = parsed_epoch(line)
        if epoch is not None and scan_minutes > 0 and epoch < cutoff:
            continue
        if (
            epoch is not None
            and " startup_anomaly.gate_resolved " in line
            and "reasons=previous_run_anomaly" in line
        ):
            if latest_previous_run_ack_epoch is None or epoch > latest_previous_run_ack_epoch:
                latest_previous_run_ack_epoch = epoch
        cycle_match = cycle_re.search(line)
        if not cycle_match:
            continue
        cycle = cycle_match.group(1)
        if cycle == current_cycle:
            continue
        info = cycles.setdefault(
            cycle,
            {
                "run_hash": "unknown",
                "start": False,
                "exit": False,
                "run_start": False,
                "run_finish": False,
                "gate_unresolved": False,
                "gate_resolved": False,
                "watchdog_anomaly": False,
                "last_boot_id": "unknown",
                "last_epoch": epoch,
                "last_line": line.strip(),
            },
        )
        hash_match = run_hash_re.search(line)
        if hash_match:
            info["run_hash"] = hash_match.group(1)
        boot_id_match = boot_id_re.search(line)
        if boot_id_match:
            info["last_boot_id"] = boot_id_match.group(1)
        if " cycle.start " in line:
            info["start"] = True
        if " cycle.exit " in line:
            info["exit"] = True
        if " run.start " in line:
            info["run_start"] = True
        if " run.finish " in line:
            info["run_finish"] = True
        if " startup_anomaly.gate_unresolved " in line:
            info["gate_unresolved"] = True
        if " startup_anomaly.gate_resolved " in line:
            info["gate_resolved"] = True
        if " watchdog.anomaly " in line:
            info["watchdog_anomaly"] = True
        info["last_epoch"] = epoch
        info["last_line"] = line.strip()

printed = 0
acknowledged = 0
for cycle, info in sorted(cycles.items(), key=lambda item: item[1]["last_epoch"] or 0, reverse=True):
    reason = ""
    if info["start"] and not info["exit"]:
        if (
            info.get("last_boot_id", "unknown") not in {"", "unknown"}
            and current_boot_id not in {"", "unknown"}
            and info["last_boot_id"] != current_boot_id
        ):
            reason = "probable_reboot_or_power_loss"
        else:
            reason = "missing_cycle_exit"
    elif info["run_start"] and not info["run_finish"] and not info["exit"]:
        reason = "missing_run_finish"
    elif info["watchdog_anomaly"]:
        reason = "watchdog_anomaly"
    elif info["gate_unresolved"] and not info["gate_resolved"]:
        reason = "startup_anomaly_gate_unresolved"
    if not reason:
        continue
    if (
        latest_previous_run_ack_epoch is not None
        and info["last_epoch"] is not None
        and info["last_epoch"] <= latest_previous_run_ack_epoch
    ):
        acknowledged += 1
        continue
    last_epoch = "unknown" if info["last_epoch"] is None else str(int(info["last_epoch"]))
    last_line = info["last_line"].replace("\\", "\\\\").replace("\t", " ")[:300]
    print(
        f"previous_cycle={cycle} previous_run_hash={info['run_hash']} "
        f"reason={reason} scan_minutes={scan_minutes} last_epoch={last_epoch} "
        f"previous_boot_id={info.get('last_boot_id', 'unknown')} current_boot_id={current_boot_id} "
        f"last_line={last_line!r}"
    )
    printed += 1
    if printed >= 10:
        break
if acknowledged:
    print(
        "__ACK__ "
        f"suppressed={acknowledged} "
        f"ack_epoch={int(latest_previous_run_ack_epoch)} "
        "reason=previous_run_anomaly_gate_reviewed"
    )
PY
}

scan_previous_run_anomalies() {
  local -a anomalies=()
  local -a state_anomalies=()
  local anomaly
  PREVIOUS_RUN_ANOMALIES=""
  mapfile -t anomalies < <(previous_run_anomaly_lines || true)
  mapfile -t state_anomalies < <(startup_anomaly_state_lines || true)
  anomalies+=("${state_anomalies[@]}")
  local -a active_anomalies=()
  for anomaly in "${anomalies[@]}"; do
    [[ -n "$anomaly" ]] || continue
    if [[ "$anomaly" == "__ACK__ "* ]]; then
      log_line "INFO" "previous_run.acknowledged ${anomaly#__ACK__ } boot_id=$(system_boot_id) uptime_seconds=$(system_uptime_seconds)"
      continue
    fi
    active_anomalies+=("$anomaly")
  done
  anomalies=("${active_anomalies[@]}")
  if [[ "${#anomalies[@]}" -eq 0 ]]; then
    log_line "INFO" "previous_run.scan status=clean scan_minutes=$CODEX_PREVIOUS_RUN_SCAN_MINUTES boot_id=$(system_boot_id) uptime_seconds=$(system_uptime_seconds)"
    return 0
  fi

  for anomaly in "${anomalies[@]}"; do
    [[ -n "$anomaly" ]] || continue
    log_line "WARN" "previous_run.anomaly $anomaly boot_id=$(system_boot_id) uptime_seconds=$(system_uptime_seconds)"
    PREVIOUS_RUN_ANOMALIES+="- $anomaly"$'\n'
  done
  STARTUP_ANOMALY_GATE="1"
  append_startup_anomaly_reason "previous_run_anomaly"
}

refresh_worktree_counts() {
  DIRTY_PATH_COUNT=0
  TRACKED_MODIFIED_PATH_COUNT=0
  UNTRACKED_PATH_COUNT=0

  local line
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    DIRTY_PATH_COUNT=$((DIRTY_PATH_COUNT + 1))
    if [[ "${line:0:2}" == "??" ]]; then
      UNTRACKED_PATH_COUNT=$((UNTRACKED_PATH_COUNT + 1))
    else
      TRACKED_MODIFIED_PATH_COUNT=$((TRACKED_MODIFIED_PATH_COUNT + 1))
    fi
  done < <(git -C "$ROOT_DIR" status --porcelain=v1 --untracked-files=all)
}

write_git_status_snapshot_json() {
  local output_file="$1"
  python3 - "$ROOT_DIR" "$output_file" <<'PY'
import json
import stat
import subprocess
import sys
from pathlib import Path

root = Path(sys.argv[1])
output = Path(sys.argv[2])


def git(args):
    return subprocess.check_output(["git", "-C", str(root), *args], stderr=subprocess.DEVNULL)


def worktree_hash(rel_path):
    path = root / rel_path
    try:
        mode = path.stat().st_mode
    except OSError:
        return "missing"
    if not stat.S_ISREG(mode):
        return "not_regular"
    try:
        return git(["hash-object", "--", rel_path]).decode("utf-8", "replace").strip() or "unknown"
    except (OSError, subprocess.CalledProcessError):
        return "unknown"


raw = git(["status", "--porcelain=v1", "-z", "--untracked-files=all"])
parts = raw.decode("utf-8", "surrogateescape").split("\0")
items = {}
i = 0
while i < len(parts):
    entry = parts[i]
    i += 1
    if not entry or len(entry) < 4:
        continue
    status_code = entry[:2]
    rel_path = entry[3:]
    if not rel_path:
        continue
    items[rel_path] = {
        "status": status_code,
        "hash": worktree_hash(rel_path),
    }
    if status_code[0] in {"R", "C"} or status_code[1] in {"R", "C"}:
        if i < len(parts):
            old_path = parts[i]
            i += 1
            if old_path:
                items.setdefault(
                    old_path,
                    {
                        "status": "old",
                        "hash": worktree_hash(old_path),
                    },
                )

output.write_text(json.dumps(items, sort_keys=True, separators=(",", ":")), encoding="utf-8")
PY
}

capture_startup_anomaly_gate_baseline() {
  [[ "$STARTUP_ANOMALY_GATE" == "1" ]] || return 0
  STARTUP_ANOMALY_GATE_BASELINE_FILE="$(run_mktemp startup-gate-baseline)"
  write_git_status_snapshot_json "$STARTUP_ANOMALY_GATE_BASELINE_FILE"
  log_line "INFO" "startup_anomaly.gate_baseline path=$(shell_quote "$STARTUP_ANOMALY_GATE_BASELINE_FILE")"
}

startup_anomaly_gate_changed_path_violations() {
  local before_file="$1"
  local after_file="$2"
  python3 - "$before_file" "$after_file" <<'PY'
import json
import sys

before_path, after_path = sys.argv[1:3]

try:
    before = json.load(open(before_path, "r", encoding="utf-8"))
    after = json.load(open(after_path, "r", encoding="utf-8"))
except OSError:
    raise SystemExit(0)

allowed_exact = {
    "Upkeeper",
    "README.md",
    "docs/scripts/upkeeper.md",
}
allowed_prefixes = (
    "prompts/",
    "templates/",
    "launcher_examples/",
)


def allowed(path):
    return path in allowed_exact or any(path.startswith(prefix) for prefix in allowed_prefixes)


for path in sorted(set(before) | set(after)):
    if allowed(path):
        continue
    if before.get(path) == after.get(path):
        continue
    before_state = before.get(path, {"status": "clean", "hash": "clean"})
    after_state = after.get(path, {"status": "clean", "hash": "clean"})
    print(
        f"changed_path={path!r} before_status={before_state.get('status', 'unknown')} "
        f"before_hash={before_state.get('hash', 'unknown')} "
        f"after_status={after_state.get('status', 'unknown')} "
        f"after_hash={after_state.get('hash', 'unknown')}"
    )
PY
}

enforce_startup_anomaly_changed_paths() {
  local after_file violation_count=0 violation
  [[ "$STARTUP_ANOMALY_GATE" == "1" ]] || return 0
  [[ -n "${STARTUP_ANOMALY_GATE_BASELINE_FILE:-}" && -f "$STARTUP_ANOMALY_GATE_BASELINE_FILE" ]] || return 0

  after_file="$(run_mktemp startup-gate-after)"
  write_git_status_snapshot_json "$after_file"
  while IFS= read -r violation; do
    [[ -n "$violation" ]] || continue
    violation_count=$((violation_count + 1))
    log_line "WARN" "startup_anomaly.gate_violation $violation"
  done < <(startup_anomaly_gate_changed_path_violations "$STARTUP_ANOMALY_GATE_BASELINE_FILE" "$after_file")

  if [[ "$violation_count" -gt 0 ]]; then
    STARTUP_ANOMALY_GATE_CHANGED_PATH_VIOLATION="1"
    append_startup_anomaly_reason "gate_changed_path_violation"
    if ! write_startup_anomaly_gate_state "unresolved" "changed_path_violation"; then
      finish_cycle 7 STARTUP_ANOMALY_STATE_UNWRITABLE ERROR "codex_exec_started=1"
    fi
  else
    log_line "INFO" "startup_anomaly.gate_violation status=none"
  fi
}

# Quota snapshot reader and projector.
#
# Codex writes rate-limit state into session JSONL files, not a stable wrapper
# API. The Python block keeps parsing isolated and returns one compact JSON
# object to Bash. Guardrails only trust exact-model buckets whose reset windows
# are still current; stale buckets are evidence, not a stop signal.
quota_state_json() {
  local target_model="${1:-$CODEX_MODEL}"
  python3 - "$CODEX_HOME_DIR" "$CODEX_SESSION_SCAN_LIMIT" "$LOG_FILE" "$target_model" <<'PY'
import json
import re
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

codex_home = Path(sys.argv[1]).expanduser()
scan_limit = int(sys.argv[2])
log_path = Path(sys.argv[3])
target_model = sys.argv[4].strip()

cycle_re = re.compile(r"cycle=([A-Za-z0-9T+-]+-\d+)")
start_model_re = re.compile(r"cycle\.start .* model=([A-Za-z0-9._:-]+)")
summary_model_re = re.compile(r"cycle\.summary .* model=([A-Za-z0-9._:-]+)")
summary_re = re.compile(
    r"cycle\.summary .*observed_primary_delta=([0-9]+(?:\.[0-9]+)?) observed_secondary_delta=([0-9]+(?:\.[0-9]+)?) .*status_marker=([^ ]+) .*codex_exit=([0-9]+)"
)

TAIL_SCAN_BYTES = 512 * 1024
HEAD_SCAN_BYTES = 128 * 1024


def snapshot_from_token_count(item, path: Path, source_mtime: float, model_hint):
    payload = item.get("payload") or {}
    rate_limits = payload.get("rate_limits") or {}
    primary = rate_limits.get("primary") or {}
    secondary = rate_limits.get("secondary") or {}
    if not primary or not secondary:
        return None
    return {
        "event_timestamp": item.get("timestamp"),
        "limit_id": rate_limits.get("limit_id"),
        "limit_name": rate_limits.get("limit_name"),
        "plan_type": rate_limits.get("plan_type"),
        "rate_limit_reached_type": rate_limits.get("rate_limit_reached_type"),
        "primary_used_percent": float(primary.get("used_percent") or 0.0),
        "primary_window_minutes": int(primary.get("window_minutes") or 0),
        "primary_resets_at": int(primary.get("resets_at") or 0),
        "secondary_used_percent": float(secondary.get("used_percent") or 0.0),
        "secondary_window_minutes": int(secondary.get("window_minutes") or 0),
        "secondary_resets_at": int(secondary.get("resets_at") or 0),
        "source_path": str(path),
        "source_mtime": source_mtime,
        "model_hint": model_hint,
    }


def model_hint_from_head(path: Path):
    try:
        with path.open("rb") as handle:
            data = handle.read(HEAD_SCAN_BYTES)
    except OSError:
        return None

    text = data.decode("utf-8", errors="ignore")
    for raw_line in text.splitlines():
        try:
            item = json.loads(raw_line)
        except json.JSONDecodeError:
            continue
        if item.get("type") != "turn_context":
            continue
        payload = item.get("payload") or {}
        context_model = payload.get("model")
        if isinstance(context_model, str) and context_model.strip():
            return context_model.strip()
    return None


def last_token_snapshot_from_tail(path: Path, source_mtime: float, model_hint):
    try:
        with path.open("rb") as handle:
            handle.seek(0, 2)
            size = handle.tell()
            handle.seek(max(0, size - TAIL_SCAN_BYTES))
            data = handle.read()
    except OSError:
        return None

    text = data.decode("utf-8", errors="ignore")
    lines = text.splitlines()
    if data and not data.startswith((b"{", b"\n", b"\r")) and lines:
        lines = lines[1:]
    for raw_line in reversed(lines):
        if '"token_count"' not in raw_line:
            continue
        try:
            item = json.loads(raw_line)
        except json.JSONDecodeError:
            continue
        if item.get("type") != "event_msg":
            continue
        payload = item.get("payload") or {}
        if payload.get("type") != "token_count":
            continue
        snapshot = snapshot_from_token_count(item, path, source_mtime, model_hint)
        if snapshot:
            return snapshot
    return None


def full_session_snapshot(path: Path, source_mtime: float):
    last_snapshot = None
    model_hint = None
    try:
        with path.open("r", encoding="utf-8", errors="ignore") as handle:
            for raw_line in handle:
                try:
                    item = json.loads(raw_line)
                except json.JSONDecodeError:
                    continue
                if item.get("type") == "turn_context":
                    payload = item.get("payload") or {}
                    context_model = payload.get("model")
                    if isinstance(context_model, str) and context_model.strip():
                        model_hint = context_model.strip()
                    continue
                if item.get("type") != "event_msg":
                    continue
                payload = item.get("payload") or {}
                if payload.get("type") != "token_count":
                    continue
                snapshot = snapshot_from_token_count(item, path, source_mtime, model_hint)
                if snapshot:
                    last_snapshot = snapshot
    except OSError:
        return None
    return last_snapshot


def session_snapshot(path: Path):
    try:
        source_mtime = path.stat().st_mtime
    except OSError:
        return None

    model_hint = model_hint_from_head(path)
    snapshot = last_token_snapshot_from_tail(path, source_mtime, model_hint)
    if snapshot and snapshot.get("model_hint"):
        return snapshot
    return full_session_snapshot(path, source_mtime)


def parse_session_snapshots(root: Path, limit: int):
    sessions_root = root / "sessions"
    if not sessions_root.exists():
        return []

    candidates = sorted(
        sessions_root.rglob("*.jsonl"),
        key=lambda p: p.stat().st_mtime,
        reverse=True,
    )[:limit]

    snapshots = []
    for path in candidates:
        snapshot = session_snapshot(path)
        if snapshot:
            snapshots.append(snapshot)

    snapshots.sort(key=lambda item: ((item.get("event_timestamp") or ""), item.get("source_mtime") or 0.0))
    return snapshots


def snapshots_for_target_model(items, model):
    if not model:
        return items, "overall_latest"
    exact = [item for item in items if item.get("model_hint") == model]
    if exact:
        return exact, "exact_model"
    return items, "overall_fallback"


def parse_event_epoch(value):
    if not isinstance(value, str) or not value.strip():
        return None
    normalized = value.strip()
    if normalized.endswith("Z"):
        normalized = f"{normalized[:-1]}+00:00"
    try:
        parsed = datetime.fromisoformat(normalized)
    except ValueError:
        return None
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return int(parsed.timestamp())


def annotate_snapshot_freshness(snapshot, now):
    event_epoch = parse_event_epoch(snapshot.get("event_timestamp"))
    primary_reset = int(snapshot.get("primary_resets_at") or 0)
    secondary_reset = int(snapshot.get("secondary_resets_at") or 0)
    primary_reset_expired = primary_reset > 0 and primary_reset <= now
    secondary_reset_expired = secondary_reset > 0 and secondary_reset <= now
    primary_bucket_current = primary_reset > now
    secondary_bucket_current = secondary_reset > now

    snapshot["snapshot_now_epoch"] = now
    snapshot["snapshot_event_epoch"] = event_epoch
    snapshot["snapshot_age_seconds"] = None if event_epoch is None else max(0, now - event_epoch)
    snapshot["primary_reset_age_seconds"] = None if primary_reset <= 0 else now - primary_reset
    snapshot["secondary_reset_age_seconds"] = None if secondary_reset <= 0 else now - secondary_reset
    snapshot["primary_reset_expired"] = primary_reset_expired
    snapshot["secondary_reset_expired"] = secondary_reset_expired
    snapshot["primary_bucket_current"] = primary_bucket_current
    snapshot["secondary_bucket_current"] = secondary_bucket_current
    snapshot["snapshot_stale_after_reset"] = primary_reset_expired or secondary_reset_expired
    return snapshot


def latest_quota_snapshot(items, now):
    # Always evaluate the newest token-count event. Bucket freshness is tracked
    # separately so one expired reset window cannot hide a newer current bucket.
    if not items:
        return None, False
    latest = items[-1]
    snapshot_has_current_bucket = (
        latest.get("primary_resets_at", 0) > now or latest.get("secondary_resets_at", 0) > now
    )
    return latest, snapshot_has_current_bucket


def snapshot_for_target_model(items, model, now):
    filtered, selection = snapshots_for_target_model(items, model)
    snapshot, snapshot_is_current = latest_quota_snapshot(filtered, now)
    if snapshot is None:
        return None, selection, 0, False
    return annotate_snapshot_freshness(dict(snapshot), now), selection, len(filtered), snapshot_is_current


def last_positive_delta_from_log(path: Path, model: str):
    # Recent successful cycles tell us what "one more run" usually costs for
    # this model. Failed or missing-marker cycles are deliberately ignored so an
    # incident does not poison the next projection.
    if not path.exists():
        return None, None
    cycle_models = {}
    primary = None
    secondary = None
    try:
        with path.open("r", encoding="utf-8", errors="ignore") as handle:
            for raw_line in handle:
                cycle_match = cycle_re.search(raw_line)
                cycle_id = cycle_match.group(1) if cycle_match else None
                start_model_match = start_model_re.search(raw_line)
                if cycle_id and start_model_match:
                    cycle_models[cycle_id] = start_model_match.group(1)
                match = summary_re.search(raw_line)
                if not match:
                    continue
                summary_model_match = summary_model_re.search(raw_line)
                summary_model = None
                if summary_model_match:
                    summary_model = summary_model_match.group(1)
                elif cycle_id:
                    summary_model = cycle_models.get(cycle_id)
                if model and summary_model and summary_model != model:
                    continue
                status_marker = match.group(3)
                codex_exit = int(match.group(4))
                if codex_exit != 0 or status_marker == "missing":
                    continue
                primary_delta = float(match.group(1))
                secondary_delta = float(match.group(2))
                if primary_delta <= 0.0 and secondary_delta <= 0.0:
                    continue
                primary = primary_delta
                secondary = secondary_delta
    except OSError:
        return None, None
    return primary, secondary


try:
    snapshots = parse_session_snapshots(codex_home, scan_limit)
    now_epoch = int(time.time())
    snapshot, snapshot_selection, matching_snapshot_count, snapshot_is_current = snapshot_for_target_model(
        snapshots,
        target_model,
        now_epoch,
    )
    if snapshot is None:
        print(json.dumps({"error": "no_rate_limit_snapshot_found"}))
        sys.exit(0)

    log_primary, log_secondary = last_positive_delta_from_log(log_path, target_model)
    if log_primary is not None and log_secondary is not None:
        primary_delta = log_primary
        secondary_delta = log_secondary
        basis = "log_summary"
    else:
        primary_delta = 1.0
        secondary_delta = 1.0
        basis = "default_1_percent"

    print(
        json.dumps(
            {
                "snapshot": snapshot,
                "snapshot_selection": snapshot_selection,
                "snapshot_is_current": snapshot_is_current,
                "matching_snapshot_count": matching_snapshot_count,
                "target_model": target_model,
                "projection": {
                    "primary_delta": primary_delta,
                    "secondary_delta": secondary_delta,
                    "basis": basis,
                },
            }
        )
    )
except KeyboardInterrupt:
    print(json.dumps({"error": "interrupted"}))
    sys.exit(0)
PY
}

