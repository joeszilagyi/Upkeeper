# Change Notes

Version numbering note:
	1. This file records committed Upkeeper wrapper states from v1.0.0 forward.
	2. Some version numbers were skipped during local batching and do not have a standalone committed wrapper state.
	3. Entries focus on notable operator-facing behavior, contracts, defaults, prompt behavior, quota handling, logging, and maintenance expectations.

2026-05-08: v1.1.7 changes:
	1. Added `prompts/p24-de-llm-ing-viability-review.md` as a standalone applicability-gated add-on prompt for reviewing whether stable LLM/Codex-adjacent behavior can move into deterministic local code with no operator-facing loss.
	2. Documented explicit P24 prompt-file usage in the README, prompt index, and operator guide while keeping default and `--prompt-pass=all` behavior on the existing P1-P23 repertoire.
	3. Extended quick validation to assert the standalone P24 prompt exists and preserves its applicability, no-loss, and cost-ceiling contract.
	4. Quoted string and path fields in root `cycle.start` log records so defaults such as `CODEX_MODE=--sandbox workspace-write` and space-bearing `CODEX_HOME` paths remain parseable as single key/value fields.
	5. Captured quota-fallback return codes under `set +e` so intentional non-zero fallback exits still write a terminal `cycle.exit` record instead of surfacing as a false previous-run anomaly.

2026-05-07: v1.1.6 changes:
	1. Rejected malformed root `CODEX_MODE` values whose first token does not begin with `--`, so operator mode typos fail before launching `codex exec` instead of being passed through as positional arguments.
	2. Added quick validation coverage for both missing-dash and triple-hyphen `CODEX_MODE` typos.
	3. Expanded startup-anomaly changed-path enforcement to allow the modular wrapper implementation, required release notes, directly paired central docs, and the validation harness during Upkeeper-suite self-repair.
	4. Aligned postmortem bug-record classification with incident-context classification when fallback child status markers are recoverable malformed candidates.

2026-05-07: v1.1.5 changes:
	1. Added separated live `LLM:` task-status blocks in `basic`, `verbose`, and `debug1` terminal modes by reusing already-streamed assistant prose before backend tool phases, without launching any extra model work.
	2. Added a concise terminal finale after each parsed review summary so `basic`, `quiet`, `verbose`, and `debug1` runs show what was wrong, what changed, and what verification ran without opening the transcript.
	3. Kept `silent` terminal mode silent, moved the older raw `bugs/fixes found` terminal line behind `verbose`/`debug1`, and suppressed duplicate successful command-completion lines from repeated Codex stream events.
	4. Documented the future stress-corpus contract for locally generated sample repositories across common language/toolchain shapes, with model-backed sample runs kept opt-in.
	5. Added a binding backward-compatibility contract that preserves the operator-visible feature surface unless compatibility would be unsafe or impossible.
	6. Rejected malformed auxiliary Codex mode strings before postmortem report or hardening launches so `CODEX_POSTMORTEM_MODE` triple-dash typos fail as clear environment skips instead of later Codex execution failures.

2026-05-07: v1.1.4 changes:
	1. Classified non-zero Codex exits with zero-byte primary transcripts as `CODEX_EXEC_EMPTY_TRANSCRIPT` before generic fallback, instead of borrowing turn-aborted state from a quota snapshot session.
	2. Added transcript byte and line counts to `run.finish` records so launch/capture failures preserve direct local evidence.
	3. Ignored session diagnostics for empty primary transcripts so `cycle.summary` no longer reports unrelated agent/tool counts from the surrounding Codex session.
	4. Added a full-validation fake-Codex check for empty-transcript launch/capture failures.
	5. Fixed the summary-mode live output filter so it consumes piped Codex output instead of replacing pipeline stdin with its Python here-doc.
	6. Suppressed Codex's initial prompt echo as a block in live and post-run transcript signal extraction so prompt text containing words like `Exception`, `failed`, or `ERROR` is not reported as runtime evidence.
	7. Added help, unexpected-argument rejection, and stop-percent validation to the Spark-5.3 xhigh launcher example so operators can inspect and validate it before starting a long-running loop.
	8. Reduced transcript signal noise by treating Codex prose, command status lines, command output, and diff blocks as separate phases before surfacing runtime failures, while de-duplicating repeated status markers.
	9. Hardened Codex I/O helpers so unreadable prompt files fail during CLI resolution, malformed analyzer JSON fails through the wrapper error path, and transcript capture errors are logged instead of being hidden behind a successful Codex exit.
	10. Added numbered command labels to summary terminal output and stopped classifying exploratory search failures as test/runtime failures.
	11. Taught review-summary parsing to capture selected files from final responses that use the compact `Selected \`path\`` wording.
	12. Fixed review-summary selected-file parsing when a Markdown selected-file link is followed by backticked metadata such as an mtime epoch.
	13. Hardened parent-loop stop handling so invalid inherited parent PIDs are rejected before signal delivery and parent-exit races return logged outcomes instead of aborting under `set -e`.
	14. Classified file-view and discovery commands as search before validation/test matching so source-code fixtures no longer appear as live or post-run runtime error signals.
	15. Hardened fallback artifact readers so transient missing or unreadable screen/marker state files return existing sentinel defaults instead of aborting wrapper cleanup or cooldown logging under `set -e`, with quick validation coverage for the helper contract.
	16. Hardened detached screen fallback exit-code artifacts so corrupt or out-of-range values fall back to a logged wrapper failure instead of being propagated into shell return paths.
	17. Changed the default terminal mode to `basic`, moved command-level search/file-view chatter to `verbose`, introduced `debug1`, `quiet`, and `silent` terminal contracts, and kept raw backend streaming behind `full`.
	18. Hardened primary quota cooldown markers so malformed non-finite reset epochs are ignored without tracebacks and marker creation writes through a temporary file before rename.

2026-05-07: v1.1.3 changes:
	1. Refreshed README examples, repository layout, and related-doc links after the module, prompt, validation, and dependency-documentation work.
	2. Fixed the README prompt-file example to reference tracked central prompt files instead of a nonexistent `prompts/review-release-blockers.md` path.
	3. Aligned help/operator-guide wording for fallback, log rotation, current-cycle log review, and dependency-graph expectations without changing wrapper behavior.

2026-05-07: v1.1.2 changes:
	1. Added `docs/dependencies.md` to track Upkeeper's real Bash/system-tool dependency surface separately from GitHub's package dependency graph.
	2. Added `tools/validate_upkeeper.sh --deps` so operators can report required, backend, conditional, and optional command availability without launching Codex.
	3. Documented that GitHub dependency graph and Dependabot alerts should remain enabled, while "No dependencies found" is expected until the repo has a real supported manifest or workflow.

2026-05-07: v1.1.1 changes:
	1. Added `tools/validate_upkeeper.sh` as a tracked validation harness for syntax, version, module-map, prompt-template, help, whitespace, dry-run, symlink, and fail-fast guardrail checks.
	2. Documented quick and full validation modes in the README, operator guide, and help text so future module or prompt packaging changes have a repeatable local release gate.
	3. Kept full validation Codex-safe by using `UPKEEPER_DRY_RUN=1` for central and symlinked startup checks.

2026-05-07: v1.1.0 changes:
	1. Stabilized the modular Upkeeper layout after the staged extraction work and kept root `Upkeeper` as the only operator entrypoint.
	2. Replaced the long module source block with an explicit `UPKEEPER_MODULES` load-order map while preserving the same module order and missing-module fail-fast behavior.
	3. Added `lib/upkeeper/README.md` to document source-only module expectations, load-order ownership, and the current module groups.

2026-05-07: v1.0.55 changes:
	1. Moved the large static default review prompt body out of Bash and into `prompts/default-review.md`.
	2. Split prompt handling into prompt pruning and prompt compilation modules while keeping dynamic wrapper context, prompt overrides, and log-review instructions in shell.
	3. Loaded the default prompt from the resolved central implementation directory so symlinked clients continue to share central prompt behavior without local prompt copies.

2026-05-07: v1.0.54 changes:
	1. Split the preflight/quota module into focused config validation, quota guardrail, session-store, bubblewrap, arg0, process-argument, log-rotation, disk-preflight, previous-run anomaly, worktree-state, and quota-state modules.
	2. Preserved the original preflight and quota function definition order while reducing the last large mixed lifecycle module outside prompt text.
	3. Kept explicit module loading in the root `Upkeeper` entrypoint so symlinked clients continue to resolve the central implementation tree.

2026-05-07: v1.0.53 changes:
	1. Split the runtime module into focused foundation, transcript artifact, active-lock, wrapper-health, progress logging, startup-anomaly state, operator-guide, cleanup/signal, JSON/time-format, and transcript-output modules.
	2. Preserved the original runtime function definition order while reducing the largest shared lifecycle module.
	3. Kept root `Upkeeper` as the only operator entrypoint with explicit module sourcing for symlinked client compatibility.

2026-05-07: v1.0.52 changes:
	1. Split the fallback/postmortem module into explicit process-control, fallback, quota-marker, screen-supervision, auxiliary-Codex, report-analysis, postmortem, and status/session modules.
	2. Kept the root `Upkeeper` entrypoint and module loader explicit so dependency order stays reviewable while reducing the largest single implementation file.
	3. Preserved symlinked-client behavior and missing-module fail-fast semantics from the v1.0.51 modular layout.

2026-05-07: v1.0.51 changes:
	1. Split the central Upkeeper implementation into sourced `lib/upkeeper/*.bash` modules while keeping root `Upkeeper` as the only operator entrypoint.
	2. Loaded modules from the resolved central implementation directory so symlinked client `Upkeeper.sh` launchers continue to run against client checkout state while sharing central wrapper behavior.
	3. Added a terminal-visible missing-module startup failure before lock acquisition, Codex launch, fallback supervision, or parent-loop stop handling can begin.

2026-05-07: v1.0.50 changes:
	1. Stopped quota guardrails from sending SIGTERM/SIGKILL to a bare interactive parent shell such as `bash`, preventing direct one-shot runs from closing the operator's terminal.
	2. Added `CODEX_PARENT_STOP_SKIPPED_EXIT_CODE` with default `75` so skipped parent-stop guardrails still return a loop-breaking status.
	3. Logged explicit `parent_stop_outcome` details on quota guardrail exits so future terminal-stop incidents can be diagnosed from `Upkeeper.log`.

2026-05-07: v1.0.49 changes:
	1. Treated deferred quota decisions as launch blockers instead of allowing Codex probes against stale or partial exact-model snapshots.
	2. Blocked auxiliary post-mortem/hardening Codex launches when either quota bucket is stale after reset, matching the primary quota-safety contract.
	3. Preserved the existing stop/fallback path so operators see a quota warning rather than an empty `codex_exit=101` transcript.

2026-05-07: v1.0.48 changes:
	1. Reported non-zero primary and auxiliary Codex exits as live `ERROR` lines instead of routine `INFO` so quiet terminals still show faults.
	2. Captured post-mortem auxiliary Codex return codes under `set +e` so failed diagnostics write normal failure records and `cycle.exit` instead of aborting through cleanup.
	3. Allowed supervised fallback children to inherit the parent cycle's active lock, and treated cleanup/final marker wrapper-health states as terminal so later runs are not quarantined by already-cleaned-up failures.

2026-05-07: v1.0.47 changes:
	1. Added concise timestamped terminal progress in default summary mode for selected file, Codex start/finish, and long-running primary cycles.
	2. Streamed live Codex/tool error lines from captured transcripts while keeping full raw prompt/code output in pruned transcript artifacts.
	3. Tightened transcript signal filtering so prompt-contract and "no ERROR/WARN" boilerplate is not replayed as high-signal run evidence.

2026-05-07: v1.0.46 changes:
	1. Tightened transcript high-signal extraction so prompt-contract text containing words like quota, failed, or UPKEEPER_STATUS is not replayed as live signal.
	2. Recovered explicit operator-direction requests as `BLOCKED` when Codex exits successfully but asks what to do after stopping on unexpected worktree changes.
	3. Preserved `MISSING_STATUS_MARKER` for genuinely unclassifiable final responses.

2026-05-07: v1.0.45 changes:
	1. Captured primary and auxiliary Codex stdout/stderr to pruned per-cycle transcript artifacts instead of streaming the full backend transcript to the live terminal by default.
	2. Added summary-first terminal output: routine INFO lines stay in `Upkeeper.log`, while WARN/ERROR lines and bounded high-signal transcript summaries remain visible.
	3. Logged high-signal transcript summaries into `Upkeeper.log` so raw prompt/code artifacts can cycle out safely.
	4. Added transcript retention controls with defaults of 24 hours and 200 MB under `runtime/upkeeper-transcripts`, plus `CODEX_TERMINAL_VERBOSITY=full` for explicit full live transcript streaming.

2026-05-07: v1.0.44 changes:
	1. Rejected empty spaced `--prompt-file ""` and `--prompt ""` arguments instead of falling back to the default review prompt.
	2. Made malformed one-cycle prompt overrides fail at argument parsing with actionable diagnostics.
	3. Corrected direct fallback execution-origin logging so non-screen fallback children no longer appear as screen-launched.
	4. Preserved existing non-empty prompt-file and inline-prompt behavior.

2026-05-07: v1.0.43 changes:
	1. Restored the local `json_field` helper used by marker, postmortem, and fallback parsers.
	2. Prevented raw `json_field: command not found` stderr during post-run status classification.
	3. Kept v1.0.42 review-outcome recovery as a fallback rather than the only successful marker path.

2026-05-07: v1.0.42 changes:
	1. Recovered wrapper status from parseable terminal review outcomes when a successful Codex final response omits the literal `UPKEEPER_STATUS` line.
	2. Prevented completed `REVIEWED_AND_FIXED` and `REVIEWED_CLEAN` cycles from stopping loops solely because the final machine marker was missing.
	3. Logged recovered cases with `status_marker.recovered_from_review_outcome` while preserving exact `UPKEEPER_STATUS` markers as the preferred contract.

2026-05-07: v1.0.41 changes:
	1. Allowed startup-anomaly self-review gates to use ignored local `Upkeeper.sh` symlinks as valid local wrapper targets.
	2. Preserved normal timestamp rotation behavior that excludes ignored local wrapper artifacts from ordinary source reviews.
	3. Fixed client-checkout gate failures where central Upkeeper was invoked through the documented symlink pattern.

2026-05-07: v1.0.40 changes:
	1. Added root `change_notes.md` as the standard release-notes file for Upkeeper.
	2. Added release-notes upkeep to the central agent contract in `AGENTS.md`.
	3. Updated the wrapper version policy and operator guide so notable future version bumps are expected to update `change_notes.md`.

2026-05-07: v1.0.39 changes:
	1. Hardened review summary logging after JSON extraction batching.
	2. Fixed the removed `json_field` helper regression in the post-Codex report path.
	3. Made `--prompt-pass=all` coverage detection accept normal Markdown formatting around P1-P23 result lines.

2026-05-07: v1.0.38 changes:
	1. Batched quota snapshot field extraction into one quoted `jq` pass per snapshot.
	2. Batched post-run marker and session diagnostic JSON extraction.
	3. Reduced repeated `jq` process churn without changing quota semantics.

2026-05-07: v1.0.37 changes:
	1. Replaced simple hot-path Python helper calls with cheaper shell, `date`, `stat`, `awk`, and `/proc` parsing.
	2. Reduced pre-Codex wrapper overhead while keeping Python for structured parsing work.
	3. Preserved existing guardrail and prompt behavior.

2026-05-07: v1.0.36 changes:
	1. Trimmed default prompt tokens by removing legacy editor-specific persistence instructions.
	2. Pruned P2, P8, and P16 from normal default prompt bodies when the preselected target is a non-test script/tool file.
	3. Kept full P1-P23 behavior available through `--prompt-pass=all`.

2026-05-07: v1.0.33 changes:
	1. Sped up quota snapshot scanning with bounded head/tail reads before full session fallback.
	2. Kept exact-model quota selection and reset-window freshness checks intact.
	3. Reduced session JSONL read cost for normal current snapshots.

2026-05-07: v1.0.32 changes:
	1. Clarified current-cycle log-review acknowledgment requirements.
	2. Required a concrete raw `UPKEEPER_LOG_REVIEW: CHECKED cycle=<cycle> anomalies=none` or `anomalies=listed` line.
	3. Rejected placeholder `anomalies=none|listed` text in final reports.

2026-05-07: v1.0.31 changes:
	1. Suppressed already-acknowledged previous-run startup anomalies after a later gate resolution.
	2. Kept unresolved gate state files active as real startup-anomaly evidence.
	3. Reduced repeated anomaly churn across healthy follow-up cycles.

2026-05-07: v1.0.30 changes:
	1. Added machine-auditable `review.pass_coverage` logging for `--prompt-pass=all` runs.
	2. Required parseable final-report lines for P1 through P23.
	3. Logged expected, present, and missing pass coverage counts.

2026-05-07: v1.0.29 changes:
	1. Treated one-second quota reset epoch jitter as the same quota window.
	2. Logged tolerated reset drift through `quota.reset_jitter`.
	3. Reduced false non-authoritative quota jump warnings.

2026-05-07: v1.0.28 changes:
	1. Guarded malformed Codex mode defaults.
	2. Ensured the default mode is `--sandbox workspace-write`.
	3. Rejected malformed triple-hyphen sandbox tokens such as `---sandbox` during startup.

2026-05-07: v1.0.27 changes:
	1. Bumped the bundled operator-guide snapshot version.
	2. Kept the tracked guide version aligned with the central wrapper.

2026-05-07: v1.0.26 changes:
	1. Retired stale wrapper-health orphan state from prior runs.
	2. Fixed startup-anomaly review acknowledgment parsing.
	3. Improved recognition of current-cycle log-review acknowledgments so reviewed gates resolve cleanly.

2026-05-07: v1.0.25 changes:
	1. Added `--target-file=PATH` for one-cycle target pinning.
	2. Added `--prompt-pass=all` for full P1-P23 audits against the selected target.
	3. Documented that prompt-pass overrides are one-cycle CLI guidance only.

2026-05-07: v1.0.24 changes:
	1. Hardened startup-anomaly gates.
	2. Added stricter gate state handling and changed-path violation checks.
	3. Improved fail-closed behavior when startup anomalies require Upkeeper self-review first.

2026-05-07: v1.0.23 changes:
	1. Added startup-anomaly detection for previous-run continuity, watchdog, and unresolved gate evidence.
	2. Routed startup-anomaly cycles toward Upkeeper self-review before normal timestamp rotation.
	3. Added startup gate prompt context and runtime gate state tracking.

2026-05-07: v1.0.20 changes:
	1. Added P23 Data Contract and Negative Fixture Audit to the review repertoire.
	2. Expanded prompt coverage for data, schema, parser, validator, and operator-input boundaries.
	3. Required explicit boundary and fixture reasoning where P23 applies.

2026-05-07: v1.0.19 changes:
	1. Moved Upkeeper preselection context to the top of the compiled prompt.
	2. Made the wrapper-selected target visible before the long review prompt body.
	3. Reduced target rediscovery and target switching by the model.

2026-05-07: v1.0.18 changes:
	1. Skipped operator-guide bootstrap when the guide path is ignored local wrapper state.
	2. Avoided tracked client-repo churn for local Upkeeper guide snapshots.
	3. Reinforced local wrapper artifacts as evidence rather than source changes.

2026-05-07: v1.0.16 changes:
	1. Treated ignored Upkeeper guide files as local artifacts.
	2. Reduced false client-repo dirty state from ignored local wrapper documentation.
	3. Strengthened the boundary between central wrapper behavior and client checkout artifacts.

2026-05-07: v1.0.15 changes:
	1. Baseline-tracked dirty Upkeeper review targets before review.
	2. Recorded selected-file git status, content state, head blob, and worktree hash.
	3. Clarified that pre-existing dirty content is not itself a blocker after a clean touch-only review.

2026-05-06: v1.0.14 changes:
	1. Made Upkeeper preselection authoritative.
	2. Directed review cycles to use the wrapper-preselected target instead of rediscovering candidates.
	3. Strengthened clean no-edit touch and content-hash verification expectations.

2026-05-06: v1.0.13 changes:
	1. Added timestamp-based preselection for eligible non-test script/tool review targets.
	2. Logged selected target metadata including path, epoch, age, git status, content state, hash, and selection basis.
	3. Reduced repeated broad candidate-discovery work inside Codex prompts.

2026-05-06: v1.0.12 changes:
	1. Warned on stale Upkeeper operator-guide snapshots.
	2. Compared bootstrapped guide versions against the wrapper version.
	3. Made guide staleness visible without overwriting local guide edits.

2026-05-06: v1.0.11 changes:
	1. Parsed selected-file summary variants more flexibly.
	2. Improved review-summary extraction when final prose used alternate wording.
	3. Reduced missed selected-file metadata in logs.

2026-05-06: v1.0.10 changes:
	1. Hardened cross-repo fallback behavior.
	2. Improved fallback and postmortem behavior when the primary model fails, blocks, or exhausts quota.
	3. Documented cross-repo fallback handling in the operator guide.

2026-05-06: v1.0.8 changes:
	1. Added Codex arg0 temporary shim cleanup preflight.
	2. Checked stale Codex arg0 temp paths before launching Codex.
	3. Quarantined or reported uncleanable temp state before spending model quota.

2026-05-06: v1.0.7 changes:
	1. Kept Upkeeper reviews out of runtime artifacts.
	2. Moved review selection away from local runtime and evidence paths.
	3. Updated guidance around runtime-local state and source-safe review targets.

2026-05-06: v1.0.6 changes:
	1. Hardened Upkeeper operations and review logging.
	2. Added the initial tracked operator guide at `docs/scripts/upkeeper.md`.
	3. Added stronger cycle logging, review summary capture, quota evidence, and operational documentation.
	4. Aligned repository documentation with the Upkeeper wrapper.

2026-05-06: v1.0.0 changes:
	1. Added the initial Upkeeper operator wrapper.
	2. Established one-cycle `codex exec` orchestration with quota guardrails.
	3. Added parent-loop stop behavior, fallback hooks, prompt compilation, status marker handling, and local evidence logging.
	4. Established the central wrapper as the source of truth for Upkeeper behavior.

Reconstructed pre-1.0 history:
	1. The v0.x entries below are reconstructed from Git history before formal Upkeeper versioning.
	2. These are milestone labels, not historical release tags.
	3. v1.0.0 remains the first committed official Upkeeper wrapper version marker.

2026-05-03: v0.4.0 reconstructed changes:
	1. Added maintenance workflow prompt documents for repeated repository care and cleanup work.
	2. Added `caretaking_22_items.md` as a broad maintenance/review workflow prompt.
	3. Added `git_hard_clean.md` as a focused Git cleanup and reset-safety workflow prompt.
	4. Established the repo as a place for reusable operational prompt workflows before the Upkeeper wrapper existed.

2026-05-03: v0.3.0 reconstructed changes:
	1. Scaffolded the prompt-library structure with `prompts/`, `templates/`, and `templates/prompt-template.md`.
	2. Added `.editorconfig` and `.gitignore` for basic repository hygiene.
	3. Switched the repository license to `0BSD` for simple reuse.
	4. Documented a lightweight prompt format with title, goal, use case, inputs, prompt body, and notes.

2026-05-03: v0.2.0 reconstructed changes:
	1. Expanded the README into a clearer reusable LLM prompt-library concept.
	2. Framed the repository around prompts that are easy to find, reuse, and evolve.
	3. Set the expectation that prompt wording should improve from real usage rather than premature over-design.

2026-05-03: v0.1.0 reconstructed changes:
	1. Created the initial repository.
	2. Added the initial `README.md` and `LICENSE` files.
	3. Established the pre-Upkeeper foundation that later became the central wrapper and prompt-operations repository.
