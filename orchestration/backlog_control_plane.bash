#!/usr/bin/env bash
# Control-plane snapshot and pre-staging audit boundary for backlog.sh.

control_plane_snapshot_root() {
  local state_root
  state_root="$(backlog_state_root)"
  printf '%s/control-plane-snapshots\n' "$state_root"
}

control_plane_lineage_root() {
  local state_root
  state_root="$(backlog_state_root)"
  printf '%s/control-plane-lineage\n' "$state_root"
}

control_plane_snapshot_path() {
  local stage="$1" snapshot_dir safe_stage
  snapshot_dir="$(control_plane_snapshot_root)"
  safe_stage="$(printf '%s' "$stage" | tr -c 'A-Za-z0-9_.-' '_')"
  mkdir -p -- "$snapshot_dir" || return 1
  chmod 700 "$snapshot_dir" 2>/dev/null || true
  printf '%s/%s.%s.%s.json\n' "$snapshot_dir" "$safe_stage" "$(date '+%Y%m%dT%H%M%S%z')" "${BASHPID:-$$}"
}

record_control_plane_snapshot() {
  local stage="$1" snapshot_path
  [[ -x "$ROOT_DIR/tools/upkeeper_control_plane_audit.py" ]] || return 0
  snapshot_path="$(control_plane_snapshot_path "$stage")" || return 0
  "$ROOT_DIR/tools/upkeeper_control_plane_audit.py" --root "$ROOT_DIR" --no-default-log --no-runtime \
    --stage "$stage" --snapshot-label "$stage" --snapshot-out "$snapshot_path" --write-lineage \
    --lineage-root "$(control_plane_lineage_root)" --resolve-missing-lineage --fail-on never >/dev/null 2>&1 || true
}

run_control_plane_pre_staging_audit() {
  local obligation_root before_snapshot after_snapshot
  local -a before_args=() after_args=()
  [[ -x "$ROOT_DIR/tools/upkeeper_control_plane_audit.py" ]] || return 0
  obligation_root="${BACKLOG_OBLIGATION_DIR:-$ROOT_DIR/runtime/upkeeper-obligations}"
  before_snapshot="$(control_plane_snapshot_path pre-staging-before 2>/dev/null || true)"
  [[ -n "$before_snapshot" ]] && before_args=(--pre-remediation-snapshot-out "$before_snapshot")
  after_snapshot="$(control_plane_snapshot_path pre-staging-after 2>/dev/null || true)"
  [[ -n "$after_snapshot" ]] && after_args=(--snapshot-out "$after_snapshot")
  log "control-plane audit: pre-staging source-boundary policy"
  "$ROOT_DIR/tools/upkeeper_control_plane_audit.py" --root "$ROOT_DIR" --no-default-log --no-runtime \
    --remediate-safe --write-obligations --obligation-root "$obligation_root" --stage pre-staging \
    --snapshot-label pre-staging-after --write-lineage --lineage-root "$(control_plane_lineage_root)" \
    --resolve-missing-lineage "${before_args[@]}" "${after_args[@]}" --fail-on blockers
}
