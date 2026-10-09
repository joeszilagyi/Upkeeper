# Upkeeper Lattice integration.
#
# Lattice is an optional local SQLite evidence ledger. The standalone Python
# tool owns schema, import/export, recovery, and query behavior; this module only
# handles wrapper lifecycle hooks and optional/required failure policy.

lattice_enabled() {
  [[ "${UPKEEPER_LATTICE_ENABLED:-1}" == "1" ]]
}

lattice_required() {
  [[ "${UPKEEPER_LATTICE_REQUIRED:-0}" == "1" ]]
}

lattice_tool_path() {
  printf '%s/tools/upkeeper_lattice.py' "$UPKEEPER_IMPLEMENTATION_DIR"
}

lattice_degraded_owner_issue() {
  printf '%s\n' "430"
}

lattice_degraded_owner_contract() {
  printf '%s\n' "advisory_lattice_degraded"
}

lattice_replacement_evidence_class() {
  printf '%s\n' "local_logs_runtime_obligations"
}

lattice_unavailable_detail_summary() {
  local detail="$1"

  python3 - "$detail" <<'PY' 2>/dev/null || {
import hashlib
import json
import re
import sys

detail = sys.argv[1]
detail_bytes = len(detail.encode("utf-8", errors="replace"))
detail_sha256 = hashlib.sha256(detail.encode("utf-8", errors="replace")).hexdigest()


def token(value):
    value = re.sub(r"[^A-Za-z0-9_.:-]+", "_", str(value))[:96]
    return value or "empty"


parts = [
    f"detail_bytes={detail_bytes}",
    f"detail_sha256={detail_sha256}",
]
try:
    data = json.loads(detail)
except Exception:
    parts.append("format=text")
else:
    parts.append("format=json")
    if isinstance(data, dict) and data.get("status") is not None:
        parts.append(f"json_status={token(data.get('status'))}")
    checks = data.get("checks") if isinstance(data, dict) else None
    failed = []

    def walk(value, prefix):
        if isinstance(value, dict):
            if value.get("ok") is False:
                failed.append(prefix or "checks")
            for key, child in value.items():
                if key == "ok":
                    continue
                child_prefix = f"{prefix}.{key}" if prefix else str(key)
                walk(child, child_prefix)
        elif isinstance(value, list):
            for index, child in enumerate(value):
                walk(child, f"{prefix}.{index}" if prefix else str(index))

    if isinstance(checks, dict):
        walk(checks, "")
    parts.append(f"failed_check_count={len(failed)}")
    if failed:
        parts.append(f"first_failed_check={token(failed[0])}")
print(" ".join(parts))
PY
    local detail_bytes
    detail_bytes="$(printf '%s' "$detail" | wc -c | tr -d ' ')"
    printf 'detail_bytes=%s format=summary_failed\n' "${detail_bytes:-0}"
  }
}

lattice_unavailable_summary_field() {
  local summary="$1"
  local key="$2"

  python3 - "$summary" "$key" <<'PY' 2>/dev/null || true
import sys

summary, key = sys.argv[1:3]
prefix = f"{key}="
for part in summary.split():
    if part.startswith(prefix):
        print(part[len(prefix):])
        break
PY
}

lattice_warn_once() {
  local reason detail detail_summary detail_status first_failed_check
  local owner_issue owner_contract replacement_evidence

  if [[ "$#" -ge 2 ]]; then
    reason="$1"
    detail="$2"
  else
    reason="unclassified"
    detail="${1:-}"
  fi

  detail_summary="$(lattice_unavailable_detail_summary "$detail")"
  detail_status="$(lattice_unavailable_summary_field "$detail_summary" "json_status")"
  first_failed_check="$(lattice_unavailable_summary_field "$detail_summary" "first_failed_check")"
  owner_issue="$(lattice_degraded_owner_issue)"
  owner_contract="$(lattice_degraded_owner_contract)"
  replacement_evidence="$(lattice_replacement_evidence_class)"

  lattice_spool_unavailable_event \
    "$reason" \
    "$detail" \
    "$detail_summary" \
    "$detail_status" \
    "$first_failed_check" \
    "$owner_issue" \
    "$owner_contract" \
    "$replacement_evidence"
  [[ "${UPKEEPER_LATTICE_WARNED:-0}" == "1" ]] && return 0
  UPKEEPER_LATTICE_WARNED="1"
  log_line_parts "WARN" \
    "lattice.unavailable required=${UPKEEPER_LATTICE_REQUIRED:-0}" \
    " reason=$(shell_quote "$reason")" \
    " owner_issue=$(shell_quote "$owner_issue")" \
    " owner_contract=$(shell_quote "$owner_contract")" \
    " replacement_evidence=$(shell_quote "$replacement_evidence")" \
    " db=$(shell_quote "${UPKEEPER_LATTICE_DB:-}")" \
    " detail_status=$(shell_quote "${detail_status:-unknown}")" \
    " first_failed_check=$(shell_quote "${first_failed_check:-none}")" \
    " detail_summary=$(shell_quote "$detail_summary")" \
    " action=continue_without_lattice"
}

lattice_spool_unavailable_event() {
  local reason="$1"
  local detail="$2"
  local detail_summary="$3"
  local detail_status="$4"
  local first_failed_check="$5"
  local owner_issue="$6"
  local owner_contract="$7"
  local replacement_evidence="$8"
  local recovery_dir recovery_file

  recovery_dir="$ROOT_DIR/runtime/upkeeper-lattice/recovery"
  recovery_file="$recovery_dir/lattice-unavailable.jsonl"
  mkdir -p "$recovery_dir" 2>/dev/null || return 0
  chmod 700 "$ROOT_DIR/runtime/upkeeper-lattice" "$recovery_dir" 2>/dev/null || true
  python3 - "$recovery_file" \
    "$CYCLE_ID" \
    "$CYCLE_RUN_HASH" \
    "${UPKEEPER_LATTICE_DB:-}" \
    "$reason" \
    "$detail" \
    "$detail_summary" \
    "$detail_status" \
    "$first_failed_check" \
    "$owner_issue" \
    "$owner_contract" \
    "$replacement_evidence" <<'PY' 2>/dev/null || true
import json
import os
import sys
import time

(
    path,
    cycle_id,
    run_hash,
    db_path,
    reason,
    detail,
    detail_summary,
    detail_status,
    first_failed_check,
    owner_issue,
    owner_contract,
    replacement_evidence,
) = sys.argv[1:13]
row = {
    "schema_version": 1,
    "row_type": "lattice_unavailable",
    "row_version": 1,
    "logical_key": f"lattice_unavailable:{cycle_id}:{run_hash}:{int(time.time())}",
    "payload": {
        "cycle_id": cycle_id,
        "run_hash": run_hash,
        "db_path": db_path,
        "reason": reason,
        "detail_summary": detail_summary,
        "detail_status": detail_status,
        "first_failed_check": first_failed_check,
        "owner_issue": owner_issue,
        "owner_contract": owner_contract,
        "replacement_evidence": replacement_evidence,
        "detail": detail,
        "observed_epoch": int(time.time()),
    },
    "payload_sha256": "",
    "exported_epoch": int(time.time()),
}
encoded = json.dumps(row, sort_keys=True, separators=(",", ":"))
row["payload_sha256"] = __import__("hashlib").sha256(
    json.dumps(row["payload"], sort_keys=True, separators=(",", ":")).encode("utf-8")
).hexdigest()
with open(path, "a", encoding="utf-8") as handle:
    print(json.dumps(row, sort_keys=True, separators=(",", ":")), file=handle)
try:
    os.chmod(path, 0o600)
except OSError:
    pass
PY
}

lattice_common_args() {
  printf '%s\0' \
    "--root" "$ROOT_DIR" \
    "--db" "$UPKEEPER_LATTICE_DB" \
    "--journal-mode" "$UPKEEPER_LATTICE_SQLITE_JOURNAL_MODE"
}

lattice_service_enabled() {
  [[ "${UPKEEPER_LATTICE_SERVICE_ENABLED:-1}" == "1" ]]
}

lattice_command_timeout_seconds() {
  local value="${UPKEEPER_LATTICE_COMMAND_TIMEOUT_SECONDS:-30}"
  if [[ ! "$value" =~ ^[0-9]+$ || "$value" -lt 1 ]]; then
    value=30
  fi
  printf '%s\n' "$value"
}

lattice_timeout_kill_after_seconds() {
  local value="${UPKEEPER_LATTICE_TIMEOUT_KILL_AFTER_SECONDS:-2}"
  if [[ ! "$value" =~ ^[0-9]+$ || "$value" -gt 30 ]]; then
    value=2
  fi
  printf '%s\n' "$value"
}

lattice_command_kind() {
  local value="${1:-unknown}"
  if [[ "$value" =~ ^[A-Za-z0-9_-]+$ ]]; then
    printf '%s\n' "$value"
  else
    printf '%s\n' "unknown"
  fi
}

lattice_timeout_detail() {
  local command_kind transport timeout_seconds phase cleanup
  command_kind="$(lattice_command_kind "${1:-unknown}")"
  transport="$(lattice_command_kind "${2:-unknown}")"
  timeout_seconds="${3:-$(lattice_command_timeout_seconds)}"
  phase="$(lattice_command_kind "${4:-lattice_run}")"
  cleanup="$(lattice_command_kind "${5:-process_tree_term_kill}")"
  printf '{"status":"timeout","command":"%s","phase":"%s","transport":"%s","timeout_seconds":%s,"cleanup":"%s"}\n' \
    "$command_kind" "$phase" "$transport" "$timeout_seconds" "$cleanup"
}

lattice_log_timeout() {
  local command_kind="$1"
  local transport="$2"
  local timeout_seconds="$3"
  declare -F log_line >/dev/null 2>&1 || return 0
  log_line "WARN" \
    "lattice.timeout command=$(shell_quote "$command_kind") phase=lattice_run transport=$(shell_quote "$transport") timeout_seconds=$timeout_seconds cleanup=process_tree_term_kill required=${UPKEEPER_LATTICE_REQUIRED:-0} action=return_failure"
}

lattice_descendant_pids() {
  local root_pid="$1"
  local table parent child found
  local -a frontier=("$root_pid")
  local -a descendants=()

  table="$(ps -eo pid=,ppid= 2>/dev/null || true)"
  while [[ "${#frontier[@]}" -gt 0 ]]; do
    parent="${frontier[0]}"
    frontier=("${frontier[@]:1}")
    while read -r child found; do
      [[ -n "$child" && "$found" == "$parent" ]] || continue
      descendants+=("$child")
      frontier+=("$child")
    done <<<"$table"
  done
  printf '%s\n' "${descendants[@]}"
}

lattice_terminate_process_tree() {
  local root_pid="$1"
  local delay pid index
  local -a descendants=()

  [[ "$root_pid" =~ ^[0-9]+$ ]] || return 0
  mapfile -t descendants < <(lattice_descendant_pids "$root_pid")
  for ((index=${#descendants[@]} - 1; index >= 0; index--)); do
    pid="${descendants[$index]}"
    [[ -n "$pid" ]] && kill -TERM "$pid" 2>/dev/null || true
  done
  kill -TERM "$root_pid" 2>/dev/null || true
  delay="$(lattice_timeout_kill_after_seconds)"
  if [[ "$delay" -gt 0 ]]; then
    sleep "$delay"
  fi
  for ((index=${#descendants[@]} - 1; index >= 0; index--)); do
    pid="${descendants[$index]}"
    [[ -n "$pid" ]] && kill -KILL "$pid" 2>/dev/null || true
  done
  kill -KILL "$root_pid" 2>/dev/null || true
}

lattice_service_close_fd() {
  local fd="${1:-}"

  [[ "$fd" =~ ^[0-9]+$ ]] || return 0
  eval "exec ${fd}>&-" 2>/dev/null || eval "exec ${fd}<&-" 2>/dev/null || true
}

lattice_start_service() {
  local -a common_args=()

  lattice_service_enabled || return 1
  [[ "${UPKEEPER_LATTICE_SERVICE_ACTIVE:-0}" == "1" ]] && return 0
  mapfile -d '' -t common_args < <(lattice_common_args)

  coproc UPKEEPER_LATTICE_SERVICE {
    python3 "$(lattice_tool_path)" "${common_args[@]}" service
  }
  UPKEEPER_LATTICE_SERVICE_PID="$!"
  UPKEEPER_LATTICE_SERVICE_OUT_FD="${UPKEEPER_LATTICE_SERVICE[0]}"
  UPKEEPER_LATTICE_SERVICE_IN_FD="${UPKEEPER_LATTICE_SERVICE[1]}"
  UPKEEPER_LATTICE_SERVICE_ACTIVE="1"
  UPKEEPER_LATTICE_SERVICE_COMMAND_COUNT="0"
  log_line_parts "INFO" \
    "lattice.service.started pid=${UPKEEPER_LATTICE_SERVICE_PID:-unknown}" \
    " db=$(shell_quote "$UPKEEPER_LATTICE_DB")"
}

lattice_force_stop_service() {
  local service_pid="${UPKEEPER_LATTICE_SERVICE_PID:-}"

  if [[ "$service_pid" =~ ^[0-9]+$ ]] && kill -0 "$service_pid" 2>/dev/null; then
    lattice_terminate_process_tree "$service_pid"
  fi
  lattice_service_close_fd "${UPKEEPER_LATTICE_SERVICE_IN_FD:-}"
  lattice_service_close_fd "${UPKEEPER_LATTICE_SERVICE_OUT_FD:-}"
  if [[ "$service_pid" =~ ^[0-9]+$ ]]; then
    wait "$service_pid" 2>/dev/null || true
  fi
  UPKEEPER_LATTICE_SERVICE_ACTIVE="0"
  UPKEEPER_LATTICE_SERVICE_PID=""
  UPKEEPER_LATTICE_SERVICE_IN_FD=""
  UPKEEPER_LATTICE_SERVICE_OUT_FD=""
}

lattice_stop_service() {
  local rc_line output_line end_line command_count shutdown_ok=1

  [[ "${UPKEEPER_LATTICE_SERVICE_ACTIVE:-0}" == "1" ]] || return 0
  command_count="${UPKEEPER_LATTICE_SERVICE_COMMAND_COUNT:-0}"
  if [[ -n "${UPKEEPER_LATTICE_SERVICE_IN_FD:-}" && -n "${UPKEEPER_LATTICE_SERVICE_OUT_FD:-}" ]]; then
    printf 'SHUTDOWN\n' >&"${UPKEEPER_LATTICE_SERVICE_IN_FD}" 2>/dev/null || true
    IFS= read -r -t 2 rc_line <&"${UPKEEPER_LATTICE_SERVICE_OUT_FD}" 2>/dev/null || shutdown_ok=0
    IFS= read -r -t 1 output_line <&"${UPKEEPER_LATTICE_SERVICE_OUT_FD}" 2>/dev/null || shutdown_ok=0
    IFS= read -r -t 1 end_line <&"${UPKEEPER_LATTICE_SERVICE_OUT_FD}" 2>/dev/null || shutdown_ok=0
  fi
  if [[ "$shutdown_ok" != "1" ]]; then
    lattice_force_stop_service
  else
    lattice_service_close_fd "${UPKEEPER_LATTICE_SERVICE_IN_FD:-}"
    lattice_service_close_fd "${UPKEEPER_LATTICE_SERVICE_OUT_FD:-}"
    if [[ -n "${UPKEEPER_LATTICE_SERVICE_PID:-}" ]]; then
      wait "$UPKEEPER_LATTICE_SERVICE_PID" 2>/dev/null || true
    fi
    UPKEEPER_LATTICE_SERVICE_ACTIVE="0"
    UPKEEPER_LATTICE_SERVICE_PID=""
    UPKEEPER_LATTICE_SERVICE_IN_FD=""
    UPKEEPER_LATTICE_SERVICE_OUT_FD=""
  fi
  log_line_parts "INFO" \
    "lattice.service.stopped commands=$command_count" \
    " db=$(shell_quote "$UPKEEPER_LATTICE_DB")"
}

lattice_run_service() {
  local rc_line output_line end_line response_b64 rc read_rc timeout_seconds command_kind
  local in_fd out_fd

  LATTICE_SERVICE_PROTOCOL_OK="0"
  LATTICE_LAST_TIMEOUT="0"
  lattice_start_service || return 1
  in_fd="${UPKEEPER_LATTICE_SERVICE_IN_FD:-}"
  out_fd="${UPKEEPER_LATTICE_SERVICE_OUT_FD:-}"
  [[ "$in_fd" =~ ^[0-9]+$ && "$out_fd" =~ ^[0-9]+$ ]] || return 1

  printf 'CMD %d\n' "$#" >&"$in_fd" || return 1
  for arg in "$@"; do
    printf '%s\0' "$arg" >&"$in_fd" || return 1
  done

  timeout_seconds="$(lattice_command_timeout_seconds)"
  command_kind="$(lattice_command_kind "${1:-unknown}")"
  if IFS= read -r -t "$timeout_seconds" rc_line <&"$out_fd"; then
    read_rc=0
  else
    read_rc="$?"
  fi
  if [[ "$read_rc" -gt 128 ]]; then
    LATTICE_LAST_TIMEOUT="1"
    LATTICE_LAST_OUTPUT="$(lattice_timeout_detail "$command_kind" service "$timeout_seconds")"
    lattice_force_stop_service
    lattice_log_timeout "$command_kind" service "$timeout_seconds"
    return 124
  fi
  [[ "$read_rc" -eq 0 ]] || return 1
  IFS= read -r -t 2 output_line <&"$out_fd" || return 1
  IFS= read -r -t 2 end_line <&"$out_fd" || return 1
  [[ "$rc_line" =~ ^RC[[:space:]]+([0-9]+)$ ]] || return 1
  rc="${BASH_REMATCH[1]}"
  [[ "$output_line" == OUTPUT_B64\ * ]] || return 1
  [[ "$end_line" == "END" ]] || return 1
  response_b64="${output_line#OUTPUT_B64 }"
  LATTICE_LAST_OUTPUT="$(printf '%s' "$response_b64" | base64 --decode 2>/dev/null || true)"
  UPKEEPER_LATTICE_SERVICE_COMMAND_COUNT="$(( ${UPKEEPER_LATTICE_SERVICE_COMMAND_COUNT:-0} + 1 ))"
  LATTICE_SERVICE_PROTOCOL_OK="1"
  return "$rc"
}

lattice_run() {
  local output rc had_errexit=0 timeout_seconds kill_after command_kind
  local -a common_args=()

  LATTICE_LAST_TIMEOUT="0"

  if lattice_service_enabled; then
    case "$-" in
      *e*) had_errexit=1 ;;
    esac
    set +e
    lattice_run_service "$@"
    rc="$?"
    if [[ "$had_errexit" == "1" ]]; then
      set -e
    else
      set +e
    fi
    if [[ "$rc" -eq 0 ]]; then
      return 0
    fi
    if [[ "${LATTICE_LAST_TIMEOUT:-0}" == "1" ]]; then
      return 124
    fi
    if [[ "${LATTICE_SERVICE_PROTOCOL_OK:-0}" == "1" ]]; then
      return "$rc"
    fi
    output="${LATTICE_LAST_OUTPUT:-lattice_service_failed}"
    UPKEEPER_LATTICE_SERVICE_ENABLED="0"
    lattice_stop_service || true
    log_line "WARN" "lattice.service.fallback_to_cli rc=$rc detail=$(shell_quote "$output")"
    LATTICE_LAST_OUTPUT="$output"
  fi

  mapfile -d '' -t common_args < <(lattice_common_args)

  timeout_seconds="$(lattice_command_timeout_seconds)"
  kill_after="$(lattice_timeout_kill_after_seconds)"
  command_kind="$(lattice_command_kind "${1:-unknown}")"
  if ! command -v timeout >/dev/null 2>&1; then
    LATTICE_LAST_OUTPUT="{\"status\":\"timeout_unavailable\",\"command\":\"$command_kind\",\"phase\":\"lattice_run\"}"
    declare -F log_line >/dev/null 2>&1 &&
      log_line "ERROR" "lattice.timeout_unavailable command=$(shell_quote "$command_kind") phase=lattice_run action=refuse_unbounded_execution"
    return 127
  fi

  case "$-" in
    *e*) had_errexit=1 ;;
    *) had_errexit=0 ;;
  esac
  set +e
  output="$(timeout --kill-after="${kill_after}s" "$timeout_seconds" python3 "$(lattice_tool_path)" "${common_args[@]}" "$@" 2>&1)"
  rc=$?
  if [[ "$had_errexit" == "1" ]]; then
    set -e
  else
    set +e
  fi
  if [[ "$rc" -eq 124 ]]; then
    LATTICE_LAST_TIMEOUT="1"
    LATTICE_LAST_OUTPUT="$(lattice_timeout_detail "$command_kind" cli "$timeout_seconds")"
    lattice_log_timeout "$command_kind" cli "$timeout_seconds"
    return 124
  fi
  LATTICE_LAST_OUTPUT="$output"
  return "$rc"
}

lattice_init_and_doctor_or_exit() {
  local detail detail_summary failure_reason

  UPKEEPER_LATTICE_AVAILABLE="0"
  lattice_enabled || return 0

  if [[ ! -r "$(lattice_tool_path)" ]]; then
    detail="missing_lattice_tool:$(lattice_tool_path)"
    if lattice_required; then
      log_line "ERROR" "lattice.unavailable required=1 reason=missing_tool tool=$(shell_quote "$(lattice_tool_path)")"
      finish_cycle 3 LATTICE_UNAVAILABLE ERROR "codex_exec_started=0 reason=missing_tool tool=$(shell_quote "$(lattice_tool_path)")"
    fi
    lattice_warn_once "missing_tool" "$detail"
    return 0
  fi

  if ! lattice_run init; then
    detail="${LATTICE_LAST_OUTPUT:-init_failed}"
    failure_reason="init_failed"
    [[ "${LATTICE_LAST_TIMEOUT:-0}" == "1" ]] && failure_reason="init_timeout"
    if lattice_required; then
      detail_summary="$(lattice_unavailable_detail_summary "$detail")"
      log_line "ERROR" "lattice.unavailable required=1 reason=$failure_reason db=$(shell_quote "$UPKEEPER_LATTICE_DB") detail_summary=$(shell_quote "$detail_summary")"
      if [[ "${LATTICE_LAST_TIMEOUT:-0}" == "1" ]]; then
        finish_cycle 3 LATTICE_TIMEOUT ERROR "codex_exec_started=0 reason=$failure_reason detail_summary=$(shell_quote "$detail_summary")"
      fi
      finish_cycle 3 LATTICE_UNAVAILABLE ERROR "codex_exec_started=0 reason=$failure_reason detail_summary=$(shell_quote "$detail_summary")"
    fi
    lattice_warn_once "$failure_reason" "$detail"
    return 0
  fi

  if ! lattice_run doctor --fast; then
    detail="${LATTICE_LAST_OUTPUT:-doctor_failed}"
    failure_reason="doctor_failed"
    [[ "${LATTICE_LAST_TIMEOUT:-0}" == "1" ]] && failure_reason="doctor_timeout"
    if lattice_required; then
      detail_summary="$(lattice_unavailable_detail_summary "$detail")"
      log_line "ERROR" "lattice.unavailable required=1 reason=$failure_reason db=$(shell_quote "$UPKEEPER_LATTICE_DB") detail_summary=$(shell_quote "$detail_summary")"
      if [[ "${LATTICE_LAST_TIMEOUT:-0}" == "1" ]]; then
        finish_cycle 3 LATTICE_TIMEOUT ERROR "codex_exec_started=0 reason=$failure_reason detail_summary=$(shell_quote "$detail_summary")"
      fi
      finish_cycle 3 LATTICE_UNAVAILABLE ERROR "codex_exec_started=0 reason=$failure_reason detail_summary=$(shell_quote "$detail_summary")"
    fi
    lattice_warn_once "$failure_reason" "$detail"
    return 0
  fi

  UPKEEPER_LATTICE_AVAILABLE="1"
  log_line_parts "INFO" \
    "lattice.ready schema_version=1 db=$(shell_quote "$UPKEEPER_LATTICE_DB")" \
    " doctor_mode=fast" \
    " journal_mode=$UPKEEPER_LATTICE_SQLITE_JOURNAL_MODE" \
    " selection_mode=$(shell_quote "$UPKEEPER_LATTICE_SELECTION_MODE")" \
    " raw_storage=$(shell_quote "$UPKEEPER_LATTICE_RAW_STORAGE")"
}

lattice_record_cycle_start() {
  lattice_enabled || return 0
  [[ "${UPKEEPER_LATTICE_AVAILABLE:-0}" == "1" ]] || return 0

  if ! lattice_run record-cycle-start \
    --cycle-id "$CYCLE_ID" \
    --run-hash "$CYCLE_RUN_HASH" \
    --execution-origin "$CODEX_EXECUTION_ORIGIN" \
    --model "$CODEX_MODEL" \
    --effort "$CODEX_REASONING_EFFORT" \
    --mode "$CODEX_MODE_STRING" \
    --config-file "$UPKEEPER_CONFIG_SOURCE" \
    --dirty-path-count "$DIRTY_PATH_COUNT" \
    --dry-run "$UPKEEPER_DRY_RUN" \
    --parent-cycle-id "${CODEX_PARENT_CYCLE_ID:-}" \
    --child-cycle-id "${CODEX_SCREEN_FALLBACK_CHILD_ID:-}" \
    --fallback-trigger "${CODEX_FALLBACK_TRIGGER:-}"; then
    lattice_warn_once "record_cycle_start_failed" "${LATTICE_LAST_OUTPUT:-record_cycle_start_failed}"
  fi
}

lattice_record_preselect() {
  local selection_file="$1"
  local candidate_file="$2"

  lattice_enabled || return 0
  [[ "${UPKEEPER_LATTICE_AVAILABLE:-0}" == "1" ]] || return 0
  [[ -s "$selection_file" ]] || return 0

  if [[ -z "$candidate_file" ]]; then
    if candidate_file="$(run_mktemp lattice-candidates)"; then
      if lattice_run query selection-candidates --mode "$UPKEEPER_LATTICE_SELECTION_MODE" --format jsonl; then
        printf '%s\n' "$LATTICE_LAST_OUTPUT" >"$candidate_file"
      else
        if [[ "${LATTICE_LAST_TIMEOUT:-0}" == "1" ]]; then
          if lattice_required; then
            log_line "ERROR" "lattice.timeout command=selection-candidates phase=record_preselect timeout_seconds=$(lattice_command_timeout_seconds) required=1 action=fail_closed"
            finish_cycle 3 LATTICE_TIMEOUT ERROR "codex_exec_started=0 command=selection-candidates phase=record_preselect timeout_seconds=$(lattice_command_timeout_seconds)"
          fi
          lattice_warn_once "selection_candidates_timeout" "${LATTICE_LAST_OUTPUT:-selection_candidates_timeout}"
        fi
        candidate_file=""
      fi
    else
      candidate_file=""
    fi
  fi

  local -a args=(
    record-preselect
    --cycle-id "$CYCLE_ID"
    --run-hash "$CYCLE_RUN_HASH"
    --selection-file "$selection_file"
    --selection-mode "$UPKEEPER_LATTICE_SELECTION_MODE"
  )
  if [[ -n "$candidate_file" && -s "$candidate_file" ]]; then
    args+=(--candidate-file "$candidate_file")
  fi
  if ! lattice_run "${args[@]}"; then
    lattice_warn_once "record_preselect_failed" "${LATTICE_LAST_OUTPUT:-record_preselect_failed}"
  fi
}

lattice_record_pass_results() {
  local last_message_file="$1"
  local selected_path="$2"
  local planned_passes="${3:-}"

  lattice_enabled || return 0
  [[ "${UPKEEPER_LATTICE_AVAILABLE:-0}" == "1" ]] || return 0
  [[ -n "$last_message_file" && -f "$last_message_file" ]] || return 0
  if [[ -z "$planned_passes" ]]; then
    if ! lattice_prepare_planned_passes; then
      lattice_warn_once "planned_pass_projection_failed" "${LATTICE_LAST_OUTPUT:-planned_pass_projection_failed}"
      return 0
    fi
    planned_passes="$(lattice_planned_passes_csv)"
  fi

  if ! lattice_run record-pass-result \
    --cycle-id "$CYCLE_ID" \
    --run-hash "$CYCLE_RUN_HASH" \
    --from-file "$last_message_file" \
    --selected-path "$selected_path" \
    --planned-passes "$planned_passes"; then
    lattice_warn_once "record_pass_result_failed" "${LATTICE_LAST_OUTPUT:-record_pass_result_failed}"
  fi
}

lattice_prepare_planned_passes() {
  local prompt_pass="default" module output
  local -a args=(planned-passes)

  [[ "${CODEX_PROMPT_PASS:-}" == "all" ]] && prompt_pass="all"
  args+=(--prompt-pass "$prompt_pass")
  for module in "${CODEX_REVIEW_MODULES[@]}"; do
    args+=(--review-module "$module")
  done
  lattice_run "${args[@]}" || return $?
  output="${LATTICE_LAST_OUTPUT//$'\n'/}"
  output="${output//$'\r'/}"
  [[ "$output" =~ ^P[0-9]+(,P[0-9]+)*$ ]] || {
    LATTICE_LAST_OUTPUT="invalid planned-pass projection: $output"
    return 1
  }
  LATTICE_PLANNED_PASSES_CSV="$output"
}

lattice_planned_passes_csv() {
  printf '%s' "${LATTICE_PLANNED_PASSES_CSV:-}"
}

lattice_finish_retry_dir() {
  printf '%s/runtime/upkeeper-lattice/recovery/finish-retry\n' "$ROOT_DIR"
}

lattice_spool_finish_retry() {
  local failure_detail="$1"
  shift
  local recovery_dir spool_path

  recovery_dir="$(lattice_finish_retry_dir)"
  mkdir -p "$recovery_dir" 2>/dev/null || return 1
  chmod 700 "$ROOT_DIR/runtime/upkeeper-lattice" \
    "$ROOT_DIR/runtime/upkeeper-lattice/recovery" "$recovery_dir" 2>/dev/null || true
  spool_path="$(python3 - "$recovery_dir" "$CYCLE_ID" "$CYCLE_RUN_HASH" "$failure_detail" "$@" <<'PY'
import hashlib
import json
import os
import sys
import tempfile
import time
from pathlib import Path

recovery_dir = Path(sys.argv[1])
cycle_id, run_hash, failure_detail = sys.argv[2:5]
command_args = sys.argv[5:]
identity = hashlib.sha256(f"{cycle_id}\0{run_hash}".encode("utf-8", errors="replace")).hexdigest()[:24]
path = recovery_dir / f"finish-{identity}.json"
payload = {
    "schema": "upkeeper.lattice-finish-retry.v1",
    "status": "pending",
    "created_at_epoch": int(time.time()),
    "cycle_id": cycle_id,
    "run_hash": run_hash,
    "command": "record-cycle-finish",
    "command_args": command_args,
    "attempt_count": 2,
    "failure_detail": failure_detail,
}
fd, temp_name = tempfile.mkstemp(prefix=f".{path.name}.", dir=recovery_dir)
try:
    os.fchmod(fd, 0o600)
    with os.fdopen(fd, "w", encoding="utf-8") as handle:
        json.dump(payload, handle, sort_keys=True, separators=(",", ":"))
        handle.write("\n")
        handle.flush()
        os.fsync(handle.fileno())
    os.replace(temp_name, path)
    directory_fd = os.open(recovery_dir, os.O_RDONLY)
    try:
        os.fsync(directory_fd)
    finally:
        os.close(directory_fd)
except Exception:
    try:
        os.unlink(temp_name)
    except OSError:
        pass
    raise
print(path)
PY
)" || return 1
  [[ -n "$spool_path" && -f "$spool_path" ]] || return 1
  UPKEEPER_LATTICE_FINISH_SPOOL_PATH="$spool_path"
  printf '%s\n' "$spool_path"
}

lattice_clear_finish_retry_spool() {
  local spool_path="${UPKEEPER_LATTICE_FINISH_SPOOL_PATH:-}"
  local recovery_dir

  [[ -n "$spool_path" ]] || return 0
  recovery_dir="$(lattice_finish_retry_dir)"
  [[ "$spool_path" == "$recovery_dir"/finish-*.json ]] || return 1
  rm -f -- "$spool_path"
  UPKEEPER_LATTICE_FINISH_SPOOL_PATH=""
}

lattice_record_cycle_finish() {
  local exit_code="$1"
  local reason="$2"
  local level="$3"
  local status_marker="${4:-}"
  local codex_exit="${5:-}"
  local codex_started="${6:-0}"
  local selected_path="${7:-${RUN_SELECTED_REVIEW_PATH:-}}"

  lattice_enabled || return 0
  [[ "${UPKEEPER_LATTICE_AVAILABLE:-0}" == "1" ]] || return 0
  [[ "${UPKEEPER_LATTICE_FINISH_RECORDED:-0}" != "1" ]] || return 0

  local -a args=(
    record-cycle-finish
    --cycle-id "$CYCLE_ID"
    --run-hash "$CYCLE_RUN_HASH"
    --wrapper-exit "$exit_code"
    --finish-reason "$reason"
    --finish-level "$level"
    --codex-exec-started "$codex_started"
    --dry-run "$UPKEEPER_DRY_RUN"
    --selected-path "$selected_path"
    --log-path "$LOG_FILE"
  )
  if [[ -n "$status_marker" ]]; then
    args+=(--status-marker "$status_marker")
  fi
  if [[ -n "$codex_exit" && "$codex_exit" =~ ^-?[0-9]+$ ]]; then
    args+=(--codex-exit "$codex_exit")
  fi
  if [[ -n "${RUN_LAST_MESSAGE_FILE:-}" && -f "$RUN_LAST_MESSAGE_FILE" ]]; then
    args+=(--last-message-file "$RUN_LAST_MESSAGE_FILE")
  fi
  if [[ -n "${RUN_TRANSCRIPT_FILE:-}" ]]; then
    args+=(--transcript-path "$RUN_TRANSCRIPT_FILE")
  fi
  if [[ -n "${RUN_COMPILED_PROMPT_FILE:-}" ]]; then
    args+=(--compiled-prompt-path "$RUN_COMPILED_PROMPT_FILE")
  fi

  if lattice_run "${args[@]}"; then
    UPKEEPER_LATTICE_FINISH_RECORDED="1"
    lattice_clear_finish_retry_spool || true
    log_line "INFO" "lattice.finish.persisted attempt=initial cycle=$(shell_quote "$CYCLE_ID") run_hash=$(shell_quote "$CYCLE_RUN_HASH")"
    return 0
  fi

  local first_failure="${LATTICE_LAST_OUTPUT:-record_cycle_finish_failed}"
  log_line "WARN" "lattice.finish.retry attempt=2 reason=initial_write_failed cycle=$(shell_quote "$CYCLE_ID") run_hash=$(shell_quote "$CYCLE_RUN_HASH")"
  if lattice_run "${args[@]}"; then
    UPKEEPER_LATTICE_FINISH_RECORDED="1"
    lattice_clear_finish_retry_spool || true
    log_line "INFO" "lattice.finish.persisted attempt=retry cycle=$(shell_quote "$CYCLE_ID") run_hash=$(shell_quote "$CYCLE_RUN_HASH")"
    return 0
  fi

  local retry_failure="${LATTICE_LAST_OUTPUT:-record_cycle_finish_retry_failed}"
  local failure_summary spool_path
  failure_summary="$(lattice_unavailable_detail_summary "$retry_failure")"
  if spool_path="$(lattice_spool_finish_retry "$failure_summary" "${args[@]}")"; then
    UPKEEPER_LATTICE_FINISH_SPOOL_PATH="$spool_path"
    log_line "ERROR" "lattice.finish.spooled attempts=2 cycle=$(shell_quote "$CYCLE_ID") run_hash=$(shell_quote "$CYCLE_RUN_HASH") retry_path=$(shell_quote "$spool_path") action=retain_for_replay"
  else
    log_line "ERROR" "lattice.finish.spool_failed attempts=2 cycle=$(shell_quote "$CYCLE_ID") run_hash=$(shell_quote "$CYCLE_RUN_HASH") action=retain_local_log_evidence"
  fi
  lattice_warn_once "record_cycle_finish_failed" "$retry_failure"
  LATTICE_LAST_OUTPUT="$first_failure; retry=$retry_failure"
  return 1
}
