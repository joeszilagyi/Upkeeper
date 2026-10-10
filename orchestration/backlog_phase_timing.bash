# Per-job phase timing for the backlog launcher.  This stays intentionally
# data-only: callers continue to own their validation, GitHub, quota, and
# obligation decisions, while this module records how long those phases took.

BACKLOG_PHASE_TIMING_ENABLED="${BACKLOG_PHASE_TIMING_ENABLED:-1}"
BACKLOG_PHASE_BUDGET_TRIVIAL_SECONDS="${BACKLOG_PHASE_BUDGET_TRIVIAL_SECONDS:-900}"
BACKLOG_PHASE_BUDGET_NORMAL_SECONDS="${BACKLOG_PHASE_BUDGET_NORMAL_SECONDS:-1800}"
BACKLOG_PHASE_BUDGET_BROAD_SECONDS="${BACKLOG_PHASE_BUDGET_BROAD_SECONDS:-3600}"
BACKLOG_PHASE_TIMING_ROWS=()
BACKLOG_PHASE_TIMING_STARTS=()
BACKLOG_PHASE_TIMING_CLASS="normal"
BACKLOG_PHASE_TIMING_BUDGET_SECONDS=""
BACKLOG_PHASE_TIMING_EVIDENCE_PATH=""
BACKLOG_PHASE_TIMING_LAST_SUMMARY=""

backlog_phase_timing_truthy() {
  case "${1:-0}" in 1|true|TRUE|yes|YES|on|ON) return 0 ;; esac
  return 1
}

backlog_phase_timing_external() {
  case "${1:-}" in
    ci_registration|ci_pending|pr_polling_idle|quota_hibernation|obligation_cooldown)
      return 0
      ;;
  esac
  return 1
}

backlog_phase_timing_budget_for_class() {
  case "${1:-normal}" in
    docs-only|mechanical|trivial)
      printf '%s\n' "$BACKLOG_PHASE_BUDGET_TRIVIAL_SECONDS"
      ;;
    high-risk|broad|contract-security|data-integrity)
      printf '%s\n' "$BACKLOG_PHASE_BUDGET_BROAD_SECONDS"
      ;;
    *)
      printf '%s\n' "$BACKLOG_PHASE_BUDGET_NORMAL_SECONDS"
      ;;
  esac
}

backlog_phase_timing_reset() {
  BACKLOG_PHASE_TIMING_ROWS=()
  BACKLOG_PHASE_TIMING_STARTS=()
  BACKLOG_PHASE_TIMING_CLASS="normal"
  BACKLOG_PHASE_TIMING_BUDGET_SECONDS="$(backlog_phase_timing_budget_for_class normal)"
  BACKLOG_PHASE_TIMING_LAST_SUMMARY=""
}

backlog_phase_timing_set_class() {
  local class="${1:-normal}"
  local budget

  budget="$(backlog_phase_timing_budget_for_class "$class")"
  if ! backlog_nonnegative_integer "$budget" || [[ "$budget" -eq 0 ]]; then
    budget=1800
  fi
  BACKLOG_PHASE_TIMING_CLASS="$class"
  BACKLOG_PHASE_TIMING_BUDGET_SECONDS="$budget"
}

backlog_phase_timing_start() {
  local phase="$1"
  local started

  backlog_phase_timing_truthy "$BACKLOG_PHASE_TIMING_ENABLED" || return 0
  started="$(backlog_now_epoch 2>/dev/null || date '+%s')" || return 1
  BACKLOG_PHASE_TIMING_STARTS+=("$phase"$'\t'"$started")
}

backlog_phase_timing_finish() {
  local phase="$1"
  local status="${2:-pass}"
  local ended start_line start_phase started index elapsed

  backlog_phase_timing_truthy "$BACKLOG_PHASE_TIMING_ENABLED" || return 0
  ended="$(backlog_now_epoch 2>/dev/null || date '+%s')" || return 1
  for ((index=${#BACKLOG_PHASE_TIMING_STARTS[@]} - 1; index >= 0; index--)); do
    start_line="${BACKLOG_PHASE_TIMING_STARTS[index]}"
    start_phase="${start_line%%$'\t'*}"
    [[ "$start_phase" == "$phase" ]] || continue
    started="${start_line#*$'\t'}"
    unset 'BACKLOG_PHASE_TIMING_STARTS[index]'
    break
  done
  [[ -n "${started:-}" ]] || return 1
  if backlog_nonnegative_integer "$started" && backlog_nonnegative_integer "$ended" && [[ "$ended" -ge "$started" ]]; then
    elapsed=$((ended - started))
  else
    elapsed=0
  fi
  BACKLOG_PHASE_TIMING_ROWS+=("$phase"$'\t'"$elapsed"$'\t'"$status")
  log "phase timing: phase=$phase elapsed_seconds=$elapsed status=$status external=$(backlog_phase_timing_external "$phase" && printf 1 || printf 0)"
}

backlog_phase_timing_summary() {
  local row phase elapsed status total=0 local_total=0 external_total=0 dominant_phase="none" dominant_seconds=0

  for row in "${BACKLOG_PHASE_TIMING_ROWS[@]}"; do
    IFS=$'\t' read -r phase elapsed status <<<"$row"
    backlog_nonnegative_integer "$elapsed" || continue
    total=$((total + elapsed))
    if backlog_phase_timing_external "$phase"; then
      external_total=$((external_total + elapsed))
    else
      local_total=$((local_total + elapsed))
    fi
    if [[ "$elapsed" -gt "$dominant_seconds" ]]; then
      dominant_phase="$phase"
      dominant_seconds="$elapsed"
    fi
  done
  printf 'class=%s budget_seconds=%s total_seconds=%s local_seconds=%s external_seconds=%s dominant_phase=%s dominant_seconds=%s' \
    "$BACKLOG_PHASE_TIMING_CLASS" "${BACKLOG_PHASE_TIMING_BUDGET_SECONDS:-unknown}" "$total" "$local_total" "$external_total" "$dominant_phase" "$dominant_seconds"
}

backlog_phase_timing_emit_summary() {
  local summary
  local total local_total budget

  backlog_phase_timing_truthy "$BACKLOG_PHASE_TIMING_ENABLED" || return 0
  [[ "${#BACKLOG_PHASE_TIMING_ROWS[@]}" -gt 0 ]] || return 0
  summary="$(backlog_phase_timing_summary)"
  BACKLOG_PHASE_TIMING_LAST_SUMMARY="$summary"
  log "phase timing summary: $summary"
  total="$(sed -n 's/.* total_seconds=\([0-9][0-9]*\).*/\1/p' <<<"$summary")"
  local_total="$(sed -n 's/.* local_seconds=\([0-9][0-9]*\).*/\1/p' <<<"$summary")"
  budget="${BACKLOG_PHASE_TIMING_BUDGET_SECONDS:-}"
  if backlog_nonnegative_integer "$budget" && backlog_nonnegative_integer "$total" && backlog_nonnegative_integer "$local_total" &&
    [[ "$total" -gt "$budget" && "$local_total" -gt "$budget" ]]; then
    backlog_phase_timing_write_evidence "$summary" breach
    backlog_phase_timing_open_obligation "$summary" "$BACKLOG_PHASE_TIMING_EVIDENCE_PATH" || true
    log "WARN phase timing budget breached: class=$BACKLOG_PHASE_TIMING_CLASS budget_seconds=$budget total_seconds=$total local_seconds=$local_total action=record_local_evidence"
    return 2
  fi
  backlog_phase_timing_write_evidence "$summary" pass
  return 0
}

backlog_phase_timing_write_evidence() {
  local summary="$1"
  local outcome="$2"
  local state_root dir path now row

  BACKLOG_PHASE_TIMING_EVIDENCE_PATH=""
  state_root="$(backlog_state_root)" || return 1
  dir="$state_root/phase-timing"
  mkdir -p -- "$dir" || return 1
  chmod 700 "$dir" 2>/dev/null || true
  now="$(backlog_now_epoch 2>/dev/null || date '+%s')"
  path="$dir/job-${now}-$$.tsv"
  {
    printf 'schema\tupkeeper.backlog-phase-timing.v1\n'
    printf 'outcome\t%s\n' "$outcome"
    printf 'summary\t%s\n' "$summary"
    printf 'phase\telapsed_seconds\tstatus\texternal\n'
    for row in "${BACKLOG_PHASE_TIMING_ROWS[@]}"; do
      local phase elapsed status
      IFS=$'\t' read -r phase elapsed status <<<"$row"
      printf '%s\t%s\t%s\t%s\n' "$phase" "$elapsed" "$status" "$(backlog_phase_timing_external "$phase" && printf 1 || printf 0)"
    done
  } >"$path" || return 1
  chmod 600 "$path" 2>/dev/null || true
  BACKLOG_PHASE_TIMING_EVIDENCE_PATH="$path"
  log "phase timing evidence: outcome=$outcome path=$path"
}

backlog_phase_timing_open_obligation() {
  local summary="$1"
  local evidence_path="$2"
  local root open_dir id path now

  [[ -n "$evidence_path" ]] || return 1
  root="${UPKEEPER_OBLIGATION_DIR:-$ROOT_DIR/runtime/upkeeper-obligations}"
  open_dir="$root/open"
  mkdir -p -- "$open_dir" || return 1
  chmod 700 "$root" "$open_dir" 2>/dev/null || true
  id="phase-timing-$(printf '%s' "$summary" | sha256sum | awk '{print substr($1, 1, 24)}')"
  path="$open_dir/$id.json"
  now="$(date '+%Y-%m-%dT%H:%M:%S%z')"
  python3 - "$path" "$id" "$now" "$summary" "$evidence_path" "$ROOT_DIR" <<'PY'
import json
import os
import sys

path, obligation_id, now, summary, evidence_path, root = sys.argv[1:]
record = {
    "schema": 1,
    "record_type": "automation_obligation",
    "status": "open",
    "id": obligation_id,
    "kind": "performance_budget_breach",
    "severity": "high",
    "summary": "Backlog local wall-clock budget exceeded",
    "root": root,
    "source": "backlog_phase_timing",
    "target_scope": "target",
    "target_file": "orchestration/backlog.sh",
    "repair_target_file": "orchestration/backlog.sh",
    "reason": "PHASE_TIMING_BUDGET_BREACH",
    "required_resolution": ["inspect the phase timing evidence", "remove avoidable local latency without weakening required gates"],
    "evidence": {"summary": summary, "path": evidence_path},
    "created_at": now,
    "updated_at": now,
}
if os.path.exists(path):
    try:
        with open(path, encoding="utf-8") as handle:
            prior = json.load(handle)
        record["created_at"] = prior.get("created_at", now)
        record["seen_count"] = int(prior.get("seen_count", 1)) + 1
    except (OSError, ValueError, TypeError):
        record["seen_count"] = 1
else:
    record["seen_count"] = 1
tmp = f"{path}.tmp.{os.getpid()}"
with open(tmp, "x", encoding="utf-8") as handle:
    json.dump(record, handle, sort_keys=True, separators=(",", ":"))
    handle.write("\n")
os.chmod(tmp, 0o600)
os.replace(tmp, path)
PY
  log "automation obligation opened for local phase timing budget breach id=$id evidence=$evidence_path"
}
