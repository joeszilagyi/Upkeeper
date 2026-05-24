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

lattice_unavailable_context() {
  local detail="$1"
  local db_path="${2:-}"
  local context reason_class

  if [[ -r "$(lattice_tool_path)" ]]; then
    if context="$(
      python3 "$(lattice_tool_path)" --root "$ROOT_DIR" classify-unavailable \
        --detail "$detail" \
        --db-path "$db_path" \
        --format log-fields 2>/dev/null
    )"; then
      printf '%s\n' "$context"
      return 0
    fi
  fi

  reason_class="unknown"
  case "${detail,,}" in
    *missing_lattice_tool*) reason_class="missing_tool" ;;
    *unsafe_db_path*|*"unsafe db path"*) reason_class="unsafe_db_path" ;;
    *"database is locked"*) reason_class="db_locked" ;;
    *"permission denied"*) reason_class="permission_denied" ;;
    *readonly*|*"read-only"*) reason_class="db_read_only" ;;
    *"unable to open database"*|*"db unavailable"*) reason_class="db_open_failed" ;;
    *schema_mismatch*) reason_class="schema_mismatch" ;;
    *integrity_failure*) reason_class="integrity_failure" ;;
  esac
  if [[ "$db_path" == *upkeeper-backlog-lattice* ]] && [[ "$reason_class" == db_* || "$reason_class" == missing_* || "$reason_class" == permission_denied ]]; then
    reason_class="backlog_lattice_${reason_class}"
  fi
  printf 'reason_class=%s owner_issue=430 doctrine=optional_degraded_local_recovery\n' "$reason_class"
}

lattice_warn_once() {
  local detail="$1"
  local detail_summary context

  lattice_spool_unavailable_event "$detail"
  [[ "${UPKEEPER_LATTICE_WARNED:-0}" == "1" ]] && return 0
  UPKEEPER_LATTICE_WARNED="1"
  detail_summary="$(lattice_unavailable_detail_summary "$detail")"
  context="$(lattice_unavailable_context "$detail" "${UPKEEPER_LATTICE_DB:-}")"
  log_line "WARN" "lattice.unavailable required=${UPKEEPER_LATTICE_REQUIRED:-0} $context db=$(shell_quote "${UPKEEPER_LATTICE_DB:-}") detail_summary=$(shell_quote "$detail_summary") action=continue_without_lattice"
}

lattice_spool_unavailable_event() {
  local detail="$1"
  local recovery_dir recovery_file

  recovery_dir="$ROOT_DIR/runtime/upkeeper-lattice/recovery"
  recovery_file="$recovery_dir/lattice-unavailable.jsonl"
  mkdir -p "$recovery_dir" 2>/dev/null || return 0
  chmod 700 "$ROOT_DIR/runtime/upkeeper-lattice" "$recovery_dir" 2>/dev/null || true
  python3 - "$recovery_file" \
    "$CYCLE_ID" \
    "$CYCLE_RUN_HASH" \
    "${UPKEEPER_LATTICE_DB:-}" \
    "$detail" <<'PY' 2>/dev/null || true
import json
import os
import sys
import time

path, cycle_id, run_hash, db_path, detail = sys.argv[1:6]
row = {
    "schema_version": 1,
    "row_type": "lattice_unavailable",
    "row_version": 1,
    "logical_key": f"lattice_unavailable:{cycle_id}:{run_hash}:{int(time.time())}",
    "payload": {
        "cycle_id": cycle_id,
        "run_hash": run_hash,
        "db_path": db_path,
        "detail": detail,
        "owner_issue": "430",
        "doctrine": "optional_degraded_local_recovery",
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

lattice_run() {
  local output rc
  local -a common_args=()
  mapfile -d '' -t common_args < <(lattice_common_args)

  set +e
  output="$(python3 "$(lattice_tool_path)" "${common_args[@]}" "$@" 2>&1)"
  rc=$?
  set -e
  LATTICE_LAST_OUTPUT="$output"
  return "$rc"
}

lattice_init_and_doctor_or_exit() {
  local detail detail_summary context

  UPKEEPER_LATTICE_AVAILABLE="0"
  lattice_enabled || return 0

  if [[ ! -r "$(lattice_tool_path)" ]]; then
    detail="missing_lattice_tool:$(lattice_tool_path)"
    if lattice_required; then
      context="$(lattice_unavailable_context "$detail" "${UPKEEPER_LATTICE_DB:-}")"
      log_line "ERROR" "lattice.unavailable required=1 reason=missing_tool $context tool=$(shell_quote "$(lattice_tool_path)")"
      finish_cycle 3 LATTICE_UNAVAILABLE ERROR "codex_exec_started=0 reason=missing_tool tool=$(shell_quote "$(lattice_tool_path)")"
    fi
    lattice_warn_once "$detail"
    return 0
  fi

  if ! lattice_run init; then
    detail="${LATTICE_LAST_OUTPUT:-init_failed}"
    if lattice_required; then
      detail_summary="$(lattice_unavailable_detail_summary "$detail")"
      context="$(lattice_unavailable_context "$detail" "$UPKEEPER_LATTICE_DB")"
      log_line "ERROR" "lattice.unavailable required=1 reason=init_failed $context db=$(shell_quote "$UPKEEPER_LATTICE_DB") detail_summary=$(shell_quote "$detail_summary")"
      finish_cycle 3 LATTICE_UNAVAILABLE ERROR "codex_exec_started=0 reason=init_failed detail_summary=$(shell_quote "$detail_summary")"
    fi
    lattice_warn_once "$detail"
    return 0
  fi

  if ! lattice_run doctor; then
    detail="${LATTICE_LAST_OUTPUT:-doctor_failed}"
    if lattice_required; then
      detail_summary="$(lattice_unavailable_detail_summary "$detail")"
      context="$(lattice_unavailable_context "$detail" "$UPKEEPER_LATTICE_DB")"
      log_line "ERROR" "lattice.unavailable required=1 reason=doctor_failed $context db=$(shell_quote "$UPKEEPER_LATTICE_DB") detail_summary=$(shell_quote "$detail_summary")"
      finish_cycle 3 LATTICE_UNAVAILABLE ERROR "codex_exec_started=0 reason=doctor_failed detail_summary=$(shell_quote "$detail_summary")"
    fi
    lattice_warn_once "$detail"
    return 0
  fi

  UPKEEPER_LATTICE_AVAILABLE="1"
  log_line "INFO" "lattice.ready schema_version=1 db=$(shell_quote "$UPKEEPER_LATTICE_DB") journal_mode=$UPKEEPER_LATTICE_SQLITE_JOURNAL_MODE selection_mode=$(shell_quote "$UPKEEPER_LATTICE_SELECTION_MODE") raw_storage=$(shell_quote "$UPKEEPER_LATTICE_RAW_STORAGE")"
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
    lattice_warn_once "${LATTICE_LAST_OUTPUT:-record_cycle_start_failed}"
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
    lattice_warn_once "${LATTICE_LAST_OUTPUT:-record_preselect_failed}"
  fi
}

lattice_record_pass_results() {
  local last_message_file="$1"
  local selected_path="$2"
  local planned_passes="$3"

  lattice_enabled || return 0
  [[ "${UPKEEPER_LATTICE_AVAILABLE:-0}" == "1" ]] || return 0
  [[ -n "$last_message_file" && -f "$last_message_file" ]] || return 0

  if ! lattice_run record-pass-result \
    --cycle-id "$CYCLE_ID" \
    --run-hash "$CYCLE_RUN_HASH" \
    --from-file "$last_message_file" \
    --selected-path "$selected_path" \
    --planned-passes "$planned_passes"; then
    lattice_warn_once "${LATTICE_LAST_OUTPUT:-record_pass_result_failed}"
  fi
}

lattice_planned_passes_csv() {
  local -a passes=()
  local module

  if [[ "${CODEX_PROMPT_PASS:-}" == "all" ]]; then
    passes=(P1 P2 P3 P4 P5 P6 P7 P8 P9 P10 P11 P12 P13 P14 P15 P16 P17 P18 P19 P20 P21 P22 P23)
  else
    # The default automatic rotation targets script/tool files, so this list
    # mirrors the default prompt's script/tool repertoire plus the always-on
    # P22 and the applicability-gated P23. Explicit non-script targets may
    # report not_applicable markers for the entries that do not fit.
    passes=(P1 P3 P4 P5 P6 P7 P9 P10 P11 P12 P13 P14 P15 P17 P18 P19 P20 P21 P22 P23)
  fi

  for module in "${CODEX_REVIEW_MODULES[@]}"; do
    case "$module" in
      p24) passes+=(P24) ;;
      p25) passes+=(P25) ;;
      p26) passes+=(P26) ;;
      p27) passes+=(P27) ;;
      p28) passes+=(P28) ;;
      p29) passes+=(P29) ;;
      p30) passes+=(P30) ;;
    esac
  done

  local IFS=,
  printf '%s' "${passes[*]}"
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
  UPKEEPER_LATTICE_FINISH_RECORDED="1"

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

  if ! lattice_run "${args[@]}"; then
    lattice_warn_once "${LATTICE_LAST_OUTPUT:-record_cycle_finish_failed}"
  fi
}
