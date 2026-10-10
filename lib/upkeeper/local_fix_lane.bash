# Conservative local-first lane for issue repairs.  A classification never
# authorizes a source edit: the only no-backend completion currently supported
# is an already-applied, editorial-only documentation change that passes the
# same deterministic docs gate used by CI.

upkeeper_local_fix_lane_truthy() {
  case "${1:-0}" in 1|true|TRUE|yes|YES|on|ON) return 0 ;; esac
  return 1
}

upkeeper_local_fix_lane_has_label() {
  local expected="$1" labels=",${CODEX_ISSUE_FIX_LABELS,,},"
  [[ "$labels" == *",${expected},"* ]]
}

upkeeper_local_fix_lane_has_sensitive_label() {
  local label
  for label in security data-integrity lattice backup restore quota fallback schema; do
    upkeeper_local_fix_lane_has_label "$label" && return 0
  done
  return 1
}

upkeeper_local_fix_lane_changed_paths() {
  {
    git diff --name-only --cached
    git diff --name-only
    git ls-files --others --exclude-standard
  } | sed '/^[[:space:]]*$/d' | LC_ALL=C sort -u
}

upkeeper_local_fix_lane_run_docs_gate() {
  "$ROOT_DIR/tools/docs_only_fast_path.sh" --validate
}

upkeeper_local_fix_lane_has_explicit_target() {
  local target="$1"

  [[ "${CODEX_ISSUE_FIX_SELECTED_LABEL:-}" == "explicit" ]] || return 1
  [[ -n "${CODEX_ISSUE_FIX_TARGET_FILE:-}" ]] || return 1
  [[ "$target" == "$CODEX_ISSUE_FIX_TARGET_FILE" ]]
}

upkeeper_local_fix_lane_escalate() {
  local reason="$1"
  local target="${2:-${RUN_SELECTED_REVIEW_PATH:-${CODEX_TARGET_FILE:-unknown}}}"

  log_line "INFO" "local_fix_lane.escalate lane=backend effort=${CODEX_REASONING_EFFORT:-unknown} grade=${UPKEEPER_TASK_PROFILE_GRADE:-unknown} reason=$reason target=$(shell_quote "$target")"
  return 1
}

upkeeper_local_fix_lane_docs_change_is_complete() {
  local target="${RUN_SELECTED_REVIEW_PATH:-${CODEX_TARGET_FILE:-}}"
  local path changed=0 target_seen=0

  upkeeper_local_fix_lane_truthy "${UPKEEPER_LOCAL_FIX_LANE_ENABLED:-1}" || return 1
  upkeeper_issue_fix_next_enabled || return 1
  [[ "${UPKEEPER_DRY_RUN:-0}" != "1" ]] || { upkeeper_local_fix_lane_escalate "dry_run" "$target"; return 1; }
  ! upkeeper_local_fix_lane_has_sensitive_label || { upkeeper_local_fix_lane_escalate "sensitive_label" "$target"; return 1; }
  upkeeper_local_fix_lane_has_explicit_target "$target" || { upkeeper_local_fix_lane_escalate "target_not_explicitly_authorized" "$target"; return 1; }
  upkeeper_change_scope_path_is_docs_only "$target" || { upkeeper_local_fix_lane_escalate "target_not_editorial" "$target"; return 1; }

  while IFS= read -r path; do
    [[ -n "$path" ]] || continue
    upkeeper_change_scope_path_is_docs_only "$path" || { upkeeper_local_fix_lane_escalate "mixed_or_non_editorial_diff" "$target"; return 1; }
    changed=1
    [[ "$path" == "$target" ]] && target_seen=1
  done < <(upkeeper_local_fix_lane_changed_paths)
  [[ "$changed" == "1" && "$target_seen" == "1" ]] || { upkeeper_local_fix_lane_escalate "no_applied_selected_editorial_diff" "$target"; return 1; }

  if upkeeper_local_fix_lane_run_docs_gate; then
    log_line "INFO" "local_fix_lane.complete lane=local effort=none class=docs_only reason=applied_editorial_diff_validated target=$(shell_quote "$target") codex_exec_started=0"
    return 0
  fi
  upkeeper_local_fix_lane_escalate "validation_failed" "$target"
  return 1
}
