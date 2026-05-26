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

## Compatibility Classes

Every operator-visible schema, prompt marker, output field, doc/help contract,
and Lattice import/export field belongs to one of these classes:

| Class | Meaning | Change rule |
| --- | --- | --- |
| `stable` | Existing operators, scripts, tests, docs, or downstream tools may rely on it. | Preserve it, or add an alias/shim/migration path before changing it. |
| `experimental` | Public enough to inspect, but not promised as long-term automation surface. | May change with a dated change note and clear docs; do not silently promote to `stable`. |
| `deprecated` | Still accepted, but no longer preferred. | Keep a warning, alias, or migration path until a documented removal date or replacement condition. |
| `removed` | No longer accepted or emitted. | Document the removal reason, migration path, and safety/compatibility rationale. |

Unclassified public behavior is treated as `stable` by default once it appears
in tracked docs, help text, prompts, JSON output, Lattice export rows, or
release notes. New experimental behavior must say it is experimental at the
point of documentation or output.

## Schema And Contract Version Rules

Schema and contract versions are compatibility boundaries, not decoration:

- JSON schemas that expose a `schema_version` or named schema id must keep
  existing field names, field types, and meanings within the same version.
- Adding optional fields is compatible when existing readers can ignore them.
- Removing fields, renaming fields, changing field types, or changing enum
  meanings requires a new schema version or a documented compatibility shim.
- Prompt markers such as `UPKEEPER_STATUS`, `UPKEEPER_LOG_REVIEW`,
  `UPKEEPER_PASS_RESULT`, `CODEX_POSTMORTEM_STATUS`, and review-module ids are
  stable contracts. New prompt wording can change, but parseable marker names,
  status values, and review-module meanings must remain compatible.
- Documentation and `./Upkeeper --help` are a paired contract. Operator-facing
  behavior changes should update help, `docs/scripts/upkeeper.md`, README or
  compatibility notes, and change notes in the same committed state.
- Lattice SQLite schema changes must advance or explicitly preserve the
  tracked schema/user-version contract, and JSONL exports must remain readable
  by same-version importers.

## Migration And Deprecation Rules

When a stable surface changes:

- Prefer an alias, shim, or normalizer over immediate rejection.
- Emit an operator-visible warning for deprecated inputs when practical.
- State the replacement field, flag, marker, or command in tracked docs.
- Keep deterministic validation for both old and new spellings during the
  migration window.
- If compatibility is unsafe or impossible, document the exact break under
  the breaking-change requirements below.

## Public Examples And Validation

Public examples are part of the compatibility surface when they show commands,
JSON fields, prompt markers, Lattice rows, config keys, or output snippets.
Examples must stay executable or structurally truthful enough for local
validation to check. The minimum local proof is one of:

- `tools/check_public_docs.sh --quick` for public documentation links, help,
  and required wording.
- `tools/docs_only_fast_path.sh --validate` for README/docs/prompt-only changes
  that should stay on the no-backend, no-GitHub local validation path.
- `tools/validate_upkeeper.sh --smoke` for fast schema/help/prompt drift.
- `tools/validate_upkeeper.sh --quick` for fixture-backed parser, marker,
  issue-workflow, Lattice, and authority contracts.
- Focused `tests/*.bash` or Python fixtures when a public example has a
  concrete input/output shape.

## Lattice Import/Export Compatibility

Lattice has two compatibility layers:

- The SQLite database schema is local runtime state. Upkeeper may migrate it,
  but the tracked schema version and `PRAGMA user_version` must describe the
  current expected shape.
- JSONL export/import is the portable exchange surface. Export rows must keep
  `schema_version`, `row_type`, `row_version`, `logical_key`, source identity,
  repo identity, payload, `payload_sha256`, and exported epoch meanings stable
  within the same row version. Import must remain idempotent for duplicate
  logical-key/payload-hash pairs and must record conflicts instead of silently
  overwriting different payloads.

Redaction defaults are part of compatibility. Default JSONL exports redact raw
payload fields, path-bearing fields, contributor identity, and commit subjects
unless the operator asks for disclosure with the documented include flags.

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
  `--p27`, `--p28`, `--p29`, `--p30`, `--model-override=...`, `--target-file=...`, and
  `--target-root=...`, `--target-depth=...`,
  `--selection-source=manifest|enumerate`,
  `--selection-order=oldest|newest|random`, `--select-untracked=0|1`,
  `--no-select-untracked`, `--tracked-only`, `--refresh-manifest`,
  `--manifest-file=...`, `--include-glob=...`, `--include-globs=...`,
  `--exclude-glob=...`, `--exclude-globs=...`,
  `--selection-review-modules=...`, `--ignore-failure-queue`,
  `--backup-queue`, `-backup_queue`, `--prompt-pass=all`, `--max-cover`,
  `--bug-report-only`, `--file-bug-only`, `--report-bug-only`,
  `--audit-only`, `--review-only`, `--no-fix`, `--read-only`,
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
  markers are bypassed for those launcher runs. Backlog quota burn bypass still
  records expired-reset stale quota evidence as a local `stale_quota_evidence`
  automation obligation before continuing, and resolves that obligation when
  current non-stale quota evidence appears.
- Backlog quota hibernation is local and pre-model. While sleeping for a quota
  reset, it checks only local git branch/upstream refs; if the checked-out
  backlog branch's upstream ref disappears after another worktree merges or
  deletes the PR branch, hibernation exits cleanly with
  `action=exit_for_merged_or_deleted_branch` instead of holding a retired branch
  until quota reset.
- `ChimneySweep` owns pre-model issue ranking for repair automation: clean
  actionable queues exit 25, security issues outrank data-integrity issues,
  data-integrity issues outrank the general queue, and the selected issue is
  handed to Upkeeper with `--fix-issue=NUMBER`. Its default workflow is
  comment, review, then apply across separate Upkeeper instantiations. The
  comment/review stages are source read-only and leave issue comments; the apply
  stage works the bug. Each stage requests all prompt passes and all P24-P30
  review modules for the locked issue target, and uses the same full-burn
  launcher protections and quota-bypass behavior as FlameOn.
- Canonical issue taxonomy for local release-gate planning is:
  `p0-release-blocker`, `p1-trust`, `p1-validation`, `p1-safety`, `p1-docs`,
  `p2-ux`, `p2-portability`, `p2-prompt`, `p3-polish`; Upkeeper currently
  uses `security`, `data-integrity`, and `bug` as the configured default label
  implementation while maintaining explicit backward-compatible mapping.
- The clean no-op path is a first-class contract. When automation health,
  unresolved obligations, and the actionable work queue are all clean, Upkeeper
  and focused launchers should exit quickly, plainly, and without backend Codex
  work or broad validation. A healthy empty run taking more than about 10
  seconds is treated as a performance and ergonomics bug.
- Machine health outranks new workload. Unresolved automation obligations and
  stale control-plane failures block fresh GitHub issue work or bug-hunting
  runs until they are repaired, resolved, or preserved as explicit obligations
  for the next run.
- Backlog batch-merge validation failures are machine-health obligations, not
  one-off terminal events. A failing local validation phase writes or updates a
  current-root obligation with the failed phase, command, exit code, bounded
  output tail, stable fingerprint, likely owner path, and required proof command
  before the launcher exits. The next backlog invocation must select that
  obligation before retrying the merge or selecting fresh issue work.
- Backlog child wrapper failures are also machine-health obligations. If
  `./Upkeeper` exits non-zero before the child run reaches a clean launcher
  outcome, the backlog launcher writes or updates a `wrapper_execution_failure`
  obligation with a private bounded child-output tail and likely wrapper owner
  path before exiting, except for the already-modeled blocked and quota lanes.
  If the child run already opened a durable automation obligation for the same
  failure, the backlog launcher preserves that native owner instead of filing a
  duplicate outer wrapper-failure record.
  Backend context-window overflows are a specialized child-failure obligation
  kind, `backend_context_overflow`, and must point at bounded-evidence handling
  instead of filing as generic missing-status residue. Empty-transcript Codex
  exits are a specialized child-failure obligation kind,
  `codex_exec_empty_transcript`, and repeated empty-transcript records for the
  same repair target must collapse even when issue-report numbers differ. Later
  prior-run anomaly scans may coalesce `run.finish`, `cycle.exit`,
  transcript-capture, live-output-filter, and missing-status companion PAGE
  lines into the owning terminal-failure obligation; they must not fan out one
  failed cycle into multiple unrelated obligations.
- Backlog PR check and merge decisions are made against the current backlog
  branch head. If the local backlog branch is clean and ahead of
  `origin/<branch>`, the launcher pushes it before PR checks or merge. Dirty,
  missing-remote, or diverged local-ahead states fail closed with an explicit
  branch-state reason.
- `./orchestration/watch-pr.sh [PR_NUMBER]` is the stable local PR-check watch
  command for backlog/manual boundaries. With no PR number it infers the
  current branch PR. It emits timestamped `status=pass|pending|fail` summaries
  with check names, conclusions, and URLs when available; exits `0` on pass,
  `1` on failed or unreadable checks, and `2` for pending checks when `--once`
  is used. The command only inspects GitHub PR checks and does not launch
  backend Codex or mutate the repository.
- The tracked authority model remains part of the public contract. Changes to
  target authority, source-write authority, shell execution, quota spend,
  backup restore, evidence pruning, GitHub issue effects, Lattice writes, or
  runtime evidence reads should update `docs/authority.md`,
  `docs/capability-profiles.md`, `docs/control-ledger.md`, and
  `docs/policy-decisions.md`.
- The threat model, degraded-mode doctrine, and override doctrine in
  `docs/security.md` are part of the stable security contract. Changes to
  model-output trust, wrapper self-repair, config trust, filesystem safety,
  same-user access, secret handling, public documentation exposure, quota,
  fallback, encrypted backup, Lattice, validator, dirty-baseline, or unsafe
  target behavior should update that doctrine and validation coverage in the
  same patch.
- The preservation policy in `docs/preservation-policy.md` is part of the
  stable evidence contract. Changes to evidence temperature, artifact privacy
  classes, log/transcript retention, backup recovery, Lattice exports, recovery
  artifacts, obligation evidence, redaction defaults, compression, pruning, or
  public evidence promotion should update that policy and validation coverage
  in the same patch.
- The source-rights metadata model in `docs/source-rights-metadata.md` is part
  of the stable evidence and public-citation contract. Changes to source
  sensitivity labels, rights fields, prompt-safe/export-safe decisions,
  paid-access or license-restricted handling, Wikipedia citation use, public
  evidence packets, archiving, or robots/terms restrictions should update that
  model and validation coverage in the same patch.
- Policy decision schema-v1 field names and types are stable. Future policy
  decision records may add optional fields, but removing, renaming, or changing
  the meaning of existing fields requires a new schema version and validation
  coverage.
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
- Trusted machine-local encrypted-backup bootstrap is now part of the stable
  operator surface. `UPKEEPER_LOCAL_ENV_FILE` may provide
  `UPKEEPER_PRECONTACT_BACKUP_AGE_RECIPIENT`, and
  `tools/upkeeper_precontact_bootstrap.sh` remains the central way to create or
  refresh that machine-local recipient without tracked repo churn.
- When encrypted backup is required for a live apply-stage or normal repair
  cycle, missing machine-local recipient setup now fails before issue
  selection and is reported as machine health, not as a target-file regression.
- The central default config remains `Upkeeper.conf`, and named config profiles
  can be selected per invocation with `--config-file=PATH`.
- Existing documented environment knobs keep their meaning unless a change note
  states an unavoidable safety reason.
- `CODEX_TERMINAL_VERBOSITY` keeps the documented modes and aliases for
  `basic`, `quiet`, `silent`, `verbose`, `debug1`, and `full`.
- Status-marker contracts remain stable:
  `UPKEEPER_STATUS`, `UPKEEPER_LOG_REVIEW`, `CODEX_POSTMORTEM_STATUS`, and their
  documented status values.
- Review-module flags, shorthand aliases, CSV normalization, prompt paths, and
  help text remain stable while their P24-P30 metadata is registry-backed in the
  central wrapper.
- Startup anomaly changed-path allowlists, source-safe exclusion prefixes,
  command-kind failure classifiers, review-module ids, and Lattice pass-code
  mappings are embedded control-plane table behavior. Changes to those tables
  should update validation, docs, and change notes in the same patch rather
  than drifting silently.
- Published loop exit meanings remain stable, especially successful work,
  intentional no-backend-task stop, fallback/postmortem failures, active locks,
  empty transcripts, local environment failures, and parent-stop guardrails.
  A successful fallback child with a successful postmortem sequence may complete
  cleanly; postmortem failures still propagate as recovery failures.
- Fallback and postmortem guardrails are part of the stable operator surface:
  fallback is primary-only, disabled inside fallback children, bounded by
  screen child/time limits, subject to exact-model quota checks, blocked by
  unsafe local evidence paths, and fully disabled only when
  `CODEX_FALLBACK_ENABLED=0`, `CODEX_FALLBACK_SCREEN_ENABLED=0`, and
  `CODEX_POSTMORTEM_ENABLED=0` are set together.
- `Upkeeper.log` keeps cycle/run evidence in parseable timestamped lines with
  `cycle=...`, `run_hash=...`, event names, and key-value fields.
- Unsafe log paths fail closed before Codex launch: symlink log files,
  non-regular log files, hard-linked log files, log files not owned by the
  current user, and symlink log parent directories are rejected instead of
  being appended to.
- Unsafe `$CODEX_HOME/sessions` paths fail closed before Codex launch:
  missing session stores are created private, while symlinked, non-directory,
  and wrong-owner session stores are rejected before Upkeeper writes a probe
  file. Owned session stores with weak inherited permissions are also rejected
  without chmod repair so operators correct the local environment explicitly
  before backend work starts.
- Review summaries continue to log outcome, selected file, findings, changes,
  verification, Codex exit, and final status-marker evidence when available.
- `--status`, `--doctor`, `--last-run`, `--open-failures`,
  `--quota-status`, and `--json-status` are local status reads. They do not
  acquire the active run lock, launch backend Codex, call GitHub, or mutate
  runtime evidence. `--json-status` emits schema `upkeeper.status.v1`.
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
- Backlog issue batches generate deterministic issue-ready reports for open
  current-root automation obligations before normal issue selection. The local
  reports are runtime evidence, not source, and GitHub issue creation remains a
  wrapper-side opt-in through `BACKLOG_OBLIGATION_GITHUB_ISSUE_WRITE=1`.
  Before a new issue is created, the bridge enumerates open GitHub issues and
  links the obligation to an exact title match when one exists. If open-issue
  lookup fails, the bridge fails closed instead of creating a possible
  duplicate. System-level obligations such as child exits, missing status
  markers, backend context overflow, and empty transcripts reconcile by failure
  class, reason, target, and repair target rather than by volatile per-cycle
  fingerprints. Obligations already linked to the same specific GitHub issue
  title and number also reconcile as one local owner even when their evidence
  fingerprints differ. Batch validation unit tests run with isolated
  obligation and automation-ledger roots, so local test fixtures cannot consume
  the live backlog obligation queue. Prior-run anomaly custody preserves the
  same boundary: quote lines already classified as `quoted_backend_source_fixture`
  and successful backlog-temp negative-test fixture output do not become fresh
  obligations, and source-cycle signals with an existing open or resolved owner
  obligation are coalesced under that owner.
- The parallel-worker lease registry is a local no-backend compatibility
  surface for future isolated backlog workers. `tools/backlog_parallel_leases.py`
  stores leases under the selected backlog state root, rejects active duplicate
  issue claims, rejects active predicted-target overlap, rejects worker leases
  that point at the main checkout or a nested worktree, supports TTL expiry and
  explicit release, and prints a stable tabular status header:
  `worker_id status issue model effort branch worktree target expires_in next_action`.
  It does not create worktrees, branches, PRs, GitHub labels, comments, or
  backend Codex work by itself.
- Upkeeper Lattice is additive local runtime evidence at
  `runtime/upkeeper-lattice/lattice.sqlite3`. Runtime artifacts under
  `runtime/upkeeper-lattice/`, including SQLite side files, backups, exports,
  and recovery records, remain ignored local state.
- Advisory `lattice.unavailable` log lines remain non-fatal when
  `UPKEEPER_LATTICE_REQUIRED=0`, but they must carry a reason class, owner issue
  or contract, and replacement-evidence class instead of only a detail hash.
- For audit, breadcrumb, anomaly, and automation-obligation custody, Lattice is
  supporting evidence, not sole custody authority, until the tracked Lattice
  integrity blockers are closed. Lattice-derived custody decisions must keep a
  fallback log/transcript/runtime evidence check, or fail closed when that
  fallback evidence is unavailable.
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
  with stale database rows. Normal rotation includes non-ignored untracked files
  by default, but `UPKEEPER_SELECT_UNTRACKED=0`, `--select-untracked=0`, or
  `--tracked-only` keeps normal rotation to tracked files only. Explicit
  `--target-file` remains the strongest one-cycle pin for safe readable text
  targets, including non-ignored untracked files.
- Open critical/high breadcrumb custody records are machine-health evidence.
  Before normal rotation, they redirect the cycle to the configured Upkeeper
  breadcrumb gate target so unresolved severe clues cannot passively rot while
  ordinary timestamp selection continues. Explicit target pins and issue-fix
  pins remain visible rather than being silently replaced.
- `--max-cover` may ask Lattice to rank a broader current tracked text-file
  pool, but final selection still revalidates the live source-safe boundary in
  the same cycle.
- `--bug-report-only` is a no-fix mode. It must not edit or touch tracked
  source, and the wrapper must fail the cycle if the source mutation
  fingerprint changes during a non-dry-run bug-report-only cycle.
- `--audit-only` is the canonical no-fix/read-only audit alias, with
  `--review-only`, `--no-fix`, and `--read-only` accepted as equivalent
  spellings. It uses the same source mutation guard and final-message report
  contract as bug-report-only, records `audit_only=1` in cycle metadata, and
  stores local report artifacts under ignored runtime audit evidence by default.
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
  `tools/validate_upkeeper.sh --deps`, `--source-contracts`, `--smoke`,
  `--quick`, `--full`, and the additive `--profile` timing flag.
- Merge-steward cleanup for already-green backlog PRs remains local and
  no-backend. `tools/backlog_merge_steward.py` emits `merge_ready=yes|no`, a
  reason, and a next action, refuses unsafe PR/check/worktree states, and uses
  the guarded `CODEX_ALLOW_PR_MERGE=<pr>` path for real merges.
- Stopped backlog loop triage remains local and no-backend. The focused
  command `tools/backlog_triage.py` emits `safe_to_restart=yes|no|wait` plus a
  reason and next action, using local evidence and optional GitHub PR/check
  metadata.
- Control-plane inventory remains local and no-backend. The focused command
  `tools/upkeeper_control_plane_audit.py` emits stable JSON or concise terminal
  text for observed repo/runtime state, including tracked local-evidence
  artifacts, root scratch files such as `$db`, active locks, open obligations,
  optional deferred issue records, and recent hard loop markers.
- Negative-space validation remains part of the tracked safety surface.
  `docs/negative-space-testing.md` names deterministic local proofs for
  behavior that must not happen, and those proofs should stay no-backend unless
  an operator explicitly requests backend-specific testing.
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
- Review-module numbering remains compatible: P29 is reuse harvesting, P30 is
  Stark Protocol hardening, and fault-injection review is reserved for future
  P31 work or a later named module with an explicit non-breaking alias plan.
  The tracked `prompts/p31-fault-injection-review.md` file defines that future
  contract before any `--review-module=p31` CLI wiring exists.
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
