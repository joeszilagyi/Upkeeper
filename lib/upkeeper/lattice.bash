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

lattice_warn_once() {
  local detail="$1"

  lattice_spool_unavailable_event "$detail"
  [[ "${UPKEEPER_LATTICE_WARNED:-0}" == "1" ]] && return 0
  UPKEEPER_LATTICE_WARNED="1"
  log_line "WARN" "lattice.unavailable required=${UPKEEPER_LATTICE_REQUIRED:-0} db=$(shell_quote "${UPKEEPER_LATTICE_DB:-}") detail=$(shell_quote "$detail") action=continue_without_lattice"
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
  local detail

  UPKEEPER_LATTICE_AVAILABLE="0"
  lattice_enabled || return 0

  if [[ ! -r "$(lattice_tool_path)" ]]; then
    detail="missing_lattice_tool:$(lattice_tool_path)"
    if lattice_required; then
      log_line "ERROR" "lattice.unavailable required=1 reason=missing_tool tool=$(shell_quote "$(lattice_tool_path)")"
      finish_cycle 3 LATTICE_UNAVAILABLE ERROR "codex_exec_started=0 reason=missing_tool tool=$(shell_quote "$(lattice_tool_path)")"
    fi
    lattice_warn_once "$detail"
    return 0
  fi

  if ! lattice_run init; then
    detail="${LATTICE_LAST_OUTPUT:-init_failed}"
    if lattice_required; then
      log_line "ERROR" "lattice.unavailable required=1 reason=init_failed db=$(shell_quote "$UPKEEPER_LATTICE_DB") detail=$(shell_quote "$detail")"
      finish_cycle 3 LATTICE_UNAVAILABLE ERROR "codex_exec_started=0 reason=init_failed detail=$(shell_quote "$detail")"
    fi
    lattice_warn_once "$detail"
    return 0
  fi

  if ! lattice_run doctor; then
    detail="${LATTICE_LAST_OUTPUT:-doctor_failed}"
    if lattice_required; then
      log_line "ERROR" "lattice.unavailable required=1 reason=doctor_failed db=$(shell_quote "$UPKEEPER_LATTICE_DB") detail=$(shell_quote "$detail")"
      finish_cycle 3 LATTICE_UNAVAILABLE ERROR "codex_exec_started=0 reason=doctor_failed detail=$(shell_quote "$detail")"
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
