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
- `transcript_output.bash`
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
- `worktree_state.bash`
- `quota_state.bash`

Prompt assembly and process control:

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
