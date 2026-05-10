# Upkeeper Modules

Root `Upkeeper` is the only operator entrypoint. Files in this directory are
source-only Bash modules loaded by that entrypoint from the resolved central
implementation directory.

Do not run these modules directly. They share the wrapper's global runtime state
and are loaded after configuration variables, cycle identity, evidence paths,
and other top-level state have been initialized.

## Load Order

The canonical load order lives in the `UPKEEPER_MODULES` array in root
`Upkeeper`. Keep that array explicit instead of relying on filename order:
later modules can depend on functions from earlier runtime, preflight, prompt,
and fallback groups.

Missing modules must fail before lock acquisition, Codex launch, fallback, or
parent-shell stop logic. The root launcher exits 70 with a terminal-visible
error when a listed module is unreadable.

## Module Design Discipline

Keep modules boring and reusable.

- Prefer a small function with a clear input/output contract when behavior is
  shared, validated, logged, or likely to be touched again.
- Keep orchestration in root `Upkeeper`; keep parsing, formatting, preflight,
  process handling, prompt assembly, and artifact handling in the module that
  owns that concern.
- Avoid adding a new module for one short one-off block unless it clarifies load
  order, isolates a risky contract, or gives validation a clean target.
- Prefer existing shell helpers and focused Python snippets over new runtime
  dependencies.
- Add validation when a reusable helper handles malformed input, missing files,
  process state, quota state, or operator-facing log/exit contracts.

## Reusable Asset Ownership

Put reusable behavior in the narrowest owner that already owns the contract.
Do not create a generic `utils.bash`, `common.bash`, or `helpers.bash` module
unless there is no clearer owner and the new file has one named responsibility.

- Runtime, logging, terminal, temp, and evidence helpers:
  `runtime_foundation.bash`
- JSON field and time formatting helpers: `runtime_format_json.bash`
- Local SQLite evidence-ledger lifecycle hooks: `lattice.bash`
- Shared automation run and obligation records:
  `automation_obligations.bash`
- Fallback marker, quote, and artifact field helpers:
  `fallback_artifacts.bash`
- Transcript path, hash, size, and line-count helpers:
  `transcript_artifacts.bash`
- Environment and config validation helpers: `config_validation.bash`
- Quota, model, and session guardrail helpers: `quota_guardrails.bash`
- Review-module CLI aliases and Codex invocation boundaries: `codex_io.bash`
- Review-module prompt path assembly and prompt loading: `prompt_compile.bash`
- Process argument formatting and process-state helpers: `process_args.bash`
  and `process_control.bash`
- Selection manifests, worktree state, and startup anomaly path rules:
  `file_manifest.bash` and `worktree_state.bash`
- Validation harness helpers: `tools/validate_upkeeper.sh`
- Public documentation drift checks: `tools/check_public_docs.sh`
- Repo-root automation launcher full-burn defaults:
  `launcher_full_burn.bash`
- Prompt-module index and reusable review-language ownership:
  `prompts/README.md` and `prompts/*.md`

If review-module ids, aliases, prompt paths, titles, and help summaries keep
growing, prefer a narrow `review_modules.bash` registry over another scattered
case-block update. Do not add that registry until the callers and validation can
prove it preserves the existing CLI, logs, prompt loading, and symlinked-client
behavior.

## Module Groups

Runtime evidence:

- `help_selection.bash`
- `runtime_foundation.bash`
- `transcript_artifacts.bash`
- `active_lock.bash`
- `wrapper_health.bash`
- `progress_logging.bash`
- `startup_anomaly_state.bash`
- `operator_guide.bash`
- `cycle_cleanup_signals.bash`
- `runtime_format_json.bash`
- `automation_obligations.bash`
- `lattice.bash`
- `transcript_output.bash`
- `tool_failure_queue.bash`
- `codex_io.bash`

Startup validation, quota, and selection:

- `config_validation.bash`
- `quota_guardrails.bash`
- `session_store_preflight.bash`
- `bwrap_preflight.bash`
- `arg0_preflight.bash`
- `process_args.bash`
- `log_rotation.bash`
- `disk_preflight.bash`
- `previous_run_anomalies.bash`
- `file_manifest.bash`
- `worktree_state.bash`
- `quota_state.bash`

Prompt assembly and process control:

- `precontact_backup.bash`
- `prompt_pruning.bash`
- `prompt_compile.bash`
- `process_control.bash`

Fallback, postmortem, and status sessions:

- `fallback_availability.bash`
- `fallback_artifacts.bash`
- `quota_block_markers.bash`
- `fallback_screen.bash`
- `aux_codex.bash`
- `report_analysis.bash`
- `postmortem_context.bash`
- `postmortem_sequence.bash`
- `fallback_orchestration.bash`
- `status_session.bash`

Launcher-only helpers:

- `launcher_full_burn.bash`
