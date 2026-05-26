# 2026 Change Notes

Version numbering note:
	1. This file records committed Upkeeper wrapper states from v1.0.0 forward.
	2. Some version numbers were skipped during local batching and do not have a standalone committed wrapper state.
	3. Entries focus on notable operator-facing behavior, contracts, defaults, prompt behavior, quota handling, logging, and maintenance expectations.
	4. Release notes are annual root files named `change_notes_YYYY.md`; new calendar years start a new root file instead of appending to an old year.

2026-05-26: control-plane audit inventory:
	1. Added `tools/upkeeper_control_plane_audit.py`, a local no-backend inventory for unexpected control-plane state before model work.
	2. The audit emits stable JSON or concise operator text for tracked local-evidence artifacts, root scratch files such as `$db`, active locks, open obligations, optional deferred issue records, and recent hard loop markers.
	3. Quick validation now covers clean inventory, tracked `$db`, tracked runtime/log/transcript/postmortem/manifest artifacts, untracked root scratch, open obligation state, and recent nonzero/PAGE log markers.

2026-05-26: control-plane audit remediation:
	1. The control-plane audit now applies a stable policy table with machine-readable decision ids, policy classes, actions, blocker status, and optional obligation output.
	2. `--remediate-safe` cleans only explicitly safe untracked local artifacts, currently root scratch files such as literal `$db` sidecars and Python bytecode caches.
	3. Backlog runs the audit before staging with safe remediation and blocker failure enabled, so tracked local-evidence artifacts and unsafe root evidence cannot be committed silently.

2026-05-26: Kirk Protocol invariant registry:
	1. Added `docs/kirk-invariants.md` and mirrored `KP-###` invariant metadata in the control-plane audit output.
	2. Audit policy decisions now identify the failed invariant and emit operator-readable invariant failure lines.
	3. `--snapshot-out` and `--before-snapshot` preserve local before/after audit deltas, and backlog records snapshots around branch sync, pre-staging, batch validation, and merge stewardship.

2026-05-26: quota guardrail telemetry custody:
	1. Prior-run anomaly custody now treats managed `quota.guardrails` deferred and partial-decision advisory lines as quota-health telemetry rather than opening duplicate `prior_run_anomaly` bug obligations.
	2. Hard failures, PAGE errors, nonzero exits, identity guardrail stops, and stale-quota obligations remain the durable custody paths for quota-related problems.

2026-05-26: nonzero launcher footer custody:
	1. Prior-run anomaly custody now coalesces backlog job-summary footer lines such as `outcome/results: Upkeeper exited with status 3` and `final disposition: launcher exiting with status 3` into a nearby owned terminal-failure obligation instead of opening a duplicate prior-run anomaly.
	2. Standalone nonzero launcher footer lines remain actionable when no nearby terminal-failure owner exists, preserving fail-closed custody for launcher failures without structured cycle evidence.

2026-05-26: quoted prior-run fixture custody:
	1. Prior-run anomaly custody now treats timestamped historical log snippets echoed through `Upkeeper: primary:` as quoted backend/source evidence instead of live control-plane output.
	2. The quick validator covers prior-run summary and PAGE fixture snippets that previously created duplicate `prior_run_anomaly` issues for `Upkeeper` and `lib/upkeeper/previous_run_anomalies.bash`.

2026-05-26: expected fixture page context:
	1. Backlog watch output now demotes transcript-artifact negative-test
	   `PAGE [ERROR]` fixture lines to `--FYI--` and appends
	   `expected_negative_fixture=transcript_artifacts`, preserving the evidence
	   without presenting passing validation fixtures as live wrapper failures.

2026-05-26: full validator quota-state isolation:
	1. Validation-owned Upkeeper dry-runs now run with explicit quota guardrail and cooldown bypasses so `tools/validate_upkeeper.sh --full` stays deterministic on machines with live quota markers.
	2. File-manifest full validation includes a future quota cooldown marker fixture and proves the audit-only dry-run still completes through the validator-owned no-quota path.
	3. Explicit quota/fallback contract tests remain responsible for exercising real guardrail behavior with their own fixtures.

2026-05-26: backlog quota hibernation retired-branch exit:
	1. Backlog quota hibernation now checks the current branch's local upstream ref before and during long sleeps.
	2. If another worktree merges or deletes the active backlog PR branch while a launcher is hibernating, the launcher exits cleanly with `action=exit_for_merged_or_deleted_branch` instead of holding the retired branch until quota reset.
	3. The check is local-only and does not poll GitHub, fetch, or launch backend Codex during quota hibernation.

2026-05-26: v1.2.37 changes:
	1. Live output custody now recognizes additional quoted backend-source fixtures, including lower-case error markers, trace assignment snippets, and prior-run search snippets, so repair prompts do not turn their own diagnostic text into fresh PAGE obligations.
	2. Startup anomaly gate review now preserves unresolved local startup-anomaly state before considering Codex exit status, reducing misleading gate resolution after backend failures.
	3. Operator-facing version metadata is synchronized across the wrapper header, `UPKEEPER_VERSION`, and the operator guide snapshot.

2026-05-26: docs-only fast path:
	1. Added `tools/docs_only_fast_path.sh --validate`, a local README/docs/prompt-only classifier and validation path that rejects mixed source changes before running public-docs, smoke, and diff checks.
	2. The helper deliberately contains no backend Codex launch, GitHub CLI call, PR polling, `curl`, `wget`, or `git fetch`, so small docs edits can be proved locally before any PR/network bookkeeping.
	3. CI now reuses the shared docs-only helper and fetches enough checkout history up front to avoid a separate classifier fetch when the changed-file scope is locally available.

2026-05-26: previous-run startup residue custody:
	1. Startup previous-run scans now consult current-root prior-run anomaly obligations before treating repeated residue as fresh machine-health evidence.
	2. Already-custodied previous-run and startup-gate residue now logs `previous_run.known_anomaly_residue` and `previous_run.scan status=known_residue` at INFO instead of reopening the startup anomaly gate.
	3. New uncustodied residue still emits `previous_run.anomaly_summary`, enters prompt details, and forces the startup anomaly gate until backlog custody or a later resolved gate records ownership.

2026-05-25: v1.2.36 changes:
	1. Backlog child-failure catchment now classifies backend context-window exhaustion as `backend_context_overflow` with a specific repair target and source cycle/run hash, instead of leaving it as generic missing-status noise.
	2. Prior-run anomaly custody now coalesces terminal-failure companion lines such as failed `run.finish`, missing-status PAGE output, and nonzero `cycle.exit` evidence into the existing terminal-failure obligation for the same cycle or run hash.
	3. Live failure transcript tails default to 24 lines with a byte cap while preserving the private transcript artifact, reducing the chance that a repair loop re-ingests an oversized failure transcript.
	4. Quoted backend source snippets that call `log_line` or `log_line_parts` are treated as fixture echoes rather than fresh live PAGE failures.
	5. Empty-transcript Codex exit failures now use a stable `codex_exec_empty_transcript` obligation identity, and the backlog launcher preserves the child-owned obligation instead of filing a second wrapper-failure record for the same cycle.

2026-05-25: duplicate obligation issue filing circuit breaker:
	1. Open system-level automation obligations now reconcile by failure class, reason, target scope, target, and repair target instead of volatile per-cycle fingerprints, so repeated child-exit or empty-transcript records collapse to one local owner before GitHub issue sync.
	2. The obligation issue-report bridge now enumerates open GitHub issues and reuses an exact title match before creating a new issue; if that lookup fails, it fails closed instead of risking duplicate public bugs.
	3. Obligations already linked to the same specific issue title and issue number now reconcile as one local owner even when their evidence fingerprints differ, so catch-up syncs can retire duplicate local custody records after exact-title GitHub reuse.
	4. Backlog logs now report `github_reused` counts during obligation issue sync, making duplicate-prevention behavior visible in operator output.

2026-05-25: batch validation state isolation:
	1. Backlog batch validation now runs unit tests with isolated obligation and automation-ledger roots, so launcher fixtures cannot inherit the live backlog obligation queue and turn a clean-queue assertion into obligation repair.
	2. ChimneySweep tests ignore ambient `UPKEEPER_OBLIGATION_DIR` by default and use an explicit fixture override when a test intentionally exercises obligation repair.
	3. Live output custody now sanitizes quoted diagnostic search/source snippets after reclassifying them, preventing embedded `[ERROR]` or `PAGE` text from creating fresh anomaly obligations while a repair prompt inspects prior failures.

2026-05-25: anomaly custody fixture suppression:
	1. Prior-run anomaly custody now treats `quoted_backend_source_fixture` lines as already-classified quote output, so old diagnostic snippets containing `[ERROR]`, `[WARN]`, or `PAGE` cannot reopen fresh repair obligations after the live-output filter has sanitized them.
	2. Backlog-temp transcript and pre-contact negative-test lines are recognized as expected fixture output when their matching local tests pass, preventing successful validation from creating new prior-run bugs.
	3. Source-cycle evidence is now coalesced under an existing open or resolved owner obligation for the same cycle/run hash, so already-fixed blocked cycles do not reappear as new incident rollups.
	4. Startup-anomaly changed-path enforcement now ignores the volatile `status_lines` status-output byte count; allowed Upkeeper-suite edits still pass through the path allowlist without keeping the gate unresolved, while disallowed path changes remain actionable.

2026-05-24: source rights metadata model:
	1. Added `docs/source-rights-metadata.md` as the tracked source sensitivity, rights, and reuse metadata model for OSINT and citation artifacts.
	2. Defined public, local-private, secret-adjacent, credential-bearing, PII-bearing, paid-access, license-restricted, prompt-safe, prompt-unsafe, export-safe, and export-unsafe labels.
	3. Defined rights fields for metadata storage, full-text storage, quoting, upload, export, summarization, Wikipedia citation use, public evidence packets, archiving, and robots/terms restrictions, with validation coverage so the vocabulary cannot silently drift.

2026-05-24: parallel backlog worker lease primitive:
	1. Added `tools/backlog_parallel_leases.py`, a no-backend local lease registry for future isolated parallel backlog workers.
	2. The lease primitive rejects duplicate active issue claims, rejects predicted target-file overlap, blocks use of the main checkout as a worker worktree, and supports TTL expiry plus explicit release.
	3. Added deterministic validation and a proposed architecture decision so live parallel worker launch can build on a tested issue/target ownership contract instead of ad hoc manual loops.

2026-05-24: prior-run incident rollups:
	1. Prior-run anomaly custody now collapses same-source-cycle hard control-plane cascades into one `incident_rollup` obligation instead of opening sibling PAGE, nonzero-exit, startup-gate, and PR-gate obligations for the same blowup.
	2. The rollup preserves each individual signal excerpt, fingerprint, target, cycle id, and run hash inside the obligation evidence so repair still has the full local context.
	3. Deterministic validation covers rollup creation, repeat updates, descriptive issue titles, and sibling-obligation suppression.
2026-05-24: per-bug source contract gate:
	1. `tools/validate_upkeeper.sh --source-contracts` now runs the cheapest source-only validation contracts used by backlog per-bug commit gates.
	2. Backlog per-bug validation now runs that source-contract gate when Upkeeper source, tools, or tests changed, catching oversized structured log call sites before commit and push.
	3. A PR-local blocker caused by an oversized `issue_fix.obligation_bind` log line was split with `log_line_parts` so runtime output stays structured while the source contract passes.
	4. Issue-fix runs that map a GitHub issue back to an existing automation obligation now scan the selected open or resolved obligation directory correctly, preventing a pre-Codex `NameError` from aborting the next repair pass.

2026-05-24: descriptive obligation issue titles:
	1. Prior-run anomaly custody now writes script-derived `issue_title` values using the anomaly signal or stable fingerprint, so warnings such as `operator_guide.stale` no longer file as generic `prior_run_anomaly` issues.
	2. The obligation issue-report bridge derives the same descriptive titles for older open records whose title was empty, generic, or still pointed at the umbrella custody issue.
	3. Local validation now covers PAGE-error and operator-guide stale-warning report titles so GitHub issue filing stays deterministic and pre-model.

2026-05-24: Lattice degraded-mode ownership:
	1. Optional `lattice.unavailable` warnings now include a reason class, `owner_issue=430`, `owner_contract=advisory_lattice_degraded`, and the replacement evidence class.
	2. Lattice-unavailable recovery JSONL rows now preserve the same ownership fields with the bounded detail summary, so recurring advisory degraded mode is not anonymous local noise.
	3. Local Lattice validation now checks the warning and recovery ownership fields while preserving fail-closed behavior when Lattice is required.

2026-05-24: preservation policy and artifact privacy:
	1. Added `docs/preservation-policy.md` with evidence temperature values for hot, warm, cold, frozen, and trashable evidence.
	2. Defined artifact privacy classes for public-safe, private-operator, and secret-adjacent material across logs, transcripts, backups, Lattice rows, exports, recovery records, obligations, postmortems, manifests, and public issue or PR text.
	3. Added validation coverage so preservation, redaction, export, recovery, and promotion policy terms cannot silently drift out of the public docs.

2026-05-24: threat model and override doctrine:
	1. Added an explicit `docs/security.md` threat model covering malicious or confused model output, wrapper bugs, config mistakes, operator mistakes, filesystem weirdness, same-user access, secret leakage, public-doc leakage, and quota/fallback weirdness.
	2. Documented degraded-mode behavior for missing `age`, unavailable encrypted backup, unavailable Landlock/bubblewrap, unavailable Lattice, missing validators, dirty baselines, and unsafe targets.
	3. Documented override rules that keep safety overrides operator-visible, evidence-backed, and unavailable to backend Codex, with validation coverage for the doctrine.

2026-05-24: compatibility promise for schemas and contracts:
	1. Defined `stable`, `experimental`, `deprecated`, and `removed` compatibility classes for public schemas, prompt markers, docs/help examples, and Lattice JSONL rows.
	2. Documented schema-version, migration, deprecation-warning, public-example validation, and Lattice import/export compatibility rules in the binding compatibility contract.
	3. Added validation coverage so the compatibility classification and Lattice export/import promises cannot silently drift out of public docs.

2026-05-24: structured policy decisions:
	1. Added `docs/policy-decisions.md` as the schema-v1 contract for local control-plane decisions that must not live only in prompt prose.
	2. Added `lib/upkeeper/policy_decisions.bash` with no-side-effect helpers for emitting and validating policy-decision JSON using the existing `jq` dependency.
	3. Added unit and quick-validation coverage so policy decision fields, capability-profile ids, denied action ids, and authority docs cannot drift silently.

2026-05-24: local PR check watcher:
	1. Added `orchestration/watch-pr.sh`, a no-backend helper for explicit or current-branch-inferred PR check watching.
	2. The watcher prints timestamped pass/pending/fail summaries plus check names, conclusions, and URLs, with distinct exit codes for pass, fail, and pending `--once` results.
	3. Backlog now prints the watcher command after creating or pushing active backlog PR branches so manual restart and merge boundaries have a deterministic local status command.

2026-05-24: serious finding repro fixture policy:
	1. Serious security, data-integrity, destructive-write, target-selection, recovery, and automation-control findings now have a tracked repro-status contract.
	2. Added GitHub issue and pull request template hooks that ask for a local deterministic repro fixture, cloud audit repro, or explicit non-repro rationale.
	3. Quick validation now checks that the serious-finding repro policy and templates remain present.

2026-05-24: after-action review contract:
	1. P27 now defines a concise after-action review shape that includes outcome, what went right, what went wrong, waste, next improvement, and reusable learning.
	2. The pull request template now asks for the same after-action review fields so successful and mostly-successful work can preserve optimization signal.
	3. Quick validation now checks that the P27 prompt, public docs, and PR template retain the after-action review contract.

2026-05-24: backlog stale quota evidence custody:
	1. Backlog quota preflight now records expired-reset stale quota evidence as a `stale_quota_evidence` automation obligation before burn bypass continues.
	2. Repeated stale quota evidence updates one fingerprinted obligation instead of printing recurring warning-only output.
	3. The stale quota obligation is retired automatically once current non-stale quota evidence is observed, keeping recovered quota state from blocking future work.

2026-05-24: backlog batch-validation retry guard:
	1. Batch merge validation now records a private retry marker after the first failed local validation phase on a branch/head/command.
	2. A second identical retry fails closed from that marker, updates the existing repair obligation, and prints the retry fingerprint instead of rerunning the full validation command again.
	3. Retry markers are discarded when the branch/head or command context changes, so repaired or advanced branches can validate normally.

2026-05-24: backlog local-ahead branch guard:
	1. Backlog now detects clean local commits on the active backlog PR branch after branch sync and before batch merge.
	2. Safe local-ahead backlog branches are pushed before PR checks or merge decisions, so checks apply to the current local head.
	3. Dirty, missing-remote, or diverged local backlog branches fail closed with a clear live-output reason instead of merging from stale remote check evidence.

2026-05-24: backlog batch-validation failure obligations:
	1. Backlog batch validation now records a structured local automation obligation when a merge-path validation phase fails, including the phase, command, exit code, bounded output tail, stable fingerprint, likely owner path, and required proof command.
	2. Repeated identical batch-validation failures update the same obligation occurrence count instead of opening noisy duplicates.
	3. The next backlog invocation sees that obligation before merge retry or fresh issue selection, so local validation breakage becomes mandatory machine-health work instead of manual chat memory.

2026-05-24: backlog merge steward:
	1. Added `tools/backlog_merge_steward.py`, a local no-backend guard for already-green backlog PR cleanup.
	2. The steward refuses draft, non-main, failing-check, pending-check, unmergeable, and dirty-secondary-main-worktree states before merge.
	3. Real execution uses the guarded `CODEX_ALLOW_PR_MERGE=<pr>` merge path with GitHub branch deletion, then fetches/prunes and verifies local main is clean.

2026-05-24: backlog stopped-loop triage:
	1. Added `tools/backlog_triage.py`, a no-backend local command that classifies whether a stopped backlog loop is safe to restart.
	2. The command emits `safe_to_restart=yes|no|wait`, a reason, a next action, branch/PR/check metadata, and a short operator summary.
	3. Local fixtures cover clean no-op, dirty worktree, active owner, active lock, open obligation, quota hibernation, pending CI, failed validation, merged-PR cleanup, and unknown PAGE/error evidence.

2026-05-24: negative-space validation contract:
	1. Added `docs/negative-space-testing.md` as the tracked catalog for deterministic "must not happen" validation contracts.
	2. The catalog links target selection, pre-contact backup redaction, replacement authority, source-mutation guards, malformed marker rejection, no-backend validation, config safety, and backend sandbox allowlisting to local proofs.
	3. `tools/validate_upkeeper.sh --quick` now checks that the catalog and its public documentation links stay present.

2026-05-24: breadcrumb custody audit:
	1. Added `tools/audit_upkeeper_breadcrumbs.py`, a deterministic local scanner that fingerprints suspicious log, transcript, automation-obligation, and tool-failure breadcrumbs.
	2. The audit command can write ignored local custody records under `runtime/upkeeper-breadcrumbs/open`, `resolved`, and `suppressed`, preserving weak clues until they are explicitly resolved or suppressed.
	3. Quick validation now covers breadcrumb record creation, duplicate updates, expected-fixture suppression, and resolve-missing behavior.

2026-05-24: Lattice custody authority policy:
	1. Documented that Lattice is supporting evidence, not sole custody authority, for audit, breadcrumb, anomaly, and automation-obligation custody while known Lattice integrity blockers remain open.
	2. Required future Lattice-derived custody decisions to keep fallback log/transcript/runtime evidence checks or fail closed when that fallback evidence is unavailable.
	3. Added validation that current breadcrumb/audit custody code does not require Lattice and that the policy remains present in public docs.

2026-05-24: breadcrumb severity gate:
	1. Open critical/high breadcrumb custody records now redirect normal Upkeeper target rotation to the configured Upkeeper gate target before backend work starts.
	2. Explicit target pins and issue-fix pins remain visible as pinned work instead of being silently replaced, while low/medium breadcrumbs remain custody-only by default.
	3. Suppressed breadcrumb records now carry a named suppression rationale plus an optional expiry field so suppression is machine-readable.

2026-05-24: embedded behavior table contracts:
	1. Quick validation now checks the embedded behavior table drift contract for startup anomaly changed-path allowlists, source-safe exclusions, command-kind classifiers, review-module ids, and Lattice pass-code mappings.
	2. Compatibility and operator docs now identify those tables as operator-visible control-plane behavior that must change with validation coverage instead of drifting silently.

2026-05-24: closed obligation issue links:
	1. Obligation issue-report sync now verifies existing GitHub issue links are still open before accepting them as custody for an open automation obligation.
	2. Closed linked issues are preserved as stale evidence, cleared from the active custody fields, and replaced with a fresh issue for the still-open obligation when GitHub filing is enabled.
	3. If an existing linked issue cannot be verified, backlog records `github_verify_failed` and fails closed before normal issue selection instead of claiming clean custody.

2026-05-24: audit-only no-fix mode:
	1. Added `--audit-only` as the canonical read-only/no-fix audit mode, with `--review-only`, `--no-fix`, and `--read-only` as aliases.
	2. Audit-only mode reuses the bug-report-only final-message report contract, records `audit_only=1` in cycle metadata, and stores local reports under ignored runtime audit evidence by default.
	3. The source mutation guard now reports audit-only source changes as `AUDIT_ONLY_MUTATION_VIOLATION`, and local validation checks the CLI, help, config, prompt, and runtime report routing contract.

2026-05-24: validation dry-run helper:
	1. `tools/validate_upkeeper.sh` now centralizes repeated fake Upkeeper dry-run environment setup in a validator-local helper.
	2. The helper preserves stdout/stderr separation, exit status, isolated CODEX_HOME, log/transcript roots, active locks, and no-backend defaults while still allowing explicit per-fixture overrides.

2026-05-24: quota and session fixtures:
	1. Validation now has named fixture writers for current, stale, wrong-model, malformed, empty, nonfinite, and missing-field quota/session JSONL cases.
	2. The fixture contract is checked locally so parser safety cases stay reusable without reading real operator CODEX_HOME data.
	3. Quota snapshot parsing now treats non-integer reset-window fields as unusable snapshot evidence instead of crashing the local quota preflight.

2026-05-24: anomaly custody issue ownership:
	1. Prior-run anomaly obligations now keep umbrella issue #418 as policy ownership only; each PAGE/error anomaly must have its own specific issue-ready record or GitHub issue before normal backlog work continues.
	2. Backlog now defaults obligation GitHub issue filing on and fails closed if filing fails, while retaining local reports only as evidence copies.
	3. Anomaly custody no longer lets already-open obligations consume the finding cap, and the default cap is unbounded within the recent log scan so later PAGE alerts are not starved by known-open residue.
	4. Quoted backend Python fixture lines such as `print(f'run_record_read=fail ...')` are treated as transcript/source text, and stale obligations containing that evidence resolve as obsolete instead of repeatedly blocking the loop.

2026-05-24: fallback and postmortem guardrail contract:
	1. Documented when fallback is allowed, when it is forbidden, how it handles dirty worktrees, whether it may mutate files, child-count/time limits, complete disablement switches, quota/spend bounds, evidence separation, and recovery success criteria.
	2. Aligned operator guide, help text, default config comments, compatibility notes, and local validation so fallback/postmortem safety rules are a tracked contract instead of scattered implementation details.

2026-05-24: v1.2.35 changes:
	1. Backlog now captures each child `./Upkeeper` invocation to a private
	   bounded evidence file and opens a deduplicated
	   `wrapper_execution_failure` obligation when the child exits non-zero
	   outside the known blocked/quota lanes.
	2. Child-failure obligations infer the likely wrapper owner file from shell
	   crash tails such as `lib/upkeeper/...: line N` so the next run repairs
	   the control-plane defect instead of only retrying the previous work item.

2026-05-24: v1.2.34 changes:
	1. Hardened the entrypoint status-marker parser override so it passes the
	   shared marker parser's full status contract instead of crashing after
	   backend failures without a final `UPKEEPER_STATUS`.
	2. Marker analysis now returns explicit empty analysis for malformed
	   internal calls, and the wrapper initializes marker-assignment defaults
	   before evaluating parsed status-marker fields, preventing repeated PAGE
	   churn from shell `set -u` crashes.

2026-05-24: review-module registry:
	1. Added a narrow review-module registry for P24-P30 ids, aliases, prompt paths, titles, and help summaries.
	2. Switched review-module CLI normalization, max-cover module selection, prompt path lookup, help generation, and validation metadata to consume the registry while preserving existing flags, aliases, logs, and prompt loading behavior.

2026-05-24: shell assignment fixtures:
	1. Added focused wrapper-contract tests for jq-generated shell assignment emitters before any reuse extraction.
	2. The tests cover malformed JSON, invalid prefixes, null and missing fields, arrays/objects, spaces, quotes, newlines, and shell metacharacters while proving emitted assignments do not execute embedded shell text.

2026-05-24: Lattice run-value rows:
	1. Lattice now records normalized `run_values` rows from deterministic pass-result markers, pass attributes, and cycle-finish status so value-oriented questions can be answered without transcript scraping.
	2. The new `query run-values` surface can filter by path, cycle, value kind, value class, and evidence source, exposing pass outcomes, validation commands/results, residual risk, finding notes, cycle status, review outcome, finish reason, and exit codes.
	3. JSONL export/import now carries run-value rows as ordinary repo-scoped SQLite evidence while malformed or missing value markers remain rejected/skipped evidence instead of fatal cycle failures.

2026-05-24: authority model and control ledger:
	1. Added tracked authority, capability-profile, and control-ledger docs that define who may select targets, write source, run shell, spend quota, restore backups, prune evidence, affect GitHub issues, modify Lattice, and read runtime evidence.
	2. Added validation that the authority docs and the initial `AUTH-###` control ids remain present, tying public safety claims to enforcement points, tests, and evidence artifacts.

2026-05-24: log-line maintainability:
	1. Long structured `log_line` call sites now use a shared `log_line_parts` helper and startup-anomaly gate logging helper so repeated field groups remain reviewable without changing emitted log fields.
	2. Local validation now fails if `log_line` or `log_line_parts` call sites exceed 240 source characters, preventing the risky long-line pattern from returning.

2026-05-24: operator status commands:
	1. Added deterministic local status commands: `--status`, `--doctor`, `--last-run`, `--open-failures`, `--quota-status`, and `--json-status`.
	2. `--json-status` emits schema `upkeeper.status.v1` with wrapper version/config, repo state, last logged run, open local failure/obligation counts, active lock state, quota snapshot summary, dependencies, and doctor findings.
	3. Status commands do not acquire the active run lock, launch backend Codex, call GitHub, or mutate runtime evidence.

2026-05-23: v1.2.33 changes:
	1. Pre-contact backup HMAC derivation now caches parent-process key material before subshell helpers run, so backup metadata and payload verification remain stable even when the persistent redaction key file is unavailable.
	2. Transcript/live-output custody now reports validation and check command failures as informational custody notices while preserving test/build failures as terminal errors, preventing already-captured local check failures from becoming fresh prior-run warning obligations.
	3. Review-summary parsing now rejects prose after `STOPPED_ON_BLOCKER for ...` as a selected path unless it has a path-shaped value, preventing blocker explanations from redirecting obligation repair to non-files.
	4. Quota bucket decisions now treat malformed or out-of-range percentage values as `defer`, preserving fail-closed quota behavior without relying on `awk` coercion.
	5. Prior-run anomaly custody and obligation reconciliation now treat quoted backend source fixture lines, including `except Exception as exc:`, as transcript content instead of fresh PAGE errors.
	6. Lattice cycle-finish recording now accepts transcript artifacts under Upkeeper-owned state/temp transcript directories, storing hashed artifact identity without failing optional Lattice recording merely because backlog keeps transcripts outside repo runtime.
	7. Obligation reconciliation now checks quoted backend fixture evidence line-by-line, so existing aggregate prior-run records with repeated source fixture excerpts can resolve deterministically instead of staying in cooldown churn.

2026-05-23: wait-plane logging:
	1. Backlog owner heartbeats now preserve the active operation instead of replacing long waits with generic `owner_process_alive` lines.
	2. Backlog and Upkeeper progress logs now include explicit `plane=...`, `waiting_for=...`, and elapsed wait fields for backend Codex, GitHub checks, git operations, quota hibernation, and local validation.
	3. Upkeeper backend launch, terminal progress, and `run.finish` records now label the LLM/backend wait plane and record backend elapsed seconds, making later speed and cost analysis possible from ordinary local logs.

2026-05-23: tracked-only target selection:
	1. Added `UPKEEPER_SELECT_UNTRACKED` plus `--select-untracked=0`, `--no-select-untracked`, and `--tracked-only` so normal timestamp rotation can exclude non-ignored untracked files.
	2. The default remains backward-compatible: tracked and non-ignored untracked files are still eligible unless the operator opts into tracked-only normal selection.
	3. Explicit `--target-file` pins remain strongest for safe readable text targets, including non-ignored untracked files, and validation now covers default, tracked-only, and explicit-target behavior.

2026-05-23: Codex profile policy documentation:
	1. Documented that the repository intentionally does not commit a project `.codex/config.toml`; Upkeeper's wrapper-owned config surface remains the source of truth for unattended Codex launch policy.
	2. Clarified that local Codex CLI profiles are operator-local state and that any future checked-in Codex profile must document how it composes with `Upkeeper.conf` and validation.

2026-05-23: platform support boundary:
	1. Documented Linux with GNU userland as the supported unattended-run baseline, WSL2 as supported through normal Linux semantics, native Windows as unsupported, and macOS as deferred until GNU/BSD utility drift is handled.
	2. `tools/validate_upkeeper.sh --deps` now prints platform support status, and normal validation modes fail early with a clear unsupported-platform message outside the documented baseline.

2026-05-23: v1.2.32 changes:
	1. Live output custody now reclassifies backend-emitted shell/test snippets that quote log markers, case globs, grep assertions, or `[WARN]`/`[ERROR]` assignments as quoted fixture/search output instead of fresh PAGE errors.
	2. The operator guide snapshot is synced to wrapper version v1.2.32.

2026-05-23: v1.2.31 changes:
	1. Backlog obligation selection now records repeated blocked repair attempts on the selected obligation and applies a deterministic cooldown after the retry limit, so one unresolved obligation cannot consume an entire bounded loop. If all local obligations are cooling down, backlog exits without selecting new GitHub issue work.
	2. Prior-run anomaly custody now treats model-emitted shell/test fixture snippets that quote `[WARN]`, `[ERROR]`, `PAGE`, cycle ids, run hashes, or startup-anomaly text as transcript content instead of fresh wrapper failures.
	3. Open backlog-loop obligations that are deterministically obsolete after the current detector or operator-guide state are moved to resolved evidence with explicit reconciliation reasons.
	4. The default backlog-owned log and transcript artifact directories are now trusted locally before Upkeeper starts, preventing repeated `log.rotate_blocked` and `transcript.prune_blocked` warnings during normal backlog loops.
	5. Backlog now generates deterministic issue-ready reports for every open current-root automation obligation before selecting fresh work. GitHub issue creation for those reports stays wrapper-owned and opt-in with `BACKLOG_OBLIGATION_GITHUB_ISSUE_WRITE=1`.

2026-05-22: v1.2.30 changes:
	1. Active-lock recovery now normalizes the runtime-local lock path, rejects symlinked lock parents or unsafe existing lock paths, and quarantines stale unowned lock directories instead of repeatedly failing the next automation cycle on the same residue.
	2. Verified-owned stale active locks now remove expected state files and quarantine unexpected residue under runtime, preserving evidence while letting the next wrapper cycle acquire a fresh lock.
	3. A deterministic internal active-lock self-test now covers expected stale-lock cleanup and residue quarantine without launching backend Codex work.
	4. Lattice doctor validation now includes backup, recovery, and import integrity probes for source preservation, backup destination collision safety, partial-output cleanup, preexisting empty recovery databases, recovery report failure cleanup, idempotent imported Upkeeper logs, and unexpected JSONL payload fields.

2026-05-22: v1.2.29 changes:
	1. Backlog now runs a deterministic open-obligation reconciliation pass immediately after branch checkout, before PR, merge, quota, or issue-selection gates. Matching current-root records are grouped by root, kind, reason, target, issue, and stable fingerprint so duplicates collapse to one active owner.
	2. Duplicate obligations are preserved under `runtime/upkeeper-obligations/resolved` with `resolved_duplicate`, `duplicate_of`, and reconciliation-key metadata instead of being deleted or handed to the model one by one.
	3. Reconciliation remains pre-model and local-only, keeps foreign-root obligations deferred and visible, and can be bypassed for one cycle with `BACKLOG_OBLIGATION_RECONCILE=0`.

2026-05-22: v1.2.28 changes:
	1. Prior-run anomaly custody now fingerprints repeated findings by stable anomaly class instead of cycle id, run hash, detail hash, timestamp, or temp path, so recurring residue updates one local obligation with occurrence counts and last-seen evidence instead of flooding `runtime/upkeeper-obligations/open`.
	2. The custody scanner no longer opens a second prior-run obligation merely because a previous cycle logged `automation.obligation.open`; the original obligation is the owner for that event.
	3. Backlog partial-work commits now identify local automation obligations by id when obligation remediation blocks, preventing empty subjects such as `Preserve partial backlog work for issue #`.
	4. Automation obligation selection now defers open obligation records whose recorded root belongs to another checkout or temp fixture, while reporting the deferred count in selection metadata so stale foreign-root evidence remains visible without hijacking the current repo's next repair cycle.

2026-05-21: v1.2.27 changes:
	1. Explicit `--target-file` cycles now preflight the pinned target before Lattice initialization, so ineligible explicit targets fail closed as target-selection obligations instead of surfacing later as unrelated Lattice or missing-status failures.
	2. Startup anomaly snapshot parsing now records redacted parse diagnostics and exits the changed-path comparison safely when baseline JSON is malformed, preserving local evidence without exposing raw file paths.

2026-05-21: prior-run anomaly custody:
	1. Backlog now performs a deterministic local prior-run health scan before normal GitHub issue selection, treating deviations from the healthy unattended-run shape as actionable unless deterministic fixture context proves they are expected test output.
	2. Actionable findings are written under `runtime/upkeeper-anomaly-custody` and opened as local automation obligations, so the next Upkeeper job receives a bounded evidence packet and repairs, classifies, or preserves the anomaly before fresh issue work starts.
	3. The custody scanner deduplicates findings by fingerprint across open and resolved obligations, preventing repeated terminal evidence from opening duplicate local obligations while still keeping the original finding record available for later review.

2026-05-21: backlog printf fixture classification repair:
	1. Backlog watch output now treats model-emitted `printf` fixture text containing timestamped `[WARN] startup_anomaly.gate` content as informational transcript output instead of a pageable wrapper/control-plane error.
	2. Formatter validation now covers both the existing echoed `ERROR:` fixture and the new `printf` warning fixture while preserving `PAGE [ERROR]` rendering for real wrapper/control-plane errors.
	3. The backlog default-environment validator now clears inherited backlog model and quota overrides before asserting documented defaults, and autoshelve validation uses fixture-local state so live backlog owner locks cannot break local validation.
	4. Log-rotation marker refresh now uses no-follow descriptor opens and exclusive temp creation, preventing a precreated marker temp symlink from redirecting rotation marker writes outside the log directory.

2026-05-21: backlog PR check settling repair:
	1. Backlog PR-check polling now treats a just-created PR with no reported checks as a pending/settling state for a bounded grace period instead of misclassifying the empty GitHub response as failed.
	2. The wait output now distinguishes "checks not reported yet" from real failed checks, keeps the local owner lease alive while checks attach, and still fails closed if checks remain absent after `BACKLOG_PR_CHECK_EMPTY_GRACE_SECONDS`.
	3. Local validation covers both the empty-check settling path and the bounded timeout path so a fresh PR cannot prematurely end a bounded operator loop before CI has a chance to appear.

2026-05-21: Lattice embedded contract validation parser repair:
	1. Lattice reuse-contract validation now stops shell-function body extraction at the first balanced close for a matched definition, so braces later in the same Bash source file no longer make a single function appear as repeated identical definitions.
	2. Lattice recovery validation now seeds malformed JSONL probes with explicit repo identity and releases in-process subcommand SQLite handles between recovery imports, preventing the doctor check from masking conflict-propagation assertions behind self-inflicted database locks.
	3. Lattice JSONL same-key conflicts again use the stable `kept_existing` resolution token, keeping import evidence aligned with the schema default and local replay validation.
	4. Malformed-only and identityless structured JSONL imports now reach conflict accounting instead of failing before import evidence is recorded; identityless structured rows are still skipped before replay as `repo_identity_missing` conflicts.
	5. Lattice query formatting now flushes stdout inside the handled output block, so downstream tools such as `head` can close the pipe without producing shutdown-time BrokenPipe stderr.
	6. `recover --backup-first` now creates the pre-recovery backup after the recovery source row is committed but before post-recovery imports, so the backup can record its own provenance artifact without foreign-key failures.
	7. Prompt-module structure validation now extracts numeric module ids correctly instead of passing a literal backreference through `grep`.

2026-05-20: finding catalog contract:
	1. The repository contract now requires any observed anomaly, confusing operator-interface defect, contract gap, repeated warning, validation drift, stale evidence, or missing bug filing that is not fixed immediately to be captured as a GitHub issue or local automation obligation with enough evidence for later repair.
	2. Every anomaly must now be treated as evidence for a specific already tracked bug or as a new bug; existing tracked items should receive the fresh evidence, while uncovered anomalies need focused new issues or obligations.
	3. Minor severity now affects priority, not whether the finding must be captured, so small process and human-interface defects cannot exist only in chat history or terminal scrollback.

2026-05-20: Lattice client-root contract validation repair:
	1. Lattice pass-registry installation now validates reusable wrapper contracts against the central wrapper source tree instead of the target repository root, so symlinked or client-root Lattice runs no longer fail only because the client checkout does not contain `lib/upkeeper`.
	2. Future or local pass codes matching the documented `P[0-9A-Za-z_.-]+` shape, such as `P999`, remain accepted as Lattice evidence rows while built-in prompt metadata still comes from the registered pass list.
	3. Backlog launcher validation now clears inherited watched-stdio state before asserting literal green job-summary bars, so batch validation does not fail just because it is itself being displayed through the backlog watch formatter.
	4. Backlog autoshelve active-validation detection now ignores validation processes that are ancestors of the autoshelve probe itself, preventing the validation harness from waiting on its own caller while still blocking on independent active validators.

2026-05-19: backlog validation gate and Lattice snapshot repair:
	1. Backlog per-bug and batch validation now explicitly return on failed syntax, compile, focused test, docs, diff, quick-validator, commit, or push commands, so Bash conditional invocation cannot mask a failed local validation step and continue to commit.
	2. The local quick validator now source-tests the backlog commit gate with simulated failing validation commands, covering the exact failure mode where a focused Lattice test failed but the launcher still staged and committed.
	3. Lattice opt-in worktree snapshot inventory again stores HMAC-only path identities in `worktree_snapshot_paths` while preserving cycle-local lookup and delta-event recording by `path_hmac`, fixing the failing `tests/lattice_test.bash` privacy assertion from PR `#410`.
	4. Session-store preflight validation and docs now match the fail-closed issue `#128` behavior: missing `$CODEX_HOME/sessions` directories are created private, while owned weak-mode directories are rejected without chmod repair before any write probe or backend Codex launch.
	5. Backlog batch merge now explicitly returns on failed local batch validation even when the merge helper is invoked from a Bash conditional, and the quick validator's interactive-stdio probe now clears inherited watch-mode state so it tests a fresh launcher invocation.
	6. Preset `RUN_TMP_DIR` paths now record whether the directory existed before private-directory repair, so a fresh wrapper-managed temp directory can be created and stamped locally while truly stale preexisting directories still require a trusted ownership marker.
	7. Codex arg0 temp cleanup now removes stale matching shim directories only with a trusted Upkeeper/Codex ownership marker and quarantines unmarked matching directories instead of deleting their contents.
	8. Lattice `recover --backup-first` again records the recovery source before the backup copy and stamps that backup with a pre-recovery artifact reference, preserving the provenance boundary before later local Git imports run.
	9. Custom file manifest paths are documented and validated as runtime-local or otherwise ignored local state by default; unsafe paths now have explicit full-validator coverage proving they require the one-cycle unsafe override, and the broad file-manifest fixture has its own timeout budget instead of sharing the tighter generic full-check limit.
	10. Lattice JSONL same-key import conflicts again use the stable `kept_existing` resolution token, malformed-row JSONL fixtures avoid tripping repository-identity fail-closed checks before their intended assertions, and worktree snapshot inventories update file state without linking HMAC-only path rows back to raw `files` identities.

2026-05-18: backlog live-output emphasis:
	1. Interactive backlog watch output now colors `PAGE` timestamps red without blink, keeps the `PAGE` block and marker bold/blinking red, and colors `--FYI--` timestamps orange with bold orange marker text while preserving plain loop logs.
	2. Backlog invocations now emit local-only green `##### ##### #####` start and finish blocks around the locked-in job, showing the target, reason, expected outcome, result, start/end time, runtime, and final disposition before the outer loop sleeps.
	3. Issue-targeted backlog passes that exit cleanly with no tracked changes are now deferred for the current backlog branch, preventing already-addressed or no-op issues from being selected repeatedly in the same loop.
	4. Custom `CODEX_LOG_FILE` paths remain honored as live log sinks, while log rotation and sibling archive pruning stay blocked for custom paths unless explicitly enabled with `CODEX_LOG_FILE_ALLOW_UNSAFE=1` and a trusted Upkeeper rotation marker.
	5. Backlog PR-check waits now print local `gh`/`jq` progress details while holding the owner lease, including pass/pending/fail counts, the active check, elapsed check time, the current Actions step when available, and the check URL.
	6. Interactive `PAGE` lines now render the timestamp as bright white text on a red background, render the non-error payload text bright white, and highlight the `ERROR` text inside `[ERROR]` with the same bold red blink used by the `PAGE` marker.
	7. Backend "usage limit" exits before any agent message now become hard local quota cooldown markers instead of missing-status repair obligations. Backlog honors those hard markers even in burn-mode bypass and hibernates until reset instead of retrying the exhausted model.

2026-05-18: backlog quality gates:
	1. Backlog invocations with recorded fixes now wait for the current PR checks before selecting another issue, stopping on failed checks and holding the local owner lease while checks remain pending.
	2. Light per-bug validation now compiles changed Python files, and Lattice issue fixes that touch `tools/upkeeper_lattice.py` run focused `tests/lattice_test.bash` coverage before the fix can be committed and recorded.
	3. CI and operator validation examples now make the `tests/*.bash` sweep fail fast explicitly, preventing a later passing test command from masking an earlier unit-test failure in copied local commands.
	4. Startup-anomaly validation fixtures now include the owner and schema fields required by the hardened state reader, keeping the local quick validator aligned with the resolver safety contract.
	5. Active-lock release now removes the ownership marker introduced by the stale-lock hardening, and full-validation plus stress-corpus dry-run fixtures now place lock directories under the relevant checkout's `runtime/` tree.

2026-05-18: Lattice JSONL import validation:
	1. Lattice JSONL import keeps verifying `payload_sha256` against the canonical exported payload before staging a row, but no longer rechecks the hash after importer-side sanitization and raw-storage normalization rewrite local evidence fields.

2026-05-18: backlog autoshelve local remediation:
	1. Backlog dirty-worktree autoshelve now distinguishes ordinary local work from Upkeeper control-plane fixes. Ordinary dirty files remain preserved on the private autoshelve branch, while dirty wrapper/modules/orchestration/tools/tests/prompts/config changes are reapplied and committed locally on the active backlog branch before issue work continues.
	2. Autoshelve branch names now avoid timestamp collisions, and a failed control-plane transplant stops the launcher before stale automation can run while leaving the autoshelve branch as local evidence.
	3. Lattice unavailable warnings now log a bounded detail summary with payload size, hash, status, and failed-check count/name; full raw init/doctor output is still spooled to private recovery JSONL for local diagnosis.
	4. Lattice source-record replay now only reuses existing rows when the source identity is anchored by raw/parsed content hash or by a concrete source path plus line number, preventing unanchored wrapper observations from collapsing into one evidence row.
	5. Lattice JSONL imports now reject any default import row carrying a `path-sha256:` redacted path marker, including malformed or truncated markers, unless the operator explicitly opts into anonymized archive import.

2026-05-18: Lattice source-record recovery:
	1. Lattice doctor now installs additive `source_records` identity columns before running internal source-record probes, so existing runtime databases can recover without an integrity-failure wall.
	2. Lattice review-summary parsing again recognizes bare final-prose `REVIEWED_*` outcome lines while still rejecting quoted, fenced, or prose-only examples.
	3. Imported log, transcript, change-note, and recovery source records now carry line/content identity so repeated local imports can update existing evidence rows without collapsing unrelated wrapper observations.
	4. Lattice JSONL query output now redirects stdout to `/dev/null` after a closed downstream pipe so ordinary `| head` usage exits cleanly without BrokenPipe stderr noise.

2026-05-17: backlog watch and cleanup fixes:
	1. Backlog watch output now treats model-echoed shell commands containing `ERROR:` as informational transcript text instead of pageable wrapper/control-plane failures.
	2. Backlog cleanup now removes literal `$db` SQLite scratch artifacts before staging so failed ad hoc validation fixtures cannot enter backlog PRs as source files.
	3. Lattice opt-in worktree snapshot rows now preserve private Git XY evidence without linking HMAC-only path rows back to raw `files` identities.
	4. Strict `UPKEEPER_STATUS` markers followed only by trailing non-control prose are recovered as malformed candidates, reducing false missing-marker failures while still rejecting ambiguous or fenced markers.
	5. Backlog launchers now maintain a local owner lease with PID/start-tick-verified heartbeats; duplicate invocations exit cleanly when the primary is healthy, stale owners are reclaimed locally, and PR-check waits poll in place instead of requiring operator restarts.
	6. Model-derived transcript signals, live terminal status, review summaries, and malformed status-marker candidate logs now pass through a redaction boundary before normal logs or terminal output; protected raw transcripts remain the local evidence source.
	7. Live backlog/watch terminal output normalizes column-one timestamps to local `YYYY-MM-DDTHH:MM:SS`; stored evidence logs keep timezone-rich timestamps where they are part of persisted run state.
	8. Backlog watch output now adds a single visual block column after the timestamp and colors that block by attention class on TTY output, preserving plain marker text for logs and automation.
	9. Backlog interactive watch mode now owns its formatter pipeline through a private FIFO and waits for it to drain before returning to the shell, preventing late PR-check or validation output from writing over the next prompt.

2026-05-16: v1.2.26 changes:
	1. Minimized quota/session metadata in normal logs, cooldown markers, postmortem incident context, and Lattice-facing validation by hashing local session sources and quota identity fields unless explicit verbose local diagnostics are requested.
	2. Hardened config-file sourcing with filesystem trust checks and fixed the assignment-file parser so a valid config no longer exits silently at EOF under `set -e`.
	3. Tightened manifest cache reuse by invalidating legacy payloads that still carry raw checkout-root fields, forcing regeneration into the hashed-root schema.
	4. Cleared raw inline prompt environment variables once a prompt file is authoritative and before screen fallback children launch, reducing descendant exposure of sensitive inline prompt text.
	5. Kept auxiliary postmortem hardening away from model-written report contents by passing only deterministic report metadata and sanitized heading structure into the opt-in hardening prompt.
	6. Fixed Lattice JSONL import reconciliation so same-logical-key schema rows with different validated payloads are recorded as conflicts instead of unconditional duplicates.
	7. Preserved Git porcelain XY status in Lattice live metadata and snapshot evidence, so unstaged-only worktree changes stay `_M` instead of being confused with staged `M_` states.
	8. Changed Lattice worktree snapshots to counts-only by default and, when inventory is explicitly enabled, store path HMACs/classes without linking raw dirty or untracked paths into `files` or `file_paths`.
	9. Recovered final `UPKEEPER_STATUS` markers wrapped only in inline markdown backticks while continuing to reject ambiguous, code-fenced, punctuated, quoted, or multi-marker final lines.

2026-05-16: v1.2.25 changes:
	1. Backlog loops now hibernate locally when quota preflight sees a stop-level quota state or active primary quota block marker, printing the blocked bucket, reset time, wake time, branch, and recent activity before sleeping without backend model work until the reset grace passes.
	2. Added deterministic fake-clock validation for backlog quota hibernation and malformed hibernation input so valid quota stops no longer require manual loop restarts.

2026-05-16: v1.2.24 changes:
	1. Hardened tool-failure queue markers with a machine-local signing key so stale or fabricated queue entries cannot steer later wrapper selection without authentication.
	2. Removed inherited parent argv text from the live wrapper environment after loop classification, keeping quota-loop diagnostics useful without preserving raw launcher command text for child phases.
	3. Tightened auxiliary post-mortem hardening so every hardening pass remains explicitly opt-in and treats prior model-written reports as untrusted structure, with sanitized incident context as the only trusted evidence.
	4. Advanced the file-manifest cache to schema version 2 with a hashed repo-root identifier instead of a stored checkout path, and fixed JSONL replay import of storage-encoded Lattice paths so encoded control-character filenames remain idempotent across export/import.

2026-05-15: v1.2.23 changes:
	1. Hardened Lattice cycle-finish recording so the wrapper-selected target remains authoritative; model-reported replacement targets are preserved as rejection evidence and convert the cycle to `STOPPED_ON_BLOCKER` instead of silently moving the selected file.
	2. Improved Lattice path fidelity for unusual Git paths by using byte-preserving path encoding, `git status --porcelain=v1 -z` parsing, and artifact-reference deduplication/indexes that keep repeated local evidence rows from corrupting recovery state; fresh file manifests now keep repo-relative paths instead of checkout-local absolute paths.
	3. Strengthened selected-target pre-contact backup publication with staged directory commits and payload-hash verification, and restored `doctor` to a single JSON document after its internal probes began exercising the cycle-finish command path.
	4. Backlog watch and detached-loop feeds now timestamp mixed child-process output with a local `YYYY-MM-DDTHH:MM:SS` column-1 prefix while preserving recent-activity summaries across old raw logs and new timestamped logs.

2026-05-15: wrapper contract focused tests:
	1. Added `tests/wrapper_contract_test.bash` as a no-backend focused contract suite for CODEX mode containment, parent-stop PID/shell guardrails, status-marker rejection, and startup-anomaly changed-path redaction.
	2. `tools/validate_upkeeper.sh` now delegates those contracts to the focused test instead of keeping all of that coverage embedded in monolithic validator functions.

2026-05-15: test invocation convention:
	1. Standardized tracked `tests/*.bash` files as non-executable test fixtures invoked through `bash`, matching CI, validation docs, and the agent contract.
	2. Added validator coverage so future executable-bit drift in focused Bash tests fails locally instead of leaving fresh checkouts ambiguous.

2026-05-15: review-module numbering compatibility:
	1. Documented that P29 remains the public reuse-harvesting module and P30 remains Stark Protocol hardening; fault-injection review is reserved for future P31 work or a later named module with a non-breaking alias plan.
	2. Added validation coverage so README, prompt index, compatibility docs, and the operator guide keep that numbering decision aligned.

2026-05-15: future P31 fault-injection contract:
	1. Added the tracked `prompts/p31-fault-injection-review.md` contract for deterministic fault-injection scenarios with a required fault model, explicit oracle classes, containment expectations, and recovery proof.
	2. Kept P31 unwired as a CLI review module for now, while adding validation so the mandatory fault/error/failure/containment, oracle, control, injection, recovery, and registry terms cannot silently drift.

2026-05-15: fault-injection scenario registry:
	1. Added `docs/fault-injection-scenarios.md` with stable `FI-###` ids, required registry columns, FMEA-style priority fields, Lattice-ready tag naming, and initial deferred rows for the major Upkeeper fault surfaces.
	2. Added validator coverage so the registry keeps required columns, sections, id format, quick/full classification, cleanup/recovery flags, surface coverage, and tag namespaces.

2026-05-15: first fault-injection fixtures:
	1. Added a reusable `tools/check_upkeeper_log_invariants.py` checker for wrapper `cycle.start`, `run.finish`, and `cycle.exit` evidence.
	2. Added the first no-quota full-validation fault-injection scenarios for missing review-module prompts, fake backends that exit zero with empty output, stale non-empty active locks, and missing `cycle.exit` log evidence.

2026-05-15: fault-injection injector catalog:
	1. Documented the P31 injector catalog, flakiness bans, and the boundary between focused fault-injection scenarios and the multi-repo stress corpus.
	2. Extended validator coverage so the P31 prompt, Scenario registry, and stress-corpus docs keep the required control/injection/recovery, oracle, not-applicable, and boundary terms.

2026-05-15: jq dependency guidance:
	1. Documented that `jq` remains a required runtime and validation dependency until the Bash JSON bridges have tested Python-backed replacements.
	2. Added portable `jq` install commands and updated wrapper/validator missing-command diagnostics to point operators at `docs/dependencies.md`.

2026-05-15: release-readiness docs:
	1. Added first-class product requirements, roadmap, release checklist, and known-issues docs so release decisions are visible from tracked source.
	2. Linked the release-readiness docs from README and added validator coverage so the entry points remain present.

2026-05-15: governance docs:
	1. Added tracked ownership, decision-log, and risk-register docs for Upkeeper product behavior, shell architecture, prompts, validation, security, compatibility, releases, baseline contracts, and high-impact risks.
	2. Linked the governance entry points from README and added validator coverage so these project-control surfaces stay discoverable.

2026-05-15: client link helpers:
	1. Added no-backend install, update, uninstall, and doctor helpers for central-first client symlinks, with local `.git/info/exclude` setup and forced-overwrite guardrails.
	2. Documented the helper workflow in README and the operator guide, and added focused tests plus validator coverage for the helper contract.

2026-05-15: prompt public lint:
	1. Corrected known public rough edges in the default and caretaking prompt files without restructuring the prompt contracts.
	2. Added quick validator coverage for the banned incomplete sentence and typo phrases so they cannot silently regress.

2026-05-15: startup anomaly watch summary:
	1. Startup anomaly scans now emit one `previous_run.anomaly_summary` warning for ordinary terminal/watch output instead of replaying every prior anomaly as a warning burst.
	2. Per-anomaly `previous_run.anomaly_detail` records are still preserved in local logs and prompt context, and diagnostic terminal modes can still surface the details directly.
	3. Added quick validation so normal output cannot regress to flooding the backlog watch feed with repeated historical anomaly lines.

2026-05-15: validation mode boundary cleanup:
	1. `tools/validate_upkeeper.sh --quick` now stops before wrapper dry-run integration checks such as manifest selection, Lattice validation, config startup, and review-module dry-runs.
	2. Those heavier no-quota checks now run under bounded `--full` validation, with timeout failures naming the specific check that exceeded its budget.
	3. CI keeps broad code-change coverage by running full validation for non-doc changes while docs-only changes keep the cheaper public-docs plus smoke-validation path.

2026-05-15: v1.2.21 changes:
	1. Hardened detached screen fallback staging so generated runner scripts live under a private owner-only state root instead of repo-local postmortem evidence, while mirrored status files remain available for normal operator inspection.
	2. Preserved fallback-chain contracts, selected-target context, issue-fix context, failure-queue context, and prompt/module arguments across staged screen fallback children so recovery workers do not silently lose the parent run's workload boundary.
	3. Added regression coverage for private screen runner staging, mirrored dry-run state, and fallback contract propagation, and documented the new `CODEX_FALLBACK_SCREEN_STAGE_ROOT` operator knob.

2026-05-15: v1.2.18 changes:
	1. Added P30 as the Stark Protocol review module for permanent hardening: useful failures must leave a guard, deterministic validation, documented invariant, automation obligation, or explicit blocked follow-up instead of relying on operator memory.
	2. Extended `--review-module=p30`, `--review-modules=...`, `--p30`, review-module selection filters, Bash completion, Lattice pass metadata, max-cover mode, FlameOn, ChimneySweep, and all-P-module testruns to include P30.
	3. Updated README, operator guide, compatibility docs, public documentation policy, prompt index, validation, and launcher tests so the P30 contract is public and non-regressible.
	4. Hardened backlog dirty-worktree autoshelve so preservation runs after the `git` gate but before `gh`, `jq`, or `rg` dependency gates, allowing dirty local work to be shelved even on minimal validation hosts before the launcher reports missing workload dependencies.

2026-05-16: backlog operator attention markers:
	1. Backlog watch-mode output now adds a second-column operator marker (`RUN`, `WORKER`, `ACTION`, `WAIT`, `--FYI--`, `OK`, `INFO`, or `PAGE`) after the timestamp so routine worker check failures are visibly distinct from true wrapper/control-plane attention events.
	2. `PAGE` is now the pageable human/system attention class; in an interactive terminal it is highlighted red with best-effort blink. Advisory health lines use a non-blinking bold orange `--FYI--` marker, while the mirrored private loop log stays plain text for scripts and assistive tooling.
	3. Recent-activity parsing now understands timestamp-plus-marker loop logs so repeated interactive launches still summarize the active issue/target correctly.
	4. Backlog batches default back to the Spark bucket (`gpt-5.3-codex-spark` with `xhigh` reasoning), set the weekly stop floor to zero, and bypass stale local quota snapshots plus active quota-cooldown markers for reset-window burn-down runs, while preserving explicit guarded-mode overrides.

2026-05-14: v1.2.17 changes:
	1. Added trusted machine-local env loading after the selected config file, with `UPKEEPER_LOCAL_ENV_FILE` and `UPKEEPER_LOCAL_ENV_DISABLE` as the operator-controlled surface for machine-only backup/bootstrap settings.
	2. Added `tools/upkeeper_precontact_bootstrap.sh` so operators and symlinked clients can create or reuse a local age identity and write only the public `UPKEEPER_PRECONTACT_BACKUP_AGE_RECIPIENT` into machine-local state instead of tracked repo config.
	3. Live apply-stage and normal repair cycles now preflight required encrypted backup before issue selection, record missing-recipient failures as machine-health obligations, and make FlameOn/ChimneySweep stop plainly for operator action instead of misclassifying the next issue target.

2026-05-14: backlog dirty-worktree autoshelve:
	1. `orchestration/backlog.sh` now preserves a dirty local wrapper worktree automatically by committing it onto a dedicated local `wip/backlog-autoshelve/...` branch before starting new issue work, then returning to the original branch clean.
	2. The launcher still refuses to start issue work on top of a dirty tree, but it no longer forces the operator to hand-stash or hand-branch routine local wrapper edits first.
	3. This preservation path stays local by default instead of auto-opening a PR, because a blind PR from an existing backlog branch can accidentally stack unrelated backlog fixes into the wrong review.

2026-05-14: v1.2.16 changes:
	1. Selected-target pre-contact backup now defaults to encrypted-required mode for ordinary `./Upkeeper` runs, so missing `age` or a missing public recipient stops the cycle before backend launch instead of silently falling back to plaintext.
	2. Plaintext pre-contact backup is now available only through an explicit unsafe operator override (`UPKEEPER_PRECONTACT_BACKUP_REQUIRE_ENCRYPTED=0` plus `UPKEEPER_PRECONTACT_BACKUP_ALLOW_UNSAFE_PLAINTEXT=1`), making the compatibility break and migration path explicit.
	3. Added a high-confidence plaintext content gate that rejects private-key material before writing `.bak` artifacts, and refreshed local tests plus operator-facing help/docs for the tightened contract.

2026-05-13: v1.2.15 changes:
	1. Backlog batch runs now support safe interactive watch mode by default: `orchestration/backlog.sh` cuts off stdin, keeps live output visible in the current terminal, and mirrors that output to the private backlog loop log, while `orchestration/backlog_loop.sh` and `BACKLOG_INTERACTIVE_MODE=detach` remain available for fully detached looping.
	2. Backlog runs default to quiet terminal verbosity, reducing live model chatter on unattended issue batches while preserving full transcripts under the backlog state directory.
	3. Explicit issue-target handoff now ignores excluded runtime/log/.git targets before preselection, and backlog issue hints map manifest-related issues to `lib/upkeeper/file_manifest.bash` instead of handing `runtime/upkeeper-file-manifest.json` to Upkeeper.
	4. Lattice backups now avoid a destination-connection path that could stall local validation while holding a zero-byte backup file and source journal.
	5. Interactive backlog notices now include the current branch, recent issue/target activity, and a ready-to-run `tail -f` command; repeat interactive invocations attach only when a validated repo-local active owner file still points at a live backlog PID for the same checkout, which avoids stale-process guesses and old log history masquerading as a current run.

2026-05-12: lattice Git import privacy defaults:
	1. `tools/upkeeper_lattice.py import-git` now stores contributor identity as a stable SHA-256 token by default and only preserves contributor name/email when `--include-contributor-pii` is explicitly requested.
	2. Git commit imports now store a subject hash plus subject length by default, keep raw subjects only behind `--include-commit-subjects`, and scrub legacy non-opt-in rows on the next mutating lattice pass.
	3. `query file-history` and `export-jsonl` now follow the same privacy contract so default operator-facing outputs no longer surface raw Git contributor PII or commit subjects from non-opt-in rows.

2026-05-14: lattice export/import privacy defaults:
	1. `tools/upkeeper_lattice.py export-jsonl` now redacts raw payload fields and path-bearing fields by default, with explicit `--include-raw`, `--include-paths`, and `--include-contributors` opt-ins for operators who need disclosure.
	2. `tools/upkeeper_lattice.py import-jsonl` now defaults to redacting imported raw source lines, and replay-oriented roundtrip validation explicitly requests `--include-paths` when it needs full-fidelity structural reconstruction instead of the privacy-default export.
	3. Structural lattice fields such as `source_kind` are no longer path-redacted, preventing privacy-default exports from corrupting source-record identity semantics.

2026-05-13: v1.2.14 changes:
	1. Cleared the deferred data-protection issue cluster by rejecting control characters in prompt-file paths, using central log key/value encoding for `run.start`, and removing the prompt-file path from compiled prompt prose.
	2. Startup-anomaly unresolved-state prompts now expose only HMAC state ids, reason classes, timestamps, and redaction markers; raw state paths, run hashes, and details stay in protected local state files.
	3. Startup-anomaly and selected-target changed-path logs now publish path HMACs, coarse path classes/extensions, statuses, and `content_changed` booleans while preserving full raw path/hash evidence in protected local diagnostics.
	4. Selected-target preselection, pre-contact backup metadata/logs, and Lattice artifact references now use keyed HMAC fingerprints for path and content identity instead of raw SHA-256/git object hashes on normal operator-facing surfaces.

2026-05-12: v1.2.13 changes:
	1. Startup disk-preflight anomaly notes now send only safe labels and free-space percentages to the model, while local logs hash path and mount metadata by default and expose raw shell-quoted values only in debug1 or full terminal mode.
	2. This release also keeps the default prompt from reintroducing replacement-target authority and sets a private process umask before runtime artifacts are created, with deterministic local validation covering the tightened contracts.

2026-05-12: default prompt no longer grants unconditional replacement targets:
	1. The default review prompt no longer contains a standalone "select the next oldest eligible file" instruction in the physical/safety exception branch.
	2. Replacement selection is now explicitly conditional on the absence of `WRAPPER_PRESELECTED_REVIEW_TARGET`, and preselected-target cycles keep `STOPPED_ON_BLOCKER` as the required outcome when the selected file is impossible or unsafe.

2026-05-12: disk preflight prompt and log metadata redaction:
	1. Startup disk-preflight prompt notes now carry only safe labels plus free-space percentages, so low-space anomaly prompts no longer expose raw paths, probe paths, mount names, or size/usage fields to the model.
	2. Local `disk.preflight` logs now hash path and mount metadata by default and emit raw shell-quoted values only in `debug1` or `full` terminal mode for explicit local diagnosis.
	3. Added deterministic quick validation for both the redacted local log contract and the sanitized prompt-note contract.

2026-05-12: private artifact umask at entry:
	1. Upkeeper now sets `umask 077` at process entry before config loading or runtime artifact creation, so logs, transcripts, queue markers, postmortem files, locks, and similar local state default to owner-only permissions even on permissive host umask settings.
	2. Added quick validation that fails if the entrypoint loses this early private-umask contract.

2026-05-12: imported Upkeeper log rows now drop sensitive parsed fields by default:
	1. `lattice import-upkeeper-log` now stores only a small safe allowlist in `source_records.parsed_json`, instead of persisting full parsed log key/value payloads when raw-line import is disabled.
	2. Imported log replay no longer backfills sensitive normalized cycle fields such as selected paths, finish reasons, model/mode, or config-file values from log text, while preserving safe lifecycle status fields needed for sparse replay.
	3. Added deterministic lattice coverage proving sensitive parsed keys are omitted from stored source records and normalized cycle rows.

2026-05-11: bug-report-only draft-gating changes:
	1. Changed `--bug-report-only` from a soft “file an issue if possible” prompt into a wrapper-owned local draft workflow, with issue-ready bug reports now expected through a final-message draft block that Upkeeper saves under runtime-local bug-report drafts.
	2. Added a bug-report-only `gh` gate inside the Genie Protocol broker so backend Codex can still use read-only GitHub inspection, but `gh issue create` stays blocked unless `UPKEEPER_ALLOW_GH_ISSUE_WRITE=1`.
	3. Required `REVIEWED_AND_REPORTED` bug-report-only runs to leave a durable local draft artifact, blocking the cycle when the final response claims a reported bug without the wrapper-readable draft block.

2026-05-11: dirty-checkout reconciliation changes:
	1. Hardened direct fallback recovery so parent cycles always create a private fallback contract directory before launching a child run, preserve contract-carried target and issue context, and cleanly finish quota-triggered dry-run fallback orchestration.
	2. Strengthened fallback and active-lock trust boundaries by hashing inherited fallback-chain tokens in lock state, requiring matching parent-process fingerprints for lock inheritance, and validating dry-run fallback tests against the real direct-child contract instead of looser shell-subprocess behavior.
	3. Hardened precontact backup and quota-marker private state by requiring private temp and vault directories, rejecting symlinked backup-root path components, removing backup identifiers from operator log lines, cleaning restore temp state on failure, and mirroring active quota markers into a private store instead of trusting public marker paths alone.
	4. Tightened operator-facing status and issue-fix trust rules by treating only plain accepted final markers as recoverable session outcomes, mapping `NO_CHANGES` to wrapper-owned work completion instead of a model marker contract, and ignoring inferred issue target files unless the issue workflow explicitly selected them.
	5. Added salvage validation for the rescued bug-fix batches and lattice edge cases covering checked-out branch import state, read-only backups, transient-artifact age pruning, secure restore cleanup, quota-marker privacy, startup-anomaly evidence requirements, and issue-workflow target handling.

2026-05-11: post-v1.2.12 catch-up changes:
	1. Fixed `CODEX_MODE` parsing so the default sandbox pair `--sandbox workspace-write` remains valid while malformed first tokens, malformed sandbox arguments, and unsafe unsandboxed modes still fail closed with clear errors.
	2. Fixed pull-request CI scope classification so docs-only detection fetches any missing base or head commit before diffing and falls back to full validation when commit scope cannot be proven locally.
	3. Removed the invalid log-parent directory link-count rejection so dedicated operator or validator temp directories no longer fail closed before the existing log-file hardlink protections run.
	4. Restored issue-fix target pinning for normalized repo-local file references inferred from queued GitHub issues, so `--fix-next-issue` and explicit issue handoffs both carry the selected target into preselection.

2026-05-11: v1.2.12 changes:
	1. Hardened startup-anomaly gate resolution to use wrapper-derived current-cycle log evidence (`cycle.start`, `run.start`, `run.finish`, `cycle.exit`) before resolving gate state.
	2. Removed the model self-attestation-only startup gate resolution path so unresolved or unverifiable gates now stay closed and force a follow-up self-review cycle.
	3. Expanded source mutation fingerprinting to include refs and recent reflogs, so committed history mutations and ref updates now count as source changes.
	4. Switched manifest-based candidate ranking to live filesystem mtimes for ordering, preventing model-writable manifest data from steering selection.

2026-05-10: v1.2.11 changes:
	1. Made `--prompt-pass=all` fail closed when final pass-result coverage is incomplete or unavailable.
	2. Counted real `UPKEEPER_PASS_RESULT` lines, including common Markdown-decorated forms, for machine pass-coverage enforcement.
	3. Added local quick validation for decorated pass-result parsing and all-pass coverage blocking.
	4. Fixed fallback postmortem completion so successful `run_postmortem_sequence` paths return the fallback child exit code instead of forcing `7`, preventing synthetic `FALLBACK_CHAIN_EXIT` outcomes during normal recovery.
	5. Documented the binding unattended-run trust contract: machine health outranks workload, no prior automation failure should escape oversight, and a healthy empty queue should exit quickly without backend work.
	6. Cut docs-only iteration cost by limiting CI push runs to `main` and routing docs-only CI validation through `tools/validate_upkeeper.sh --smoke` instead of `--quick`.
	7. Prefixed wrapper-posted ChimneySweep staged issue comments as `Upkeeper ChimneySweep proposal:` and `Upkeeper ChimneySweep review:` so public GitHub actions are visibly distinguishable from human comments.

2026-05-10: v1.2.10 changes:
		1. Hardened target selection so paths matching Git ignore rules are rejected even when they have been force-added to Git.
		2. Applied the same `git check-ignore --no-index` contract to explicit `--target-file` validation, normal enumerate/manifest selection, manifest generation, and Lattice/max-cover candidate diagnostics.
		3. Added deterministic quick validation with a temp repo containing a force-added ignored executable to prove explicit, automatic, manifest, and Lattice selection paths exclude it.
		4. Hardened target selection so tracked symlinks are rejected before stat, read, hash, prompt selection, manifest generation, or Lattice/max-cover candidate reporting can follow them outside the repository.
		5. Added deterministic quick validation with a temp repo containing a tracked symlink to an outside sentinel file to prove explicit, automatic, manifest, and Lattice selection paths fail closed.
		6. Hardened the Codex session-store write preflight so `$CODEX_HOME/sessions` must be a real user-owned directory; owned session directories with weak inherited permissions are repaired to `0700` before Upkeeper probes them.
		7. Replaced the predictable session-store marker file with an unpredictable `mktemp -d` probe directory and child probe file, preventing a preexisting marker symlink from being followed or truncated.
		8. Added quick validation proving normal session-store probes leave no residue, predictable marker symlinks are not followed, symlinked session stores fail closed before probing, and owned weak-mode session stores are repaired before probing.
		9. Made compact `review.summary` and `review.fix_details` logging fall back to the wrapper-selected target when the final model message omits a selected file, preventing live issue-workflow evidence from degrading to `selected_file=unknown`.
		10. Added the shared automation obligation framework: every Upkeeper cycle can write a durable run record under `runtime/upkeeper-automation-ledger`, and non-zero cycle exits create unresolved obligations under `runtime/upkeeper-obligations`.
		11. Made FlameOn and ChimneySweep identify themselves through the shared automation framework so future derivative launchers can supply identity and policy without inventing separate state formats.
		12. Made FlameOn and ChimneySweep reconcile open automation obligations before their normal bug-finding or GitHub issue-selection policies, handing the selected obligation to Upkeeper as a locked target plus wrapper-generated prompt file.
		13. Added successful obligation-cycle resolution: when an obligation-selected non-dry-run cycle exits cleanly, Upkeeper moves the selected obligation from `open` to `resolved` with resolver cycle evidence.
		14. Added `5.3-codex-spark_xhigh` as a supported Upkeeper model override alongside `5.5_xhigh` so launcher dogfooding can intentionally use the Spark quota bucket after reset.
		15. Added `--model-override=...` plus `--model ... --reasoning-effort ...` shortcuts to FlameOn and ChimneySweep, with dry-run and completion coverage.
		16. Added `tools/validate_upkeeper.sh --smoke` for fast local edit-loop validation and `--profile` for per-check timing without reducing quick/full validation coverage.

2026-05-09: v1.2.9 changes:
	1. Made `ChimneySweep` default to a staged issue workflow: comment, review, then apply, with a separate Upkeeper/Codex instantiation for each stage.
	2. Added `--issue-workflow-stage=comment|review|apply` for scripted issue-fix handoffs. comment and review stages are tracked-source read-only and instruct Codex to leave `ChimneySweep proposal:` / `ChimneySweep review:` issue comments; apply is the implementation stage.
	3. Added `--workflow=comment-review-apply|comment-review|comment|review|apply` to ChimneySweep so every stage combination can be dry-run or live-tested against the same deterministic issue ranking.
	4. Generalized the bug-report-only source mutation check into a source mutation guard reused by issue comment/review stages.
	5. Rendered staged issue-comment commands with the resolved issue number instead of relying on wrapper-local shell variables inside Codex tool commands.
	6. Made the local tool-failure queue resolve same-run failures after a later successful rerun, even when the model correctly ends BLOCKED for a separate reporting or coverage reason.
	7. Added the Genie Protocol boundary for backend Codex launches: Upkeeper scrubs GitHub token environment variables, points `gh` at an empty per-run config directory, and shadows direct `gh`, `curl`, `wget`, and `hub` calls with blocker commands.
	8. Moved staged issue comments to a wrapper relay: comment/review models emit a final-message draft block, and the wrapper extracts and posts it to GitHub only after the source-read-only guard passes.
	9. Rejected `CODEX_MODE` values that request `danger-full-access` or `--dangerously-bypass-approvals-and-sandbox`, because those modes are incompatible with the Genie Protocol backend containment contract.
	10. Forced comment/review issue-workflow backend launches into `--sandbox read-only`, with no backend-writable draft directory, so those stages can inspect source but cannot modify tracked source or local draft artifacts.
	11. Allowed staged review comments to put their decision on the first line, such as `ChimneySweep review: revise`, while still requiring the final-message draft block and wrapper-owned GitHub relay.

2026-05-09: v1.2.8 changes:
	1. Made the repo-root `FlameOn` and `ChimneySweep` automation launchers full-burn by default: Lattice is required, pre-contact backup is required, encrypted backup is required, and `CODEX_MODE` is pinned to `--sandbox workspace-write`.
	2. Made `ChimneySweep` hand locked issues to Upkeeper with `--prompt-pass=all` and all P24-P29 review modules so repair automation exercises the full review surface against the scripted target.
	3. Extended launcher dry-run output and tests so the fail-closed evidence, vault, and containment defaults are visible before backend launch.
	4. Added `age` to CI and dependency/workflow documentation as the live full-burn launcher dependency, including local recipient setup and private-identity handling guidance.
	5. Made full-burn launchers spend-to-zero by forcing five-hour and weekly quota stop floors and buffers to `0`, bypassing wrapper quota guardrail stops, and bypassing persisted quota-cooldown markers from earlier guarded runs.
	6. Isolated validator postmortem state and launcher-only full-burn environment knobs so live quota-cooldown, guardrail-bypass, and encrypted-backup settings cannot block no-quota quick checks.
	7. Left plain `./Upkeeper` compatibility defaults unchanged; the full-burn contract applies to the automation launchers intended for dogfooding and scheduled stress.

2026-05-09: v1.2.7 changes:
	1. Hardened live wrapper log preparation so symlink, non-regular, hard-linked, or wrong-owner `Upkeeper.log` paths fail closed before the first wrapper log append and before Codex launch.
	2. Routed wrapper-owned log appends through a no-follow append helper that creates new logs as user-owned `0600` regular files and rejects symlink log parent directories.
	3. Added deterministic quick validation proving a default symlinked-client `Upkeeper.log` is rejected without modifying the symlink target, and documented the new security behavior.
	4. Ignored rotated `Upkeeper.log.*.zip` archives so local log rotation evidence remains out of source control.

2026-05-09: v1.2.6 changes:
	1. Added the repo-root `ChimneySweep` launcher as a separate issue-fix automation path from `FlameOn`.
	2. Made `ChimneySweep` list and rank open GitHub issues deterministically before any backend Codex process can start; clean actionable queues print `high five yay` and exit 25.
	3. Ranked `ChimneySweep` issue repair by security class first, data-integrity class second, then the general queue by containment title/tag signals, severity, and least-recently-touched age.
	4. Added `--fix-issue=NUMBER` and `UPKEEPER_FIX_ISSUE` so scripted callers can hand Upkeeper one locked issue without letting Upkeeper reselect a different issue.
	5. Updated Bash completion, validation, docs, compatibility notes, CI syntax checks, and local tests for the new launcher and explicit issue handoff.

2026-05-09: v1.2.5 changes:
	1. Added selected-target pre-contact backups before the compiled prompt grants Codex authority over the shell-selected target.
	2. Added plain local backup mode as a recovery aid and age public-recipient encrypted mode for encrypted backup artifacts without requiring a private identity during backup creation.
	3. Made required backup failures stop before backend launch with `codex_exec_started=0`, while logging only opaque backup id, selected relative target, content sha256, mode, encrypted flag, backend-protection flag, and `path_redacted=1`.
	4. Added retention pruning per repo/path key, conservative manual restore by backup id through `tools/upkeeper_precontact_restore.sh`, and local tests for success, failure, redaction, retention, restore, and age command behavior.
	5. Removed prompt authority for Codex to choose a replacement target when the preselected target is impossible or unsafe; the prompt now requires `BLOCKED` because replacement selection is wrapper-only and backup coverage is target-specific.
	6. Rejected symlink selected targets for this first backup slice and updated symlinked-client stress coverage so invocation still works while backup targets remain regular files.
	7. Documented the no-root/no-sudo boundary, including that plain same-user backups are not LLM-inaccessible and that Landlock, bubblewrap, and privileged vaults are separate future hardening layers.

2026-05-09: v1.2.4 changes:
	1. Added `--bug-report-only` with `--file-bug-only` and `--report-bug-only` aliases so an Upkeeper cycle can investigate and file/report confirmed bugs without editing or touching tracked source.
	2. Made `FlameOn` pass `--bug-report-only` by default, turning high-coverage burn cycles into issue-finding/reporting runs instead of source-fixing runs.
	3. Added a bug-report-only source mutation fingerprint check so a non-dry-run report-only cycle fails as `BUG_REPORT_ONLY_MUTATION_VIOLATION` if tracked source state changes during the run.
	4. Added `--fix-next-issue` with the `--fix-oldest-bug` alias so Upkeeper can select the oldest open GitHub issue by priority label order `security`, `data-integrity`, then `bug`, infer a starting target file from the issue body, and run a focused repair cycle.
	5. Added the `REVIEWED_AND_REPORTED` review outcome for cycles that file an issue or produce a complete issue-ready bug report without applying a source fix.
	6. Documented and validated the new mode flags, config defaults, FlameOn default, completion entries, and compatibility boundaries.

2026-05-09: v1.2.3 changes:
	1. Added `.upkeeperignore` as a first-class Upkeeper target-selection firewall for files Git may still track but Upkeeper should not spend model upkeep cycles reviewing.
	2. Wired `.upkeeperignore` into manifest construction, normal selection, explicit `--target-file` eligibility, failure-queue target eligibility, and Lattice/max-cover candidate ranking.
	3. Added `UPKEEPER_IGNORE_FILE` so scheduled profiles can point a checkout at a different ignore file while preserving `.upkeeperignore` as the default.
	4. Documented that `.upkeeperignore` is a spend/selection control, not a Git ignore rule, Codex sandbox boundary, or secret-protection mechanism.
	5. Extended validation and Lattice tests so `.upkeeperignore` paths cannot become explicit targets or max-cover candidates.

2026-05-09: v1.2.2 changes:
	1. Added the repo-root `FlameOn` launcher for one-command high-coverage smoke/burn runs. It invokes Upkeeper with `--model-override=5.5_xhigh --max-cover`, limits terminal verbosity flags to `--silent`, `--basic`, and `--debug1`, and preserves normal quota, startup, fallback, and evidence guardrails.
	2. Added `--max-cover` and `UPKEEPER_MAX_COVER` as one-cycle/high-coverage mode controls that force `--prompt-pass=all`, append P24-P29, and ask Lattice for max-cover target ranking.
	3. Added `--backup-queue` plus the legacy `-backup_queue` spelling so one cycle can use `runtime/unaddressed-tool-failures-backup` without changing the normal failure queue.
	4. Extended Lattice `selection-candidates --mode max-cover` to rank current tracked source-safe text by unrun active passes, least per-pass coverage count, and oldest mtime while keeping live source-safety revalidation authoritative.
	5. Added optional Bash completion for `Upkeeper`, `Upkeeper.sh`, and `FlameOn` at `completions/upkeeper.bash`, plus deterministic tests and docs for the new launcher and max-cover path.
	6. Clarified that Upkeeper config files are sourced by Bash and must be treated as trusted executable shell code, not inert data.
	7. Made `tools/check_public_docs.sh` fail with an explicit `not a Git worktree` diagnostic when run from a checkout copy without Git metadata.
	8. Hardened review-summary parsing so baseline metadata such as `Selected target baseline: epoch ...` cannot replace the actual selected file in compact `review.summary` log fields.
	9. Reduced validator log noise and transient failure risk by keeping expected invalid-flag checks in temp logs and allowing manifest-reuse validation to continue when the repo fingerprint changes during an active validation window.
	10. Made Lattice query output tolerate closed stdout pipes, so commands such as `tools/upkeeper_lattice.py query selection-candidates ... | head` do not print a Python `BrokenPipeError`.

2026-05-09: v1.2.1 changes:
	1. Hardened `tools/upkeeper_lattice.py import-git` so rerunning a local Git import skips already-recorded per-commit file changes instead of multiplying `git_file_changes` churn evidence.
	2. Added a unique Git file-change guard and normal `init` repair for duplicate Git change rows left by older local Lattice databases.
	3. Kept renamed-file lineage attached when a renamed path is changed later, and allowed `file-history` queries to resolve through prior path aliases.
	4. Extended Lattice validation with repeated Git import, duplicate repair, and rename-after-modify fixtures.

2026-05-08: v1.2.0 changes:
	1. Added Upkeeper Lattice as a default-on local SQLite evidence ledger at `runtime/upkeeper-lattice/lattice.sqlite3`, using Python stdlib `sqlite3` without a daemon, ORM, package manifest, network sync, or GitHub token storage.
	2. Added the normalized schema v1 ledger, doctor, backup, JSONL export/import, local recovery, Git import, Upkeeper log import, change-note import, regression marking, pruning, and initial query surface.
	3. Wired wrapper lifecycle hooks to record cycle starts, preselection evidence, candidate rows, pass-result markers, worktree snapshots, and terminal finish paths while preserving live source-safe target eligibility and current oldest-mtime default behavior.
	4. Added optional `UPKEEPER_PASS_RESULT` final-response markers; `UPKEEPER_STATUS` and `UPKEEPER_LOG_REVIEW` remain unchanged, missing markers do not fail a cycle, and malformed markers become rejected evidence.
	5. Added `UPKEEPER_LATTICE_*` defaults to central configs and documented required/optional behavior: `REQUIRED=0` warns and continues with recovery spooling, while `REQUIRED=1` fails before Codex launch.
	6. Added Lattice docs and local validation covering schema initialization, doctor, backup, export/import idempotence, import conflicts, P999 pass rows and attributes, malformed pass markers, Git import, no-Git handling, recovery, unsafe DB paths, wrapper required policy, and filename torture fixtures.

2026-05-08: v1.1.22 changes:
	1. Switched the repository license from `0BSD` to `MIT`.
	2. Updated the README license summary and added public-documentation validation so `LICENSE` and the README license line stay aligned.

2026-05-08: v1.1.21 changes:
	1. Hardened the P29 reuse harvesting prompt with explicit P12/P24/P25/P28 boundaries, wrong-abstraction rollback rules, shell reuse safety gates, command reuse policy, registry preference, command recipe harvesting, and reuse-debt output.
	2. Added reusable data-table, fixture-writer, ShellCheck policy, and negative-example requirements so reuse work stays practical and verifiable in shell-heavy code.
	3. Added a reusable asset ownership map to `lib/upkeeper/README.md` and recorded the follow-on P29 priority queue in `PLANS.md`.
	4. Extended quick validation and public-documentation checks to require the hardened P29 prompt sections and reusable asset ownership map.

2026-05-08: v1.1.20 changes:
	1. Tightened the P29 reuse harvesting prompt to the full handoff contract text while preserving the existing `# P29 Reuse Harvesting Review` heading.
	2. Added the explicit P29 aliases `library-reuse`, `function-reuse`, and `asset-reuse` for `--review-module`, `--review-modules`, config defaults, and selection review-module filters.
	3. Extended quick validation to prove the new P29 reuse aliases are accepted and that the prompt keeps both the utility dumping-ground and `utils.bash` hard boundaries.

2026-05-08: v1.1.19 changes:
	1. Added P29 as an opt-in reuse harvesting review module through `--review-module=p29`, `--review-modules=...`, `--p29`, config defaults, and selection-review filtering.
	2. Added `prompts/p29-reuse-harvesting-review.md` so reusable helpers, fixtures, prompt language, docs, command idioms, validation patterns, and local assets can be extracted or consolidated when they have stable contracts and clear owners.
	3. Updated README, operator guide, compatibility notes, public documentation policy, prompt index, AGENTS, and all-pass testrun launchers for the P29 public contract.
	4. Extended validation and public-doc checks to require P29 prompt wiring, help text, shorthand flags, and dry-run prompt loading without backend Codex work.
	5. Added root `PLANS.md` and recorded the P29 implementation plan so complex Upkeeper changes have a durable planning surface.

2026-05-08: v1.1.18 changes:
	1. Added `docs/security.md` as Upkeeper's local trust model for what the wrapper can read, write, execute, and record.
	2. Documented shell-sourced config risks, Codex sandbox expectations, `$CODEX_HOME` session parsing, logs/transcripts, runtime artifacts, ignored files, symlinked central checkouts, client repo trust, fallback/postmortem behavior, secret handling, what not to commit, when not to run Upkeeper, and safe no-backend commands.
	3. Linked the security model from README, the public documentation policy, and the operator guide/help text.
	4. Extended public documentation checks to require the security trust model and its core coverage sections.

2026-05-08: v1.1.17 changes:
	1. Added `.github/workflows/ci.yml` for no-quota GitHub Actions validation on pushes and pull requests.
	2. The CI workflow starts on `ubuntu-latest`, installs required tools including `jq`, and runs shell syntax checks, `tests/*.bash`, `tools/check_public_docs.sh --quick`, and `tools/validate_upkeeper.sh --quick`.
	3. Documented the CI validation path in README, the operator guide, and dependency docs, including that CI does not launch real Codex backend work or upload runtime artifacts by default.
	4. Extended public documentation checks to require the tracked CI workflow and its core no-quota validation steps.
	5. Uses the current `actions/checkout` major release so the new workflow does not start with the Node 20 deprecation warning emitted by older action majors.

2026-05-08: v1.1.16 changes:
	1. Added `tools/stress_upkeeper_corpus.sh --local`, a no-quota local stress corpus harness that generates temporary sample repositories and exercises Upkeeper through repo-local `./Upkeeper.sh` symlinks.
	2. Covered Bash, Python, Node/TypeScript, docs-only, generated-heavy, symlinked-client, dirty-worktree, historical-log, active-lock, terminal-mode, review-summary, and transcript-filter local scenarios without launching real Codex backend work.
	3. Wired the stress corpus into `tools/validate_upkeeper.sh --full` while keeping `--quick` free of sample-repo runtime cost.
	4. Updated README, operator guide, compatibility notes, and `docs/stress-corpus.md` with the implemented command, current coverage, and the future backend-mode boundary.

2026-05-08: v1.1.15 changes:
	1. Fixed the explicit `--target-file` contract so human-pinned targets may be any source-safe readable text file inside the repo, including docs, prompts, config, tests, and scripts.
	2. Kept automatic rotation limited to script/tool candidates while preserving exclusions for `.git`, ignored paths, runtime evidence, generated outputs, directories, unreadable files, and binary-looking files.
	3. Added dry-run validation for explicit docs targets, unsafe runtime and `.git` targets, and automatic docs-only selection remaining outside script/tool rotation.

2026-05-08: v1.1.14 changes:
	1. Hardened disk-space preflight logging so path-like fields are shell-quoted, keeping space-bearing operator paths parseable in `disk.preflight` records and prompt notes.
	2. Parsed the trusted `free_percent` field directly instead of scanning the whole log payload, preventing path text that contains `free_percent=` from creating false low-disk decisions.
	3. Added quick validation coverage for disk-preflight log quoting and free-percent extraction.
	4. Added tracked `testruns/*.sh` launchers for repeatable all-pass P-module loops, documentation-focused P26 loops, and manifest/enumerate selector dry-runs.
	5. Hardened active-lock startup so a second wrapper exits on a fresh incomplete lock instead of reclaiming it during the owner process's state-file publish window, with validation coverage for that race.
	6. Hardened operator-guide bootstrap so a guide created during startup cannot be overwritten by generated help output, with validation coverage for the no-overwrite race.
	7. Made runtime JSON helper failures operator-visible instead of suppressing malformed-JSON diagnostics under `set -e`, with validation coverage for normal, null, boolean-false, and malformed helper input.
	8. Hardened startup-anomaly state parsing so malformed state files and space-bearing state paths cannot inject ambiguous `previous_run.anomaly` log fields, with validation coverage for the negative fixture.
	9. Hardened central-wrapper health logging so state-file and archive paths with spaces remain parseable, documented the retired-wrapper archive directory knob, and added validation coverage for stale-state archive log quoting.
	10. Narrowed Codex arg0 temporary cleanup to stale `codex-arg0*` shim directories so unrelated stale directories under the same root remain untouched, with validation coverage for the negative path.
	11. Hardened Codex bubblewrap temp preflight so operator-configured registry roots that begin with `-` are treated as paths rather than command options, with validation coverage for the path-boundary case.

2026-05-08: v1.1.13 changes:
	1. Added manifest-backed target selection defaults and related operator configuration fields for selection source, order, target root/depth, include/exclude globs, and selection review modules.
	2. Hardened postmortem report and hardening phases so exit-0 auxiliary Codex runs must still return the expected `CODEX_POSTMORTEM_STATUS` marker before the wrapper treats the phase as complete, and intentional postmortem failure returns remain capturable by the fallback caller.
	3. Hardened status-session JSONL parsing so malformed row shapes degrade to sentinel values instead of crashing wrapper status classification, with validation for malformed rows and log-safe abort reasons.

2026-05-08: v1.1.12 changes:
	1. Added root `Upkeeper.conf` as the default active configuration file, sourced before built-in defaults and before CLI parsing.
	2. Added `configurations/default.conf` as the basic self-contained profile template for scheduled or named runs.
	3. Added `--config-file=PATH` to select one config file per invocation and `--no-config` to skip the default config.
	4. Added `UPKEEPER_*` config defaults for flag-like behavior, including target file, review modules, prompt file/text, prompt pass, model override, and failure-queue bypass.
	5. Kept CLI flags as final one-cycle overrides over config defaults, with validation coverage for config loading, CLI override behavior, missing explicit config files, and `--no-config`.

2026-05-08: v1.1.11 changes:
	1. Added P28 as a first-class opt-in review module through `--review-module=p28`, `--review-modules=...`, and `--p28` for unit-test harvesting.
	2. Added `prompts/p28-unit-test-harvesting-review.md` so bugs, reusable exploratory commands, parser edge cases, and deterministic LLM-discovered facts can become cheap local tests or fixtures when practical.
	3. Documented the P28 scope in README, help, the operator guide, prompt index, compatibility notes, and validation.
	4. Renamed root release notes from `change_notes.md` to the annual file `change_notes_2026.md`.
	5. Added the annual release-note contract: each new calendar year starts its own root `change_notes_YYYY.md` file, and validation checks the current year's file for the committed wrapper version entry.

2026-05-08: v1.1.10 changes:
	1. Added a local unaddressed tool-failure queue under `runtime/unaddressed-tool-failures/` that records interesting script/tool command failures from backend transcripts without launching another model pass.
	2. Updated preselection so the oldest still-eligible open tool-failure marker becomes the next priority repair/upkeep target before normal timestamp rotation.
	3. Added `--ignore-failure-queue` for one-cycle human override; `--target-file=PATH` continues to take priority over the queue.
	4. Resolved queued markers automatically when the selected target completes with `WORK_DONE` and no new unaddressed local command failure remains, moving marker history from `open/` to `resolved/`.
	5. Documented the queue behavior, local runtime paths, env knobs, and validation coverage.

2026-05-08: v1.1.9 changes:
	1. Added P26 as a first-class opt-in review module through `--review-module=p26`, `--review-modules=...`, and `--p26` for public documentation, comment, help-text, release-note, and prompt clarity review.
	2. Added `docs/public-documentation-policy.md` and `tools/check_public_docs.sh` so Upkeeper treats every committed patch and release as public project material with deterministic checks for version/doc sync, required prompt wiring, broken local Markdown links, and obvious placeholder/legalese text.
	3. Updated README, the operator guide, compatibility docs, prompt index, help output, and validation so P26 is part of the documented review-module surface.
	4. Added P27 as a first-class opt-in review module through `--review-module=p27`, `--review-modules=...`, and `--p27` for concise educational debriefs after useful fixes or reviews.
	5. Added `prompts/p27-educational-debrief-review.md` with a saved debrief structure covering what went wrong, why it probably happened, why it mattered, how to avoid it, how it was fixed, what was already good, and what can still improve.
	6. Reframed the README opening so Upkeeper presents the current checked-in state as the delivered public tool: adaptable by professionals, usable by hobbyists, and accountable from tracked source.

2026-05-08: v1.1.8 changes:
	1. Added P24 and P25 as first-class opt-in review modules through `--review-module=...`, `--review-modules=...`, and shorthand `--p24`/`--p25` flags while preserving existing `--prompt-file` behavior.
	2. Added `prompts/p25-contract-intent-compliance-review.md` for explicit central-first, compatibility, simplicity, module ownership, dependency, validation, release-note, prompt-marker, and design-intent compliance review.
	3. Appended selected review modules from the resolved central Upkeeper checkout during prompt compilation so symlinked clients can opt in by flag without hard-coding central prompt paths.
	4. Propagated selected review modules into direct and screen fallback child invocations.
	5. Documented the new flags in help, the operator guide, README, prompt index, and compatibility contract, with validation coverage for prompt existence and flag behavior.

2026-05-08: v1.1.7 changes:
	1. Added `prompts/p24-de-llm-ing-viability-review.md` as a standalone applicability-gated add-on prompt for reviewing whether stable LLM/Codex-adjacent behavior can move into deterministic local code with no operator-facing loss.
	2. Documented explicit P24 prompt-file usage in the README, prompt index, and operator guide while keeping default and `--prompt-pass=all` behavior on the existing P1-P23 repertoire.
	3. Extended quick validation to assert the standalone P24 prompt exists and preserves its applicability, no-loss, and cost-ceiling contract.
	4. Quoted string and path fields in root `cycle.start` log records so defaults such as `CODEX_MODE=--sandbox workspace-write` and space-bearing `CODEX_HOME` paths remain parseable as single key/value fields.
	5. Captured quota-fallback return codes under `set +e` so intentional non-zero fallback exits still write a terminal `cycle.exit` record instead of surfacing as a false previous-run anomaly.
	6. Made full validation dry-runs use self-contained quota and runtime fixtures so local stale model snapshots cannot make the harness fail before the intended dry-run checks.
	7. Documented maintainability requirements that favor small reusable local functions, clear module ownership, and the simplest sufficient tool before adding new dependencies or runtime machinery.

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

2026-05-11: ChimneySweep obligation repair loop containment:
- ChimneySweep now remaps poisoned obligation `target_file` values such as `runtime/` fixtures back to a repo-local control-plane file instead of replaying an ineligible explicit target forever.
- Obligation-repair cycles that immediately fail again with the same poisoned `TARGET_FILE_NOT_ELIGIBLE` explicit target now keep the original obligation open instead of multiplying duplicate open records.

2026-05-11: allowlisted `CODEX_MODE` tuple parsing:
- `CODEX_MODE` now accepts only the allowlisted sandbox tuples `--sandbox workspace-write` and `--sandbox read-only` in both the primary wrapper and auxiliary Codex path.
- Extra trailing mode tokens are now rejected instead of being forwarded into backend Codex option parsing.

2026-05-11: postmortem evidence privacy hardening:
- Postmortem sequences now store primary last-message metadata by status/outcome/hash instead of copying the full primary last message by default.
- Default postmortem summary emission now logs only artifact metadata, not copied report prose.
- Postmortem context, incident logs, bug records, and private raw auxiliary evidence are now written under private `0700`/`0600` postmortem permissions, and auxiliary environment failures no longer echo raw runtime paths into the live loop log.

2026-05-11: selected-target write-boundary hardening:
- Preselected review cycles now treat the selected target as the only writable file by default, even when later prompt modules would normally suggest paired tests, docs, helper, caller, or validation edits.
- Non-selected repository files remain readable for context, but runs that need extra edits must now report `BLOCKED` with an `ADDITIONAL_FILES_NEEDED:` list instead of widening the write scope beyond the selected target's pre-contact backup coverage.

2026-05-11: log self-review control-plane boundary hardening:
- Current-cycle log self-review no longer permits same-pass repair of unselected `Upkeeper` control-plane files.
- If log review finds a wrapper, prompt, or logging defect outside the selected target path, the cycle must now leave that file unchanged and report `BLOCKED` for a follow-up wrapper-selected run instead of widening write scope past the selected target backup boundary.

2026-05-11: pre-contact backup log path redaction:
- Pre-contact backup create, failure, and restore log lines now use a stable `target_hash` instead of logging the raw selected relative path while claiming `path_redacted=1`.
- Protected backup metadata and restore behavior are unchanged, but normal runtime logs no longer leak target names such as customer, incident, or secret-bearing file labels.

2026-05-11: sensitive target denylist before prompt launch:
- Upkeeper now fails closed on common secret-bearing target paths such as `.env*`, credential dotfiles, kubeconfig, SSH private key names, and private-key extensions before pre-contact backup, prompt compilation, or backend launch can treat them as ordinary review files.
- The deny gate is built in and does not depend on `.upkeeperignore`, so tracked or otherwise eligible secret-like files no longer reach the normal backup-and-prompt flow by default.

2026-05-11: restore temp-file mode stays private until rename:
- Plain and age restore flows now keep the randomized temporary restore file on its private `mktemp` mode until after the final rename, instead of chmodding the temp path to the restored file mode first.
- The restored destination still receives its recorded mode after rename, but the temporary filename no longer becomes briefly readable at a permissive mode before the move completes.

2026-05-12: issue-fix private issue packet gate:
- Issue-fix mode now withholds private GitHub issue title/body/comment text from model prompts by default, while preserving wrapper-side issue selection and inferred-target extraction before Codex starts.
- Selected-issue runtime logs now record only stable issue title/URL hashes plus the explicit model-exposure gate state instead of emitting raw private issue metadata.
- Operators can still opt into private issue prompt exposure explicitly with `UPKEEPER_ALLOW_PRIVATE_ISSUE_BODY_TO_MODEL=1` when a responsible fix requires the original issue prose.

2026-05-12: backlog orchestration wrench:
- Added `orchestration/backlog.sh`, a deliberately small operator launcher that opens or reuses a `[backlog]` PR, targets the newest open non-feature/non-research issue, runs one Upkeeper repair pass, pushes the result, waits for PR checks, and merges the batch after 10 recorded fixes.
- The launcher keeps quota stop thresholds configurable for this workflow and falls back to a normal newest-file Upkeeper pass when no eligible issue is open.

2026-05-12: backlog wrench post-fix efficiency hardening:
- `orchestration/backlog.sh` now scrubs Python bytecode cache artifacts before the commit path and disables bytecode generation during backlog runs so one-file issue fixes do not stall on transient `__pycache__` junk.
- Existing open backlog PRs with recorded fixes now wait only up to a bounded interval for GitHub checks to settle before the next loop iteration, instead of hanging indefinitely on stale aggregate check states.
- A clean backlog branch now gates the next issue on the current PR checks completing, so the loop does not spend model cycles starting a new fix while the previous fix is still waiting on CI.
- Issue text that clearly describes bug-report-only dirty-state fingerprinting now pins directly to `lib/upkeeper/codex_io.bash` so those issue runs do not burn a full selected-file cycle on an unrelated rotation target.
- The backlog launcher now logs each local validation phase plus the commit/push/check-wait transitions so long post-fix validation windows read as active progress instead of a silent apparent hang.
- The backlog launcher now defaults to light per-bug validation (`bash -n` plus `git diff --check`) and defers the full unit-test, docs, quick-validator, and PR-check gate to the batch-merge boundary, so an open backlog PR can stack fixes faster instead of serializing on full validation and CI after every issue.
- `cycle.start` / `record-cycle-start` metadata issues now pin to `Upkeeper` before generic Lattice keyword matches, so wrapper-emitter privacy bugs do not waste a full selected-file cycle on importer-side mitigation first.
- Blocked-issue deferral now preserves the real Upkeeper exit status instead of accidentally converting `BLOCKED` into success through shell negation, so repeated selected-file-boundary blockers are skipped for the current backlog branch instead of being retried immediately.
- The backlog launcher now checks the local exact-model quota snapshot before issue selection and skips the cycle cleanly when the primary bucket is still in `defer`, preventing one-minute retry churn and repeated quota-stop obligations on the same issue.
- Backlog control flow now also captures the real function exit statuses in `main()` for both quota preflight and issue runs, fixing a second shell-negation bug that was still turning `BLOCKED` issue reviews and quota-defer preflights into apparent success paths.
- Backlog `main()` now captures those nonzero statuses in `if ...; then ... else ... fi` form so `set -e` does not abort the script before blocked-issue deferral or quota-defer handling can run.
- Issue text describing log-rotation archives, startup-anomaly gate path/hash leaks, unresolved startup-anomaly state leakage, and `prompt_file` / `run.start` log injection now pins directly to the wrapper modules that actually own those behaviors, preventing the backlog loop from wasting full issue cycles on excluded artifacts like `Upkeeper.log` or unrelated quota helpers.

2026-05-16: quota/session metadata privacy minimization:
- Normal quota log lines now hash session-source paths and quota identity fields instead of emitting raw session JSONL paths, plan/account labels, or other quota identity detail into the live loop log.
- Persisted primary quota cooldown markers now keep only enforcement-critical fields by default, so reset diagnostics, usage percentages, and raw quota identity details no longer spill into durable marker files.
- Postmortem incident context now stores hashed quota/session identifiers by default and moves the fuller quota/session diagnostics behind explicit `UPKEEPER_VERBOSE_METADATA=1` within chmod-protected local artifacts.
- Lattice doctor coverage and focused quota-marker validation now explicitly assert the hashed quota-log import contract and the reduced cooldown-marker surface.
