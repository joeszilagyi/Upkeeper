# Primary quota cooldown marker helpers.
#
# Upkeeper writes per-cycle markers under CODEX_POSTMORTEM_DIR when primary
# quota guardrails stop a run. Later primary invocations read those markers
# before spending more quota and stop until the recorded reset time passes.
# Operator-facing behavior is summarized in docs/scripts/upkeeper.md; update
# that guide and the current year's change_notes_YYYY.md when changing marker
# semantics.
latest_active_primary_quota_block_marker() {
  local target_model="$1"

  python3 - "$CODEX_POSTMORTEM_DIR" "$target_model" <<'PY'
from pathlib import Path
import math
import sys
import time

root = Path(sys.argv[1])
target_model = sys.argv[2]
now = int(time.time())
candidates = []

if root.exists():
    for marker_path in root.glob("*/primary-quota-blocked-until.txt"):
        fields = {}
        try:
            lines = marker_path.read_text(encoding="utf-8", errors="replace").splitlines()
        except OSError:
            continue
        for line in lines:
            if ":" not in line:
                continue
            key, value = line.split(":", 1)
            fields[key.strip()] = value.strip()
        if fields.get("primary_model") != target_model:
            continue
        try:
            blocked_until_value = float(fields.get("blocked_until_epoch", ""))
        except (OverflowError, ValueError):
            continue
        if not math.isfinite(blocked_until_value):
            continue
        blocked_until_epoch = int(blocked_until_value)
        if blocked_until_epoch <= now:
            continue
        try:
            marker_mtime = marker_path.stat().st_mtime
        except OSError:
            marker_mtime = 0
        candidates.append((blocked_until_epoch, marker_mtime, str(marker_path)))

if not candidates:
    raise SystemExit(1)

candidates.sort()
print(candidates[-1][2])
PY
}

write_primary_quota_blocked_marker() {
  local stop_reason="$1"
  local marker_source_phase="${2:-before_run}"
  local pm_root marker_path marker_tmp_path blocked_buckets blocked_until_epoch
  local created_at recommended_action
  local primary_reset_value secondary_reset_value
  local marker_primary_decision marker_secondary_decision
  local marker_primary_used marker_primary_left marker_secondary_used marker_secondary_left
  local marker_primary_reset marker_secondary_reset
  local marker_primary_bucket_current marker_secondary_bucket_current
  local marker_identity_changed

  if [[ "$marker_source_phase" == "after_run" ]]; then
    marker_primary_decision="${after_primary_guardrail_decision:-defer}"
    marker_secondary_decision="${after_secondary_guardrail_decision:-defer}"
    marker_primary_used="${after_primary:-unknown}"
    marker_primary_left="${after_primary_left:-unknown}"
    marker_secondary_used="${after_secondary:-unknown}"
    marker_secondary_left="${after_secondary_left:-unknown}"
    marker_primary_reset="${after_primary_reset:-}"
    marker_secondary_reset="${after_secondary_reset:-}"
    marker_primary_bucket_current="${after_primary_bucket_current:-unknown}"
    marker_secondary_bucket_current="${after_secondary_bucket_current:-unknown}"
  else
    marker_source_phase="before_run"
    marker_primary_decision="${primary_guardrail_decision:-defer}"
    marker_secondary_decision="${secondary_guardrail_decision:-defer}"
    marker_primary_used="${primary_used:-unknown}"
    marker_primary_left="${primary_left:-unknown}"
    marker_secondary_used="${secondary_used:-unknown}"
    marker_secondary_left="${secondary_left:-unknown}"
    marker_primary_reset="${primary_reset:-}"
    marker_secondary_reset="${secondary_reset:-}"
    marker_primary_bucket_current="${before_primary_bucket_current:-unknown}"
    marker_secondary_bucket_current="${before_secondary_bucket_current:-unknown}"
  fi
  primary_reset_value="$marker_primary_reset"
  secondary_reset_value="$marker_secondary_reset"
  marker_identity_changed="$(quota_identity_changed_flag "${limit_id:-unknown}" "${limit_name:-unknown}" "${after_limit_id:-unknown}" "${after_limit_name:-unknown}")"

  blocked_buckets=""
  blocked_until_epoch=0
  if [[ "$marker_primary_decision" == "stop" ]]; then
    blocked_buckets="${blocked_buckets:+$blocked_buckets,}primary"
    if [[ "$primary_reset_value" =~ ^[0-9]+$ && "$primary_reset_value" -gt "$blocked_until_epoch" ]]; then
      blocked_until_epoch="$primary_reset_value"
    fi
  fi
  if [[ "$marker_secondary_decision" == "stop" ]]; then
    blocked_buckets="${blocked_buckets:+$blocked_buckets,}secondary"
    if [[ "$secondary_reset_value" =~ ^[0-9]+$ && "$secondary_reset_value" -gt "$blocked_until_epoch" ]]; then
      blocked_until_epoch="$secondary_reset_value"
    fi
  fi
  [[ -n "$blocked_buckets" ]] || return 0

  pm_root="$CODEX_POSTMORTEM_DIR/$CYCLE_ID"
  marker_path="$pm_root/primary-quota-blocked-until.txt"
  created_at="$(timestamp_now)"
  recommended_action="wait_until_reset_or_switch_primary_model"

  if ! mkdir -p -- "$pm_root"; then
    log_line "ERROR" "quota.blocked_marker_failed path=$(shell_quote "$marker_path") reason=mkdir_failed"
    return 0
  fi
  marker_tmp_path="$marker_path.tmp.$$"
  if ! {
    cat <<EOF
incident_cycle_id: $CYCLE_ID
created_at: $created_at
marker_source_phase: $marker_source_phase
primary_model: $CODEX_MODEL
blocked_bucket: $blocked_buckets
blocked_until_epoch: $blocked_until_epoch
blocked_until: $(format_epoch_local "$blocked_until_epoch")
reason: $stop_reason
before_limit_id: ${limit_id:-unknown}
before_limit_name: ${limit_name:-unknown}
after_limit_id: ${after_limit_id:-unknown}
after_limit_name: ${after_limit_name:-unknown}
quota_identity_changed: $marker_identity_changed
before_primary_reset_epoch: ${primary_reset:-unknown}
before_primary_reset: $(format_epoch_local "${primary_reset:-}")
before_secondary_reset_epoch: ${secondary_reset:-unknown}
before_secondary_reset: $(format_epoch_local "${secondary_reset:-}")
after_primary_reset_epoch: ${after_primary_reset:-unknown}
after_primary_reset: $(format_epoch_local "${after_primary_reset:-}")
after_secondary_reset_epoch: ${after_secondary_reset:-unknown}
after_secondary_reset: $(format_epoch_local "${after_secondary_reset:-}")
primary_used: ${marker_primary_used:-unknown}%
primary_left: ${marker_primary_left:-unknown}%
primary_bucket_current: ${marker_primary_bucket_current:-unknown}
primary_projected_left: ${primary_projected_left:-unknown}%
primary_threshold: ${five_hour_threshold:-unknown}%
primary_reset_epoch: ${marker_primary_reset:-unknown}
primary_reset: $(format_epoch_local "${marker_primary_reset:-}")
secondary_used: ${marker_secondary_used:-unknown}%
secondary_left: ${marker_secondary_left:-unknown}%
secondary_bucket_current: ${marker_secondary_bucket_current:-unknown}
secondary_projected_left: ${secondary_projected_left:-unknown}%
secondary_threshold: ${week_threshold:-unknown}%
secondary_reset_epoch: ${marker_secondary_reset:-unknown}
secondary_reset: $(format_epoch_local "${marker_secondary_reset:-}")
recommended_operator_action: $recommended_action
EOF
  } >"$marker_tmp_path"; then
    rm -f -- "$marker_tmp_path"
    log_line "ERROR" "quota.blocked_marker_failed path=$(shell_quote "$marker_path") reason=write_failed"
    return 0
  fi
  if ! mv -f -- "$marker_tmp_path" "$marker_path"; then
    rm -f -- "$marker_tmp_path"
    log_line "ERROR" "quota.blocked_marker_failed path=$(shell_quote "$marker_path") reason=rename_failed"
    return 0
  fi

  log_line "WARN" "quota.blocked_marker path=$(shell_quote "$marker_path") target_model=$CODEX_MODEL marker_source_phase=$marker_source_phase blocked_bucket=$blocked_buckets blocked_until=$(format_epoch_local "$blocked_until_epoch") quota_identity_changed=$marker_identity_changed"
}

enforce_primary_quota_block_marker() {
  if [[ "$CODEX_ATTEMPT_ROLE" != "primary" || "$CODEX_FALLBACK_CHAIN_ACTIVE" == "1" ]]; then
    return 0
  fi

  local marker_path blocked_until_epoch blocked_until blocked_bucket reason source_cycle recommended_action
  local marker_path_q reason_q blocked_until_q
  if ! marker_path="$(latest_active_primary_quota_block_marker "$CODEX_MODEL")"; then
    return 0
  fi

  blocked_until_epoch="$(marker_field "$marker_path" "blocked_until_epoch")"
  blocked_until="$(marker_field "$marker_path" "blocked_until")"
  blocked_bucket="$(marker_field "$marker_path" "blocked_bucket")"
  reason="$(marker_field "$marker_path" "reason")"
  source_cycle="$(marker_field "$marker_path" "incident_cycle_id")"
  recommended_action="$(marker_field "$marker_path" "recommended_operator_action")"

  marker_path_q="$(shell_quote "$marker_path")"
  reason_q="$(shell_quote "${reason:-unknown}")"
  blocked_until_q="$(shell_quote "${blocked_until:-unknown}")"
  log_line "WARN" "quota.cooldown active target_model=$CODEX_MODEL blocked_bucket=${blocked_bucket:-unknown} blocked_until=$blocked_until_q blocked_until_epoch=${blocked_until_epoch:-unknown} source_cycle=${source_cycle:-unknown} marker_path=$marker_path_q reason=$reason_q recommended_operator_action=${recommended_action:-wait_until_reset_or_switch_primary_model}"
  finish_cycle 7 QUOTA_HANDOFF_COOLDOWN INFO "codex_exec_started=0 target_model=$CODEX_MODEL blocked_until=$blocked_until_q marker_path=$marker_path_q"
}
