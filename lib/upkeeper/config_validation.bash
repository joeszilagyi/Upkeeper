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

