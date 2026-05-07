# Change Notes

Version numbering note:
	1. This file records committed Upkeeper wrapper states from v1.0.0 forward.
	2. Some version numbers were skipped during local batching and do not have a standalone committed wrapper state.
	3. Entries focus on notable operator-facing behavior, contracts, defaults, prompt behavior, quota handling, logging, and maintenance expectations.

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
