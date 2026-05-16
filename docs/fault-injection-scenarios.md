# Fault-Injection Scenario Registry

This registry tracks deterministic fault-injection scenario ideas for the future
P31 fault-injection review contract. It is a planning and prioritization
surface, not an executable harness. Rows may start as `deferred`, but each row
must keep a stable id and enough structure for a future test, stress-corpus
case, or Lattice import to consume without guessing.

Stable ids use `FI-###` and never get reused. If a scenario is replaced, keep
the original id with `priority=retired` and add a new row for the replacement.

## Required Columns

- `scenario_id`
- `module_or_file`
- `fault_surface`
- `injected_fault`
- `expected_reason`
- `expected_exit`
- `expected_log_event`
- `cleanup_required`
- `recovery_run_required`
- `validation_command`
- `quick_or_full`
- `lattice_ready_tags`

## Priority Fields

- `severity`: how bad the operator or repo impact is if the fault is mishandled.
- `likelihood`: how plausible the fault is during normal or stressed operator
  use.
- `detectability`: how quickly an operator would notice the problem without the
  scenario.
- `fixture_cost`: the cost to build and keep a deterministic local fixture.
- `priority`: `high`, `medium`, `low`, `deferred`, or `retired`. A scenario is
  usually high priority when severity is high, detectability is low, and fixture
  cost is low.

## Initial Matrix

| scenario_id | module_or_file | fault_surface | injected_fault | expected_reason | expected_exit | expected_log_event | cleanup_required | recovery_run_required | validation_command | quick_or_full | lattice_ready_tags | severity | likelihood | detectability | fixture_cost | priority |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| FI-001 | `lib/upkeeper/help_selection.bash` | Review module wiring | unknown review module id such as `p99` | `review_module_unknown` | `2` | `review_module.invalid` | no | no | `tools/validate_upkeeper.sh --quick` | quick | `surface:review-module,status:deferred` | medium | medium | high | low | deferred |
| FI-002 | `lib/upkeeper/prompt_compile.bash` | Prompt compilation | prompt file with control character path segment | `prompt_path_invalid` | `2` | `prompt.path_rejected` | no | no | `tools/validate_upkeeper.sh --quick` | quick | `surface:prompt-compile,status:deferred` | high | low | medium | low | deferred |
| FI-003 | `lib/upkeeper/codex_io.bash` | Fake backend | fake `codex` emits no final message and exits non-zero | `empty_transcript` | `8` | `codex.session_diagnostics_ignored` | yes | yes | `tools/validate_upkeeper.sh --full` | full | `surface:fake-backend,status:deferred` | high | medium | medium | medium | deferred |
| FI-004 | `runtime/upkeeper-transcripts` | Transcript artifacts | transcript path exists but is empty | `empty_transcript` | `8` | `empty_transcript` | yes | yes | `tools/validate_upkeeper.sh --full` | full | `surface:transcript,status:deferred` | high | medium | medium | medium | deferred |
| FI-005 | `lib/upkeeper/report_analysis.bash` | Status markers | final message contains quoted or fenced `UPKEEPER_STATUS` | `decorated_marker` | `0` | `status_marker.candidate_rejected` | no | no | `bash tests/wrapper_contract_test.bash` | quick | `surface:status-marker,status:covered-by-contract-test` | high | medium | low | low | medium |
| FI-006 | `lib/upkeeper/report_analysis.bash` | Review summary parser | selected-file summary line contains colon-bearing path | `selected_file_parse_error` | `0` | `review.summary` | no | no | `tools/validate_upkeeper.sh --quick` | quick | `surface:review-summary,status:deferred` | medium | medium | medium | low | deferred |
| FI-007 | `lib/upkeeper/status_session.bash` | Quota/session JSONL | JSONL row has malformed rate-limit payload shape | `session_jsonl_malformed` | `0` | `session_diagnostics` | no | no | `tools/validate_upkeeper.sh --quick` | quick | `surface:quota-session-jsonl,status:deferred` | medium | medium | medium | low | deferred |
| FI-008 | `lib/upkeeper/active_lock.bash` | Active lock | active lock directory has incomplete owner metadata | `ACTIVE_LOCK_INCOMPLETE` | `7` | `active_lock.incomplete` | yes | yes | `tools/validate_upkeeper.sh --full` | full | `surface:active-lock,status:deferred` | high | medium | high | medium | deferred |
| FI-009 | `lib/upkeeper/previous_run_anomalies.bash` | Wrapper health | prior wrapper-health state references stale changed-path violation | `startup_anomaly_gate_unresolved` | `0` | `previous_run.anomaly_summary` | yes | yes | `tools/stress_upkeeper_corpus.sh --local` | full | `surface:wrapper-health,status:covered-by-stress-corpus` | high | medium | medium | medium | medium |
| FI-010 | `lib/upkeeper/fallback_artifacts.bash` | Fallback artifacts | fallback child exit file contains non-integer text | `invalid_exit_code_artifact` | `8` | `fallback.screen.finish` | yes | yes | `tools/validate_upkeeper.sh --full` | full | `surface:fallback-artifact,status:deferred` | medium | low | medium | medium | deferred |
| FI-011 | `lib/upkeeper/fallback_orchestration.bash` | Fallback orchestration | dirty worktree predicted before fallback launch | `dirty_worktree_predicted_block` | `7` | `fallback.skip` | yes | yes | `tools/validate_upkeeper.sh --full` | full | `surface:fallback-orchestration,status:deferred` | high | medium | high | medium | deferred |
| FI-012 | `lib/upkeeper/fallback_screen.bash` | Screen fallback | heartbeat file missing while screen runner remains unresolved | `fallback_screen_heartbeat_missing` | `8` | `fallback.screen.wait` | yes | yes | `tools/validate_upkeeper.sh --full` | full | `surface:screen-fallback,status:deferred` | medium | low | low | high | deferred |
| FI-013 | `lib/upkeeper/worktree_state.bash` | Worktree state | changed-path snapshot contains unallowlisted source mutation | `changed_path_violation` | `0` | `startup_anomaly.gate_violation_summary` | yes | yes | `tools/validate_upkeeper.sh --quick` | quick | `surface:worktree-state,status:covered-by-contract-test` | high | medium | medium | low | medium |
| FI-014 | `lib/upkeeper/help_selection.bash` | Selection | target-file path is a symlink inside repo | `symlink_target` | `3` | `review.preselect.blocked` | no | no | `tools/validate_upkeeper.sh --full` | full | `surface:selection,status:deferred` | high | medium | high | medium | deferred |
| FI-015 | `lib/upkeeper/tool_failure_queue.bash` | Tool failure queue | forged failure marker points at ineligible target | `failure_queue_marker_invalid` | `0` | `tool_failure_queue.selection_ignored` | yes | yes | `tools/validate_upkeeper.sh --full` | full | `surface:tool-failure-queue,status:deferred` | high | medium | medium | medium | deferred |
| FI-016 | `Upkeeper.conf` | Config/env | config requests unsupported `CODEX_MODE` token | `invalid_CODEX_MODE` | `2` | `none` | no | no | `bash tests/wrapper_contract_test.bash` | quick | `surface:config-env,status:covered-by-contract-test` | high | medium | high | low | medium |
| FI-017 | `tools/validate_upkeeper.sh` | Dependency surface | required local dependency missing from PATH fixture | `dependency_missing` | `1` | `validate_upkeeper` | no | no | `tools/validate_upkeeper.sh --deps` | quick | `surface:dependency,status:deferred` | medium | high | high | low | deferred |
| FI-018 | `orchestration/backlog.sh` | Operator diagnostics | interactive loop attaches to stale owner metadata | `stale_active_owner` | `0` | `backlog.active_owner_ignored` | yes | yes | `tools/validate_upkeeper.sh --quick` | quick | `surface:operator-diagnostics,status:deferred` | medium | medium | low | medium | deferred |
| FI-019 | `lib/upkeeper/cycle_cleanup_signals.bash` | Cleanup | SIGINT arrives while fallback child has completed invalid exit artifact | `signal_completed_fallback_invalid_exit` | `8` | `signal.completed_fallback_result` | yes | yes | `tools/validate_upkeeper.sh --full` | full | `surface:cleanup,status:deferred` | medium | low | low | high | deferred |

## Lattice Import Naming

Future Lattice import should treat `scenario_id` as the stable primary key and
split `lattice_ready_tags` on commas into tag strings. Tags should use
`namespace:value` pairs so import can filter surfaces without parsing prose.
Rows marked `status:deferred` are design inventory, not implemented coverage.
