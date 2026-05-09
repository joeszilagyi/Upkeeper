# Codex I/O and CLI boundary helpers.
#
# This module is sourced by the root Upkeeper entrypoint after logging helpers
# are available. It owns Codex transcript capture, analyzer JSON-to-shell
# assignment bridges, per-cycle CLI flags, and command availability checks.
# Operator-facing flag changes must stay aligned with docs/scripts/upkeeper.md
# and lib/upkeeper/help_selection.bash.

run_codex_exec_capture() {
  local label="$1"
  local transcript_file="$2"
  local stdin_file="$3"
  local codex_rc
  local tee_rc=0
  local filter_rc=0
  local -a pipe_status
  shift 3

  if terminal_wants_full_output; then
    "$@" <"$stdin_file" 2>&1 | tee "$transcript_file"
    pipe_status=("${PIPESTATUS[@]}")
    codex_rc="${pipe_status[0]}"
    tee_rc="${pipe_status[1]}"
  else
    "$@" <"$stdin_file" 2>&1 | tee "$transcript_file" | codex_live_output_filter "$label"
    pipe_status=("${PIPESTATUS[@]}")
    codex_rc="${pipe_status[0]}"
    tee_rc="${pipe_status[1]}"
    filter_rc="${pipe_status[2]}"
    emit_codex_transcript_summary "$label" "$transcript_file" "$codex_rc"
  fi

  if [[ "$tee_rc" -ne 0 ]]; then
    log_line "ERROR" "codex.transcript_capture_failed label=$label transcript=$(shell_quote "$transcript_file") tee_exit=$tee_rc codex_exit=$codex_rc" || true
    [[ "$codex_rc" -ne 0 ]] || return "$tee_rc"
  fi
  if [[ "$filter_rc" -ne 0 ]]; then
    log_line "WARN" "codex.live_output_filter_failed label=$label transcript=$(shell_quote "$transcript_file") filter_exit=$filter_rc codex_exit=$codex_rc" || true
  fi
  return "$codex_rc"
}

emit_assignment_failure_command() {
  local message="$1"

  printf 'die %q\n' "$message"
}

validate_assignment_prefix() {
  local prefix="$1"

  if [[ ! "$prefix" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
    emit_assignment_failure_command "invalid shell assignment prefix: $prefix"
    return 1
  fi
}

quota_json_assignments() {
  local json="$1"
  local prefix="$2"

  validate_assignment_prefix "$prefix" || return 1
  jq -r --arg prefix "$prefix" '
    def value($path; $fallback):
      (getpath($path) // $fallback | tostring);
    def assignment($name; $path; $fallback):
      "\($prefix)_\($name)=\((value($path; $fallback)) | @sh)";
    [
      assignment("error"; ["error"]; ""),
      assignment("ts"; ["snapshot", "event_timestamp"]; "unknown"),
      assignment("source"; ["snapshot", "source_path"]; "unknown"),
      assignment("model_hint"; ["snapshot", "model_hint"]; "unknown"),
      assignment("selection"; ["snapshot_selection"]; "unknown"),
      assignment("snapshot_is_current"; ["snapshot_is_current"]; "false"),
      assignment("matching_snapshot_count"; ["matching_snapshot_count"]; "0"),
      assignment("snapshot_age_seconds"; ["snapshot", "snapshot_age_seconds"]; "unknown"),
      assignment("primary_reset_age_seconds"; ["snapshot", "primary_reset_age_seconds"]; "unknown"),
      assignment("secondary_reset_age_seconds"; ["snapshot", "secondary_reset_age_seconds"]; "unknown"),
      assignment("snapshot_stale_after_reset"; ["snapshot", "snapshot_stale_after_reset"]; "false"),
      assignment("primary_reset_expired"; ["snapshot", "primary_reset_expired"]; "false"),
      assignment("secondary_reset_expired"; ["snapshot", "secondary_reset_expired"]; "false"),
      assignment("primary_bucket_current"; ["snapshot", "primary_bucket_current"]; "false"),
      assignment("secondary_bucket_current"; ["snapshot", "secondary_bucket_current"]; "false"),
      assignment("primary_used"; ["snapshot", "primary_used_percent"]; ""),
      assignment("primary_window"; ["snapshot", "primary_window_minutes"]; ""),
      assignment("primary_reset"; ["snapshot", "primary_resets_at"]; ""),
      assignment("secondary_used"; ["snapshot", "secondary_used_percent"]; ""),
      assignment("secondary_window"; ["snapshot", "secondary_window_minutes"]; ""),
      assignment("secondary_reset"; ["snapshot", "secondary_resets_at"]; ""),
      assignment("plan_type"; ["snapshot", "plan_type"]; "unknown"),
      assignment("limit_id"; ["snapshot", "limit_id"]; "unknown"),
      assignment("limit_name"; ["snapshot", "limit_name"]; "unknown"),
      assignment("projected_primary_delta"; ["projection", "primary_delta"]; ""),
      assignment("projected_secondary_delta"; ["projection", "secondary_delta"]; ""),
      assignment("projected_basis"; ["projection", "basis"]; "unknown")
    ] | .[]
  ' <<<"$json" || {
    emit_assignment_failure_command "invalid quota snapshot JSON for shell assignment prefix: $prefix"
    return 1
  }
}

status_marker_analysis_assignments() {
  local json="$1"
  local prefix="$2"

  validate_assignment_prefix "$prefix" || return 1
  jq -r --arg prefix "$prefix" '
    def value($path; $fallback):
      (getpath($path) // $fallback | tostring);
    def assignment($name; $path; $fallback):
      "\($prefix)_\($name)=\((value($path; $fallback)) | @sh)";
    [
      assignment("candidate_line"; ["candidate_line"]; ""),
      assignment("candidate_marker"; ["candidate_marker"]; ""),
      assignment("candidate_rejection_reason"; ["candidate_rejection_reason"]; ""),
      assignment("accepted_marker"; ["accepted_marker"]; "")
    ] | .[]
  ' <<<"$json" || {
    emit_assignment_failure_command "invalid status marker analysis JSON for shell assignment prefix: $prefix"
    return 1
  }
}

session_diagnostics_assignments() {
  local json="$1"
  local prefix="$2"

  validate_assignment_prefix "$prefix" || return 1
  jq -r --arg prefix "$prefix" '
    def value($path; $fallback):
      (getpath($path) // $fallback | tostring);
    def assignment($name; $path; $fallback):
      "\($prefix)_\($name)=\((value($path; $fallback)) | @sh)";
    [
      assignment("agent_message_count"; ["agent_message_count"]; "0"),
      assignment("tool_call_count"; ["tool_call_count"]; "0"),
      assignment("tool_result_count"; ["tool_result_count"]; "0"),
      assignment("task_complete_last_agent_message"; ["task_complete_last_agent_message"]; "missing"),
      assignment("last_rate_limit_reached_type"; ["last_rate_limit_reached_type"]; "unknown"),
      assignment("last_rate_limit_limit_id"; ["last_rate_limit_limit_id"]; "unknown"),
      assignment("last_rate_limit_limit_name"; ["last_rate_limit_limit_name"]; "unknown"),
      assignment("last_rate_limit_plan_type"; ["last_rate_limit_plan_type"]; "unknown"),
      assignment("last_rate_limit_primary_used_percent"; ["last_rate_limit_primary_used_percent"]; "unknown"),
      assignment("last_rate_limit_secondary_used_percent"; ["last_rate_limit_secondary_used_percent"]; "unknown")
    ] | .[]
  ' <<<"$json" || {
    emit_assignment_failure_command "invalid session diagnostics JSON for shell assignment prefix: $prefix"
    return 1
  }
}

review_summary_assignments() {
  local json="$1"
  local prefix="$2"

  validate_assignment_prefix "$prefix" || return 1
  jq -r --arg prefix "$prefix" '
    def value($path; $fallback):
      (getpath($path) // $fallback | tostring);
    def assignment($name; $path; $fallback):
      "\($prefix)_\($name)=\((value($path; $fallback)) | @sh)";
    [
      assignment("outcome"; ["outcome"]; ""),
      assignment("selected_file"; ["selected_file"]; ""),
      assignment("findings"; ["findings"]; ""),
      assignment("changes"; ["changes"]; ""),
      assignment("verification"; ["verification"]; "")
    ] | .[]
  ' <<<"$json" || {
    emit_assignment_failure_command "invalid review summary JSON for shell assignment prefix: $prefix"
    return 1
  }
}

review_pass_coverage_assignments() {
  local json="$1"
  local prefix="$2"

  validate_assignment_prefix "$prefix" || return 1
  jq -r --arg prefix "$prefix" '
    def value($path; $fallback):
      (getpath($path) // $fallback | tostring);
    def assignment($name; $path; $fallback):
      "\($prefix)_\($name)=\((value($path; $fallback)) | @sh)";
    [
      assignment("status"; ["status"]; "unknown"),
      assignment("expected"; ["expected"]; "23"),
      assignment("present"; ["present"]; "0"),
      assignment("missing"; ["missing"]; "unknown")
    ] | .[]
  ' <<<"$json" || {
    emit_assignment_failure_command "invalid review pass coverage JSON for shell assignment prefix: $prefix"
    return 1
  }
}

resolve_path() {
  python3 -c 'import os, sys; print(os.path.realpath(os.path.expanduser(sys.argv[1])))' "$1"
}

apply_model_override() {
  local spec="$1"

  case "$spec" in
    5.5_xhigh)
      CODEX_MODEL="gpt-5.5"
      CODEX_REASONING_EFFORT="xhigh"
      CODEX_MODEL_OVERRIDE_APPLIED="1"
      ;;
    *)
      die "unknown model override: $spec (supported: 5.5_xhigh)"
      ;;
  esac
}

enable_max_cover_mode() {
  CODEX_MAX_COVER_MODE="1"
  UPKEEPER_LATTICE_SELECTION_MODE="max-cover"
  set_prompt_pass_or_die "all"
  add_review_modules_spec "p24,p25,p26,p27,p28,p29"
}

normalize_review_module() {
  local module="$1"

  module="$(printf '%s' "$module" | tr '[:upper:]_' '[:lower:]-')"
  case "$module" in
    p24|de-llm|de-llm-ing|dellm|de-llming)
      printf 'p24'
      ;;
    p25|contract|contract-intent|intent|design-intent|architecture|architecture-fitness)
      printf 'p25'
      ;;
    p26|docs|documentation|public-docs|public-documentation|doc-rigor|readability)
      printf 'p26'
      ;;
    p27|education|educational|educational-mode|teaching|teach|debrief|learning)
      printf 'p27'
      ;;
    p28|unit-test|unit-tests|unit-testing|test-harvest|test-harvesting|fixture-harvest|fixture-harvesting)
      printf 'p28'
      ;;
    p29|reuse|reuse-harvest|reuse-harvesting|reusable|library-reuse|function-reuse|asset-reuse|consolidation|extract-helper|helper-extraction)
      printf 'p29'
      ;;
    *)
      return 1
      ;;
  esac
}

add_review_module() {
  local raw_module="$1"
  local module existing

  [[ -n "$raw_module" ]] || die "--review-module requires a non-empty value"
  if ! module="$(normalize_review_module "$raw_module")"; then
    die "unknown review module: $raw_module (supported: p24, p25, p26, p27, p28, p29)"
  fi

  for existing in "${CODEX_REVIEW_MODULES[@]}"; do
    [[ "$existing" == "$module" ]] && return 0
  done
  CODEX_REVIEW_MODULES+=("$module")
}

add_review_modules_spec() {
  local spec="$1"
  local item
  local -a items=()

  [[ -n "$spec" ]] || die "--review-modules requires a non-empty value"
  IFS=, read -r -a items <<<"$spec"
  for item in "${items[@]}"; do
    item="${item#"${item%%[![:space:]]*}"}"
    item="${item%"${item##*[![:space:]]}"}"
    [[ -n "$item" ]] || die "--review-modules contains an empty value"
    add_review_module "$item"
  done
}

normalize_review_modules_spec_csv() {
  local spec="$1"
  local item module existing
  local -a items=()
  local -a modules=()

  [[ -n "$spec" ]] || die "review module filter requires a non-empty value"
  IFS=, read -r -a items <<<"$spec"
  for item in "${items[@]}"; do
    item="${item#"${item%%[![:space:]]*}"}"
    item="${item%"${item##*[![:space:]]}"}"
    [[ -n "$item" ]] || die "review module filter contains an empty value"
    if ! module="$(normalize_review_module "$item")"; then
      die "unknown review module filter: $item (supported: p24, p25, p26, p27, p28, p29)"
    fi
    for existing in "${modules[@]}"; do
      [[ "$existing" == "$module" ]] && continue 2
    done
    modules+=("$module")
  done

  local IFS=,
  printf '%s' "${modules[*]}"
}

review_modules_csv() {
  if [[ "${#CODEX_REVIEW_MODULES[@]}" -eq 0 ]]; then
    printf 'none'
    return 0
  fi

  local IFS=,
  printf '%s' "${CODEX_REVIEW_MODULES[*]}"
}

config_truthy() {
  local raw="$1"
  raw="${raw,,}"
  case "$raw" in
    1|true|yes|on)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

truthy_as_int() {
  if config_truthy "${1:-0}"; then
    printf '1'
  else
    printf '0'
  fi
}

upkeeper_bug_report_only_enabled() {
  config_truthy "${CODEX_BUG_REPORT_ONLY:-0}"
}

upkeeper_issue_fix_next_enabled() {
  config_truthy "${CODEX_ISSUE_FIX_NEXT:-0}"
}

upkeeper_source_mutation_fingerprint() {
  {
    printf 'tracked-diff\n'
    git diff --no-ext-diff --binary --
    printf '\nindexed-diff\n'
    git diff --cached --no-ext-diff --binary --
    printf '\nstatus\n'
    git status --porcelain=v1 --untracked-files=all
  } 2>/dev/null | git hash-object --stdin
}

append_csv_value() {
  local current="$1"
  local value="$2"

  [[ -n "$value" ]] || die "empty comma-list value"
  if [[ -n "$current" ]]; then
    printf '%s,%s' "$current" "$value"
  else
    printf '%s' "$value"
  fi
}

validate_codex_mode_args_or_exit() {
  CODEX_MODE_ARGS=()
  read -r -a CODEX_MODE_ARGS <<<"$CODEX_MODE_STRING"
  if [[ "${CODEX_MODE_ARGS[0]:-}" != --* || "${CODEX_MODE_ARGS[0]:-}" == ---* ]]; then
    printf 'Upkeeper: invalid CODEX_MODE first token %q; expected a Codex option beginning with --\n' "${CODEX_MODE_ARGS[0]:-}" >&2
    exit 2
  fi
}

set_prompt_pass_or_die() {
  local prompt_pass="$1"

  [[ -n "$prompt_pass" ]] || die "--prompt-pass requires a value"
  case "$prompt_pass" in
    all)
      CODEX_PROMPT_PASS="$prompt_pass"
      ;;
    *)
      die "unknown prompt pass: $prompt_pass (supported: all)"
      ;;
  esac
}

reset_config_review_modules_for_cli_override() {
  if [[ "$CODEX_REVIEW_MODULES_FROM_CONFIG" == "1" && "$CODEX_REVIEW_MODULES_CLI_OVERRIDE" != "1" ]]; then
    CODEX_REVIEW_MODULES=()
    CODEX_REVIEW_MODULES_CLI_OVERRIDE="1"
  fi
}

apply_configured_cli_defaults() {
  if [[ -n "${UPKEEPER_MODEL_OVERRIDE:-}" ]]; then
    CODEX_MODEL_OVERRIDE_SPEC="$UPKEEPER_MODEL_OVERRIDE"
    apply_model_override "$CODEX_MODEL_OVERRIDE_SPEC"
  fi

  if [[ -n "${UPKEEPER_REVIEW_MODULES:-}" ]]; then
    add_review_modules_spec "$UPKEEPER_REVIEW_MODULES"
    CODEX_REVIEW_MODULES_FROM_CONFIG="1"
  fi

  if [[ -n "${CODEX_PROMPT_PASS:-}" ]]; then
    set_prompt_pass_or_die "$CODEX_PROMPT_PASS"
  fi

  if config_truthy "${UPKEEPER_MAX_COVER:-0}"; then
    enable_max_cover_mode
  fi

  if config_truthy "${UPKEEPER_IGNORE_FAILURE_QUEUE:-0}"; then
    CODEX_TOOL_FAILURE_QUEUE_BYPASS="1"
  fi

  if [[ -n "${CODEX_SELECTION_REVIEW_MODULES:-}" ]]; then
    CODEX_SELECTION_REVIEW_MODULES="$(normalize_review_modules_spec_csv "$CODEX_SELECTION_REVIEW_MODULES")"
  fi

  if upkeeper_issue_fix_next_enabled; then
    CODEX_BUG_REPORT_ONLY="0"
  fi
}

resolve_issue_fix_next_or_exit() {
  local issue_json status target_from_issue

  upkeeper_issue_fix_next_enabled || return 0

  if ! command -v gh >/dev/null 2>&1; then
    log_line "ERROR" "issue.fix_next unavailable reason=gh_missing"
    finish_cycle 3 ISSUE_FIX_GH_MISSING ERROR "codex_exec_started=0"
  fi

  set +e
  issue_json="$(
    python3 - "$ROOT_DIR" "${CODEX_ISSUE_PRIORITY_LABELS:-security,data-integrity,bug}" "${CODEX_ISSUE_SKIP_LABELS:-}" <<'PY'
import json
import os
import re
import subprocess
import sys
from pathlib import Path

root = Path(sys.argv[1]).resolve()
priority_labels = [item.strip() for item in sys.argv[2].split(",") if item.strip()]
skip_labels = {item.strip().lower() for item in sys.argv[3].split(",") if item.strip()}


def gh_json(args):
    cp = subprocess.run(["gh", *args], text=True, capture_output=True, check=False)
    if cp.returncode != 0:
        print(json.dumps({"status": "gh_error", "stderr": cp.stderr.strip()}))
        raise SystemExit(2)
    try:
        return json.loads(cp.stdout or "[]")
    except json.JSONDecodeError as exc:
        print(json.dumps({"status": "gh_json_error", "error": str(exc)}))
        raise SystemExit(2)


def issue_label_names(issue):
    return [str(label.get("name", "")).lower() for label in issue.get("labels", []) if label.get("name")]


def skip_issue(issue):
    names = set(issue_label_names(issue))
    return bool(names & skip_labels)


def normalize_candidate(raw):
    candidate = raw.strip().strip("`'\"()[]{}<>.,;")
    if not candidate:
        return ""
    candidate = re.sub(r"(?::L?\d+(?:-L?\d+)?)$", "", candidate)
    candidate = re.sub(r"#L?\d+(?:-L?\d+)?$", "", candidate)
    candidate = candidate.strip().strip("`'\"()[]{}<>.,;")
    if not candidate:
        return ""
    path = Path(os.path.expanduser(candidate))
    if path.is_absolute():
        try:
            rel = path.resolve().relative_to(root)
        except (OSError, ValueError):
            return ""
    else:
        rel = Path(candidate)
    rel_text = str(rel).replace(os.sep, "/")
    if rel_text in {"", "."} or rel_text.startswith("../") or "/../" in f"/{rel_text}/":
        return ""
    abs_path = root / rel_text
    if abs_path.is_file():
        return rel_text
    return ""


def candidate_paths(text):
    seen = set()
    patterns = [
        r"`([^`\n]+)`",
        r"\[([^\]\n]+)\]\([^)\n]+\)",
        r"(?<![\w./-])((?:\.?/)?(?:Upkeeper|FlameOn|README\.md|AGENTS\.md|LICENSE|\.gitignore|Upkeeper\.conf|change_notes_2026\.md|[A-Za-z0-9_.+-]+/[A-Za-z0-9_./+@-]+))(?![\w./-])",
    ]
    for pattern in patterns:
        for match in re.finditer(pattern, text):
            groups = [group for group in match.groups() if group]
            raw = groups[0] if groups else match.group(0)
            normalized = normalize_candidate(raw)
            if normalized and normalized not in seen:
                seen.add(normalized)
                yield normalized


for priority_label in priority_labels:
    issues = gh_json(
        [
            "issue",
            "list",
            "--state",
            "open",
            "--label",
            priority_label,
            "--limit",
            "200",
            "--json",
            "number,title,url,labels,createdAt",
        ]
    )
    candidates = [issue for issue in issues if not skip_issue(issue)]
    if not candidates:
        continue
    candidates.sort(key=lambda issue: (str(issue.get("createdAt", "")), int(issue.get("number", 0))))
    selected = candidates[0]
    number = str(selected.get("number", ""))
    body_data = gh_json(["issue", "view", number, "--json", "body"])
    body = str(body_data.get("body", ""))
    combined = "\n".join([str(selected.get("title", "")), body])
    target = next(candidate_paths(combined), "")
    label_names = [str(label.get("name", "")) for label in selected.get("labels", []) if label.get("name")]
    print(
        json.dumps(
            {
                "status": "ok",
                "number": number,
                "title": str(selected.get("title", "")),
                "url": str(selected.get("url", "")),
                "labels": ",".join(label_names),
                "selected_label": priority_label,
                "created_at": str(selected.get("createdAt", "")),
                "target_file": target,
                "body": body,
            }
        )
    )
    raise SystemExit(0)

print(json.dumps({"status": "none"}))
PY
  )"
  local issue_rc=$?
  set -e

  if [[ "$issue_rc" -ne 0 ]]; then
    log_line "ERROR" "issue.fix_next select_failed rc=$issue_rc detail=$(shell_quote "$issue_json")"
    finish_cycle 3 ISSUE_FIX_SELECTION_FAILED ERROR "codex_exec_started=0"
  fi

  status="$(jq -r '.status // "unknown"' <<<"$issue_json")"
  case "$status" in
    ok)
      ;;
    none)
      log_line "INFO" "issue.fix_next none priority_labels=$(shell_quote "${CODEX_ISSUE_PRIORITY_LABELS:-none}") skip_labels=$(shell_quote "${CODEX_ISSUE_SKIP_LABELS:-none}")"
      finish_cycle 5 NO_ISSUE_FIX_TARGET INFO "codex_exec_started=0"
      ;;
    *)
      log_line "ERROR" "issue.fix_next select_failed status=$(shell_quote "$status") detail=$(shell_quote "$issue_json")"
      finish_cycle 3 ISSUE_FIX_SELECTION_FAILED ERROR "codex_exec_started=0"
      ;;
  esac

  CODEX_ISSUE_FIX_NUMBER="$(jq -r '.number // ""' <<<"$issue_json")"
  CODEX_ISSUE_FIX_TITLE="$(jq -r '.title // ""' <<<"$issue_json")"
  CODEX_ISSUE_FIX_URL="$(jq -r '.url // ""' <<<"$issue_json")"
  CODEX_ISSUE_FIX_LABELS="$(jq -r '.labels // ""' <<<"$issue_json")"
  CODEX_ISSUE_FIX_SELECTED_LABEL="$(jq -r '.selected_label // ""' <<<"$issue_json")"
  CODEX_ISSUE_FIX_CREATED_AT="$(jq -r '.created_at // ""' <<<"$issue_json")"
  CODEX_ISSUE_FIX_TARGET_FILE="$(jq -r '.target_file // ""' <<<"$issue_json")"
  CODEX_ISSUE_FIX_BODY="$(jq -r '.body // ""' <<<"$issue_json")"

  target_from_issue="$CODEX_ISSUE_FIX_TARGET_FILE"
  if [[ -z "${CODEX_TARGET_FILE:-}" ]]; then
    if [[ -n "$target_from_issue" ]]; then
      CODEX_TARGET_FILE="$target_from_issue"
    else
      CODEX_TARGET_FILE="Upkeeper"
    fi
  fi

  log_line "INFO" "issue.fix_next selected number=$(shell_quote "$CODEX_ISSUE_FIX_NUMBER") selected_label=$(shell_quote "$CODEX_ISSUE_FIX_SELECTED_LABEL") labels=$(shell_quote "$CODEX_ISSUE_FIX_LABELS") created_at=$(shell_quote "$CODEX_ISSUE_FIX_CREATED_AT") target_file=$(shell_quote "${CODEX_TARGET_FILE:-none}") inferred_target=$(shell_quote "${CODEX_ISSUE_FIX_TARGET_FILE:-none}") url=$(shell_quote "$CODEX_ISSUE_FIX_URL") title=$(shell_quote "$CODEX_ISSUE_FIX_TITLE")"
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --help|-h)
        show_help
        exit 0
        ;;
      --version)
        printf '%s %s\n' "$SCRIPT_NAME" "$UPKEEPER_VERSION"
        exit 0
        ;;
      --prompt-file)
        [[ $# -ge 2 ]] || die "--prompt-file requires a path"
        PROMPT_FILE="$2"
        INLINE_PROMPT=""
        [[ -n "$PROMPT_FILE" ]] || die "--prompt-file requires a non-empty path"
        shift 2
        ;;
      --prompt)
        [[ $# -ge 2 ]] || die "--prompt requires text"
        INLINE_PROMPT="$2"
        PROMPT_FILE=""
        [[ -n "$INLINE_PROMPT" ]] || die "--prompt requires non-empty text"
        shift 2
        ;;
      --config-file=*)
        shift
        ;;
      --config-file)
        die "use --config-file=PATH (spaced form is intentionally unsupported)"
        ;;
      --no-config)
        shift
        ;;
      --review-module=*)
        reset_config_review_modules_for_cli_override
        add_review_module "${1#--review-module=}"
        shift
        ;;
      --review-module)
        die "use --review-module=p24, --review-module=p25, --review-module=p26, --review-module=p27, --review-module=p28, or --review-module=p29 (spaced form is intentionally unsupported)"
        ;;
      --review-modules=*)
        reset_config_review_modules_for_cli_override
        add_review_modules_spec "${1#--review-modules=}"
        shift
        ;;
      --review-modules)
        die "use --review-modules=p24,p25,p26,p27,p28,p29 (spaced form is intentionally unsupported)"
        ;;
      --p24)
        reset_config_review_modules_for_cli_override
        add_review_module p24
        shift
        ;;
      --p25)
        reset_config_review_modules_for_cli_override
        add_review_module p25
        shift
        ;;
      --p26)
        reset_config_review_modules_for_cli_override
        add_review_module p26
        shift
        ;;
      --p27)
        reset_config_review_modules_for_cli_override
        add_review_module p27
        shift
        ;;
      --p28)
        reset_config_review_modules_for_cli_override
        add_review_module p28
        shift
        ;;
      --p29)
        reset_config_review_modules_for_cli_override
        add_review_module p29
        shift
        ;;
      --model-override=*)
        CODEX_MODEL_OVERRIDE_SPEC="${1#--model-override=}"
        [[ -n "$CODEX_MODEL_OVERRIDE_SPEC" ]] || die "--model-override requires a value"
        apply_model_override "$CODEX_MODEL_OVERRIDE_SPEC"
        shift
        ;;
      --model-override)
        die "use --model-override=5.5_xhigh (spaced form is intentionally unsupported)"
        ;;
      --target-file=*)
        CODEX_TARGET_FILE="${1#--target-file=}"
        [[ -n "$CODEX_TARGET_FILE" ]] || die "--target-file requires a value"
        shift
        ;;
      --target-file)
        die "use --target-file=PATH (spaced form is intentionally unsupported)"
        ;;
      --target-root=*|--target-dir=*)
        CODEX_TARGET_ROOT="${1#*=}"
        [[ -n "$CODEX_TARGET_ROOT" ]] || die "--target-root requires a value"
        shift
        ;;
      --target-root|--target-dir)
        die "use --target-root=PATH (spaced form is intentionally unsupported)"
        ;;
      --target-depth=*|--target-max-depth=*)
        CODEX_TARGET_MAX_DEPTH="${1#*=}"
        [[ -n "$CODEX_TARGET_MAX_DEPTH" ]] || die "--target-depth requires a value"
        shift
        ;;
      --target-depth|--target-max-depth)
        die "use --target-depth=N (spaced form is intentionally unsupported)"
        ;;
      --selection-source=*)
        CODEX_SELECTION_SOURCE="${1#--selection-source=}"
        [[ -n "$CODEX_SELECTION_SOURCE" ]] || die "--selection-source requires a value"
        shift
        ;;
      --selection-source)
        die "use --selection-source=manifest or --selection-source=enumerate (spaced form is intentionally unsupported)"
        ;;
      --selection-order=*)
        CODEX_SELECTION_ORDER="${1#--selection-order=}"
        [[ -n "$CODEX_SELECTION_ORDER" ]] || die "--selection-order requires a value"
        shift
        ;;
      --selection-order)
        die "use --selection-order=oldest|newest|random (spaced form is intentionally unsupported)"
        ;;
      --random-target)
        CODEX_SELECTION_ORDER="random"
        shift
        ;;
      --refresh-manifest)
        CODEX_FILE_MANIFEST_MODE="refresh"
        CODEX_SELECTION_SOURCE="manifest"
        shift
        ;;
      --manifest-file=*)
        CODEX_FILE_MANIFEST_PATH="${1#--manifest-file=}"
        [[ -n "$CODEX_FILE_MANIFEST_PATH" ]] || die "--manifest-file requires a value"
        shift
        ;;
      --manifest-file)
        die "use --manifest-file=PATH (spaced form is intentionally unsupported)"
        ;;
      --include-glob=*)
        CODEX_SELECTION_INCLUDE_GLOBS="$(append_csv_value "$CODEX_SELECTION_INCLUDE_GLOBS" "${1#--include-glob=}")"
        shift
        ;;
      --include-globs=*)
        CODEX_SELECTION_INCLUDE_GLOBS="${1#--include-globs=}"
        [[ -n "$CODEX_SELECTION_INCLUDE_GLOBS" ]] || die "--include-globs requires a value"
        shift
        ;;
      --include-glob|--include-globs)
        die "use --include-glob=PATTERN or --include-globs=a,b (spaced form is intentionally unsupported)"
        ;;
      --exclude-glob=*)
        CODEX_SELECTION_EXCLUDE_GLOBS="$(append_csv_value "$CODEX_SELECTION_EXCLUDE_GLOBS" "${1#--exclude-glob=}")"
        shift
        ;;
      --exclude-globs=*)
        CODEX_SELECTION_EXCLUDE_GLOBS="${1#--exclude-globs=}"
        [[ -n "$CODEX_SELECTION_EXCLUDE_GLOBS" ]] || die "--exclude-globs requires a value"
        shift
        ;;
      --exclude-glob|--exclude-globs)
        die "use --exclude-glob=PATTERN or --exclude-globs=a,b (spaced form is intentionally unsupported)"
        ;;
      --selection-review-modules=*)
        CODEX_SELECTION_REVIEW_MODULES="$(normalize_review_modules_spec_csv "${1#--selection-review-modules=}")"
        shift
        ;;
      --selection-review-modules)
        die "use --selection-review-modules=p24,p25,p26,p27,p28,p29 (spaced form is intentionally unsupported)"
        ;;
      --max-cover)
        enable_max_cover_mode
        shift
        ;;
      --bug-report-only|--file-bug-only|--report-bug-only)
        CODEX_BUG_REPORT_ONLY="1"
        CODEX_ISSUE_FIX_NEXT="0"
        shift
        ;;
      --fix-next-issue|--fix-oldest-bug)
        CODEX_ISSUE_FIX_NEXT="1"
        CODEX_BUG_REPORT_ONLY="0"
        shift
        ;;
      --backup-queue|-backup_queue)
        CODEX_TOOL_FAILURE_QUEUE_DIR="$ROOT_DIR/runtime/unaddressed-tool-failures-backup"
        CODEX_TOOL_FAILURE_QUEUE_BYPASS="0"
        shift
        ;;
      --ignore-failure-queue|--bypass-failure-queue)
        CODEX_TOOL_FAILURE_QUEUE_BYPASS="1"
        shift
        ;;
      --prompt-pass=*)
        set_prompt_pass_or_die "${1#--prompt-pass=}"
        shift
        ;;
      --prompt-pass)
        die "use --prompt-pass=all (spaced form is intentionally unsupported)"
        ;;
      *)
        die "unknown argument: $1"
        ;;
    esac
  done
}

require_commands() {
  local missing=0
  local cmd
  for cmd in awk cat cut date df find git grep jq ln mkdir mktemp mv ps python3 rm rmdir sed sort tail tee tr; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      log_line "ERROR" "required command missing: $cmd"
      missing=1
    fi
  done

  if ! command -v codex >/dev/null 2>&1; then
    if [[ "$UPKEEPER_DRY_RUN" == "1" ]]; then
      log_line "WARN" "optional command missing: codex dry_run=1"
    else
      log_line "ERROR" "required command missing: codex dry_run=0"
      missing=1
    fi
  fi

  if upkeeper_issue_fix_next_enabled && ! command -v gh >/dev/null 2>&1; then
    log_line "ERROR" "required command missing: gh issue_fix_next=1"
    missing=1
  fi

  if [[ "$CODEX_FALLBACK_ENABLED" == "1" && "$CODEX_FALLBACK_SCREEN_ENABLED" == "1" ]] && ! command -v screen >/dev/null 2>&1; then
    log_line "ERROR" "required command missing: screen fallback_screen_enabled=1"
    missing=1
  fi

  if [[ "$CODEX_LOG_ROTATE_AFTER_HOURS" != "0" ]] && ! command -v zip >/dev/null 2>&1; then
    log_line "WARN" "optional command missing: zip; wrapper log rotation disabled for this cycle"
    CODEX_LOG_ROTATE_AFTER_HOURS=0
  fi

  [[ "$missing" -eq 0 ]] || exit 3
}

resolve_prompt_file() {
  if [[ -n "$PROMPT_FILE" && -n "$INLINE_PROMPT" ]]; then
    die "use either --prompt-file or --prompt, not both"
  fi
  if [[ -n "$PROMPT_FILE" ]]; then
    PROMPT_FILE="$(resolve_path "$PROMPT_FILE")"
    [[ -f "$PROMPT_FILE" ]] || die "prompt file not found: $PROMPT_FILE"
    [[ -r "$PROMPT_FILE" ]] || die "prompt file not readable: $PROMPT_FILE"
  fi
}
