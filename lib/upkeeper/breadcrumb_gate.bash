# Startup gate for unresolved high-severity breadcrumb custody.

upkeeper_breadcrumb_gate_scan() {
  local state_root="${UPKEEPER_BREADCRUMB_STATE_DIR:-$ROOT_DIR/runtime/upkeeper-breadcrumbs}"
  local severities="${UPKEEPER_BREADCRUMB_GATE_SEVERITIES:-critical,high}"
  local target_file="${UPKEEPER_BREADCRUMB_GATE_TARGET:-Upkeeper}"

  python3 - "$state_root" "$severities" "$target_file" <<'PY'
import json
import sys
from pathlib import Path

state_root = Path(sys.argv[1])
blocking = {item.strip().lower() for item in sys.argv[2].split(",") if item.strip()}
target_file = sys.argv[3] or "Upkeeper"
open_dir = state_root / "open"


def emit(**fields: str) -> None:
    for key in sorted(fields):
        value = str(fields[key]).replace("\n", " ").replace("\r", " ")
        print(f"{key}={value}")


def read_json(path: Path) -> dict:
    try:
        with path.open("r", encoding="utf-8") as handle:
            data = json.load(handle)
    except (OSError, json.JSONDecodeError):
        return {}
    return data if isinstance(data, dict) else {}


if not open_dir.exists():
    emit(status="clean", open_count="0", blocking_count="0", target_file=target_file)
    raise SystemExit(0)

items: list[dict] = []
for path in sorted(open_dir.glob("*.json")):
    data = read_json(path)
    status = str(data.get("status") or "open").lower()
    if status not in {"open", "unresolved"}:
        continue
    severity = str(data.get("severity") or "").lower()
    if severity not in blocking:
        continue
    items.append(
        {
            "path": str(path),
            "id": str(data.get("id") or path.stem),
            "kind": str(data.get("kind") or "breadcrumb"),
            "severity": severity,
            "reason": str(data.get("reason") or data.get("summary") or "open breadcrumb requires review"),
        }
    )

if not items:
    emit(status="clean", open_count="0", blocking_count="0", target_file=target_file)
    raise SystemExit(0)

priority = {"critical": 0, "high": 1, "medium": 2, "low": 3}
items.sort(key=lambda item: (priority.get(item["severity"], 99), item["kind"], item["id"]))
selected = items[0]
emit(
    status="blocking",
    open_count=str(len(items)),
    blocking_count=str(len(items)),
    selected_id=selected["id"],
    selected_kind=selected["kind"],
    selected_path=selected["path"],
    selected_reason=selected["reason"],
    selected_severity=selected["severity"],
    target_file=target_file,
)
PY
}

enforce_breadcrumb_gate_or_exit() {
  local scan status target_file blocking_count selected_id selected_kind selected_severity selected_reason

  config_truthy "${UPKEEPER_BREADCRUMB_GATE_ENABLED:-1}" || return 0
  scan="$(upkeeper_breadcrumb_gate_scan)" || {
    log_line "ERROR" "breadcrumb.gate status=scan_failed state_root=$(shell_quote "${UPKEEPER_BREADCRUMB_STATE_DIR:-$ROOT_DIR/runtime/upkeeper-breadcrumbs}")"
    finish_cycle 7 BREADCRUMB_GATE_SCAN_FAILED ERROR "codex_exec_started=0"
  }
  status="$(upkeeper_preselect_output_field status "$scan")"
  [[ "$status" == "blocking" ]] || {
    log_line "INFO" "breadcrumb.gate status=clean state_root=$(shell_quote "${UPKEEPER_BREADCRUMB_STATE_DIR:-$ROOT_DIR/runtime/upkeeper-breadcrumbs}")"
    return 0
  }

  target_file="$(upkeeper_preselect_output_field target_file "$scan")"
  blocking_count="$(upkeeper_preselect_output_field blocking_count "$scan")"
  selected_id="$(upkeeper_preselect_output_field selected_id "$scan")"
  selected_kind="$(upkeeper_preselect_output_field selected_kind "$scan")"
  selected_severity="$(upkeeper_preselect_output_field selected_severity "$scan")"
  selected_reason="$(upkeeper_preselect_output_field selected_reason "$scan")"
  target_file="${target_file:-Upkeeper}"

  if [[ -n "${CODEX_TARGET_FILE:-}" ]]; then
    log_line_parts "WARN" \
      "breadcrumb.gate status=blocking action=target_already_pinned" \
      " blocking_count=${blocking_count:-0}" \
      " selected_id=$(shell_quote "${selected_id:-unknown}")" \
      " selected_kind=$(shell_quote "${selected_kind:-unknown}")" \
      " selected_severity=$(shell_quote "${selected_severity:-unknown}")" \
      " pinned_target=$(shell_quote "$CODEX_TARGET_FILE")" \
      " reason=$(shell_quote "${selected_reason:-unknown}")"
    return 0
  fi

  CODEX_TARGET_FILE="$target_file"
  log_line_parts "WARN" \
    "breadcrumb.gate status=blocking action=force_target" \
    " target_file=$(shell_quote "$CODEX_TARGET_FILE")" \
    " blocking_count=${blocking_count:-0}" \
    " selected_id=$(shell_quote "${selected_id:-unknown}")" \
    " selected_kind=$(shell_quote "${selected_kind:-unknown}")" \
    " selected_severity=$(shell_quote "${selected_severity:-unknown}")" \
    " reason=$(shell_quote "${selected_reason:-unknown}")"
}
