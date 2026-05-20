## Codex arg0 temp cleanup.
##
## Upkeeper owns cleanup for stale Codex `codex-arg0*` shim directories before a
## live backend launch. Matching directories under the same root are only
## deleted when they carry an Upkeeper/Codex ownership marker and must otherwise
## be quarantined.

ARG0_TMP_OWNERSHIP_MARKER=".upkeeper-arg0.owner"

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

arg0_tmp_is_owned_by_upkeeper() {
  local dir="$1"
  local marker_path="$dir/$ARG0_TMP_OWNERSHIP_MARKER"
  local marker_owner marker_mode marker_header

  [[ -f "$marker_path" && ! -L "$marker_path" ]] || return 1
  marker_owner="$(stat -Lc '%u' -- "$marker_path" 2>/dev/null || printf '')"
  marker_mode="$(stat -Lc '%a' -- "$marker_path" 2>/dev/null || printf '')"
  [[ "$marker_owner" == "$(id -u)" && "$marker_mode" == "600" ]] || return 1

  IFS= read -r marker_header <"$marker_path" || return 1
  [[ "$marker_header" == "upkeeper-arg0-owner-v1" ]]
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

  mapfile -d '' candidates < <(find "$arg0_root" -mindepth 1 -maxdepth 1 -type d -name 'codex-arg0*' -mmin "+$stale_minutes" -print0 2>"$err_file")
  if [[ -s "$err_file" ]]; then
    printf 'find_failed:%s' "$(tr '\n' ' ' <"$err_file")"
    rm -f "$err_file"
    return 1
  fi

  for candidate in "${candidates[@]}"; do
    [[ -d "$candidate" && ! -L "$candidate" ]] || continue
    : >"$err_file"

    if ! arg0_tmp_is_owned_by_upkeeper "$candidate"; then
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
        quarantines+=("$candidate->missing_marker:$quarantine")
        continue
      fi

      detail="$(tr '\n' ' ' <"$err_file")"
      blocked+=("$candidate:quarantine_failed_missing_marker:${detail:-unknown_error}")
      continue
    fi

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
