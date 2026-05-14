# Upkeeper Compatibility Contract

Upkeeper is central operational infrastructure. Changes should keep existing
operators and symlinked client repositories working unless there is literally no
responsible way to do so.

Backward compatibility is the default. A breaking change is allowed only when at
least one of these is true:

- Keeping compatibility would preserve a real security or safety risk.
- An external dependency, platform, or Codex behavior change makes compatibility
  impossible.
- The old behavior is provably broken and preserving it would cause materially
  worse failures than rejecting it.

Examples include refusing a risky outdated TLS/SSL behavior, retiring a wrapper
path that can target the wrong repository, or rejecting an input format that can
hide malformed operator data as absence.

## Binding Feature Surface

Future changes should preserve this operator-visible surface as far as possible:

- Root `Upkeeper` remains the executable entrypoint.
- Root `FlameOn` remains a thin convenience launcher over `Upkeeper` max-cover
  mode rather than a second implementation path.
- Root `ChimneySweep` remains a separate issue-fix launcher with its own
  deterministic GitHub queue-ranking path before it hands one locked issue to
  Upkeeper.
- Symlinked clients can continue invoking a local `./Upkeeper.sh` that points to
  the central root `Upkeeper` file.
- The root entrypoint resolves paired modules, prompt files, and documentation
  from the central checkout, not from each client repo.
- Existing documented CLI flags keep working:
  `--help`, `-h`, `--version`, `--config-file=...`, `--no-config`,
  `--prompt-file`, `--prompt`,
  `--review-module=...`, `--review-modules=...`, `--p24`, `--p25`, `--p26`,
  `--p27`, `--p28`, `--p29`, `--model-override=...`, `--target-file=...`, and
  `--target-root=...`, `--target-depth=...`,
  `--selection-source=manifest|enumerate`,
  `--selection-order=oldest|newest|random`, `--refresh-manifest`,
  `--manifest-file=...`, `--include-glob=...`, `--include-globs=...`,
  `--exclude-glob=...`, `--exclude-globs=...`,
  `--selection-review-modules=...`, `--ignore-failure-queue`,
  `--backup-queue`, `-backup_queue`, `--prompt-pass=all`, `--max-cover`,
  `--bug-report-only`, `--file-bug-only`, `--report-bug-only`,
  `--fix-next-issue`, `--fix-oldest-bug`, `--fix-issue=...`, and
  `--issue-workflow-stage=comment|review|apply`.
- Upkeeper model override shorthands include `5.5_xhigh` and
  `5.3-codex-spark_xhigh`. FlameOn and ChimneySweep pass those through and also
  accept `--model ... --reasoning-effort ...` shortcuts for supported pairs.
- `FlameOn` remains a thin max-cover launcher and defaults to
  `--bug-report-only`; it should investigate and file/report bugs rather than
  patch tracked source during burn cycles. Its launcher path is full burn by
  default: Lattice is required, encrypted pre-contact backup is required, and
  the Codex sandbox mode is pinned before launch. Quota stop floors are set to
  zero, wrapper quota guardrail stops are bypassed, and persisted quota cooldown
  markers are bypassed for those launcher runs.
- `ChimneySweep` owns pre-model issue ranking for repair automation: clean
  actionable queues exit 25, security issues outrank data-integrity issues,
  data-integrity issues outrank the general queue, and the selected issue is
  handed to Upkeeper with `--fix-issue=NUMBER`. Its default workflow is
  comment, review, then apply across separate Upkeeper instantiations. The
  comment/review stages are source read-only and leave issue comments; the apply
  stage works the bug. Each stage requests all prompt passes and all P24-P29
  review modules for the locked issue target, and uses the same full-burn
  launcher protections and quota-bypass behavior as FlameOn.
- The clean no-op path is a first-class contract. When automation health,
  unresolved obligations, and the actionable work queue are all clean, Upkeeper
  and focused launchers should exit quickly, plainly, and without backend Codex
  work or broad validation. A healthy empty run taking more than about 10
  seconds is treated as a performance and ergonomics bug.
- Machine health outranks new workload. Unresolved automation obligations and
  stale control-plane failures block fresh GitHub issue work or bug-hunting
  runs until they are repaired, resolved, or preserved as explicit obligations
  for the next run.
- Backend Codex issue workflows use the Genie Protocol boundary. The wrapper
  owns GitHub reads and writes, passes only wrapper-fetched issue evidence plus
  local artifact paths into the model, strips GitHub token variables from the
  backend environment, points `gh` at an empty per-run config directory, and
  shadows direct `gh`, `curl`, `wget`, and `hub` commands for backend launches.
  The comment/review stages also override the backend mode to
  `--sandbox read-only`; their issue-comment text returns through a final-message
  draft block that the wrapper extracts and posts after validation. Those
  wrapper-posted staged comments are prefixed `Upkeeper ChimneySweep proposal:`
  and `Upkeeper ChimneySweep review:` so operators can distinguish wrapper
  actions from human comments.
- `CODEX_MODE` remains configurable for supported Codex sandbox modes, but
  Upkeeper rejects `danger-full-access` and
  `--dangerously-bypass-approvals-and-sandbox` because those modes bypass the
  backend containment contract.
- `.upkeeperignore` remains the repo-local target-selection firewall. It blocks
  normal rotation, Lattice/max-cover candidates, failure-queue eligibility,
  manifest entries, and explicit `--target-file` pins for matching paths without
  changing Git tracking or Codex sandbox access.
- Selected-target pre-contact backups remain shell-side and happen after target
  selection but before the selected-target prompt block is compiled. Required
  backup failures must stop before backend launch with `codex_exec_started=0`.
  The default vault is outside the repository, and wrapper-generated prompts,
  logs, and Lattice preselect evidence must not expose the vault root.
- The central defaults now require encrypted pre-contact backup. Keeping the
  old silent plaintext fallback was unsafe, so operators who intentionally need
  plaintext recovery must explicitly set both
  `UPKEEPER_PRECONTACT_BACKUP_REQUIRE_ENCRYPTED=0` and
  `UPKEEPER_PRECONTACT_BACKUP_ALLOW_UNSAFE_PLAINTEXT=1`.
- The central default config remains `Upkeeper.conf`, and named config profiles
  can be selected per invocation with `--config-file=PATH`.
- Existing documented environment knobs keep their meaning unless a change note
  states an unavoidable safety reason.
- `CODEX_TERMINAL_VERBOSITY` keeps the documented modes and aliases for
  `basic`, `quiet`, `silent`, `verbose`, `debug1`, and `full`.
- Status-marker contracts remain stable:
  `UPKEEPER_STATUS`, `UPKEEPER_LOG_REVIEW`, `CODEX_POSTMORTEM_STATUS`, and their
  documented status values.
- Published loop exit meanings remain stable, especially successful work,
  intentional no-backend-task stop, fallback/postmortem failures, active locks,
  empty transcripts, local environment failures, and parent-stop guardrails.
  A successful fallback child with a successful postmortem sequence may complete
  cleanly; postmortem failures still propagate as recovery failures.
- `Upkeeper.log` keeps cycle/run evidence in parseable timestamped lines with
  `cycle=...`, `run_hash=...`, event names, and key-value fields.
- Unsafe log paths fail closed before Codex launch: symlink log files,
  non-regular log files, hard-linked log files, log files not owned by the
  current user, and symlink log parent directories are rejected instead of
  being appended to.
- Unsafe `$CODEX_HOME/sessions` paths fail closed before Codex launch:
  symlinked, non-directory, and wrong-owner session stores are rejected before
  Upkeeper writes a probe file. Owned session stores with weak inherited
  permissions are repaired to `0700` and rechecked before probing; stores that
  remain group/other writable after repair are rejected.
- Review summaries continue to log outcome, selected file, findings, changes,
  verification, Codex exit, and final status-marker evidence when available.
- Runtime artifacts stay under documented local paths such as `runtime/`,
  `runtime/upkeeper-transcripts`, `runtime/journals/upkeeper-postmortems`,
  `runtime/upkeeper-file-manifest.json`, and
  `runtime/unaddressed-tool-failures`. Automation run records and unresolved
  obligations use the shared Upkeeper-owned framework under
  `runtime/upkeeper-automation-ledger` and `runtime/upkeeper-obligations`, even
  when the cycle was launched by FlameOn, ChimneySweep, or a future derivative
  launcher. FlameOn and ChimneySweep reconcile open obligations before their
  normal bug-finding or GitHub issue-selection policies. Backup failure-queue
  runs use `runtime/unaddressed-tool-failures-backup`.
- Upkeeper Lattice is additive local runtime evidence at
  `runtime/upkeeper-lattice/lattice.sqlite3`. Runtime artifacts under
  `runtime/upkeeper-lattice/`, including SQLite side files, backups, exports,
  and recovery records, remain ignored local state.
- `UPKEEPER_PASS_RESULT` is additive. `UPKEEPER_STATUS` and
  `UPKEEPER_LOG_REVIEW` remain unchanged.
- Review outcomes recognized in final prose include `REVIEWED_AND_FIXED`,
  `REVIEWED_AND_REPORTED`, `REVIEWED_CLEAN`, and `STOPPED_ON_BLOCKER`.
- Missing `UPKEEPER_PASS_RESULT` markers remain additive-only for normal runs.
  When `--prompt-pass=all` is active, incomplete or unavailable pass-result
  coverage now forces the cycle to `BLOCKED`. Malformed pass-result markers are
  recorded as rejected evidence, not clean pass results.
- Default target selection remains current-compatible. Live source-safe
  eligibility stays authoritative; Lattice does not replace current eligibility
  with stale database rows.
- `--max-cover` may ask Lattice to rank a broader current tracked text-file
  pool, but final selection still revalidates the live source-safe boundary in
  the same cycle.
- `--bug-report-only` is a no-fix mode. It must not edit or touch tracked
  source, and the wrapper must fail the cycle if the source mutation
  fingerprint changes during a non-dry-run bug-report-only cycle.
- `--fix-next-issue`, `--fix-oldest-bug`, `--fix-issue=...`,
  `--issue-workflow-stage=...`, and `ChimneySweep` may require the GitHub CLI
  for pre-launch issue selection or loading, but normal Upkeeper and
  bug-report-only cycles do not make `gh` a hard runtime dependency.
- Explicit targets still win. Startup anomaly gates still win. The local
  failure queue still wins before normal timestamp rotation.
- Codex must not receive authority to choose an unbacked replacement target. If
  the preselected target is physically impossible or unsafe to review, the
  prompt contract is to report `BLOCKED`; replacement selection remains a
  wrapper-only behavior for a later cycle.
- Validation entrypoints remain available:
  `tools/validate_upkeeper.sh --deps`, `--smoke`, `--quick`, `--full`, and the
  additive `--profile` timing flag.
- The GitHub Actions no-quota CI workflow remains available at
  `.github/workflows/ci.yml` for pushes and pull requests.
- The local stress-corpus entrypoint remains available:
  `tools/stress_upkeeper_corpus.sh --local`.
- Optional Bash completion remains an additive helper at
  `completions/upkeeper.bash`.
- Default validation and local stress-corpus checks do not spend backend Codex
  quota unless the operator explicitly opts in through a future backend-specific
  command.
- Central prompt files remain usable by absolute path from symlinked clients.
- Central review modules remain usable by flag from symlinked clients.
- Local unaddressed tool-failure markers can prioritize the next eligible target
  without changing tracked source; operator `--target-file` and
  `--ignore-failure-queue` still override that local queue for one cycle.
- Config files can provide scheduled-run defaults, but CLI flags remain the
  final one-cycle override surface.
- The default target rotation is manifest-backed when a current local manifest
  exists or can be built. Direct enumeration remains available through
  `--selection-source=enumerate`, and operator-pinned `--target-file` keeps
  priority over manifest, queue, and filter behavior.
- Explicit `--target-file` pins may select any source-safe readable text file
  inside the repo, including docs, prompts, config, tests, and scripts, while
  automatic rotation remains limited to script/tool candidates. Selected targets
  must not be symlinks in this pre-contact backup slice.
- Source-safe target selection rejects symlink paths before reading or statting
  them. This applies to explicit targets, direct enumeration, manifest entries,
  and Lattice/max-cover candidate diagnostics.
- Selection filters such as target root, depth, include/exclude globs, random
  order, and review-module approximations narrow which file Upkeeper chooses.
  They do not silently enable extra review modules or change the single-selected-
  file prompt contract.
- Public documentation, help text, prompt docs, code comments, and release
  notes remain understandable enough for public review without private context.
- The default review prompt keeps the single-selected-file review contract and
  the P1-P23 pass repertoire, including the P23 data-contract pass.
- Client repos keep `Upkeeper.sh`, `Upkeeper.log`, `runtime/`, and local
  generated operator-guide state out of tracked source unless a client-specific
  issue requires otherwise.

Internal Bash function names, module boundaries, helper implementations, and
prompt wording can change when the operator-visible behavior above remains
compatible.

## Maintainability And Simplicity Requirements

Future compatibility work should make Upkeeper easier to maintain, not only
larger.

- Prefer small reusable local functions for behavior that is repeated, parsed,
  logged, validated, or relied on by more than one module.
- Keep the root `Upkeeper` entrypoint focused on orchestration; put reusable
  behavior in `lib/upkeeper` modules with clear ownership.
- Start with the smallest sufficient mechanism: a Bash helper, existing command,
  focused Python parser, fixture, or validation check is preferred over a new
  framework, service, daemon, database, or background runtime.
- Add new dependencies only when the existing local toolchain would make the
  solution materially less safe, less clear, or less testable.
- Do not over-fragment one-off code. Split or extract only when it reduces real
  coupling, removes meaningful duplication, clarifies a contract, or makes a
  behavior easier to verify.
- Prefer deterministic local code for stable parsing, classification,
  formatting, routing, preflight, and guardrail enforcement. Keep LLM-backed
  paths for open-ended review, ambiguous judgement, and remediation planning.
- When a helper becomes part of a contract, add focused validation coverage for
  both normal and malformed paths.
- Avoid introducing a larger runtime system for a problem solved by a small
  local helper. The simplest tool that satisfies the documented contract is the
  preferred tool.

## Breaking-Change Requirements

If a breaking change is unavoidable:

- Keep a compatibility alias, shim, warning, or migration path when feasible.
- Prefer rejecting unsafe input with a clear diagnostic over silently changing
  behavior.
- Update `UPKEEPER_VERSION`, the current year's root `change_notes_YYYY.md`,
  README/operator-guide docs, and any affected validation coverage in the same
  committed state.
- State the broken surface, reason compatibility could not be kept, operator
  impact, migration path, and rollback risk.
- Avoid tracked client-repo churn for central wrapper compatibility changes.
