# Change Notes

Version numbering note:
	1. This file records committed Upkeeper wrapper states from v1.0.0 forward.
	2. Some version numbers were skipped during local batching and do not have a standalone committed wrapper state.
	3. Entries focus on notable operator-facing behavior, contracts, defaults, prompt behavior, quota handling, logging, and maintenance expectations.

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
