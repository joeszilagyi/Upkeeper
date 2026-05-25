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

quota_sum_percent_thresholds_fallback() {
  local first="$1"
  local second="$2"

  [[ -n "$first" && -n "$second" ]] || {
    printf '%s' "$first"
    return 0
  }

  [[ "$first" =~ ^[-+]?[0-9]+([.][0-9]*)?$ || "$first" =~ ^[.][0-9]+$ ]] || {
    printf '%s' "$first"
    return 0
  }
  [[ "$second" =~ ^[-+]?[0-9]+([.][0-9]*)?$ || "$second" =~ ^[.][0-9]+$ ]] || {
    printf '%s' "$first"
    return 0
  }

  awk -v first="$first" -v second="$second" '
    BEGIN {
      value = first + second
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
  ' || printf '%s' "$first"
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
  local percent
  buffer="$(quota_week_stop_buffer_percent_for_model "$target_model")"
  percent="$CODEX_WEEK_STOP_PERCENT"

  if type -t sum_percent_thresholds >/dev/null 2>&1; then
    sum_percent_thresholds "$percent" "$buffer"
  else
    quota_sum_percent_thresholds_fallback "$percent" "$buffer"
  fi
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

quota_percent_value_is_valid() {
  local value="$1"

  [[ "$value" =~ ^([0-9]+([.][0-9]*)?|[.][0-9]+)$ ]] || return 1
  awk -v value="$value" 'BEGIN { exit !((value + 0) >= 0 && (value + 0) <= 100) }'
}

quota_bucket_decision() {
  local bucket_current="${1:-false}"
  local projected_left="${2:-}"
  local threshold="${3:-}"

  if [[ "$bucket_current" != "true" || -z "$projected_left" || -z "$threshold" ]]; then
    printf 'defer'
    return 0
  fi
  if ! quota_percent_value_is_valid "$projected_left" || ! quota_percent_value_is_valid "$threshold"; then
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
