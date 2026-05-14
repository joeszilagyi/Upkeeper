# Codex I/O and CLI boundary helpers.
#
# This module is sourced by the root Upkeeper entrypoint after logging helpers
# are available. It owns Codex transcript capture, analyzer JSON-to-shell
# assignment bridges, per-cycle CLI flags, and command availability checks.
# Operator-facing flag changes must stay aligned with docs/scripts/upkeeper.md
# and lib/upkeeper/help_selection.bash.

GENIE_PROTOCOL_BLOCKED_COMMANDS=(gh curl wget hub)

upkeeper_bug_report_issue_write_allowed() {
  config_truthy "${UPKEEPER_ALLOW_GH_ISSUE_WRITE:-0}"
}

upkeeper_issue_fix_private_issue_body_to_model_allowed() {
  config_truthy "${UPKEEPER_ALLOW_PRIVATE_ISSUE_BODY_TO_MODEL:-0}"
}

issue_fix_log_hash() {
  local value="${1:-}"
  upkeeper_value_hmac issue "$value"
}

issue_fix_explicit_target_ineligible_reason() {
  local path="${1:-}"
  local abs_path

  case "$path" in
    ""|/*|../*|*/../*)
      printf 'outside_repository'
      return 0
      ;;
    .git|.git/*|runtime|runtime/*|Upkeeper.log|*.log|*.log.*|*.zip)
      printf 'excluded_runtime_or_log_target'
      return 0
      ;;
  esac

  abs_path="${ROOT_DIR:-$PWD}/$path"
  if [[ -L "$abs_path" ]]; then
    printf 'symlink_target'
    return 0
  fi
  if [[ ! -f "$abs_path" || ! -r "$abs_path" ]]; then
    printf 'missing_or_unreadable'
    return 0
  fi

  return 1
}

prepare_bug_report_draft_artifact() {
  local draft_root="${UPKEEPER_BUG_REPORT_DRAFT_DIR:-${ROOT_DIR:-$PWD}/runtime/upkeeper-bug-report-drafts}"

  upkeeper_bug_report_only_enabled || return 0
  mkdir -p -- "$draft_root" || return 1
  chmod 700 "$draft_root" 2>/dev/null || true
  RUN_BUG_REPORT_DRAFT_FILE="$draft_root/${CYCLE_ID}-${CYCLE_RUN_HASH}.md"
  log_line "INFO" "bug_report_only.draft.destination path=$(shell_quote "$RUN_BUG_REPORT_DRAFT_FILE") issue_write_allowed=$(truthy_as_int "${UPKEEPER_ALLOW_GH_ISSUE_WRITE:-0}")"
}

prepare_genie_protocol_env() {
  local command_name stub_path real_gh_bin

  ensure_run_tmp_dir
  RUN_GENIE_BIN_DIR="$RUN_TMP_DIR/genie-bin"
  RUN_GENIE_GH_CONFIG_DIR="$RUN_TMP_DIR/genie-gh-config"
  RUN_GENIE_REAL_GH_BIN=""
  mkdir -p -- "$RUN_GENIE_BIN_DIR" "$RUN_GENIE_GH_CONFIG_DIR"
  chmod 700 "$RUN_GENIE_BIN_DIR" "$RUN_GENIE_GH_CONFIG_DIR" 2>/dev/null || true
  real_gh_bin="$(command -v gh 2>/dev/null || true)"
  RUN_GENIE_REAL_GH_BIN="$real_gh_bin"

  for command_name in "${GENIE_PROTOCOL_BLOCKED_COMMANDS[@]}"; do
    stub_path="$RUN_GENIE_BIN_DIR/$command_name"
    if [[ ! -e "$stub_path" ]]; then
      if [[ "$command_name" == "gh" ]] && upkeeper_bug_report_only_enabled; then
        cat >"$stub_path" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

truthy() {
  case "${1,,}" in
    1|true|yes|on)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

real_gh="${UPKEEPER_REAL_GH_BIN:-}"
if [[ -z "$real_gh" || ! -x "$real_gh" ]]; then
  printf 'Upkeeper bug-report-only: real gh binary is unavailable; use the wrapper-owned local draft artifact instead.\n' >&2
  exit 126
fi

original_args=("$@")
cmd1="${1:-}"
cmd2="${2:-}"
allow_read=0
case "${cmd1}:${cmd2}" in
  auth:status|repo:view|label:list|issue:list|issue:view)
    allow_read=1
    ;;
  api:*)
    method="GET"
    has_write_payload=0
    shift
    while [[ $# -gt 0 ]]; do
      case "$1" in
        -X|--method)
          method="${2:-}"
          shift 2
          ;;
        --method=*)
          method="${1#*=}"
          shift
          ;;
        -f|--field|-F|--raw-field|--input)
          has_write_payload=1
          shift 2
          ;;
        --field=*|--raw-field=*|--input=*)
          has_write_payload=1
          shift
          ;;
        *)
          shift
          ;;
      esac
    done
    if [[ "${method^^}" == "GET" && "$has_write_payload" == "0" ]]; then
      allow_read=1
    fi
    ;;
esac

if [[ "$allow_read" == "1" ]]; then
  exec "$real_gh" "${original_args[@]}"
fi

if [[ "$cmd1" == "issue" && "$cmd2" == "create" ]]; then
  if ! truthy "${UPKEEPER_ALLOW_GH_ISSUE_WRITE:-0}"; then
    printf 'Upkeeper bug-report-only: gh issue create is blocked unless UPKEEPER_ALLOW_GH_ISSUE_WRITE=1; write the wrapper-owned local draft instead.\n' >&2
    exit 126
  fi
  visibility="$("$real_gh" repo view --json visibility --jq .visibility 2>/dev/null || printf 'unknown')"
  [[ -n "$visibility" ]] || visibility="unknown"
  printf 'Upkeeper bug-report-only: gh issue create allowed by UPKEEPER_ALLOW_GH_ISSUE_WRITE=1 repo_visibility=%s\n' "$visibility" >&2
  exec "$real_gh" "$@"
fi

printf 'Upkeeper bug-report-only: direct gh command is blocked for backend Codex; use read-only gh inspection or the wrapper-owned local draft artifact.\n' >&2
exit 126
EOF
      else
        cat >"$stub_path" <<'EOF'
#!/usr/bin/env bash
printf 'Upkeeper Genie Protocol: direct %s access is blocked for backend Codex; use wrapper-provided issue packets and local draft artifacts.\n' "${0##*/}" >&2
exit 126
EOF
      fi
      chmod 700 "$stub_path"
    fi
  done

  log_line "INFO" "genie_protocol.ready broker=wrapper github_direct=blocked bin_dir=$(shell_quote "$RUN_GENIE_BIN_DIR") gh_config_dir=$(shell_quote "$RUN_GENIE_GH_CONFIG_DIR") commands=$(IFS=,; printf '%s' "${GENIE_PROTOCOL_BLOCKED_COMMANDS[*]}")" >/dev/null
}

run_codex_exec_capture() {
  local label="$1"
  local transcript_file="$2"
  local stdin_file="$3"
  local codex_rc
  local tee_rc=0
  local filter_rc=0
  local -a pipe_status
  local -a genie_env
  shift 3

  prepare_genie_protocol_env
  genie_env=(
    env
    -u GITHUB_TOKEN
    -u GH_TOKEN
    -u GITHUB_PAT
    -u GH_ENTERPRISE_TOKEN
    -u GITHUB_ENTERPRISE_TOKEN
    -u CODEX_GITHUB_PERSONAL_ACCESS_TOKEN
    -u GITHUB_API_URL
    -u GITHUB_GRAPHQL_URL
    PATH="$RUN_GENIE_BIN_DIR:$PATH"
    UPKEEPER_REAL_GH_BIN="$RUN_GENIE_REAL_GH_BIN"
    GH_CONFIG_DIR="$RUN_GENIE_GH_CONFIG_DIR"
    GIT_TERMINAL_PROMPT=0
  )

  if terminal_wants_full_output; then
    "${genie_env[@]}" "$@" <"$stdin_file" 2>&1 | tee "$transcript_file"
    pipe_status=("${PIPESTATUS[@]}")
    codex_rc="${pipe_status[0]}"
    tee_rc="${pipe_status[1]}"
  else
    "${genie_env[@]}" "$@" <"$stdin_file" 2>&1 | tee "$transcript_file" | codex_live_output_filter "$label"
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
    5.5_xhigh|gpt-5.5_xhigh)
      CODEX_MODEL="gpt-5.5"
      CODEX_REASONING_EFFORT="xhigh"
      CODEX_MODEL_OVERRIDE_APPLIED="1"
      ;;
    5.3-codex-spark_xhigh|gpt-5.3-codex-spark_xhigh|spark_xhigh)
      CODEX_MODEL="gpt-5.3-codex-spark"
      CODEX_REASONING_EFFORT="xhigh"
      CODEX_MODEL_OVERRIDE_APPLIED="1"
      ;;
    *)
      die "unknown model override: $spec (supported: 5.5_xhigh, 5.3-codex-spark_xhigh)"
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
  config_truthy "${CODEX_ISSUE_FIX_NEXT:-0}" || [[ -n "${CODEX_ISSUE_FIX_REQUESTED_NUMBER:-}" ]]
}

set_issue_workflow_stage_or_die() {
  local stage="$1"

  case "$stage" in
    ""|comment|review|apply)
      CODEX_ISSUE_WORKFLOW_STAGE="$stage"
      ;;
    *)
      die "unknown issue workflow stage: $stage (supported: comment, review, apply)"
      ;;
  esac
}

upkeeper_issue_workflow_read_only_enabled() {
  case "${CODEX_ISSUE_WORKFLOW_STAGE:-}" in
    comment|review)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

upkeeper_backend_mode_args_for_current_stage() {
  if upkeeper_issue_workflow_read_only_enabled; then
    printf '%s\0' --sandbox read-only
    return 0
  fi

  printf '%s\0' "${CODEX_MODE_ARGS[@]}"
}

upkeeper_source_mutation_guard_enabled() {
  upkeeper_bug_report_only_enabled || upkeeper_issue_workflow_read_only_enabled
}

upkeeper_source_mutation_guard_mode() {
  if upkeeper_issue_workflow_read_only_enabled; then
    printf 'issue_%s' "$CODEX_ISSUE_WORKFLOW_STAGE"
  elif upkeeper_bug_report_only_enabled; then
    printf 'bug_report_only'
  else
    printf 'none'
  fi
}

upkeeper_issue_workflow_comment_stage_enabled() {
  case "${CODEX_ISSUE_WORKFLOW_STAGE:-}" in
    comment|review)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

upkeeper_issue_workflow_comment_prefix() {
  case "${CODEX_ISSUE_WORKFLOW_STAGE:-}" in
    comment)
      printf 'Upkeeper ChimneySweep proposal:'
      ;;
    review)
      printf 'Upkeeper ChimneySweep review:'
      ;;
    *)
      return 1
      ;;
  esac
}

upkeeper_issue_workflow_extract_comment_from_last_message() {
  local last_message_file="$1"
  local draft_file="$2"
  local prefix="$3"

  [[ -r "$last_message_file" ]] || return 1
  [[ -n "$draft_file" ]] || return 1

  python3 - "$last_message_file" "$draft_file" "$prefix" <<'PY'
import os
import pathlib
import sys

last_message = pathlib.Path(sys.argv[1])
draft_path = pathlib.Path(sys.argv[2])
prefix = sys.argv[3]
start = "UPKEEPER_ISSUE_COMMENT_DRAFT_START"
end = "UPKEEPER_ISSUE_COMMENT_DRAFT_END"

try:
    lines = last_message.read_text(encoding="utf-8", errors="replace").splitlines()
except OSError as exc:
    print(f"read_error:{exc}", file=sys.stderr)
    sys.exit(1)

blocks = []
current = None
for line in lines:
    if line == start:
        if current is not None:
            print("nested_start", file=sys.stderr)
            sys.exit(1)
        current = []
        continue
    if line == end:
        if current is None:
            print("end_without_start", file=sys.stderr)
            sys.exit(1)
        blocks.append(current)
        current = None
        continue
    if current is not None:
        current.append(line)

if current is not None:
    print("missing_end", file=sys.stderr)
    sys.exit(1)
if len(blocks) != 1:
    print(f"wrong_block_count:{len(blocks)}", file=sys.stderr)
    sys.exit(1)

body_lines = blocks[0]
while body_lines and body_lines[-1] == "":
    body_lines.pop()
body = "\n".join(body_lines).rstrip() + "\n"

if not body.strip():
    print("empty_body", file=sys.stderr)
    sys.exit(1)
first_line = body.splitlines()[0]
if first_line != prefix and not first_line.startswith(prefix + " "):
    print("wrong_prefix", file=sys.stderr)
    sys.exit(1)
if len(body.encode("utf-8", errors="replace")) > 65536:
    print("body_too_large", file=sys.stderr)
    sys.exit(1)
if "\0" in body:
    print("nul_byte", file=sys.stderr)
    sys.exit(1)

try:
    draft_path.parent.mkdir(parents=True, exist_ok=True)
    fd = os.open(str(draft_path), os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w", encoding="utf-8") as handle:
        handle.write(body)
    os.chmod(str(draft_path), 0o600)
except OSError as exc:
    print(f"write_error:{exc}", file=sys.stderr)
    sys.exit(1)
PY
}

upkeeper_issue_workflow_materialize_comment_draft() {
  local stage="${CODEX_ISSUE_WORKFLOW_STAGE:-}"
  local draft_file="${RUN_ISSUE_WORKFLOW_COMMENT_FILE:-}"
  local prefix output rc

  [[ -n "$draft_file" ]] || return 1
  if [[ -s "$draft_file" ]]; then
    return 0
  fi

  prefix="$(upkeeper_issue_workflow_comment_prefix)" || return 1
  if [[ -z "${RUN_LAST_MESSAGE_FILE:-}" || ! -r "$RUN_LAST_MESSAGE_FILE" ]]; then
    log_line "ERROR" "issue.workflow_comment.unavailable stage=$(shell_quote "$stage") number=$(shell_quote "${CODEX_ISSUE_FIX_NUMBER:-unknown}") path=$(shell_quote "$draft_file") reason=missing_last_message"
    return 1
  fi

  set +e
  output="$(upkeeper_issue_workflow_extract_comment_from_last_message "$RUN_LAST_MESSAGE_FILE" "$draft_file" "$prefix" 2>&1)"
  rc=$?
  set -e
  if [[ "$rc" -ne 0 ]]; then
    log_line "ERROR" "issue.workflow_comment.unavailable stage=$(shell_quote "$stage") number=$(shell_quote "${CODEX_ISSUE_FIX_NUMBER:-unknown}") path=$(shell_quote "$draft_file") reason=extract_failed detail=$(shell_quote "$output")"
    return 1
  fi

  log_line "INFO" "issue.workflow_comment.extracted stage=$(shell_quote "$stage") number=$(shell_quote "${CODEX_ISSUE_FIX_NUMBER:-unknown}") path=$(shell_quote "$draft_file") source=last_message_block"
  return 0
}

upkeeper_issue_workflow_post_comment() {
  local stage="${CODEX_ISSUE_WORKFLOW_STAGE:-}"
  local draft_file="${RUN_ISSUE_WORKFLOW_COMMENT_FILE:-}"
  local prefix first_line output rc

  upkeeper_issue_workflow_comment_stage_enabled || return 0

  if [[ -z "${CODEX_ISSUE_FIX_NUMBER:-}" || -z "$draft_file" ]]; then
    log_line "ERROR" "issue.workflow_comment.unavailable stage=$(shell_quote "$stage") number=$(shell_quote "${CODEX_ISSUE_FIX_NUMBER:-unknown}") reason=missing_context"
    return 1
  fi
  if ! upkeeper_issue_workflow_materialize_comment_draft; then
    log_line "ERROR" "issue.workflow_comment.unavailable stage=$(shell_quote "$stage") number=$(shell_quote "$CODEX_ISSUE_FIX_NUMBER") path=$(shell_quote "$draft_file") reason=missing_or_empty_draft"
    return 1
  fi

  prefix="$(upkeeper_issue_workflow_comment_prefix)" || return 1
  IFS= read -r first_line <"$draft_file" || first_line=""
  if [[ "$first_line" != "$prefix" && "$first_line" != "$prefix "* ]]; then
    log_line "ERROR" "issue.workflow_comment.unavailable stage=$(shell_quote "$stage") number=$(shell_quote "$CODEX_ISSUE_FIX_NUMBER") path=$(shell_quote "$draft_file") reason=wrong_prefix expected=$(shell_quote "$prefix")"
    return 1
  fi

  set +e
  output="$(gh issue comment "$CODEX_ISSUE_FIX_NUMBER" --body-file "$draft_file" 2>&1)"
  rc=$?
  set -e
  if [[ "$rc" -ne 0 ]]; then
    log_line "ERROR" "issue.workflow_comment.post_failed stage=$(shell_quote "$stage") number=$(shell_quote "$CODEX_ISSUE_FIX_NUMBER") path=$(shell_quote "$draft_file") exit=$rc detail=$(shell_quote "$output")"
    return 1
  fi

  log_line "INFO" "issue.workflow_comment.posted stage=$(shell_quote "$stage") number=$(shell_quote "$CODEX_ISSUE_FIX_NUMBER") path=$(shell_quote "$draft_file")"
  return 0
}

upkeeper_bug_report_extract_draft_from_last_message() {
  local last_message_file="$1"
  local draft_file="$2"

  [[ -r "$last_message_file" ]] || return 1
  [[ -n "$draft_file" ]] || return 1

  python3 - "$last_message_file" "$draft_file" <<'PY'
import os
import pathlib
import sys

last_message = pathlib.Path(sys.argv[1])
draft_path = pathlib.Path(sys.argv[2])
start = "UPKEEPER_BUG_REPORT_DRAFT_START"
end = "UPKEEPER_BUG_REPORT_DRAFT_END"

try:
    lines = last_message.read_text(encoding="utf-8", errors="replace").splitlines()
except OSError as exc:
    print(f"read_error:{exc}", file=sys.stderr)
    sys.exit(1)

blocks = []
current = None
for line in lines:
    if line == start:
      if current is not None:
        print("nested_start", file=sys.stderr)
        sys.exit(1)
      current = []
      continue
    if line == end:
      if current is None:
        print("end_without_start", file=sys.stderr)
        sys.exit(1)
      blocks.append(current)
      current = None
      continue
    if current is not None:
      current.append(line)

if current is not None:
    print("missing_end", file=sys.stderr)
    sys.exit(1)
if len(blocks) != 1:
    print(f"wrong_block_count:{len(blocks)}", file=sys.stderr)
    sys.exit(1)

body_lines = blocks[0]
while body_lines and body_lines[-1] == "":
    body_lines.pop()
while body_lines and body_lines[0] == "":
    body_lines.pop(0)
body = "\n".join(body_lines).rstrip() + "\n"

if not body.strip():
    print("empty_body", file=sys.stderr)
    sys.exit(1)
first_line = body.splitlines()[0]
if not first_line.startswith("Title: ") or not first_line[len("Title: "):].strip():
    print("missing_title", file=sys.stderr)
    sys.exit(1)
if len(body.encode("utf-8", errors="replace")) > 131072:
    print("body_too_large", file=sys.stderr)
    sys.exit(1)
if "\0" in body:
    print("nul_byte", file=sys.stderr)
    sys.exit(1)

try:
    draft_path.parent.mkdir(parents=True, exist_ok=True)
    fd = os.open(str(draft_path), os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w", encoding="utf-8") as handle:
        handle.write(body)
    os.chmod(str(draft_path), 0o600)
except OSError as exc:
    print(f"write_error:{exc}", file=sys.stderr)
    sys.exit(1)
PY
}

upkeeper_bug_report_materialize_draft() {
  local draft_file="${RUN_BUG_REPORT_DRAFT_FILE:-}"
  local output rc

  [[ -n "$draft_file" ]] || return 1
  if [[ -s "$draft_file" ]]; then
    return 0
  fi
  if [[ -z "${RUN_LAST_MESSAGE_FILE:-}" || ! -r "$RUN_LAST_MESSAGE_FILE" ]]; then
    log_line "ERROR" "bug_report_only.draft.unavailable path=$(shell_quote "$draft_file") reason=missing_last_message"
    return 1
  fi

  set +e
  output="$(upkeeper_bug_report_extract_draft_from_last_message "$RUN_LAST_MESSAGE_FILE" "$draft_file" 2>&1)"
  rc=$?
  set -e
  if [[ "$rc" -ne 0 ]]; then
    log_line "ERROR" "bug_report_only.draft.unavailable path=$(shell_quote "$draft_file") reason=extract_failed detail=$(shell_quote "$output")"
    return 1
  fi

  log_line "INFO" "bug_report_only.draft.extracted path=$(shell_quote "$draft_file") issue_write_allowed=$(truthy_as_int "${UPKEEPER_ALLOW_GH_ISSUE_WRITE:-0}")"
  return 0
}

upkeeper_bug_report_finalize() {
  local summary_json outcome

  upkeeper_bug_report_only_enabled || return 0
  summary_json="$(review_report_summary_json "${RUN_LAST_MESSAGE_FILE:-}" 2>/dev/null || true)"
  outcome="$(json_field "$summary_json" '.outcome' 2>/dev/null || printf '')"
  if [[ "$outcome" != "REVIEWED_AND_REPORTED" ]]; then
    return 0
  fi
  upkeeper_bug_report_materialize_draft
}

upkeeper_source_mutation_status_summary() {
  (
    set -o pipefail
    git status --porcelain=v1 --untracked-files=all 2>/dev/null |
      awk '
        {
          code = substr($0, 1, 2)
          if (code == "??") {
            counts["untracked"]++
          } else if (code != "") {
            counts["status:" code]++
          }
        }
        END {
          for (key in counts) {
            printf "%s=%d\n", key, counts[key]
          }
        }
      ' | sort
  )
}

upkeeper_source_mutation_hmac() {
  local key="${1:-}"

  python3 -c '
import hashlib
import hmac
import sys

key = sys.argv[1].encode("utf-8", "surrogateescape")
payload = sys.stdin.buffer.read()
print(hmac.new(key, payload, hashlib.sha256).hexdigest()[:24])
' "$key" 2>/dev/null || return 1
}

upkeeper_source_mutation_fingerprint() {
  local head_ref branch_ref index_tree hmac_key status_summary

  hmac_key="${CYCLE_RUN_HASH:-${CYCLE_ID:-upkeeper-source-mutation}}"
  status_summary="$(upkeeper_source_mutation_status_summary)" || return 1
  (
    set -o pipefail
    {
      printf 'tracked-diff\n'
      git diff --no-ext-diff --binary --
      printf '\nindexed-diff\n'
      git diff --cached --no-ext-diff --binary --
      printf '\nstatus-summary\n%s\n' "$status_summary"
      printf 'HEAD\n'
      if ! head_ref="$(git rev-parse --verify HEAD 2>/dev/null)"; then
        printf 'unknown'
      else
        printf '%s' "$head_ref"
      fi
      printf '\nbranch\n'
      if ! branch_ref="$(git symbolic-ref --short -q HEAD 2>/dev/null)"; then
        printf 'detached_or_missing'
      else
        printf '%s' "$branch_ref"
      fi
      printf '\nindex-tree\n'
      if ! index_tree="$(git write-tree 2>/dev/null)"; then
        printf 'unknown'
      else
        printf '%s' "$index_tree"
      fi
    } 2>/dev/null | upkeeper_source_mutation_hmac "$hmac_key"
  )
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
  local first_mode_token sandbox_mode extra_mode_token

  CODEX_MODE_ARGS=()
  if [[ -z "${CODEX_MODE_STRING:-}" ]]; then
    printf 'Upkeeper: invalid CODEX_MODE first token %q; expected a Codex option beginning with --\n' "${CODEX_MODE_STRING:-}" >&2
    exit 2
  fi
  read -r -a CODEX_MODE_ARGS <<<"$CODEX_MODE_STRING"
  first_mode_token="${CODEX_MODE_ARGS[0]:-}"
  sandbox_mode="${CODEX_MODE_ARGS[1]:-}"
  extra_mode_token="${CODEX_MODE_ARGS[2]:-}"

  if [[ "$first_mode_token" != --* || "$first_mode_token" == ---* ]]; then
    printf 'Upkeeper: invalid CODEX_MODE token %q; expected a Codex option beginning with --\n' "$first_mode_token" >&2
    exit 2
  fi
  case "$first_mode_token" in
    danger-full-access|--dangerously-bypass-approvals-and-sandbox)
      printf 'Upkeeper: invalid CODEX_MODE token %q; Genie Protocol requires sandboxed backend Codex execution\n' "$first_mode_token" >&2
      exit 2
      ;;
    --sandbox)
      ;;
    *)
      printf 'Upkeeper: invalid CODEX_MODE token %q; expected first token --sandbox\n' "$first_mode_token" >&2
      exit 2
      ;;
  esac

  if [[ -z "$sandbox_mode" ]]; then
    printf 'Upkeeper: invalid CODEX_MODE token --sandbox; expected a sandbox mode argument\n' >&2
    exit 2
  fi
  if [[ "$sandbox_mode" != workspace-write && "$sandbox_mode" != read-only ]]; then
    if [[ "$sandbox_mode" == danger-full-access || "$sandbox_mode" == --dangerously-bypass-approvals-and-sandbox ]]; then
      printf 'Upkeeper: invalid CODEX_MODE token %q; Genie Protocol requires sandboxed backend Codex execution\n' "$sandbox_mode" >&2
      exit 2
    fi
    printf 'Upkeeper: invalid CODEX_MODE token %q; expected a sandbox mode argument\n' "$sandbox_mode" >&2
    exit 2
  fi
  if [[ -n "$extra_mode_token" ]]; then
    if [[ "$extra_mode_token" == danger-full-access || "$extra_mode_token" == --dangerously-bypass-approvals-and-sandbox ]]; then
      printf 'Upkeeper: invalid CODEX_MODE token %q; Genie Protocol requires sandboxed backend Codex execution\n' "$extra_mode_token" >&2
      exit 2
    fi
    printf 'Upkeeper: invalid CODEX_MODE token %q; CODEX_MODE only supports --sandbox workspace-write or --sandbox read-only\n' "$extra_mode_token" >&2
    exit 2
  fi

  CODEX_MODE_ARGS=(--sandbox "$sandbox_mode")
  CODEX_MODE_SANDBOX="$sandbox_mode"
  CODEX_MODE_STRING="--sandbox $sandbox_mode"
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

  if [[ -n "${CODEX_ISSUE_WORKFLOW_STAGE:-}" ]]; then
    set_issue_workflow_stage_or_die "$CODEX_ISSUE_WORKFLOW_STAGE"
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
  local issue_event issue_json requested_number status target_from_issue title_hash url_hash ineligible_reason

  upkeeper_issue_fix_next_enabled || return 0
  requested_number="${CODEX_ISSUE_FIX_REQUESTED_NUMBER:-}"
  issue_event="issue.fix_next"
  [[ -n "$requested_number" ]] && issue_event="issue.fix_issue"

  if ! command -v gh >/dev/null 2>&1; then
    log_line "ERROR" "$issue_event unavailable reason=gh_missing"
    finish_cycle 3 ISSUE_FIX_GH_MISSING ERROR "codex_exec_started=0"
  fi

  set +e
  issue_json="$(
    python3 - "$ROOT_DIR" "${CODEX_ISSUE_PRIORITY_LABELS:-security,data-integrity,bug}" "${CODEX_ISSUE_SKIP_LABELS:-}" "$requested_number" <<'PY'
import json
import os
import re
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

root = Path(sys.argv[1]).resolve()
priority_labels = [item.strip() for item in sys.argv[2].split(",") if item.strip()]
skip_labels = {item.strip().lower() for item in sys.argv[3].split(",") if item.strip()}
requested_number = sys.argv[4].strip()


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


def parse_issue_timestamp(value):
    value_text = str(value or "").strip()
    if not value_text:
        return datetime.min.replace(tzinfo=timezone.utc)
    if value_text.endswith("Z"):
        value_text = f"{value_text[:-1]}+00:00"
    try:
        return datetime.fromisoformat(value_text).astimezone(timezone.utc)
    except (TypeError, ValueError):
        return datetime.min.replace(tzinfo=timezone.utc)


def normalize_candidate(raw):
    if not isinstance(raw, str):
        return ""
    candidate = raw.strip().strip("`'\"()[]{}<>.,;")
    if not candidate:
        return ""
    if any(ord(char) < 32 for char in candidate):
        return ""
    candidate = re.sub(r"(?::L?\d+(?:-L?\d+)?)$", "", candidate, flags=re.IGNORECASE)
    candidate = re.sub(r"#L?\d+(?:-L?\d+)?$", "", candidate, flags=re.IGNORECASE)
    candidate = candidate.strip().strip("`'\"()[]{}<>.,;")
    if not candidate or any(ord(char) < 32 for char in candidate):
        return ""

    if "\0" in candidate:
        return ""

    path = Path(os.path.expanduser(candidate))
    path_parts = path.as_posix().split("/")
    if any(part in ("", ".", "..") for part in path_parts):
        return ""
    if path.is_absolute():
        try:
            abs_path = path.resolve()
        except OSError:
            return ""
    else:
        abs_path = Path(root / path).resolve()

    if not abs_path.is_file():
        return ""

    try:
        rel = abs_path.relative_to(root)
    except ValueError:
        return ""
    rel_text = str(rel).replace(os.sep, "/")
    if rel_text in {"", "."} or rel_text.startswith("../") or "/../" in f"/{rel_text}/":
        return ""
    return rel_text


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


def emit_selected(issue, selected_label, body=None, comments=None):
    number = str(issue.get("number", ""))
    if body is None:
        body_data = gh_json(["issue", "view", number, "--json", "body,comments"])
        body = str(body_data.get("body", ""))
        comments = body_data.get("comments", []) if comments is None else comments
    if comments is None:
        comments = issue.get("comments", [])
    if not isinstance(comments, list):
        comments = []
    comment_texts = []
    for comment in comments:
        if isinstance(comment, str):
            comment_texts.append(comment)
            continue
        if isinstance(comment, dict):
            body_text = comment.get("body")
            if isinstance(body_text, str):
                comment_texts.append(body_text)
            else:
                url = comment.get("url")
                if isinstance(url, str):
                    comment_texts.append(url)
    combined = "\n".join([str(issue.get("title", "")), str(body), *comment_texts])
    target = next(candidate_paths(combined), "")
    label_names = [str(label.get("name", "")) for label in issue.get("labels", []) if label.get("name")]
    print(
        json.dumps(
            {
                "status": "ok",
                "number": number,
                "title": str(issue.get("title", "")),
                "url": str(issue.get("url", "")),
                "labels": ",".join(label_names),
                "selected_label": selected_label,
                "created_at": str(issue.get("createdAt", "")),
                "target_file": target,
                "body": body,
                "comments": comments,
            }
        )
    )


if requested_number:
    if not requested_number.isdigit():
        print(json.dumps({"status": "invalid_issue_number", "number": requested_number}))
        raise SystemExit(0)

    issue = gh_json(
        [
            "issue",
            "view",
            requested_number,
            "--json",
            "number,title,url,labels,createdAt,body,state,comments",
        ]
    )
    state = str(issue.get("state", "")).lower()
    if state and state != "open":
        print(json.dumps({"status": "not_open", "number": requested_number, "state": state}))
        raise SystemExit(0)
    emit_selected(issue, "explicit", str(issue.get("body", "")), issue.get("comments", []))
    raise SystemExit(0)


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
    candidates.sort(key=lambda issue: (parse_issue_timestamp(issue.get("createdAt", "")), int(issue.get("number", 0))))
    selected = candidates[0]
    emit_selected(selected, priority_label)
    raise SystemExit(0)

print(json.dumps({"status": "none"}))
PY
  )"
  local issue_rc=$?
  set -e

  if [[ "$issue_rc" -ne 0 ]]; then
    log_line "ERROR" "$issue_event select_failed rc=$issue_rc detail=$(shell_quote "$issue_json")"
    finish_cycle 3 ISSUE_FIX_SELECTION_FAILED ERROR "codex_exec_started=0"
  fi

  status="$(jq -r '.status // "unknown"' <<<"$issue_json")"
  case "$status" in
    ok)
      ;;
    none)
      log_line "INFO" "$issue_event none priority_labels=$(shell_quote "${CODEX_ISSUE_PRIORITY_LABELS:-none}") skip_labels=$(shell_quote "${CODEX_ISSUE_SKIP_LABELS:-none}")"
      finish_cycle 5 NO_ISSUE_FIX_TARGET INFO "codex_exec_started=0"
      ;;
    invalid_issue_number)
      log_line "ERROR" "$issue_event select_failed status=invalid_issue_number detail=$(shell_quote "$issue_json")"
      finish_cycle 3 ISSUE_FIX_SELECTION_FAILED ERROR "codex_exec_started=0"
      ;;
    *)
      log_line "ERROR" "$issue_event select_failed status=$(shell_quote "$status") detail=$(shell_quote "$issue_json")"
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
  CODEX_ISSUE_FIX_COMMENTS_JSON="$(jq -c '.comments // []' <<<"$issue_json")"
  title_hash="$(issue_fix_log_hash "${CODEX_ISSUE_FIX_TITLE:-}")"
  url_hash="$(issue_fix_log_hash "${CODEX_ISSUE_FIX_URL:-}")"

  if ! upkeeper_issue_fix_private_issue_body_to_model_allowed; then
    CODEX_ISSUE_FIX_TITLE=""
    CODEX_ISSUE_FIX_URL=""
    CODEX_ISSUE_FIX_BODY=""
    CODEX_ISSUE_FIX_COMMENTS_JSON="[]"
  fi

  target_from_issue="$CODEX_ISSUE_FIX_TARGET_FILE"
  if [[ -z "${CODEX_TARGET_FILE:-}" ]]; then
    if [[ "$CODEX_ISSUE_FIX_SELECTED_LABEL" == "explicit" && -n "$target_from_issue" ]]; then
      if ineligible_reason="$(issue_fix_explicit_target_ineligible_reason "$target_from_issue")"; then
        log_line "WARN" "issue_fix.target ignored reason=ineligible_explicit_issue_target number=$(shell_quote "$CODEX_ISSUE_FIX_NUMBER") target_file=$(shell_quote "$target_from_issue") detail=$(shell_quote "$ineligible_reason")"
      else
        CODEX_TARGET_FILE="$target_from_issue"
        log_line "INFO" "issue_fix.target file_selected_from_explicit_issue number=$(shell_quote "$CODEX_ISSUE_FIX_NUMBER") target_file=$(shell_quote "$CODEX_TARGET_FILE")"
      fi
    elif [[ -n "$target_from_issue" ]]; then
      log_line "WARN" "issue_fix.target ignored reason=untrusted_inferred_source selected_label=$(shell_quote "$CODEX_ISSUE_FIX_SELECTED_LABEL") inferred_file=$(shell_quote "$target_from_issue")"
    fi
  fi

  log_line "INFO" "$issue_event selected number=$(shell_quote "$CODEX_ISSUE_FIX_NUMBER") selected_label=$(shell_quote "$CODEX_ISSUE_FIX_SELECTED_LABEL") labels=$(shell_quote "$CODEX_ISSUE_FIX_LABELS") created_at=$(shell_quote "$CODEX_ISSUE_FIX_CREATED_AT") target_file=$(shell_quote "${CODEX_TARGET_FILE:-none}") inferred_target=$(shell_quote "${CODEX_ISSUE_FIX_TARGET_FILE:-none}") issue_packet_to_model=$(truthy_as_int "${UPKEEPER_ALLOW_PRIVATE_ISSUE_BODY_TO_MODEL:-0}") url_hash=$(shell_quote "$url_hash") title_hash=$(shell_quote "$title_hash")"
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
        die "use --model-override=5.5_xhigh or --model-override=5.3-codex-spark_xhigh (spaced form is intentionally unsupported)"
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
        CODEX_ISSUE_FIX_REQUESTED_NUMBER=""
        shift
        ;;
      --fix-next-issue|--fix-oldest-bug)
        CODEX_ISSUE_FIX_NEXT="1"
        CODEX_ISSUE_FIX_REQUESTED_NUMBER=""
        CODEX_BUG_REPORT_ONLY="0"
        shift
        ;;
      --issue-workflow-stage=*)
        set_issue_workflow_stage_or_die "${1#--issue-workflow-stage=}"
        shift
        ;;
      --issue-workflow-stage)
        die "use --issue-workflow-stage=comment, --issue-workflow-stage=review, or --issue-workflow-stage=apply (spaced form is intentionally unsupported)"
        ;;
      --fix-issue=*)
        CODEX_ISSUE_FIX_REQUESTED_NUMBER="${1#--fix-issue=}"
        [[ "$CODEX_ISSUE_FIX_REQUESTED_NUMBER" =~ ^[0-9]+$ ]] || die "--fix-issue requires a numeric issue number"
        CODEX_ISSUE_FIX_NEXT="1"
        CODEX_BUG_REPORT_ONLY="0"
        shift
        ;;
      --fix-issue)
        die "use --fix-issue=NUMBER (spaced form is intentionally unsupported)"
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
  for cmd in awk cat chmod cut date df env find git grep jq ln mkdir mktemp mv ps python3 rm rmdir sed sort tail tee tr wc; do
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
  local prompt_trust_root="${UPKEEPER_PROMPT_TRUST_ROOT:-$ROOT_DIR/prompts}"
  local allow_external_prompt="${UPKEEPER_ALLOW_EXTERNAL_PROMPT_FILE:-0}"

  if [[ -n "$PROMPT_FILE" && -n "$INLINE_PROMPT" ]]; then
    die "use either --prompt-file or --prompt, not both"
  fi
  if [[ -n "$PROMPT_FILE" ]]; then
    if upkeeper_value_has_control_chars "$PROMPT_FILE"; then
      die "prompt file path contains control characters"
    fi
    PROMPT_FILE="$(resolve_path "$PROMPT_FILE")"
    if upkeeper_value_has_control_chars "$PROMPT_FILE"; then
      die "resolved prompt file path contains control characters"
    fi
    if [[ "$UPKEEPER_AUTOMATION_LAUNCHER" != "$SCRIPT_NAME" ]]; then
      prompt_trust_root="$(resolve_path "$prompt_trust_root")"
      if upkeeper_value_has_control_chars "$prompt_trust_root"; then
        die "prompt trust root contains control characters"
      fi
      [[ -d "$prompt_trust_root" ]] || die "prompt trust root is not a directory: $prompt_trust_root"
      case "$PROMPT_FILE" in
        "$prompt_trust_root"|"$prompt_trust_root"/*)
          ;;
        *)
          if [[ "$allow_external_prompt" == "1" ]]; then
            log_line "WARN" "prompt_file_external_allowed execution_origin=$CODEX_EXECUTION_ORIGIN prompt_file=$(shell_quote "$PROMPT_FILE") trust_root=$(shell_quote "$prompt_trust_root") automation_launcher=$(shell_quote "${UPKEEPER_AUTOMATION_LAUNCHER:-$SCRIPT_NAME}")"
          else
            die "prompt file outside trust root; set UPKEEPER_ALLOW_EXTERNAL_PROMPT_FILE=1 to override: $PROMPT_FILE"
          fi
          ;;
      esac
    fi
    [[ -f "$PROMPT_FILE" ]] || die "prompt file not found: $PROMPT_FILE"
    [[ -r "$PROMPT_FILE" ]] || die "prompt file not readable: $PROMPT_FILE"
  fi
}
