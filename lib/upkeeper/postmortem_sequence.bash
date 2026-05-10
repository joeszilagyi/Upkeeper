# Postmortem sequence orchestration.
#
# The parent wrapper owns these phases after fallback because the useful
# evidence spans the failed primary handoff, fallback child, quota state, and
# local runtime checks. Documentation: lib/upkeeper/README.md and
# docs/scripts/upkeeper.md.

compile_postmortem_report_prompt() {
  local compiled_file="$1"
  local context_path="$2"
  local report_path="$3"

  cat >"$compiled_file" <<EOF
You are operating inside the git repository at $ROOT_DIR.

This is a post-mortem analysis pass for an Upkeeper incident.

What this run must do:
- read the incident context at $context_path
- inspect any referenced local files, logs, or session artifacts needed to understand the failure
- write or replace the markdown report at $report_path
- do not implement code changes in this phase except creating or updating the report file itself
- keep the report actionable, concrete, and specific to the local repo and wrapper behavior

Report requirements:
- use exactly these top-level headings in this order:
  1. # Upkeeper Postmortem
  2. ## Incident Summary
  3. ## Observed Signals
  4. ## Root Cause Hypotheses
  5. ## Action Plan
  6. ## Hardening Targets
  7. ## Relaunch Checklist
- under Action Plan, include flat checklist bullets with the smallest safe next actions first
- under Hardening Targets, call out wrapper/logging/prompt/guardrail fixes separately from repo-lane fixes when relevant

Response marker requirements:
- the final response must end with one marker line exactly as plain text
- do not wrap the marker in Markdown, backticks, a code fence, quotes, bullets, or trailing punctuation
- if the report file was written successfully, the final line must be exactly: CODEX_POSTMORTEM_STATUS: REPORT_WRITTEN
- if you are blocked, the final line must be exactly: CODEX_POSTMORTEM_STATUS: BLOCKED
EOF
}

compile_postmortem_hardening_prompt() {
  local compiled_file="$1"
  local context_path="$2"
  local report_path="$3"

  cat >"$compiled_file" <<EOF
You are operating inside the git repository at $ROOT_DIR.

This is the final hardening pass after an Upkeeper incident report.

What this run must do:
- read the incident context at $context_path
- read the post-mortem report at $report_path
- implement the smallest safe hardening change or coherent hardening slice that directly addresses the report
- prefer wrapper, logging, control-flow, guardrail, or prompt hardening first when the incident points there
- run focused validation for any changes you make
- update the same report file by appending or replacing a final section titled exactly:
  ## Hardening Outcome
- in that section include:
  - what changed
  - what validation ran
  - remaining risks or manual follow-up
- do not push or open a PR

Response marker requirements:
- the final response must end with one marker line exactly as plain text
- do not wrap the marker in Markdown, backticks, a code fence, quotes, bullets, or trailing punctuation
- if you completed a concrete hardening pass, the final line must be exactly: CODEX_POSTMORTEM_STATUS: HARDENING_DONE
- if you are blocked, the final line must be exactly: CODEX_POSTMORTEM_STATUS: BLOCKED
EOF
}

write_quota_skipped_postmortem_report() {
  local report_path="$1"
  local trigger="$2"
  local detail_text="$3"
  local child_exit="$4"
  local skipped_phase="$5"
  local target_model="$6"
  local five_hour_threshold week_threshold

  five_hour_threshold="$(quota_5h_stop_percent_for_model "$target_model")"
  week_threshold="$(quota_week_stop_percent_for_model "$target_model")"

  cat >"$report_path" <<EOF
# Upkeeper Postmortem
## Incident Summary
Cycle \`$CYCLE_ID\` entered fallback handling for \`$trigger\` after: $detail_text.

The fallback child exit recorded by the wrapper was \`$child_exit\`. The scripted \`$skipped_phase\` Codex pass was intentionally skipped before launch because the auxiliary model \`$target_model\` did not pass the wrapper quota preflight. This preserves the remaining recovery bucket instead of spending more tokens while already handling a quota incident.
## Observed Signals
- Trigger: \`$trigger\`.
- Detail: \`$detail_text\`.
- Fallback child exit: \`$child_exit\`.
- Skipped auxiliary phase: \`$skipped_phase\`.
- Skipped auxiliary model: \`$target_model\`.
- Incident context: \`$POSTMORTEM_CONTEXT_PATH\`.
- Incident log: \`$POSTMORTEM_INCIDENT_LOG_PATH\`.
## Root Cause Hypotheses
- The wrapper reached recovery handling while quota state was already constrained, and an auxiliary postmortem/report/hardening pass would have consumed the same stronger model bucket.
- The auxiliary quota snapshot was missing, stale, non-exact, or projected below the configured stop thresholds.
## Action Plan
- [ ] Inspect \`$POSTMORTEM_INCIDENT_LOG_PATH\` for the \`$skipped_phase.quota\` and \`$skipped_phase.skip\` lines.
- [ ] Wait for the constrained model bucket to reset or switch \`CODEX_POSTMORTEM_MODEL\` to a model with a current exact snapshot above thresholds.
- [ ] Relaunch the wrapper once the quota guardrail can pass.
## Hardening Targets
- Wrapper/logging/prompt/guardrail fixes: keep auxiliary postmortem Codex execs behind the same exact-model quota preflight used by primary and fallback cycles.
- Repo-lane fixes: continue the active backend lane only after the recovery bucket is no longer constrained.
## Relaunch Checklist
- [ ] Confirm \`Upkeeper.log\` has a current exact-model quota snapshot for \`$target_model\`.
- [ ] Confirm projected 5-hour and weekly remaining capacity are above \`$five_hour_threshold%\` and \`$week_threshold%\`.
- [ ] Relaunch \`while ./$SCRIPT_NAME; do sleep 60; done\` from a clean terminal.
## Hardening Outcome
- No auxiliary hardening Codex pass was launched because the quota guardrail blocked \`$skipped_phase\`.
- This shell-generated report exists so the incident remains documentable without spending the constrained model bucket.
EOF
}

write_environment_skipped_postmortem_report() {
  local report_path="$1"
  local trigger="$2"
  local detail_text="$3"
  local child_exit="$4"
  local skipped_phase="$5"
  local target_model="$6"
  local environment_detail="$7"
  local five_hour_threshold week_threshold

  five_hour_threshold="$(quota_5h_stop_percent_for_model "$target_model")"
  week_threshold="$(quota_week_stop_percent_for_model "$target_model")"

  cat >"$report_path" <<EOF
# Upkeeper Postmortem
## Incident Summary
Cycle \`$CYCLE_ID\` entered fallback handling for \`$trigger\` after: $detail_text.

The fallback child exit recorded by the wrapper was \`$child_exit\`. The scripted \`$skipped_phase\` Codex pass was intentionally skipped before launch because the local Codex runtime for \`$target_model\` was not writable. This is a local filesystem/environment failure, not a backend-lane or model-response failure.
## Observed Signals
- Trigger: \`$trigger\`.
- Detail: \`$detail_text\`.
- Fallback child exit: \`$child_exit\`.
- Skipped auxiliary phase: \`$skipped_phase\`.
- Skipped auxiliary model: \`$target_model\`.
- CODEX_HOME: \`$CODEX_HOME_DIR\`.
- Session store: \`$CODEX_HOME_DIR/sessions\`.
- Arg0 temp root: \`$CODEX_ARG0_TMP_ROOT\`.
- Arg0 quarantine root: \`$CODEX_ARG0_TMP_QUARANTINE_ROOT\`.
- Bubblewrap temp registry: \`$CODEX_BWRAP_TMP_ROOT\`.
- Write-check detail: \`$environment_detail\`.
- Incident context: \`$POSTMORTEM_CONTEXT_PATH\`.
- Incident log: \`$POSTMORTEM_INCIDENT_LOG_PATH\`.
## Root Cause Hypotheses
- The wrapper was launched from an environment where \`$CODEX_HOME_DIR/sessions\`, \`$CODEX_ARG0_TMP_ROOT\`, or \`$CODEX_BWRAP_TMP_ROOT\` could not be created, written, or cleaned up.
- Because Codex creates a session before model work starts, primary, fallback, report, and hardening Codex calls would all fail the same way until the local filesystem or \`CODEX_HOME\` is fixed.
## Action Plan
- [ ] Confirm the current terminal or container can write to \`$CODEX_HOME_DIR/sessions\`.
- [ ] Confirm stale \`$CODEX_ARG0_TMP_ROOT/codex-arg0*\` shim directories can be removed or moved to \`$CODEX_ARG0_TMP_QUARANTINE_ROOT\`.
- [ ] Confirm the current terminal or container can write to \`$CODEX_BWRAP_TMP_ROOT\` and its \`lock\` file.
- [ ] If the home directory is intentionally read-only, relaunch with \`CODEX_HOME\` pointed at a writable local directory.
- [ ] Keep fallback and postmortem Codex execs blocked until local Codex runtime write checks pass.
## Hardening Targets
- Wrapper/logging/prompt/guardrail fixes: keep live Codex execs behind local runtime write preflights and classify failures as local environment problems before attempting fallback.
- Repo-lane fixes: do not treat this incident as evidence of a backend task failure; resume the active repo lane only after the local Codex runtime is writable.
## Relaunch Checklist
- [ ] Run the wrapper from a terminal with writable \`CODEX_HOME\`, \`$CODEX_HOME_DIR/sessions\`, \`$CODEX_ARG0_TMP_ROOT\`, \`$CODEX_ARG0_TMP_QUARANTINE_ROOT\`, and \`$CODEX_BWRAP_TMP_ROOT\`.
- [ ] Confirm projected 5-hour capacity is above \`$five_hour_threshold%\` for \`$target_model\`, and weekly/main capacity is above \`$week_threshold%\`.
- [ ] Relaunch \`while ./$SCRIPT_NAME; do sleep 60; done\` from the repo root.
## Hardening Outcome
- No auxiliary hardening Codex pass was launched because the local Codex runtime was not writable.
- This shell-generated report exists so the incident remains documentable without recursively launching Codex in the same broken environment.
EOF
}

# Postmortem summaries are copied into the root loop log so the terminal scroll
# carries the key facts even if the operator never opens the full report.
emit_postmortem_summary() {
  local report_path="$1"
  local trigger="$2"
  local sequence_status="$3"

  local summary_block
  local marker_path marker_block
  if [[ -s "$report_path" ]]; then
    summary_block="$(
      awk '
        /^## Incident Summary$/ { section="Incident Summary"; count=0; next }
        /^## Action Plan$/ { section="Action Plan"; count=0; next }
        /^## Hardening Outcome$/ { section="Hardening Outcome"; count=0; next }
        /^## / { section=""; next }
        section != "" && count < 6 && NF {
          if (!(section in seen)) {
            print section ":"
            seen[section]=1
          }
          print $0
          count++
        }
      ' "$report_path"
    )"
  else
    summary_block="Report file missing or empty."
  fi

  marker_path="$CODEX_POSTMORTEM_DIR/$CYCLE_ID/primary-quota-blocked-until.txt"
  if [[ -s "$marker_path" ]]; then
    marker_block="$(
      printf 'Cooldown Marker:\n'
      printf 'cooldown_marker_path: %s\n' "$marker_path"
      printf 'blocked_bucket: %s\n' "$(marker_field "$marker_path" "blocked_bucket")"
      printf 'blocked_until: %s\n' "$(marker_field "$marker_path" "blocked_until")"
      printf 'recommended_operator_action: %s\n' "$(marker_field "$marker_path" "recommended_operator_action")"
    )"
  else
    marker_block=""
  fi

  {
    printf 'POSTMORTEM_SUMMARY_BEGIN cycle=%s trigger=%s status=%s report=%s\n' "$CYCLE_ID" "$trigger" "$sequence_status" "$report_path"
    if [[ -n "$summary_block" ]]; then
      printf '%s\n' "$summary_block" | sed 's/^/  /'
    fi
    if [[ -n "$marker_block" ]]; then
      printf '%s\n' "$marker_block" | sed 's/^/  /'
    fi
    printf 'POSTMORTEM_SUMMARY_END\n'
  } | while IFS= read -r summary_line; do
    printf '%s\n' "$summary_line"
    append_log_line_secure "$summary_line" "postmortem_summary" || exit $?
  done
}

run_postmortem_sequence() {
  local trigger="$1"
  local detail_text="$2"
  local child_exit="$3"

  POSTMORTEM_REPORT_PATH=""
  POSTMORTEM_CONTEXT_PATH=""
  POSTMORTEM_INCIDENT_LOG_PATH=""
  POSTMORTEM_BUG_RECORD_PATH=""
  POSTMORTEM_SEQUENCE_STATUS="not_run"

  local pm_root report_path context_path incident_log_path bug_record_path primary_last_message_copy
  local report_prompt_file report_last_message hardening_prompt_file hardening_last_message
  local report_exit report_marker hardening_exit hardening_marker
  local incident_classification errexit_was_set

  pm_root="$CODEX_POSTMORTEM_DIR/$CYCLE_ID"
  report_path="$pm_root/postmortem.md"
  context_path="$pm_root/incident-context.txt"
  incident_log_path="$pm_root/incident-log.txt"
  bug_record_path="$pm_root/bug-record.md"
  primary_last_message_copy="$pm_root/primary-last-message.txt"

  mkdir -p "$pm_root"
  POSTMORTEM_INCIDENT_LOG_PATH="$incident_log_path"
  refresh_postmortem_incident_log "$incident_log_path"
  if [[ -n "${last_message_file:-}" && -f "${last_message_file:-}" ]]; then
    cp "$last_message_file" "$primary_last_message_copy"
  else
    : >"$primary_last_message_copy"
  fi
  write_postmortem_context "$context_path" "$trigger" "$detail_text" "$child_exit" "$incident_log_path" "$primary_last_message_copy"
  incident_classification="$(awk -F': ' '/^incident_classification: / { print $2; exit }' "$context_path" || true)"
  log_line "INFO" "postmortem.classification trigger=$trigger classification=${incident_classification:-unknown} child_exit=$child_exit"

  POSTMORTEM_REPORT_PATH="$report_path"
  POSTMORTEM_CONTEXT_PATH="$context_path"
  POSTMORTEM_BUG_RECORD_PATH="$bug_record_path"
  write_postmortem_bug_record "$bug_record_path" "$trigger" "$detail_text" "$child_exit" "$POSTMORTEM_SEQUENCE_STATUS" "$report_path" "$context_path" "$incident_log_path"
  log_line "INFO" "postmortem.bug_record path=$bug_record_path trigger=$trigger status=$POSTMORTEM_SEQUENCE_STATUS"

  if [[ "$UPKEEPER_DRY_RUN" == "1" ]]; then
    cat >"$report_path" <<EOF
# Upkeeper Postmortem
## Incident Summary
Dry-run stub summary for trigger $trigger.
## Observed Signals
- Dry run skipped live post-mortem Codex exec.
## Root Cause Hypotheses
- Dry run path only.
## Action Plan
- Relaunch the loop with the updated wrapper.
## Hardening Targets
- Verify fallback and post-mortem branches on the next real incident.
## Relaunch Checklist
- Inspect the real report after a live fallback incident.
## Hardening Outcome
- Dry run only; no live hardening change was executed.
EOF
    POSTMORTEM_SEQUENCE_STATUS="dry_run_stub"
    write_postmortem_bug_record "$bug_record_path" "$trigger" "$detail_text" "$child_exit" "$POSTMORTEM_SEQUENCE_STATUS" "$report_path" "$context_path" "$incident_log_path"
    emit_postmortem_summary "$report_path" "$trigger" "$POSTMORTEM_SEQUENCE_STATUS"
    return 7
  fi

  ensure_run_tmp_dir
  report_prompt_file="$(run_mktemp postmortem-report-prompt)"
  report_last_message="$(run_mktemp postmortem-report-last-message)"
  hardening_prompt_file="$(run_mktemp postmortem-hardening-prompt)"
  hardening_last_message="$(run_mktemp postmortem-hardening-last-message)"

  compile_postmortem_report_prompt "$report_prompt_file" "$context_path" "$report_path"
  # The fallback caller disables errexit so it can record intentional postmortem
  # return codes. Preserve that state while still capturing the auxiliary exit.
  errexit_was_set=0
  [[ $- == *e* ]] && errexit_was_set=1
  set +e
  run_aux_codex_exec "postmortem.report" "$CODEX_POSTMORTEM_MODEL" "$CODEX_POSTMORTEM_REASONING_EFFORT" "$CODEX_POSTMORTEM_MODE" "$report_prompt_file" "$report_last_message"
  report_exit=$?
  if [[ "$errexit_was_set" -eq 1 ]]; then
    set -e
  else
    set +e
  fi
  report_marker="$(parse_postmortem_marker "$report_last_message")"
  log_line "INFO" "postmortem.report.finish exit_code=$report_exit marker=${report_marker:-missing} report_path=$report_path report_exists=$([[ -e "$report_path" ]] && printf 1 || printf 0) report_nonempty=$([[ -s "$report_path" ]] && printf 1 || printf 0)"

  if [[ "$report_exit" -eq 86 ]]; then
    POSTMORTEM_SEQUENCE_STATUS="report_quota_skipped"
    write_quota_skipped_postmortem_report "$report_path" "$trigger" "$detail_text" "$child_exit" "postmortem.report" "$CODEX_POSTMORTEM_MODEL"
    log_line "WARN" "postmortem.report skipped reason=quota_guardrail exit_code=$report_exit marker=${report_marker:-missing} report_path=$report_path"
    write_postmortem_bug_record "$bug_record_path" "$trigger" "$detail_text" "$child_exit" "$POSTMORTEM_SEQUENCE_STATUS" "$report_path" "$context_path" "$incident_log_path"
    emit_postmortem_summary "$report_path" "$trigger" "$POSTMORTEM_SEQUENCE_STATUS"
    rm -f "$report_prompt_file" "$report_last_message" "$hardening_prompt_file" "$hardening_last_message"
    return 7
  fi

  if [[ "$report_exit" -eq 87 ]]; then
    local report_environment_detail report_environment_reason
    report_environment_detail="$(awk '/^detail: / { sub(/^detail: /, ""); print; exit }' "$report_last_message" || true)"
    if [[ -z "$report_environment_detail" ]]; then
      report_environment_detail="unknown"
    fi
    report_environment_reason="$(awk '/^reason: / { sub(/^reason: /, ""); print; exit }' "$report_last_message" || true)"
    if [[ -z "$report_environment_reason" ]]; then
      report_environment_reason="local Codex runtime is not writable"
    fi
    POSTMORTEM_SEQUENCE_STATUS="report_environment_skipped"
    write_environment_skipped_postmortem_report "$report_path" "$trigger" "$detail_text" "$child_exit" "postmortem.report" "$CODEX_POSTMORTEM_MODEL" "$report_environment_detail"
    log_line "WARN" "postmortem.report skipped reason=local_codex_runtime_unwritable environment_reason=$(shell_quote "$report_environment_reason") exit_code=$report_exit marker=${report_marker:-missing} report_path=$report_path"
    write_postmortem_bug_record "$bug_record_path" "$trigger" "$detail_text" "$child_exit" "$POSTMORTEM_SEQUENCE_STATUS" "$report_path" "$context_path" "$incident_log_path"
    emit_postmortem_summary "$report_path" "$trigger" "$POSTMORTEM_SEQUENCE_STATUS"
    rm -f "$report_prompt_file" "$report_last_message" "$hardening_prompt_file" "$hardening_last_message"
    return 7
  fi

  # Exit 0 alone is not enough here: the auxiliary prompt marker is the
  # machine-readable contract that tells the parent which phase actually
  # completed.
  if [[ "$report_exit" -ne 0 || "$report_marker" != "REPORT_WRITTEN" || ! -s "$report_path" ]]; then
    POSTMORTEM_SEQUENCE_STATUS="report_failed"
    log_line "ERROR" "postmortem.report failed exit_code=$report_exit marker=${report_marker:-missing} expected_marker=REPORT_WRITTEN report_path=$report_path"
    write_postmortem_bug_record "$bug_record_path" "$trigger" "$detail_text" "$child_exit" "$POSTMORTEM_SEQUENCE_STATUS" "$report_path" "$context_path" "$incident_log_path"
    emit_postmortem_summary "$report_path" "$trigger" "$POSTMORTEM_SEQUENCE_STATUS"
    rm -f "$report_prompt_file" "$report_last_message" "$hardening_prompt_file" "$hardening_last_message"
    return 8
  fi

  compile_postmortem_hardening_prompt "$hardening_prompt_file" "$context_path" "$report_path"
  # Preserve the caller's errexit state here for the same reason as the report
  # phase: non-zero sequence returns are part of the wrapper contract.
  errexit_was_set=0
  [[ $- == *e* ]] && errexit_was_set=1
  set +e
  run_aux_codex_exec "postmortem.hardening" "$CODEX_POSTMORTEM_MODEL" "$CODEX_POSTMORTEM_REASONING_EFFORT" "$CODEX_POSTMORTEM_MODE" "$hardening_prompt_file" "$hardening_last_message"
  hardening_exit=$?
  if [[ "$errexit_was_set" -eq 1 ]]; then
    set -e
  else
    set +e
  fi
  hardening_marker="$(parse_postmortem_marker "$hardening_last_message")"

  if [[ "$hardening_exit" -eq 86 ]]; then
    POSTMORTEM_SEQUENCE_STATUS="hardening_quota_skipped"
    cat >>"$report_path" <<EOF

## Hardening Outcome
- The scripted hardening Codex pass was skipped before launch because \`$CODEX_POSTMORTEM_MODEL\` did not pass the auxiliary quota preflight.
- The report was preserved and the wrapper stopped for manual relaunch instead of spending more recovery quota.
EOF
    log_line "WARN" "postmortem.hardening skipped reason=quota_guardrail exit_code=$hardening_exit marker=${hardening_marker:-missing} report_path=$report_path"
    write_postmortem_bug_record "$bug_record_path" "$trigger" "$detail_text" "$child_exit" "$POSTMORTEM_SEQUENCE_STATUS" "$report_path" "$context_path" "$incident_log_path"
    emit_postmortem_summary "$report_path" "$trigger" "$POSTMORTEM_SEQUENCE_STATUS"
    rm -f "$report_prompt_file" "$report_last_message" "$hardening_prompt_file" "$hardening_last_message"
    return 7
  fi

  if [[ "$hardening_exit" -eq 87 ]]; then
    POSTMORTEM_SEQUENCE_STATUS="hardening_environment_skipped"
    cat >>"$report_path" <<EOF

## Hardening Outcome
- The scripted hardening Codex pass was skipped before launch because the local Codex runtime was not writable.
- The report was preserved and the wrapper stopped for manual relaunch instead of recursively launching Codex in the same broken environment.
EOF
    log_line "WARN" "postmortem.hardening skipped reason=local_codex_runtime_unwritable exit_code=$hardening_exit marker=${hardening_marker:-missing} report_path=$report_path"
    write_postmortem_bug_record "$bug_record_path" "$trigger" "$detail_text" "$child_exit" "$POSTMORTEM_SEQUENCE_STATUS" "$report_path" "$context_path" "$incident_log_path"
    emit_postmortem_summary "$report_path" "$trigger" "$POSTMORTEM_SEQUENCE_STATUS"
    rm -f "$report_prompt_file" "$report_last_message" "$hardening_prompt_file" "$hardening_last_message"
    return 7
  fi

  if [[ "$hardening_exit" -ne 0 || "$hardening_marker" != "HARDENING_DONE" ]]; then
    POSTMORTEM_SEQUENCE_STATUS="hardening_failed"
    log_line "ERROR" "postmortem.hardening failed exit_code=$hardening_exit marker=${hardening_marker:-missing} expected_marker=HARDENING_DONE report_path=$report_path"
    write_postmortem_bug_record "$bug_record_path" "$trigger" "$detail_text" "$child_exit" "$POSTMORTEM_SEQUENCE_STATUS" "$report_path" "$context_path" "$incident_log_path"
    emit_postmortem_summary "$report_path" "$trigger" "$POSTMORTEM_SEQUENCE_STATUS"
    rm -f "$report_prompt_file" "$report_last_message" "$hardening_prompt_file" "$hardening_last_message"
    return 8
  fi

  POSTMORTEM_SEQUENCE_STATUS="complete"
  write_postmortem_bug_record "$bug_record_path" "$trigger" "$detail_text" "$child_exit" "$POSTMORTEM_SEQUENCE_STATUS" "$report_path" "$context_path" "$incident_log_path"
  emit_postmortem_summary "$report_path" "$trigger" "$POSTMORTEM_SEQUENCE_STATUS"
  rm -f "$report_prompt_file" "$report_last_message" "$hardening_prompt_file" "$hardening_last_message"
  return 7
}
