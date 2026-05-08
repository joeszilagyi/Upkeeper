# Prompt compilation.
#
# Variable wrapper context stays in shell; the large static review prompt lives
# in prompts/default-review.md beside the resolved central implementation.
default_review_prompt_path() {
  printf '%s/prompts/default-review.md' "$UPKEEPER_IMPLEMENTATION_DIR"
}

review_module_prompt_path() {
  local module="$1"

  case "$module" in
    p24)
      printf '%s/prompts/p24-de-llm-ing-viability-review.md' "$UPKEEPER_IMPLEMENTATION_DIR"
      ;;
    p25)
      printf '%s/prompts/p25-contract-intent-compliance-review.md' "$UPKEEPER_IMPLEMENTATION_DIR"
      ;;
    p26)
      printf '%s/prompts/p26-public-documentation-review.md' "$UPKEEPER_IMPLEMENTATION_DIR"
      ;;
    p27)
      printf '%s/prompts/p27-educational-debrief-review.md' "$UPKEEPER_IMPLEMENTATION_DIR"
      ;;
    p28)
      printf '%s/prompts/p28-unit-test-harvesting-review.md' "$UPKEEPER_IMPLEMENTATION_DIR"
      ;;
    *)
      return 1
      ;;
  esac
}

append_default_review_prompt_or_exit() {
  local compiled_file="$1"
  local prompt_path

  prompt_path="$(default_review_prompt_path)"
  if [[ ! -r "$prompt_path" ]]; then
    log_line "ERROR" "review.prompt_template_missing path=$(shell_quote "$prompt_path")"
    finish_cycle 70 PROMPT_TEMPLATE_MISSING ERROR "codex_exec_started=0 path=$(shell_quote "$prompt_path")"
  fi

  cat "$prompt_path" >>"$compiled_file"
}

append_review_module_prompts_or_exit() {
  local compiled_file="$1"
  local module prompt_path

  [[ "${#CODEX_REVIEW_MODULES[@]}" -gt 0 ]] || return 0

  {
    printf '\nWRAPPER_REVIEW_MODULES\n'
    printf 'review_modules=%s\n' "$(review_modules_csv)"
    printf '\nRules for selected review modules:\n'
    printf -- '- These modules were requested explicitly by operator flags for this invoked cycle.\n'
    printf -- '- Apply each requested module only when its applicability gate matches the selected file.\n'
    printf -- '- If a requested module is not applicable, state that using the module-specific not-applicable line and continue normal selected-file review.\n'
    printf -- '- These flags are one-cycle CLI guidance only; they do not persist to later loop iterations.\n'
  } >>"$compiled_file"

  for module in "${CODEX_REVIEW_MODULES[@]}"; do
    if ! prompt_path="$(review_module_prompt_path "$module")"; then
      log_line "ERROR" "review.module_prompt_unknown module=$(shell_quote "$module")"
      finish_cycle 70 REVIEW_MODULE_PROMPT_MISSING ERROR "codex_exec_started=0 module=$(shell_quote "$module")"
    fi
    if [[ ! -r "$prompt_path" ]]; then
      log_line "ERROR" "review.module_prompt_missing module=$(shell_quote "$module") path=$(shell_quote "$prompt_path")"
      finish_cycle 70 REVIEW_MODULE_PROMPT_MISSING ERROR "codex_exec_started=0 module=$(shell_quote "$module") path=$(shell_quote "$prompt_path")"
    fi

    {
      printf '\nAdditional review module %s from %s:\n' "$module" "$prompt_path"
      cat "$prompt_path"
    } >>"$compiled_file"
    log_line "INFO" "review.module_prompt enabled module=$(shell_quote "$module") path=$(shell_quote "$prompt_path")"
  done
}

compile_prompt() {
  local compiled_file="$1"
  local prune_stats

  ensure_run_tmp_dir
  : >"$compiled_file"
  append_preselected_review_target "$compiled_file"
  if [[ "$CODEX_PROMPT_PASS" == "all" ]]; then
    {
      printf '\nWRAPPER_PROMPT_PASS_OVERRIDE\n'
      printf 'prompt_pass=all\n'
      printf '\nRules for this prompt-pass override:\n'
      printf -- '- This invoked cycle was started with `--prompt-pass=all`.\n'
      printf -- '- Run every repertoire pass P1 through P23 against the selected target, even if the default schedule or applicability filter would normally skip it.\n'
      printf -- '- For a pass whose domain does not fit the selected target, still include that pass in the final report and mark it `not applicable` with a short reason.\n'
      printf -- '- For machine-readable coverage, include one final-report line for each pass, and start each such line with `P<N>:` where N is 1 through 23.\n'
      printf -- '- Do not use non-applicability as permission to switch targets or skip the selected file.\n'
      printf -- '- This override is one-cycle CLI guidance only; it does not persist to later loop iterations.\n'
    } >>"$compiled_file"
    log_line "INFO" "review.prompt_pass_override prompt_pass=all target_file=$(shell_quote "${CODEX_TARGET_FILE:-preselected}")"
  fi
  if [[ -n "$PREVIOUS_RUN_ANOMALIES" || -n "$DISK_SPACE_PROMPT_NOTE" ]]; then
    {
      printf '\nWRAPPER_STARTUP_ANOMALIES\n'
      if [[ -n "$PREVIOUS_RUN_ANOMALIES" ]]; then
        printf 'Previous-run continuity anomalies detected before this Codex launch:\n'
        printf '%s' "$PREVIOUS_RUN_ANOMALIES"
      fi
      if [[ -n "$DISK_SPACE_PROMPT_NOTE" ]]; then
        printf 'Disk-space preflight note:\n'
        printf '%s\n' "$DISK_SPACE_PROMPT_NOTE"
      fi
      printf '\nRules for these startup anomalies:\n'
      printf -- '- These anomalies are a startup gate. The repo-local Upkeeper suite must be checked/remediated before normal timestamp rotation may touch another file.\n'
      printf -- '- Upkeeper suite means `Upkeeper` plus directly paired central docs, prompts, and launcher examples needed to validate or repair wrapper behavior.\n'
      printf -- '- Inspect these signals during the final current-cycle log review.\n'
      printf -- '- If they point to a concrete Upkeeper wrapper, prompt, logging, or launcher defect in this central repo, apply the smallest safe self-repair and verify it.\n'
      printf -- '- If they point to environment state only, report the evidence and avoid speculative code changes.\n'
    } >>"$compiled_file"
  fi

  append_default_review_prompt_or_exit "$compiled_file"
  append_review_module_prompts_or_exit "$compiled_file"

  if [[ -n "$PROMPT_FILE" ]]; then
    {
      printf '\nAdditional task guidance from %s:\n' "$PROMPT_FILE"
      cat "$PROMPT_FILE"
    } >>"$compiled_file"
  elif [[ -n "$INLINE_PROMPT" ]]; then
    {
      printf '\nAdditional task guidance:\n'
      printf '%s\n' "$INLINE_PROMPT"
    } >>"$compiled_file"
  fi

  {
    printf '\nCurrent-cycle log self-review -- required final task before your final response:\n'
    printf -- '- After all selected-file review work, edits, touches, and verification are complete, inspect this cycle'\''s own Upkeeper log lines before writing the final response.\n'
    printf -- '- Log file: `%s`\n' "$LOG_FILE"
    printf -- '- Current cycle id: `%s`\n' "$CYCLE_ID"
    printf -- '- Preferred command: `rg "cycle=%s " "%s"`; if `rg` is unavailable, use `grep "cycle=%s " "%s"`.\n' "$CYCLE_ID" "$LOG_FILE" "$CYCLE_ID" "$LOG_FILE"
    printf -- '- Review only the current cycle lines. Do not inventory rotated archives or unrelated cycles.\n'
    printf -- '- Check for wrapper/prompt/logging defects, unexpected ERROR/WARN lines, parser misses, environment preflight surprises, previous_run.anomaly lines, disk.preflight warnings, missing or irregular --MARK-- continuity, and any command failure from your own tool output that still needs explanation or correction.\n'
    printf -- '- If `startup_anomaly.gate` or `WRAPPER_STARTUP_ANOMALIES` is active, do not touch unrelated non-Upkeeper-suite files; the gate must be checked or remediated first.\n'
    printf -- '- If the log review exposes a concrete Upkeeper wrapper, prompt, or logging defect and this current repo owns a tracked `Upkeeper` file, apply the smallest safe self-repair now, run focused validation, and report it as a log self-repair. This is the only reason to patch `Upkeeper` when it was not the selected target.\n'
    printf -- '- If this is a symlinked client repo and the defect belongs to central Upkeeper behavior, do not patch a copied client wrapper; report the central fix needed unless the central Upkeeper checkout is the current repo.\n'
    printf -- '- If a suspicious line was expected negative-test output, say so briefly. If a one-off shell command failed, rerun the corrected check or state why it is irrelevant before final status.\n'
    printf -- '- Include exactly one machine-readable acknowledgment line before the final UPKEEPER_STATUS marker.\n'
    printf -- '- If no anomalies were found, write exactly: `UPKEEPER_LOG_REVIEW: CHECKED cycle=%s anomalies=none`\n' "$CYCLE_ID"
    printf -- '- If anomalies were found or expected anomaly signals were present, write exactly: `UPKEEPER_LOG_REVIEW: CHECKED cycle=%s anomalies=listed`\n' "$CYCLE_ID"
    printf -- '- Do not write the placeholder text `anomalies=none|listed`; choose one concrete value.\n'
    printf -- '- Put the machine-readable acknowledgment on its own raw line with no Markdown, punctuation, or trailing text. The wrapper parses that line directly.\n'
    printf -- '- You may also include a short human-readable current-cycle log review summary on separate lines.\n'

    printf '\nWrapper control marker compatibility:\n'
    printf -- '- If edits are made, report changed files and the focused verification performed.\n'
    printf -- '- Report the review outcome in the body using one of: REVIEWED_AND_FIXED, REVIEWED_CLEAN, or STOPPED_ON_BLOCKER.\n'
    printf -- '- The literal final line must still be a wrapper status marker with no Markdown or trailing punctuation.\n'
    printf -- '- If the review outcome is REVIEWED_AND_FIXED or REVIEWED_CLEAN, the final line must be exactly: UPKEEPER_STATUS: WORK_DONE\n'
    printf -- '- If the review outcome is STOPPED_ON_BLOCKER, the final line must be exactly: UPKEEPER_STATUS: BLOCKED\n'
    printf -- '- Do not emit UPKEEPER_STATUS: NO_BACKEND_TASK for this prompt family.\n'
  } >>"$compiled_file"

  if [[ "${CODEX_PROMPT_PASS:-}" != "all" ]]; then
    if prune_stats="$(prune_default_prompt_sections "$compiled_file")"; then
      log_line "INFO" "review.prompt_pruned prompt_pass=default $prune_stats"
    else
      log_line "WARN" "review.prompt_pruned prompt_pass=default status=failed"
    fi
  fi
}
