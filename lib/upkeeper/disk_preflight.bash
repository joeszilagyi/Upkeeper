# Disk-space startup preflight.
#
# These helpers log machine-readable free-space evidence before Codex starts.
# Path-like values are shell-quoted because operators can point Upkeeper at
# space-bearing directories through environment/configuration knobs.
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
  local probe_path df_fields
  local size_kb used_kb avail_kb used_percent free_percent mount

  probe_path="$(existing_df_probe_path "$path")"
  [[ -n "$probe_path" ]] || return 1
  df_fields="$(df -Pk "$probe_path" 2>/dev/null | awk 'NR == 2 {
    used = $5
    gsub("%", "", used)
    free = 100 - used
    printf "%s\t%s\t%s\t%s\t%s\t%s", $2, $3, $4, used, free, $6
  }')" || return 1
  [[ -n "$df_fields" ]] || return 1
  IFS=$'\t' read -r size_kb used_kb avail_kb used_percent free_percent mount <<<"$df_fields"
  [[ "$free_percent" =~ ^-?[0-9]+([.][0-9]+)?$ ]] || return 1

  printf "label=%s size_kb=%s used_kb=%s avail_kb=%s used_percent=%s free_percent=%s mount=%s path=%s probe_path=%s" \
    "$(shell_quote "$label")" \
    "$size_kb" \
    "$used_kb" \
    "$avail_kb" \
    "$used_percent" \
    "$free_percent" \
    "$(shell_quote "$mount")" \
    "$(shell_quote "$path")" \
    "$(shell_quote "$probe_path")"
}

disk_preflight_free_percent_from_fields() {
  local fields="$1"
  local value

  value="${fields#* free_percent=}"
  [[ "$value" != "$fields" ]] || return 1
  value="${value%% *}"
  [[ "$value" =~ ^-?[0-9]+([.][0-9]+)?$ ]] || return 1
  printf '%s' "$value"
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
      log_line "WARN" "disk.preflight status=unavailable label=$(shell_quote "$label") path=$(shell_quote "$path")"
      notes+="- disk.preflight unavailable label=$(shell_quote "$label") path=$(shell_quote "$path")"$'\n'
      continue
    fi

    free_percent="$(disk_preflight_free_percent_from_fields "$fields" || true)"
    if [[ -z "$free_percent" ]]; then
      unavailable_count=$((unavailable_count + 1))
      log_line "WARN" "disk.preflight status=unavailable label=$(shell_quote "$label") path=$(shell_quote "$path") reason=invalid_free_percent"
      notes+="- disk.preflight unavailable label=$(shell_quote "$label") path=$(shell_quote "$path") reason=invalid_free_percent"$'\n'
      continue
    fi
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
