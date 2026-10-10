# Plans

This file captures active or recently completed implementation plans for complex
Upkeeper changes. Keep entries brief and update their status before merge.

## Issue #734: Startup Control-Plane Phase Extraction

Status: implementation and local validation complete; ready for focused PR

Goal:
- reduce the phase-spanning responsibility of `Upkeeper` `main()` by giving the
  post-argument startup control plane one named owner without changing its
  safety, custody, or target-selection sequence

Constraints:
- preserve the existing early operator/self-test exits, active-lock ownership,
  timing boundaries, cycle-start evidence, encrypted-backup preflight,
  issue/obligation binding, Lattice initialization, anomaly gate, quota marker,
  and manifest ordering
- retain `main()` as orchestration rather than moving control-plane policy into
  an unrelated helper; use local state only where it was not an intentional
  cross-phase input
- prove the actual dry-run/validator paths remain intact; no live backend use

Plan:
- extract the contiguous startup control-plane sequence after early argument
  handling and before quota snapshot parsing into one named entrypoint helper
- add a focused contract that verifies the phase boundary and its required
  ordering, complemented by existing real wrapper dry-run coverage
- run focused, full deterministic, and validator checks, then retain #734 open
  for the remaining `main()` and large-function work

Implemented and validated:
- extracted the contiguous startup control-plane sequence into
  `upkeeper_run_startup_control_plane_preflight`, retaining early command and
  self-test exits in `main()` and keeping all original timing/custody calls in
  their original order
- added a focused dependency-stubbed phase test that records and proves the
  critical lock, evidence, backup, issue, Lattice, quota, and manifest order
- passed focused syntax/phase checks, the real private no-backend probe, the
  full 80-test suite, public-doc checks, and real quick/full validation runs

Limitation:
- this reduces `main()` by one control-plane phase only. It does not claim to
  finish the remaining entrypoint, embedded-Python, or large-module work in
  #734, nor does it establish live backend behavior.

## Issue #705: Validator Mode-Boundary Extraction

Status: implementation and local validation complete; ready for focused PR

Goal:
- remove the validator's brittle self-source `rindex` inspection of the quick
  and full mode blocks, while preserving exactly which integration and full-only
  checks run in each validation mode

Constraints:
- retain quick, smoke, full, dependency, source-contract, and architecture
  behavior; do not turn any required validation into a warning or skip a gate
- keep the mode ownership executable and independently testable without running
  the entire validator or a live backend
- make this a narrow #705 increment; the remaining backlog-orchestration and
  large-entrypoint extraction work stays separately tracked

Plan:
- move integration/full-only check dispatch into a focused sourced helper whose
  only dependency is the validator's existing bounded-check/timing interface
- replace source-position inspection with a hermetic dispatcher regression that
  records actual requested checks for quick and full modes, including an
  unsupported-mode failure case
- run focused tests, syntax checks, the full deterministic suite, and quick and
  full validators; retain #705 open after this incremental PR

Implemented and validated:
- extracted the 27 integration and seven full-only checks into the small
  executable dispatcher, leaving the validator as its timeout/timing/check
  implementation owner
- replaced brittle source-position parsing with a hermetic dispatcher test that
  proves quick skips, full ordering/timeouts, unsupported modes, and immediate
  propagation of a bounded-check failure
- passed focused syntax/test checks, `tools/run_tests.sh` (79/79), public-doc
  checks, and real `tools/validate_upkeeper.sh --quick` and `--full` runs

Limitation:
- this is one #705 acceptance increment only. It does not claim to complete
  the remaining backlog-orchestration boundary work or establish live backend
  operation.

## Issue #685: Wrapper-Owned Current-Cycle Log Review

Status: complete; pending PR

Goal:
- stop making clean backend cycles spend a tool command to read/hash deterministic
  current-cycle wrapper evidence, while retaining the strict parseable
  `UPKEEPER_LOG_REVIEW` compatibility marker and anomaly escalation path

Constraints:
- generate review evidence in the wrapper immediately before backend contact;
  never disclose raw logs, raw paths, or unredacted runtime state in the prompt
- preserve the existing strict final-marker parser and startup-anomaly custody;
  only anomalous or unavailable wrapper evidence may ask the backend to inspect
  the sanitized helper output
- use deterministic fixtures and no live backend validation

Plan:
- make one wrapper-owned compact review snapshot (status, anomaly class, and
  digest) available to the prompt compiler and the final-marker verifier
- make clean snapshots instruct the model to reuse supplied values without a
  helper command; keep the sanitized helper as an explicit anomalous/fail-safe
  inspection path
- add focused clean/anomalous/compiler/parser regressions before the full suite

Implemented and validated:
- added one wrapper-owned pre-backend sanitized snapshot and made its compact
  anomaly/digest fields available to both the prompt and the strict final-marker
  verifier
- clean snapshots now omit the model helper command; anomalous or unavailable
  snapshots retain it, and mismatched/anomaly-class-inconsistent markers remain
  rejected
- passed focused compiler/parser/negative checks, the private no-backend probe,
  public-doc checks, `tools/run_tests.sh` (78/78), and the quick validator

Limitation:
- this proves local deterministic prompt and marker behavior only; it does not
  establish a live backend's cache or tool-use behavior, which remains outside
  no-quota validation

## Issue #704: No-Backend Fast-Path Budget and Regression Guard

Status: complete; pending PR

Goal:
- make the actual wrapper's isolated dry-run path observable as one bounded,
  pre-model sequence, so individually reasonable local gates cannot silently
  turn a healthy no-backend run into an expensive startup

Constraints:
- preserve the required startup, backup, Lattice, anomaly, manifest, quota,
  and target-selection checks; a budget observation may warn or make the
  dedicated probe fail, but must not skip a gate or contact a backend
- run the regression fixture through a symlinked central wrapper with private
  HOME/XDG, ledger, obligation, backup, Lattice, log, and lock roots; it must
  never use operator state or invoke live Codex

Plan:
- add one small module that records elapsed pre-model phases with an injectable
  clock for deterministic unit coverage and emits a clear aggregate summary
- time the existing anomaly, backup/target, Lattice startup/record, manifest,
  and prompt-preparation boundaries without duplicating their policy decisions
- add a standalone probe that makes a temporary Git fixture, instruments real
  Python process launches, executes `UPKEEPER_DRY_RUN=1`, verifies no backend
  launch, and enforces a configurable overall budget
- retain the measurement as evidence only in ordinary cycles; the probe is the
  explicit regression gate for a budget breach

Validation:
- use the module's fake-clock test for phase math and warning behavior, then
  exercise the real symlinked wrapper probe for its private state and no-backend
  invariant before the full required shell validation suite

Implemented and validated:
- added one pre-model timing owner with an aggregate 10-second default budget
  and named anomaly, backup/target, Lattice, manifest, and prompt boundaries;
  ordinary cycles retain all gates and only log a visible warning on a breach
- added an explicit isolated probe that runs the real wrapper in dry-run mode,
  verifies the dry-run completion/no-backend invariant, and reports actual
  Python, Lattice, and control-plane-audit subprocess counts
- passed fake-clock timing coverage, the real within-budget probe, its forced
  over-budget failure, public-document checks, the full 77-test suite, and the
  required quick validator

Limitation:
- the probe is a deterministic fixture-level workflow integration check, not
  authorization for real Codex execution or evidence of a live operator cycle;
  the ordinary budget warning deliberately records pressure without changing
  required validation or safety policy

## Issue #718: Per-Fix Wall-Clock Budget and Phase Evidence

Status: complete; merged in PR #898

Goal:
- make the whole issue-repair path observable as a bounded sequence of local,
  external, and waiting phases instead of treating individually reasonable
  waits as invisible aggregate cost

Constraints:
- do not lower or skip existing validation, quota, obligation, or PR gates to
  meet a time target; distinguish external pending time from local regression
- use the backlog's injectable clock and private state roots so tests do not
  sleep, call a live backend, or modify operator state

Plan:
- map existing job summaries and time-aware paths to establish one phase-timing
  owner rather than duplicate elapsed-time arithmetic in validation, PR, and
  quota code
- record ordinary-language phase summary and configured class budget for issue
  work, preserving the current low/medium/high/xhigh task classification
- create a durable, deduplicated obligation only for an avoidable local budget
  breach; external CI pending, quota hibernation, and cooldown remain explicit
  external reasons rather than synthetic failures
- add fake-clock coverage for passing and breached budgets plus pending CI,
  registration grace, quota hibernation, and cooldown defer evidence

Implemented and validated:
- added one backlog phase-timing owner that records model, local validation,
  push, PR registration/pending checks, merge, and quota-hibernation elapsed
  time; external waiting is explicitly separated from local elapsed time
- class budgets follow the existing task classes, retain a private per-job TSV
  evidence record, and open/update an obligation only when local time—not
  external waiting—exceeds the selected budget
- added fake-clock regression coverage for summary math, local breach evidence
  and obligation creation, and external-CI exclusion; updated isolated launcher
  fixtures to include the new sibling module
- passed syntax, focused tests, public-doc checks, `tools/run_tests.sh`
  (75/75), `tools/validate_upkeeper.sh --quick`, and `git diff --check`

Limitation:
- phase evidence observes the launcher workflow but does not authorize a retry,
  skip a required gate, or identify a performance improvement by itself; the
  resulting obligation remains ordinary evidence-backed repair work

## Issue #719: Fail-Closed Local Trivial-Fix Lane

Status: complete; pending PR

Goal:
- prevent ordinary issue repair from unconditionally crossing the backend
  boundary when the selected issue provides enough trusted, deterministic
  evidence for a bounded local check or a no-backend completion

Constraints:
- preserve wrapper-owned issue selection, machine-health-first preflights,
  Lattice evidence, required backup/authority boundaries, and full backend
  escalation for uncertainty, safety/data-integrity/control-plane work
- do not let labels alone authorize a source edit or change a target; local
  successes must be concrete validator outcomes with retained reason evidence

Plan:
- map the issue packet, preselection, and cycle-finalization boundaries to find
  one shared classification owner before any Codex launch
- add a conservative local-only allowlist for proven docs/check cases and an
  explicit unknown/unsafe escalation path; retain profile-selected lower effort
  when a model is still needed
- exercise actual no-backend completion, failed/ambiguous local proof, and
  safety-sensitive escalation with private fixtures; document the lane and its
  non-goals

Validation:
- use focused deterministic fixtures first, then the required shell syntax,
  full suite, whitespace, public docs, and quick validator without backend work

Implemented so far:
- added a narrowly scoped local-fix owner after selected-target prompt setup and
  before backend launch; it accepts only an explicitly authorized target in an
  already-applied docs-only diff that contains no sensitive control-plane labels
  and passes the shared docs gate
- all other path/diff states deliberately return to the existing model path;
  the local test covers safe completion plus inferred-target, security,
  mixed-path, empty-diff, failed-validation, dry-run, and disabled-lane
  rejection

Validation completed:
- `bash -n Upkeeper lib/upkeeper/*.bash tools/*.sh tests/*.bash testruns/*.sh Upkeeper.conf configurations/default.conf`
- `bash tests/local_fix_lane_test.bash`
- `tools/check_public_docs.sh --quick`
- `tools/run_tests.sh` (74/74 passed)
- `tools/validate_upkeeper.sh --quick`
- `git diff --check`

Limitations:
- this is an intentionally narrow completion lane for an explicitly selected,
  already-applied editorial target; it does not treat an inferred target,
  labels, or a documentation check as general proof that arbitrary issue prose
  has been semantically resolved
- no formatter or syntax fixer is introduced because this checkout has no
  established deterministic repair tool for those source classes; those
  model-needed classes continue to use the existing task-profile effort policy

## Issue #684: Preserve Explicit Primary Reasoning-Effort Overrides

Status: complete; pending PR

Goal:
- retain the existing deterministic task profile that lowers the built-in
  `xhigh` baseline for routine work, while ensuring a deliberate primary
  effort from an environment, named config, or local env file is never silently
  replaced before backend contact

Verified defect:
- `upkeeper_apply_task_profile` correctly runs before prompt compilation and
  backend contact, but it currently replaces any direct `CODEX_REASONING_EFFORT`
  value unless a `--model-override` was used; the config loader does not retain
  provenance that distinguishes a named profile from `Upkeeper.conf`'s baseline

Plan:
- carry explicit-effort provenance from startup and trusted config loading into
  the shared task-profile owner, treating only the built-in default as
  profile-adjustable
- log the effort decision source and cover both the direct profile decision and
  an actual sourced-entrypoint named-config fixture without backend work
- update generated help, public compatibility guidance, and current change
  notes; retain automatic low/medium/high/xhigh classification for values that
  were only defaults

Validation:
- run the focused profile regression and public-doc checks; then required shell
  syntax, full deterministic suite, whitespace check, and quick validator

Completed implementation:
- recorded explicit primary-effort provenance before the default config loads
  and when trusted named/local configuration assigns `CODEX_REASONING_EFFORT`;
  the repository default remains a compatibility baseline, not an implicit
  operator override
- made the shared profile owner preserve that provenance and log
  `effort_source=task_profile|operator_override|model_override|auto_effort_disabled`
  alongside the before/after effort
- added a sourced-entrypoint named-config fixture under a private state-root
  temporary directory, proving the real trusted config loader and profile
  retain a deliberate `high` setting for an otherwise docs-only target

Validation evidence:
- required shell syntax, focused task-profile regression, public-doc checks,
  `git diff --check`, the complete 73-test deterministic suite, and
  `tools/validate_upkeeper.sh --quick` passed with no backend model execution
- the quick validator's slowest existing check was the autoshelve contract at
  about 71 seconds; no timeout or validation policy was changed

## Issue #715: Expand Validation Artifact Reuse Beyond Unit Tests

Status: complete; merged in PR #894

Goal:
- extend the existing fail-closed same-tree unit-test attestation into an
  explicit validation artifact that can safely explain reuse or rerun decisions
  at the backlog's per-bug, batch, and merge boundaries
- retain fresh validation whenever the command, tracked tree, environment, or
  trusted artifact state does not match

Verified current state:
- `tools/test_attestation_lib.bash` already safely attests a successful
  `tools/run_tests.sh` execution and `tools/validate_upkeeper.sh` can reuse
  individual test results on the same clean tree/environment
- `orchestration/backlog.sh` still independently invokes per-bug and batch
  validation without producing or consuming a broader manifest for its
  command/phase decisions, so #715 is not closed by the existing #713 work

Plan:
- inspect the existing attestation ownership and add the smallest compatible
  manifest capability needed for backlog-owned validation phases rather than a
  parallel format
- key reusable proof to command, selected phase set, tracked tree, environment,
  tool identities, and relevant changed paths; reject missing, stale, changed,
  or untrusted proof with an explicit reason
- add deterministic backlog fixtures for valid reuse and the required rejection
  cases, then document the local-evidence boundary and operator logs

Validation:
- run focused attestation/backlog tests, required syntax and docs checks, full
  deterministic suite, whitespace, and quick validation before PR

Completed implementation:
- added one private `upkeeper.validation-attestation.v1` owner for phase-level
  proof rather than extending the incompatible per-test row format; it records
  successful command phases, exit status, durations, UTC timestamp, Git
  head/tree, complete tracked and untracked input hashes, environment class,
  and tool versions
- batch and merge-steward invocation now share a branch-local state-root
  artifact, per-bug validation records/reuses its own scoped proof, and CI
  supplies only runner-temporary evidence; missing or unsafe proof cannot skip
  a gate and reports `validation_rerun` or `validation_reuse_rejected`
- added isolated regression coverage for valid runner reuse and fail-closed
  stale-head, command, environment, and broader-input mismatches; updated
  copied backlog fixtures so their controlled roots retain the new dependency

Validation evidence:
- local syntax, public-doc, whitespace, focused attestation fixtures, and the
  complete 73-test deterministic suite passed; `tools/validate_upkeeper.sh
  --quick` passed
- PR #894 passed phase gates, full validation, and CodeQL at head
  `09df7281aae107f37a0b7fc71ae69ff35dc1d690`; merged main commit
  `89f6c55c115e502adc98b7f3228cf9480151cdf2` then passed separate push-to-main
  CI and CodeQL verification

## Issue #703: Reuse Control-Plane Audit Inventory During Staging

Status: complete; merged in PR #893

Goal:
- avoid independently rebuilding the same tracked-repository and control-plane
  inventory for the before snapshot and policy/remediation operation in one
  staging boundary
- retain actual post-remediation observation, before/after snapshots, lineage,
  blocker custody, and fail-closed staging semantics

Verified defect:
- `run_control_plane_pre_staging_audit` starts the audit executable once to
  write a before snapshot, then starts it again for remediation and the after
  snapshot; the latter can rebuild its full payload again after safe cleanup
- `cleanup_ephemeral_artifacts` and snapshot-only lifecycle points are separate
  boundaries and must not be conflated with a transaction that needs a current
  after-state observation

Plan:
- add one explicit pre-staging transaction interface in the audit owner that
  writes the pre-remediation snapshot and evaluates/remediates within one
  process, sharing immutable repository inventory only where it cannot be
  invalidated by safe cleanup
- make the backlog use that interface for the paired pre-staging snapshots;
  leave other audit lifecycle calls explicit and current-state based
- add an isolated invocation-count regression plus preservation coverage for
  safe remediation, snapshot delta, obligations, and blocking failures

Validation:
- run focused audit/backlog fixtures and required syntax; then full tests,
  diff whitespace, quick validation, and appropriate public-doc checks

Completed evidence:
- focused audit regression proves one `git ls-files -z` inventory across the
  paired snapshot/remediation transaction and retains the KP-002 snapshot delta
- syntax, public-doc checks, the full 71-test deterministic suite,
  `git diff --check`, and `tools/validate_upkeeper.sh --quick` passed without
  live backend work

## Issue #716: Make Obligation Retry Cooldown State-Aware

Status: complete; merged in PR #892

Goal:
- prevent identical blocked automation-obligation repairs from spinning while
  allowing an immediately meaningful retry when the repair inputs change
- replace the six-hour default with a bounded, shorter cooldown and make a
  deferred decision understandable from normal backlog output

Verified defect:
- the selector currently treats every record with `next_retry_epoch` later
  than now as ineligible, without comparing its repair target, current
  branch/HEAD, relevant evidence, linked issue, or an operator-directed retry
  context; the default delay is 21,600 seconds

Plan:
- centralize a privacy-preserving retry-state snapshot/fingerprint helper
  shared by cooldown recording and selection; exclude mutable attempt custody
  so recording an attempt cannot itself bypass the guard
- store the snapshot with a cooldown, permit selection on a meaningful state
  change or explicit override, and retain time-based deferral for an identical
  state or legacy records lacking a snapshot
- pass the policy through the backlog launcher, report remaining wait, ID,
  fingerprint, and immediate-retry conditions, and document the shorter
  default plus explicit context/override controls

Validation:
- add a fully isolated deterministic retry-state fixture covering unchanged,
  target, branch/HEAD, evidence, override, and expired cases; prove stored
  retry custody remains intact
- run required syntax, focused tests, full deterministic suite, whitespace,
  quick validation, and public-doc checks before the focused PR

Completed evidence:
- `bash -n Upkeeper lib/upkeeper/*.bash orchestration/backlog.sh tools/*.sh
  tests/*.bash testruns/*.sh Upkeeper.conf configurations/default.conf` passed
- focused retry-state, identity, and claim fixtures; public-doc checks; full
  71-test deterministic suite; `git diff --check`; and
  `tools/validate_upkeeper.sh --quick` passed without backend execution

## Issue #876: Make Lattice CLI Fixture Cleanup Non-Interactive

Status: complete; merged in PR #877

Goal:
- keep the serial Lattice CLI integration fixture within its existing 45-second
  deadline when its test-owned Git repository contains read-only object files
- preserve all Lattice assertions, fixture permissions, and timeout budgets

Verified defect:
- `tests/lattice_test.bash` prints successful CLI-integration assertions, then
  its EXIT trap invokes `rm -r` on an `mktemp` root that contains mode-0444 Git
  object fixtures; on a terminal this suppresses an interactive confirmation
  prompt and waits for input until the outer deadline expires

Plan:
- make cleanup non-interactive while retaining the exact test-owned temporary
  root as its only deletion target
- run the CLI group through a pseudo-terminal in its existing wrapper so the
  regression exercises the formerly blocking prompt path
- keep cleanup/reaping behavior intact for both passing and failing groups

Validation:
- reproduce the prior terminal cleanup timeout, then show the existing
  45-second CLI wrapper completes without input after the repair
- run focused Lattice coverage, the full deterministic suite, syntax,
  whitespace, and quick validation without increasing any deadline

## Issue #728: Remove Remaining Sourced-Module Function Shadow

Status: complete; merged in PR #878

Goal:
- remove the remaining real `precontact_backup_hmac_text` entrypoint override
  so the pre-contact backup module owns its public HMAC behavior
- remove stale #728 allowlist debt now that the status-session function is
  already module-owned

Verified defect:
- the architecture lint finds a real, allowlisted duplicate
  `precontact_backup_hmac_text`: the module is sourced first, then `Upkeeper`
  replaces it to cache a parent-process fallback redaction key; this makes
  runtime behavior depend on load order
- `resolved_status_marker_from_analysis` is no longer duplicated, but remains
  needlessly listed in the transitional allowlist

Plan:
- move the pre-contact-specific fallback-key cache and HMAC implementation
  into `lib/upkeeper/precontact_backup.bash`, preserving stable HMAC values
  when the redaction key cannot be persisted
- remove the root override and both obsolete allowlist entries
- make the architecture regression prove the sourced entrypoint and direct
  module load expose the same `precontact_backup_hmac_text` implementation

Validation:
- run the focused architecture and pre-contact backup regressions plus the
  existing entrypoint HMAC self-test
- run required syntax, deterministic test suite, diff whitespace, and quick
  validation before opening the focused PR


## Issue #727: Tier Recovery Reasoning Effort by Trigger

Status: complete; merged in PR #880

Goal:
- keep fallback, postmortem reporting, and opt-in hardening from inheriting the
  primary `xhigh` effort while choosing lower effort for known non-capability
  recovery paths
- retain an explicit operator override and deterministic, no-backend regression
  coverage

Verified defect:
- #794 changed the static fallback/postmortem defaults to `high`/`medium`, but
  every fallback trigger still uses the same fallback effort and every
  postmortem phase still uses the same postmortem effort; no runtime record
  names the selected trigger class or policy reason

Plan:
- add one shared trigger-to-effort policy in the postmortem/fallback ownership
  layer, with distinct quota/environment, dirty/no-backend, blocked, no-output,
  capability-failure, report, and opt-in-hardening behavior
- apply it to the actual direct and detached-screen fallback child and centrally
  at the auxiliary postmortem execution boundary, so root compatibility wrappers
  cannot bypass the policy
- preserve explicit environment effort settings, document the automatic-policy
  behavior, and record selected effort, trigger class, and reason before every
  recovery model call

Validation:
- use fake child and auxiliary-Codex fixtures to prove the real launch argument
  changes for quota, generic failure, blocked, no-output, report, hardening,
  and explicit-override paths without launching Codex
- run required syntax, the full deterministic suite, whitespace check, and
  quick validator; inspect operator docs/help and synchronize version notes

## Issue #725: Batch Selected-Target Backup Metadata

Status: complete; merged in PR #882

Goal:
- remove repeated Python interpreter launches from selected-target pre-contact
  backup metadata collection without weakening backup privacy or durability

Verified defect:
- the selected-target path separately launches Python for file SHA-256,
  content/path/repository HMACs, repository realpath, derivation SHA, and file
  metadata, despite all values being one snapshot of the target and cycle inputs

Plan:
- establish one structured metadata helper for selected-target backup creation
- preserve hash/HMAC namespaces, redacted output, and metadata fields; leave
  age encryption and restore-validation boundaries unchanged
- measure actual Python-launch count in a deterministic selected-target fixture

Validation:
- retain existing plain/age/restore/redaction/mode/mtime coverage and add real
  selected-target launch-count and helper-failure regression coverage
- run required syntax, full deterministic suite, whitespace, and quick
  validation before PR

## Issue #706: Remove Per-Log-Line `date` Forks

Status: complete; merged in PR #883

Goal:
- remove the `date(1)` process launch from the central timestamp helpers used
  for every log line and terminal timestamp, while retaining byte-compatible
  timestamp and epoch output on supported Bash runtimes

Verified defect:
- `timestamp_now`, `terminal_timestamp_now`, and `epoch_now_fraction` each
  execute external `date`; `log_line` calls the first helper for every record
  and terminal/progress output calls the others repeatedly

Plan:
- use Bash's `printf '%(... )T'` and epoch special variables on supported
  runtimes, with a contained compatibility fallback only when those facilities
  are unavailable
- retain the existing timestamp shapes, timezone offset, five-place fractional
  epoch contract, and progress/log error paths

Validation:
- make a deterministic runtime test poison `date` and prove the supported
  helpers and `log_line` continue to emit valid output without using it
- exercise the explicit fallback boundary with a controlled `date` fixture,
  then run required syntax, focused regression, full deterministic suite,
  whitespace, and quick validation before PR

## Issue #707: Cache Backlog Branch Identity

Status: complete; merged in PR #884

Goal:
- avoid repeated `git rev-parse --abbrev-ref HEAD` launches during one backlog
  iteration without allowing owner records, retry state, autoshelving, or push
  guards to use a branch value after Git has changed it

Verified defect:
- the source has independent branch-resolution calls in hibernation, ownership,
  notices, deferred/retry paths, autoshelving, push guards, and publication;
  several occur in ordinary stable-branch control flow

Plan:
- make one explicit mutable branch-identity cache owned by the backlog launcher
  and use assignment-style refreshes so command substitutions cannot discard
  cache updates
- invalidate it immediately after every checkout, branch creation, reset, and
  merge-cleanup branch transition; retain direct fresh reads where an invariant
  requires one

Validation:
- add an isolated Git fixture with a counting Git wrapper to prove stable reuse
  and post-transition refresh, including detached/unknown fallback and push
  guard correctness
- run focused backlog regressions plus required syntax, full deterministic
  suite, whitespace, and quick validation before PR

## Issue #708: Batch Homogeneous Lattice Import Writes

Status: complete; merged in PR #885

Goal:
- reduce Python-to-SQLite overhead only for importer rows whose statement shape
  and conflict behavior can be preserved without losing source identity,
  idempotency, privacy, or foreign-key ordering

Verified defect:
- the original issue's implementation filename is stale after the import-cache
  split, but the live `tools/upkeeper_lattice_core.py` import commands still
  contain no `executemany` calls; some high-volume loops are homogeneous while
  others require per-row ids and conflict handling

Plan:
- identify one high-volume insert path that needs no immediate `lastrowid` or
  per-row branch, batch it in bounded groups, and leave identity-sensitive
  source/cycle/file/import paths alone
- use real Lattice import fixtures to compare row counts, idempotency, privacy,
  and conflict outcomes before considering a broader importer change

Validation:
- add a deterministic batch-count or SQLite connection fixture that exercises
  production importer behavior rather than source text alone
- run focused Lattice import coverage plus the required full local validation
  before opening a PR

## Issue #709: Tighten PR Check Registration Grace

Status: complete; merged in PR #886

Goal:
- reduce the unconditional five-minute no-check registration wait without
  bypassing the fail-closed PR gate or confusing absent, registering, pending,
  and failed check states

Verified defect:
- normal backlog PR-check waits default to a 300-second empty response grace;
  the effective delay can be longer because the 60-second poll is not clipped
  to the grace deadline

Plan:
- set a defensible shorter registration default and cap each empty-state sleep
  by the remaining registration window
- preserve the global timeout, existing explicit override, owner custody, and
  failed-check stop behavior while naming registration state distinctly in
  durable logs

Validation:
- extend the fake-clock PR-check tests for empty-then-present success, a
  permanently empty failure at the exact bounded grace, and pending/pass
  behavior unaffected by registration handling
- update the operator guide for the changed default and run required full
  validation before PR

## Issue #710: Tighten PR Check Polling Cadence

Status: implementation and local validation complete; ready for focused PR

Goal:
- reduce avoidable post-green idle time in the required PR-check gate without
  creating an unbounded GitHub API polling loop or weakening the CI authority

Verified defect:
- normal pending-check polling defaults to 60 seconds even after #709 narrowed
  empty registration, so a check that completes just after a poll can still
  add nearly a minute to a trivial repair

Plan:
- choose a shorter documented default with the existing explicit environment
  override retained; preserve the registration-window clipping introduced by
  #709 and all timeout/custody behavior
- make pending logs and fake-clock tests prove the new cadence and maximum
  detection delay instead of merely asserting a config literal

Validation:
- update deterministic pending/pass and empty-registration tests for the new
  default; retain explicit long-interval fixture coverage as an override case
- update the operator guide and run required full validation before PR

## Issue #711: Plan Batch Validation by Affected Surface

Status: implementation and local validation complete; ready for focused PR

Goal:
- avoid paying the complete local test/quick-validator cost for an explicitly
  safe, narrow batch while preserving a fail-closed full-validation fallback
  for every operational or uncertain change

Constraints:
- retain isolated test-state roots, failure obligations, snapshots, and the
  required CI gate; do not use reduced local work as authority to bypass CI
- make the plan reproducible from an explicit base/head plus staged and
  unstaged paths; missing revisions or an empty/uncertain path set select full
- keep control-plane, Lattice, prompt, config, test, workflow, and runtime
  changes on the full lane until a focused contract can justify otherwise

Likely files:
- `orchestration/backlog.sh`
- a small deterministic validation-plan helper and focused tests
- `tools/validate_upkeeper.sh`, operator documentation, and change notes

Validation:
- deterministic path fixtures proving editorial-only selection,
  full-lane selection for each sensitive class, and missing-range fail-closed
  behavior
- required syntax, full suite, diff, docs, and quick-validator commands before
  PR

## Issue #717: Make Quota Hibernation Prompt at the Reset Boundary

Status: implementation and local validation complete; ready for focused PR

Goal:
- remove the unconditional one-minute post-reset hibernation tax while keeping
  quota protection, local-only waiting, and operator-visible custody intact

Verified defect:
- `backlog_hibernate_until_epoch()` defaults both the reset grace and local
  wake/branch-check poll interval to 60 seconds; a known reset therefore waits
  until `reset + 60` even though the next preflight can safely re-evaluate
  fresh quota evidence before any backend work
- its existing final `min(remaining,poll)` chunk avoids oversleeping a chosen
  wake epoch, but it does not make the one-minute grace explicit, configurable
  down to zero, or suitably responsive near the boundary

Plan:
- use a small, explicitly documented default grace and shorter bounded polling,
  with a tighter local check cadence near the reset boundary; preserve the
  configured maximum-wait guard, hard usage-limit behavior, branch-retired
  exit, and no-backend hibernation semantics
- make logs and owner heartbeat evidence state the reset, grace, next local
  check, and final recheck timing in ordinary operator language
- extend deterministic fake-clock coverage for immediate/near reset, explicit
  zero grace, invalid configuration fallback, branch retirement, and both
  marker and snapshot callers without querying a live quota provider

Likely files:
- `orchestration/backlog.sh`
- focused quota-hibernation regression coverage and validation contracts
- `lib/upkeeper/help_selection.bash`, `docs/scripts/upkeeper.md`,
  `docs/compatibility.md`, `change_notes_2026.md`, and this plan

Validation:
- demonstrate the old 60-second default grace under a fake clock, then prove
  the new configured/default boundary timings, exact exit status, and retained
  branch/maximum-wait safeguards
- run required syntax, deterministic suite, whitespace, public-doc checks,
  quick validator, and the focused no-backend quota tests before PR

## Issue #724: Remove Remaining Hot-Path Logging Subshells

Status: implementation and local validation complete; ready for focused PR

Verified current state:
- issue #706 already replaced routine `date` timestamp generation in
  `runtime_foundation.bash` with Bash `printf '%(...)T'` and preserves a tested
  compatibility fallback, so the timestamp portion of this report is stale
- `log_kv()` still nests `log_kv_value()` in command substitution, while
  structured call sites commonly compose fields through command substitution

Goal:
- introduce assignment-style, builtin quoting/key-value helpers and migrate the
  demonstrably hot structured-log construction path without changing the log
  schema or weakening control-character protection

Constraints:
- retain exact `%q` semantics, invalid-key normalization, timestamp formats,
  compatibility fallback, and existing secure log-write behavior
- measure command/subshell avoidance with a deterministic test or benchmark;
  do not make speculative bulk edits across hundreds of unrelated log sites

Likely files:
- `lib/upkeeper/runtime_foundation.bash`
- focused runtime/data-protection tests, validation contracts, docs, notes

Validation:
- deterministic tests for empty/control-character/special values, invalid keys,
  timestamp compatibility, schema identity, and assignment helper behavior
- required syntax, full suite, diff, docs, and quick-validator commands before
  PR

## Issue #730: Batch Lattice Candidate Git Metadata

Status: in progress

Goal:
- remove per-eligible-candidate Git process launches from max-cover metadata
  collection while preserving source safety, status, and hash semantics

Verified defect:
- candidate enumeration already batches path, status, and HEAD-blob discovery,
  but `selected_git_metadata()` still invokes `git hash-object` for every
  eligible candidate

Plan:
- classify candidates first, hash only eligible non-symlink paths in bounded
  Git argument batches, then construct the existing row metadata from those
  results
- preserve argv-based handling for paths containing newlines and fall back to
  the established single-path behavior only for a failed batch

Validation:
- measure real selection subprocess count before and after in the deterministic
  profile, including newline-path and unavailable-file behavior
- run focused Lattice tests plus full repository validation before PR

## Issue #731: Batch Lattice Max-Cover Coverage Queries

Status: implementation and local validation complete; awaiting PR CI

Goal:
- replace per-candidate file-ID and pass-coverage SQL lookups in max-cover
  selection with bounded set-based queries while preserving ranking output

Verified defect:
- `annotate_max_cover_scores()` calls `file_id_for_path()` and
  `pass_coverage_counts_for_file()` once per eligible candidate, creating an
  N-plus-one SQLite query pattern

Plan:
- collect eligible candidate paths once, resolve file identities in a bounded
  `IN` query, and fetch grouped coverage counts for those identities
- annotate rows from in-memory maps and add a real query-count regression that
  compares mixed covered/uncovered scoring against the existing contract

Validation:
- reproduce the pre-change query shape in an isolated Lattice fixture
- exercise output/ranking, missing-file, covered, and uncovered paths, then
  run focused Lattice tests and repository validation before PR

## Issue #729: Cache Lattice Pass-Result HMAC Key Per Selection Query

Status: implementation and local validation complete; awaiting PR CI

Goal:
- stop `selection-candidates --mode max-cover` from deriving the same
  repository-scoped pass-result HMAC key once for each candidate hash
- preserve the existing key derivation, override-key behavior, and redacted
  output values without introducing a stale process-global repository cache

Verified defect:
- `live_candidate_paths()` HMACs both the worktree hash and the HEAD blob for
  each candidate, and each `content_value_hmac()` call derives its key through
  `repo_git_info()`, which invokes several Git commands

Plan:
- derive the key once at the candidate-query boundary and pass it explicitly to
  the HMAC helper for each row
- extend the deterministic selection profiler to count repository-identity
  derivations during the actual query and enforce a constant bound

Validation:
- capture the pre-change profile, then prove the actual max-cover query derives
  the HMAC key once while retaining candidates and redacted hash output
- run focused profile and Lattice tests, syntax checks, full deterministic
  tests, and repository validation before PR

## Issue #798: Authoritative Issue-Repair Target Selection

Status: complete; merged in PR #860

Goal:
- prevent the backlog launcher from pinning a broad keyword-derived target
  before the wrapper reads the selected issue's concrete repository paths
- keep one wrapper-owned source of truth for issue-repair targets
- make a genuine operator explicit-target override visibly conflict with a
  differing issue inference

Validation:
- an Issue #793-style fixture keeps `tools/run_tests.sh` as the wrapper target
  even when its evidence also names `tools/upkeeper_lattice.py`
- the backlog handoff invokes `--fix-issue` without `--target-file`
- an explicit conflicting target remains an override but emits its reason and
  both target values

## Issue #694: Redact Plain Backup Sidecar Paths

Status: complete; merged in PR #854

Goal:
- honor the default-on path-redaction setting in plain backup sidecars
- preserve legacy raw-path metadata only when redaction is explicitly disabled
- require an explicit restore destination when a plain sidecar omits its path

Verified defect:
- `UPKEEPER_PRECONTACT_BACKUP_REDACT_PATHS=1` is the documented default, but
  the plain metadata writer always serialized `selected_relative_path`
- age public sidecars already omit the field; their private encrypted payload
  correctly retains it for automatic restore

Validation:
- redacted plain sidecars contain only the path HMAC and require `--restore-to`
- opt-out plain sidecars retain automatic legacy restore behavior
- age public/private metadata behavior remains unchanged

## Issue #695: NUL-Safe Restore Sidecar Discovery

Status: complete; merged in PR #855

Goal:
- preserve sidecar paths containing embedded newlines during restore-by-id
- count complete discovered paths rather than newline-separated fragments
- keep missing and duplicate backup ids fail-closed in root and standalone paths

Verified defect:
- the shared finder used `find -print`, and restore captured its output in a
  scalar before counting and selecting lines with `sed` and `wc -l`
- the root entrypoint's filtered Python finder also printed one path per line

Validation:
- library and standalone restores recover the expected bytes through a vault
  path containing a newline
- a second matching sidecar is rejected with
  `backup_id_not_unique_or_missing` using an array count
- static validation covers the root entrypoint's separate NUL writer and array
  consumer

## Issue #693: Preserve Encrypted Restore Modification Time

Status: complete; merged in PR #856

Goal:
- record the selected file's nanosecond modification time in private metadata
- restore that timestamp without weakening fd-relative destination installation
- keep encrypted payloads created before the new field backward compatible

Verified defect:
- metadata recorded only a formatted `mtime`, not integer `mtime_ns`
- payload extraction created a new file and secure installation preserved that
  new timestamp instead of the selected file's original modification time

Validation:
- an encrypted backup restores a known filesystem-reported `st_mtime_ns`
  exactly through the standalone helper
- root and module installers validate and apply the optional timestamp before
  atomic rename
- a rewritten legacy payload without `mtime_ns` still restores its bytes

## Issue #696: Component-Aware Sensitive Worktree Paths

Status: complete; merged in PR #857

Goal:
- stop classifying ordinary paths by incidental sensitive-word substrings
- keep actual sensitive paths HMAC-only without deleting their snapshot rows
- preserve dirty-path and delta accounting without retaining secret metadata

Verified defect:
- the classifier matched `secret`, `credential`, and `token` anywhere in the
  normalized path, including `secretary.md`, `credentialing.md`, and
  `tokenizer.py`
- snapshot collection skipped every row when either rename path was classified
  sensitive

Validation:
- the four reported false positives remain ordinary snapshot entries
- `.env`, private-key, credential-store, and token-file fixtures remain
  sensitive and HMAC-only
- sensitive rows retain status/accounting but omit content metadata and file
  inventory linkage

## Issue #688: Typed JSON-to-Shell Parsing

Status: complete; merged in PR #853

Goal:
- replace JSON-generated shell assignments and their seven `eval` consumers
- preserve structured/string values through the NUL-delimited JSON transport
- restrict every destination prefix and field name to a fixed parser schema

Verified defect:
- five helpers used `jq @sh` to generate assignment source consumed by `eval`
  in quota, status, session, review-summary, and pass-coverage paths
- escaping was currently sound, but correctness depended on continuing to
  generate executable shell text for data transport

Validation:
- quotes, newlines, tabs, backslashes, arrays, objects, and shell-looking text
  round-trip as inert data without `eval`
- malformed JSON and unapproved destination prefixes fail closed
- production and tests contain no consumers of the removed assignment helpers

## Issue #689: Safe Fallback Token Descriptor Close

Status: complete; merged in PR #852

Goal:
- remove entrypoint `eval` from fallback-token descriptor cleanup
- share one numeric-only dynamic-fd close helper with the active-lock module
- preserve valid inherited-token reads while rejecting untrusted fd syntax

Verified defect:
- root entrypoint overrides retained two `eval "exec ${token_fd}<&-"` calls
  after the sourced active-lock implementation had moved to safe Bash fd syntax
- the descriptor originates in `CODEX_FALLBACK_CHAIN_TOKEN_FD`, so malformed
  environment text reached shell evaluation in both root cleanup paths

Validation:
- valid numeric descriptors are read and closed in module and root paths
- empty, alphabetic, and shell-looking values cannot close an unrelated fd or
  create an attack marker
- repository validation rejects reintroduction of the root `eval` pattern

## Issue #676: Wrapper-Owned Bug-Report Issue Creation

Status: complete; merged in PR #851

Goal:
- always block backend `gh issue create`, independent of wrapper write opt-in
- validate and deduplicate the local issue draft before wrapper-owned creation
- keep audit-only and non-opted-in runs local-artifact-only

Verified defect:
- the backend command stub conditionally forwarded `gh issue create` even
  though backend execution removes GitHub credentials and isolates config
- the write opt-in therefore authorized a contradictory, ambient-auth-dependent
  backend side effect instead of a wrapper-owned actuator

Validation:
- backend create attempts fail with and without wrapper write opt-in
- wrapper filing parses title, labels, and body only after successful runtime
  evidence; disabled policy and exact-title duplicates do not invoke transport
- focused, full test, and repository validation suites cover the boundary

## Issue #675: Typed Issue-Comment Actuator

Status: complete; merged in PR #850

Goal:
- require `upkeeper.issue_comment_action.v1` before any issue-comment write
- bind the action to issue, stage, draft path/content, accepted status, backend
  exit, unchanged-source result, and selected target
- distinguish action validation refusal from GitHub transport failure

Verified defect:
- the actuator materialized a prose draft and called `gh issue comment` using
  ambient globals without an accepted-outcome action record
- review-decision status mapping happened only after the GitHub write
- unavailable source-mutation evidence did not prevent comment posting

Validation:
- valid bound comment and review actions post through a fake `gh` transport
- missing status, wrong target, mutation violation, wrong prefix, invalid schema,
  and altered draft content fail before transport
- runtime builds the record only after the status and source guard are known

## Issue #674: Strict Status Authority Airlock

Status: complete; merged in PR #849

Goal:
- accept status authority only from one exact final legacy marker or a strict
  `upkeeper.final-status.v1` JSON record
- keep decorated, duplicated, fenced, and prose-derived status diagnostic-only
- apply the same boundary to primary and fallback/postmortem paths

Verified defect:
- the module parser classified malformed marker candidates, but entrypoint and
  session overrides promoted several rejected forms back into runtime status
- an entrypoint override selected the last decorated marker from duplicates
- default review-summary and blocker-request recovery synthesized status from
  natural-language text, bypassing the documented airlock

Validation:
- exact legacy and typed JSON fixtures pass through one normalized record
- quotes, backticks, bullets, fences, punctuation, trailing prose, indentation,
  duplicate markers, and invalid JSON schemas fail closed with a reason
- fallback/postmortem classification cannot recover malformed candidates

## Issue #673: Bound the Private-Packet Validation Contract

Status: complete; merged in PR #848

Goal:
- give the private issue-packet contract a documented focused deadline
- isolate its quota, backup, postmortem, ledger, and obligation fixture state
- prove timeout cleanup reaches a nested child and grandchild

Verified current state:
- issue #671 already gave every ordinary validator check a 240-second bound,
  structured timing evidence, and recursive TERM/KILL cleanup
- this contract still lacks its requested tighter budget and explicit minimal
  environment, while the process-tree test covers only one spawned level

Validation:
- run the private-packet contract through a dedicated 90-second bounded check
- assert the focused fixture sees only validator-owned state roots
- simulate a hanging child/grandchild tree and prove both are terminated

## Issue #672: Preserve Prompt-Pass Coverage Failures

Status: complete; merged in PR #847

Goal:
- preserve the original coverage-gate return status in the production path
- force `BLOCKED` for incomplete or unavailable all-pass evidence
- test the production enforcement helper rather than a duplicated shell sketch

Verified defect:
- the runtime captured `$?` inside an `if ! gate; then` branch, where Bash had
  already replaced the gate's `2`/`3` status with the negated status `0`
- the existing validator reproduced the intended logic separately and therefore
  passed without exercising the defective runtime block

Validation:
- complete P1-P23 evidence preserves the original status and source
- incomplete evidence overrides to `BLOCKED` and logs gate status 2
- unavailable analysis overrides to `BLOCKED` and logs gate status 3

## Issue #671: Bounded Lattice Validation

Status: complete; merged in PR #846

Goal:
- make every validator check and delegated test independently bounded
- give expensive direct Lattice probes their own command-level deadline
- retain exact phase, command, timeout, and cleanup evidence on timeout

Verified current state:
- suite runners now bound whole test files and full-mode integration groups
- direct `validate_upkeeper.sh --quick` checks still use a zero timeout
- delegated validator tests do not announce or record their exact command
- the in-process Lattice harness has read deadlines, but does not retain a
  structured timeout artifact; one direct max-cover pipe has no local deadline

Validation:
- simulate a wedged Lattice command and assert bounded exit plus JSONL custody
- exercise validator timeout output/artifact fields and process-tree cleanup
- keep the existing Lattice CLI, wrapper, evidence, and full validator green

## Issue #670: Atomic Automation Obligation Claims

Status: complete; merged in PR #845

Goal:
- atomically reserve an open obligation before launcher/backend work
- make claims independently enforceable from outer checkout ownership
- recover dead or PID-reused owners without stealing live work

Verified defect:
- production launchers selected an `open/*.json` record without any obligation-
  layer reservation, so a shared obligation root could hand the same work to
  multiple launch contexts

Constraints:
- preserve the compatible open/resolved record layout
- publish private, durable `O_EXCL` sidecars containing token, root, owner PID,
  process start ticks, launcher, cycle/run, and timestamp evidence
- blocked/failed attempts release back to open; verified resolution removes the
  claim only after resolved custody is published
- dry runs release immediately; active claims stop fresh work

Validation:
- two concurrent selectors racing one record produce exactly one winner
- blocked attempt release, wrong-token resolution rejection, valid resolution
  release, and dead-owner recovery are deterministic
- existing FlameOn, ChimneySweep, backlog, and obligation-resolution contracts
  remain covered

## Issue #669: Stable Repeatable Obligation Identity

Status: complete; merged in PR #844

Goal:
- make wrapper/control-plane failure obligations stable by failure class,
  reason, scope, target, and repair target instead of by cycle/run
- retain each source cycle and run as bounded occurrence evidence
- make created versus updated-existing publication visible to operators

Verified defect:
- only five hardcoded terminal reasons used stable identities
- all other repeatable failures included cycle and run identity in the record id,
  producing duplicate open records until later reconciliation

Constraints:
- per-run identity is exception-only; no current terminal reason requires it
- repository boundaries remain enforced, including for a shared custom root
- distinct reasons, targets, scopes, and repair targets must not coalesce
- legacy duplicate reconciliation remains unchanged as a safety net

Validation:
- separate cycle ids and run hashes for the same BLOCKED target update one open
  record, increment its count, and preserve first/latest occurrence evidence
- distinct target and reason fixtures retain separate records
- operator logs distinguish `created` from `updated_existing`

## Issue #668: Registry-Derived Lattice Planned Passes

Status: complete; merged in PR #843

Goal:
- derive pass-result planned coverage from the active Python pass registry
- remove the separate Bash base-pass list and P24-P30 case mapping
- keep reserved, unwired P31 outside planned coverage

Verified defect:
- `lattice_planned_passes_csv` duplicated the active base and review-module
  passes even though `PASS_REGISTRY` already owned that metadata
- adding or retiring a pass could therefore leave run evidence with stale
  planned coverage while the registry and prompt wiring appeared valid

Constraints:
- preserve the exact existing default and all-pass projections
- append only active registered module passes selected for the cycle
- reject unknown, inactive, base, and reserved module requests
- do not run a nested warm-service command in a command-substitution subshell

Validation:
- focused CLI and Bash-wrapper tests cover default, all, P24/P30, and rejected
  P31 projections
- embedded behavior validation compares both projections directly with the
  authoritative registry and rejects any restored Bash case mapping

## Issue #667: Proof-Bound Automation Obligation Resolution

Status: complete; merged in PR #842

Goal:
- prevent a zero-exit no-op, wrong-target run, or unrelated successful review
  from retiring the selected automation obligation
- bind resolution to the obligation id, selected repair target, and canonical
  required-resolution digest
- retain inspectable proof in the resolved record

Verified defect:
- the resolver checked only selected obligation id, exit zero, and non-dry-run
  reason before moving the open record to resolved custody
- the stored `required_resolution`, final response, selected target, and actual
  target delta were not consulted

Constraints:
- repaired classification requires an independently observed in-cycle target
  content change plus explicit final-response evidence
- obsolete classification requires explicit evidence and an unchanged target
- absent, malformed, duplicated, mismatched, placeholder, or blocked proof must
  preserve the open record
- no live backend Codex validation

Validation:
- deterministic tests cover proved repair, zero-exit missing proof, asserted
  repair without a change, wrong-target success, blocked review, and explicit
  obsolete classification
- resolved records retain classification, evidence, required-resolution digest,
  target before/after state, and final-response digest

## Issue #666: Fail-Closed Lattice for Backlog Mutation

Status: complete; merged in PR #841

Goal:
- require a healthy Lattice before backlog issue, newest-file, or obligation
  repair can contact the backend and mutate source
- preserve the advisory default for direct operator-driven Upkeeper runs
- provide a narrow, explicit, operator-visible degraded backlog override

Audit result:
- FlameOn and ChimneySweep already force Lattice enabled and required through
  the shared full-burn profile
- backlog sets its own mutation environment around plain `./Upkeeper` and did
  not override the advisory default for issue or obligation repair

Constraints:
- never allow disabling Lattice to bypass the required backlog gate
- keep existing required-mode init, doctor, unsafe-path, and timeout custody
- degraded operation must be an explicit one-cycle choice with replacement
  evidence logged before backend work
- no live backend Codex validation

Validation:
- backlog issue and obligation repair export enabled/required Lattice
- explicit degraded override exports enabled/advisory Lattice and logs custody
- existing plain-wrapper validation retains the advisory default
- FlameOn and ChimneySweep required-mode tests remain green

## Issue #665: Terminal Evidence Before Lattice Finish

Status: complete; merged in PR #840

Goal:
- publish canonical `cycle.exit` evidence before Lattice hashes the log artifact
- preserve automation-ledger ordering ahead of Lattice finish recording
- retain terminal evidence even when Lattice persistence fails

Verified defect:
- `finish_cycle` called both finish ledgers before `log_line`, while Lattice
  received `--log-path "$LOG_FILE"` during its write
- the Lattice artifact observation could therefore predate the terminal line it
  was meant to anchor

Constraints:
- pass identical exit code, reason, level, and status to both ledgers
- do not make Lattice success a prerequisite for cleanup or wrapper exit
- no live backend Codex validation

Validation:
- successful and failing Lattice mocks both observe `cycle.exit` before they run
- traces prove `cycle.exit`, automation finish, then Lattice finish ordering
- focused retry test, complete unit suite, and quick/full repository validation

## Issue #662: Anomaly Custody Publication Integrity

Status: complete; merged in PR #839

Goal:
- make every anomaly-custody JSON promotion atomic and crash-durable
- prevent corrupt or foreign-root obligation records from being overwritten or
  updated when their IDs collide with current-root evidence
- make promoted, skipped, corrupt, duplicate, and foreign-root outcomes
  operator-visible

Audit result:
- publication used atomic rename but did not fsync file contents or the parent
  directory and did not serialize concurrent read/modify/write publishers
- malformed records were silently ignored and could be replaced under the same
  filename
- fingerprint IDs were repository-independent, while existing-record matching
  did not enforce record root, so one checkout could suppress or mutate another

Constraints:
- preserve corrupt and foreign-root evidence byte-for-byte
- retain stable legacy IDs when they are unoccupied or already owned by the
  current root; scope only real collisions
- no live backend Codex validation

Validation:
- concurrent publishers retain every occurrence update and expose only complete
  JSON
- colliding corrupt and foreign-root records remain unchanged while current-root
  evidence is promoted beside them
- operator and latest-audit records distinguish all requested disposition states
- Python compile, quick/full validator, complete unit suite, and public docs

## Issue #661: Canonical Lattice JSONL Import Identity

Status: complete; merged in PR #838

Goal:
- prevent missing-primary-key JSONL rows from sharing `table:None` identity
- validate declared logical keys against canonical payload identity
- distinguish malformed/skipped rows from true stored-data conflicts in import
  summaries

Audit result:
- current export sanitization/redaction retains every table primary key, so
  normal exports do not currently generate `table:None`
- externally sanitized or edited JSONL can omit the primary key, and import
  previously trusted its declared logical key while allowing an auto-generated
  database identity

Constraints:
- fail closed rather than inventing a replacement database primary key
- retain unique, explainable evidence for every rejected missing-PK row
- preserve the existing aggregate `conflicts` gate and exit behavior
- no live backend Codex validation

Validation:
- normal exports retain their PK and canonical `table:<pk>` logical key
- two distinct missing-PK rows are skipped, not inserted, and receive distinct
  `table:sha256:<payload-hash>` conflict keys
- summaries report skipped rows separately from actual existing-row conflicts
- focused Lattice suite, complete unit suite, and quick/full validation

## Issue #660: Bounded Recent-Log Reads

Status: complete; merged in PR #837

Goal:
- keep stopped-loop triage memory independent of total loop-log size
- keep quota delta projection work independent of total `Upkeeper.log` size
- preserve the newest relevant event and existing missing/unreadable fallback
  behavior

Constraints:
- cap both reads by bytes, not only by output line count
- discard a potentially partial first line when a read begins mid-file
- retain triage's `--lines` cap after the byte-tail read
- retain quota's deterministic default when no usable recent summary exists
- no live backend Codex validation

Validation:
- a multi-megabyte triage log still finds the latest pending-check marker
- a multi-megabyte quota log still selects the latest valid model summary and
  its exact primary/secondary deltas
- static contracts require both byte-cap constants
- focused regression, complete unit suite, and quick/full validation

## Issue #659: Safe Active-Lock Fallback Token FD Close

Status: complete; merged in PR #836

Goal:
- remove shell evaluation from the active-lock fallback token descriptor close
- accept only numeric descriptor values at the close boundary
- preserve token-based lock inheritance for descriptor and direct-env inputs

Constraints:
- do not interpret nonnumeric environment text as shell syntax
- close a valid inherited descriptor after its token has been consumed
- ignore empty or invalid descriptors when a direct inherited token is valid
- no live backend Codex validation

Validation:
- the existing numeric descriptor inheritance path still succeeds and closes
  the descriptor
- direct token inheritance succeeds with empty and malicious-looking descriptor
  values while leaving an unrelated descriptor open
- the malicious-looking value cannot create its sentinel side effect
- focused regression, complete unit suite, and quick/full validation

## Issue #658: Backlog Owner PID-Reuse Detection

Status: complete; merged in PR #835

Goal:
- distinguish the recorded backlog owner from an unrelated process that reused
  its PID
- report dead and recycled owner records explicitly while allowing safe restart
- retain conservative compatibility for owner records created before process
  start ticks were recorded

Constraints:
- parse `/proc/<pid>/stat` without assuming the process name contains no spaces
- treat unreadable or malformed fingerprints as live when the PID still exists
- preserve all later lock, dirty-worktree, obligation, and CI safety gates
- no live backend Codex validation

Validation:
- matching PID/start ticks waits for the live owner
- a current PID with different start ticks is reported as recycled and stale
- a dead PID is reported as stale, and a legacy record keeps PID-only behavior
- focused triage test, complete unit suite, and quick/full repository validation

## Issue #657: Repository-Scoped Parallel Worker Leases

Status: complete; merged in PR #834

Goal:
- scope lease renewal, issue conflicts, target conflicts, and release to one
  normalized repository root
- allow unrelated repositories to share the global per-user registry safely
- preserve corrupt registry evidence and fail closed

Constraints:
- retain global conflict behavior for legacy records with no usable root
- do not rewrite decode-corrupt or structurally invalid registry files
- expose stable reason codes without leaking registry contents
- no live backend Codex validation

Validation:
- same worker/issue in two roots creates distinct leases without overwriting
- same-root issue conflicts and root-scoped release remain enforced
- decode-corrupt and valid-JSON/wrong-shape registries return blocked status and
  remain byte-for-byte unchanged
- focused lease test, complete unit suite, and quick/full repository validation

## Issue #656: Rotation-Safe Quota Session Enumeration

Status: complete; merged in PR #833

Goal:
- keep quota evaluation alive when Codex rotates a session during enumeration
- continue with remaining readable snapshots
- fail closed with structured evidence when no reliable snapshot survives

Constraints:
- guard each candidate `stat` and the directory walk against `OSError`
- preserve deterministic mtime/path ordering for surviving candidates
- never expose filesystem exception details or session paths in structured errors
- no live backend Codex validation

Validation:
- a dangling session JSONL candidate simulates rotation during enumeration
- a readable sibling still supplies quota evidence and reports the skipped count
- an all-rotated fixture returns `session_scan_failed` without a traceback
- complete unit suite and quick/full repository validation

## Issue #655: Quota Snapshot Instant Ordering

Status: complete; merged in PR #832

Goal:
- select the newest quota snapshot by chronological instant across ISO-8601
  offset representations
- keep malformed timestamp handling deterministic and non-crashing
- preserve operator-readable timestamp and freshness evidence

Constraints:
- reuse the existing timestamp parser used by freshness annotation
- fall back to source-file mtime only when an event timestamp is unparseable
- retain stable tie breakers for reproducible selection
- no live backend Codex validation

Validation:
- mixed `Z`, `+00:00`, and nonzero-offset fixtures where lexical order differs
  from chronological order
- malformed timestamp fixtures with deliberately ordered source mtimes
- complete unit suite and quick/full repository validation

## Issue #654: Crash-Durable Lattice Backup Publication

Status: complete; merged in PR #831

Goal:
- make a reported Lattice backup contingent on durable final-name publication
- cover both overwrite and no-overwrite backup modes
- surface directory durability failures as operator-visible command failures

Constraints:
- fsync the final backup's parent directory after publication and permission setup
- fail closed with the existing database-unavailable exit contract on open or
  fsync failure
- retain the published artifact when a post-publication sync fails so recovery
  evidence is not destructively discarded
- no live backend Codex validation

Validation:
- full-doctor regression observes a directory fsync in both publication modes
- injected directory-fsync failure must return the database-unavailable code,
  preserve the published artifact, and leave no temporary backup
- focused Lattice suite and quick/full repository validation

## Issue #653: Crash-Durable Atomic Pre-Contact Backup Publication

Status: complete; merged in PR #830

Goal:
- publish each backup payload and sidecar as one discoverable unit
- make reported success contingent on durable file and directory metadata
- preserve restore and retention compatibility with legacy flat backup pairs

Constraints:
- fsync both staged files and the staged directory before publication
- atomically rename the complete staging directory into place
- fsync the parent directory after publication and fail closed on any error
- never expose an incomplete pair as a valid backup id
- no live backend Codex validation

Validation:
- plain and age backup-id directory layout assertions
- incomplete-pair rejection, orphan-payload invisibility, and missing-artifact
  restore evidence
- explicit file/staged-directory/rename/parent-directory ordering contract
- complete unit suite and quick/full repository validation

## Issue #692: Fd-Safe Standalone Restore Installation

Status: complete; merged in PR #829

Goal:
- install standalone restores through verified directory descriptors
- reject parent swaps and symlinks across destination creation and publication
- align root and standalone restore paths on the same nofollow primitive

Constraints:
- walk and recheck parent components with `O_NOFOLLOW`
- publish with `os.replace(..., dst_dir_fd=...)`
- apply recorded mode through a nofollow file descriptor
- never fall back to path-based `mkdir`, `mv`, or `chmod`
- no live backend Codex validation

Validation:
- deterministic parent-symlink swap after hashing and before installation
- outside-target no-mutation assertion and recorded-mode preservation
- complete unit suite and quick/full repository validation

## Issue #691: Bind Standalone Restore to Repository Identity

Status: complete; merged in PR #828

Goal:
- reject a standalone pre-contact restore when its metadata belongs to another
  repository
- keep the existing explicit unsafe-restore override for deliberate recovery
- align the reusable library path with the guarded root entrypoint behavior

Constraints:
- validate both repository identity fields before selecting or installing the
  restore destination
- leave a rejected destination byte-for-byte unchanged
- preserve the stable `restore_repo_identity_mismatch` failure reason
- no live backend Codex validation

Validation:
- focused cross-repository reject, no-mutation, and explicit-override regression
- complete unit suite and quick/full repository validation

## Issue #690: Preserve Known File Identity in Lattice Snapshots

Status: complete; merged in PR #827

Goal:
- retain an existing `files.file_id` on HMAC-only worktree snapshot rows
- attribute changed and deleted delta events to the known file lineage
- preserve the path privacy boundary for both known and unknown dirty paths

Constraints:
- never insert raw snapshot path identities merely to obtain a file id
- keep snapshot `path`, `path_hmac`, and rename fields HMAC-only
- leave previously unknown paths unlinked from `files` and `file_paths`
- no live backend Codex validation

Validation:
- internal full-doctor probe for known modified-file snapshot and changed event
- focused real-CLI deleted-file state and opaque foreign-key regression
- complete six-group Lattice runner and unit suite
- quick and full repository validation

## Issue #664: Retryable Lattice Finish Persistence

Status: complete; merged in PR #826

Goal:
- set the finish-recorded guard only after successful Lattice persistence
- retry one transient finish failure inside the terminal cycle boundary
- retain exact private replay custody if both bounded writes fail

Constraints:
- never duplicate a successful finish write
- keep failed or spooled finish state distinguishable from persisted state
- atomically publish private retry payloads beneath ignored runtime state
- report initial persistence, retry persistence, spooling, and spool failure
- no live backend Codex validation

Validation:
- injected first-failure/second-success retry and duplicate suppression
- persistent two-write failure, payload schema/privacy, and later-spool cleanup
- complete six-group Lattice runner and unit suite
- quick and full repository validation

## Issue #663: Bounded Lattice Commands and Max-Cover Selection

Status: complete; merged in PR #825

Goal:
- bound every wrapper-issued warm-service and direct-CLI Lattice command
- make startup and max-cover timeouts deterministic without backend contact
- retain structured timeout, cleanup, degraded-mode, and obligation evidence

Constraints:
- optional Lattice failures may continue only with local recovery evidence
- required Lattice timeouts fail closed as `LATTICE_TIMEOUT`
- max-cover may fall back only to the oldest current source-safe text candidate
- terminate the complete local command process tree after a short TERM grace
- no live backend Codex validation

Validation:
- focused warm-service, direct-CLI, optional, required, max-cover, and cleanup
  regression
- complete five-group Lattice runner and unit suite
- quick and full repository validation

## Issue #712: Import-Once Lattice Test Harness

Status: complete; merged in PR #824

Goal:
- stop serializing the broad Lattice regression surface through repeated core
  imports and one monolithic Bash test
- keep representative executable, parser, stream, and failure-exit smoke tests
  while routing ordinary command assertions through one imported core process
- separate independent full-CLI, wrapper-policy, core-ledger, and
  evidence/recovery scenarios so the standard runner can execute them in
  parallel

Constraints:
- preserve every existing assertion and separate stdout/stderr behavior
- retain real subprocess coverage for environment-sensitive and broken-pipe
  cases
- hard-bound the deliberately slower full-CLI and wrapper integration groups
- no live backend Codex validation

Validation:
- focused four-group runner and complete unit suite
- quick and full repository validation
- before/after standalone and parallel wall-clock measurements

Measured local result:
- monolithic sequential baseline: 29.329s
- core `tests/lattice_test.bash`: 3.743s
- all four groups in parallel: 11.826s wall time
- complete 51-test shared runner: 20.437s wall time, with the core Lattice group
  at 5.829s under concurrent load (the prior 48-test run took 51.920s)
- explicit slow groups: CLI/full-doctor 11.826s with a 45s inner bound;
  wrapper policy 8.479s with a 30s inner bound
- evidence/recovery group: 5.198s with a 30s inner bound

## Issue #702: Bounded Lattice Startup Doctor

Status: complete; merged in PR #823

Goal:
- keep ordinary wrapper startup bounded as the append-only Lattice DB grows
- use a startup-specific liveness/schema doctor that avoids database-wide
  integrity scans and the full internal self-test surface
- retain the existing plain `doctor` command as the explicit full integrity
  and maintenance boundary

Constraints:
- preserve full-doctor behavior, exit codes, and backup behavior
- fail startup on unavailable, unwritable, or schema-incompatible databases
- make the selected doctor mode explicit in JSON and readiness logs
- do not add an automatic full-doctor cadence without a separately specified
  scheduling and failure-custody policy
- no live backend Codex validation

Validation:
- focused fast/full mode regression, including an injected foreign-key orphan
- growing synthetic database timing that compares fast and explicit full modes
- complete Lattice, unit, quick, and full validation

Measured local result:
- fast startup doctor averaged 0.0921s on an empty DB and 0.0834s after 50,000
  rows, while the explicit full doctor took 2.8712s on the populated DB

## Issue #700: Import-Cacheable Lattice CLI

Status: complete; merged in PR #822

Goal:
- keep `tools/upkeeper_lattice.py` as the stable executable and import surface
- move the large implementation into an import-cacheable module so repeated
  direct CLI and validation invocations reuse bytecode
- retain the existing warm per-cycle Lattice service and CLI behavior

Constraints:
- preserve every command, exit code, and direct-import contract
- keep Lattice paths classified as high-risk and under focused validation
- no live backend Codex validation

Validation:
- deterministic core-bytecode creation and reuse regression
- direct CLI/import compatibility and focused Lattice suite
- complete unit, quick, and full validation
- before/after direct CLI and `tests/lattice_test.bash` timings

Measured local result:
- repeated direct CLI startup fell from 0.157s on the monolithic script to
  0.072s through a warm core bytecode cache
- standalone `tests/lattice_test.bash` passed in 31.421s
- the eight-way unit run passed all 47 tests and reduced the Lattice test from
  the final pre-change 84.646s sample to 47.362s under concurrent load

## Issue #713: Same-Checkout Test Attestation Reuse

Status: complete; merged in PR #821

Goal:
- stop the sequential CI full-validator phase from rerunning test scripts that
  already passed in the same checkout and environment
- bind reuse to Git head/tree, a clean tracked tree, environment class, exact
  test path and content hash, and passing status
- preserve standalone full validation by rerunning whenever evidence is absent
  or mismatched

Constraints:
- fail closed on stale, dirty, malformed, cross-environment, or changed-test
  evidence
- keep attestations in runner-local ignored/transient storage
- no live backend Codex validation

Validation:
- focused attestation acceptance/rejection test, including dirty-tree and
  cross-environment rejection
- complete 46-test unit suite and clean-tree attestation production
- quick and full validators with a valid attestation; absent or rejected
  evidence retains the existing rerun path
- GitHub CI comparison against PR #820's retained timing artifact

Measured local result:
- quick and full validation accepted the same clean-tree 46-test attestation
  and logged each reused test explicitly
- full validation passed; `file_manifest_selection` remained the dominant
  integration check at 360.919s despite reusing its three eligible unit tests
- issue #714 was separately closed as stale: the current focused Lattice
  contract no longer reruns `tests/lattice_test.bash`

## Issue #726: Structured Full-Validation Timing

Status: completed locally; pending PR CI

Goal:
- make the blocking full-validator path emit durable per-check timing evidence
- bind timing rows to the validator mode, Git head/tree, command, status,
  duration, timeout, and cleanup outcome
- print the slowest full-validation checks even on failure and retain the JSONL
  artifact in GitHub CI
- use current measurements, rather than the old Lattice estimate, to choose the
  next backlog throughput optimization

Constraints:
- no live backend Codex validation
- preserve the validation surface and fail-closed behavior
- keep timeout cleanup explicit and prevent descendant fixture processes from
  escaping validator custody
- keep local timing evidence ignored and uncommitted

Files likely touched:
- `.github/workflows/ci.yml`
- `tools/validation_timing_lib.bash`
- `tools/validate_upkeeper.sh`
- `tests/validation_timing_test.bash`
- validation documentation and `change_notes_2026.md`

Validation:
- `bash -n tools/validation_timing_lib.bash tools/validate_upkeeper.sh tests/validation_timing_test.bash`
- `bash tests/validation_timing_test.bash`
- `tools/run_tests.sh`
- `tools/check_public_docs.sh --quick`
- `tools/validate_upkeeper.sh --quick --profile`
- `tools/validate_upkeeper.sh --full --profile`
- `git diff --check`

Validation discovery:
- the parallel suite exposed issue #819, where the #652 reclaim guard was
  released after replacement `mkdir` but before state/marker publication
- the same patch now retains reclaim custody through complete ownership
  publication and strengthens the race fixture against early guard release

Measured full-validator result:
- `file_manifest_selection`: 350.949s
- `stress_corpus_harness`: 136.114s
- `fault_injection_first_scenarios`: 121.742s
- `backlog_autoshelve_contract`: 101.466s
- `config_file_support`: 57.196s
- complete `lattice_contract`: 4.396s
- these current measurements make manifest/integration duplication—not the
  older Lattice estimate—the next validation-throughput target

## Issue #819: Complete Active-Lock Reclaim Publication Custody

Status: completed locally; pending PR CI

Goal:
- keep the stale-reclaim guard held until replacement ownership is completely
  published
- clean up lock and guard custody on state, rename, or marker failures
- make the concurrency fixture explicitly reject pre-publication guard release

Constraints:
- preserve normal atomic first acquisition and fallback inheritance
- keep the correction within the #652 ownership model
- no live backend Codex validation

Validation:
- repeated and concurrent `tests/active_lock_reclaim_race_test.bash`
- `UPKEEPER_INTERNAL_ACTIVE_LOCK_SELF_TEST=1 ./Upkeeper`
- whole test suite and quick/full validators listed above

## Issue #652: Serialized Active-Lock Stale Reclaim

Status: completed locally; pending PR CI

Goal:
- serialize stale-lock reclamation so exactly one wrapper can replace a stale
  active-lock directory
- make losing reclaimers fail closed with explicit `reclaim_lost` evidence
- revalidate the lock instance after winning reclaim custody so a changed or
  newly live lock is never removed
- preserve fallback-child lock inheritance and normal atomic first acquisition

Constraints:
- no live backend Codex validation
- keep the change limited to active-lock ownership and deterministic fixtures
- preserve stale-lock evidence and existing unsafe-path protections

Files likely touched:
- `Upkeeper`
- `lib/upkeeper/active_lock.bash`
- `tests/active_lock_reclaim_race_test.bash`
- `tools/validate_upkeeper.sh`
- `docs/fault-injection-scenarios.md`
- `change_notes_2026.md`

Validation:
- `bash -n Upkeeper lib/upkeeper/active_lock.bash tests/active_lock_reclaim_race_test.bash tools/validate_upkeeper.sh`
- `bash tests/active_lock_reclaim_race_test.bash`
- `UPKEEPER_INTERNAL_ACTIVE_LOCK_SELF_TEST=1 ./Upkeeper`
- `tools/run_tests.sh`
- `tools/check_public_docs.sh --quick`
- `tools/validate_upkeeper.sh --quick`
- `tools/validate_upkeeper.sh --full`
- `git diff --check`

## Issue #799: Deferred Backlog PR Publication

Status: completed locally; pending PR CI

Goal:
- stop backlog runs from opening or publishing an empty GitHub PR before any
  real tracked fix exists on the branch
- keep the backlog branch local until the first publish-worthy commit is ready,
  then create the PR from that real change
- preserve branch reuse, PR-check gating after publication, and the existing
  batch merge workflow

Constraints:
- no live backend Codex validation
- keep the fix narrow to the backlog launcher and its local regression tests
- preserve the current batch-merging and issue-selection contract once a PR has
  been published

Files likely touched:
- `orchestration/backlog.sh`
- `tests/*.bash`
- `docs/scripts/upkeeper.md`
- `README.md`
- `change_notes_2026.md`

Validation:
- `bash -n Upkeeper lib/upkeeper/*.bash tools/*.sh tests/*.bash testruns/*.sh Upkeeper.conf configurations/default.conf`
- focused backlog launcher regression test(s)
- `tools/run_tests.sh`
- `tools/check_public_docs.sh --quick`
- `tools/validate_upkeeper.sh --quick`
- `tools/validate_upkeeper.sh --smoke`
- `git diff --check`

## Issues #732-#733: Prompt Compilation And Selection Batch

Status: completed locally; pending PR CI

Goal:
- fix the two completed queue items, #732 and #733
- collapse prompt compilation's tiny Python subprocess chain into a more
  efficient emitter path without changing the emitted issue-fix packet contract
- remove duplicate candidate-selection logic where help text and Lattice keep
  the same policy in separate places
- keep ownership boundaries visible if the oversized main/phase functions need
  to be split for maintainability

Constraints:
- no live backend Codex validation
- preserve existing prompt packet shape, candidate selection semantics, and
  operator-visible help text
- keep each bug fix focused enough to validate independently

Files likely touched:
- `lib/upkeeper/prompt_compile.bash`
- `lib/upkeeper/help_selection.bash`
- `tools/upkeeper_lib/*`
- `tests/*.bash`
- `docs/scripts/upkeeper.md`
- `change_notes_2026.md`
- `tools/validate_upkeeper.sh`

Validation:
- `bash -n Upkeeper lib/upkeeper/*.bash tools/*.sh tests/*.bash testruns/*.sh Upkeeper.conf configurations/default.conf`
- focused prompt-compilation tests and candidate-selection tests
- `tools/run_tests.sh`
- `tools/check_public_docs.sh --quick` when docs/help change
- `tools/validate_upkeeper.sh --quick`
- `git diff --check`

## Issues #720-#721: Backlog Effort Sizing And Hot-Path Batch

Status: completed locally; pending PR CI

Goal:
- complete the two implemented queue items, #720 and #721, with one focused
  fix per issue
- reduce the backlog launcher's blanket `xhigh` default by selecting effort
  tier from deterministic issue/task context before `prepare_backlog_runtime_env`
  exports model settings
- keep the selection fail-closed for high-risk wrapper, recovery, lattice,
  quota, fallback, restore, security, and data-integrity work
- extend the docs-only CI fast path into a broader low-risk lane for
  mechanical config, shell, test, and tool changes so those changes can skip
  the full validator while still running the shared local gates

Constraints:
- no live backend Codex validation
- preserve existing issue selection, validation authority, and PR-check flow
- keep operator overrides explicit and documented
- keep per-issue changes narrow enough that each can be validated and pushed
  before the next open bug is started

Files likely touched:
- `orchestration/backlog.sh`
- `lib/upkeeper/change_scope.bash`
- `.github/workflows/ci.yml`
- `tools/docs_only_fast_path.sh`
- `lib/upkeeper/help_selection.bash`
- `docs/scripts/upkeeper.md`
- `tests/*.bash`
- `change_notes_2026.md`
- `README.md`
- `docs/dependencies.md`
- `docs/release-checklist.md`
- `lib/upkeeper/README.md`
- `tools/validate_upkeeper.sh`

Validation:
- `bash -n Upkeeper ChimneySweep FlameOn lib/upkeeper/*.bash tools/*.sh tests/*.bash testruns/*.sh Upkeeper.conf configurations/default.conf orchestration/backlog.sh orchestration/backlog_loop.sh`
- focused backlog effort-sizer tests
- `tools/run_tests.sh`
- `tools/check_public_docs.sh --quick` when docs/help change
- `tools/validate_upkeeper.sh --quick`
- `git diff --check`

## ChimneySweep Combined Default Alignment

Status: completed locally; pending PR CI after push

Goal:
- align ChimneySweep tests, help, docs, completion, and release notes with the
  current combined single-invocation issue-fix default on PR #801
- preserve explicit staged `comment -> review -> apply` coverage through
  `--cycle-mode=separate` and legacy `--workflow=...`
- clear the PR #801 local-validation blocker without launching backend Codex

Constraints:
- no live backend Codex validation
- keep comment/review source-read-only and Genie Protocol documentation clear
  for explicit staged runs
- keep default combined behavior and legacy staged behavior both deterministic
  in local tests

Files likely touched:
- `ChimneySweep`
- `completions/upkeeper.bash`
- `tests/chimneysweep_test.bash`
- README and operator docs covering ChimneySweep
- `tools/check_public_docs.sh`
- `change_notes_2026.md`

Validation:
- `bash -n Upkeeper ChimneySweep FlameOn lib/upkeeper/*.bash tools/*.sh tests/*.bash testruns/*.sh Upkeeper.conf configurations/default.conf orchestration/backlog.sh orchestration/backlog_loop.sh`
- `bash tests/chimneysweep_test.bash`
- `tools/run_validation_phases.sh --phases shell_syntax,unit_tests,public_docs,diff_whitespace`
- `tools/validate_upkeeper.sh --quick`
- `git diff --check`

## Issues #739-#735: Validator Architecture And Contract Batch

Status: completed locally; pending PR/CI on `backlog/20260601-validator-architecture-contracts`

Goal:
- close the next five high-priority time-savings bugs by removing nested
  full-test execution from validator checks, moving tool-failure queue custody
  into its owning module, making inline Python debt measurable with an
  extracted importable helper surface, adding Lattice selection performance
  telemetry, and replacing representative grep walls with manifest-backed
  contract checks
- keep all changes deterministic and local; do not launch backend Codex
- preserve standalone tests and existing operator-visible queue behavior

Constraints:
- no live backend Codex validation
- keep queue marker privacy, signing, and target validation fail-closed
- keep new architecture/performance checks report-oriented where existing debt
  is still being ratcheted down
- migrate contracts incrementally without weakening current public-doc checks

Files likely touched:
- `Upkeeper`
- `lib/upkeeper/runtime_foundation.bash`
- `lib/upkeeper/tool_failure_queue.bash`
- `tools/upkeeper_lib/`
- `tools/validate_upkeeper.sh`
- `tools/check_public_docs.sh`
- new contract/performance tooling and focused tests
- docs, release notes, and architecture allowlists as needed

Validation:
- focused helper tests for issue-fix private packet, Lattice contract,
  architecture lint, contract manifests, queue custody, and Lattice profile
- `python3 -m py_compile tools/*.py tools/upkeeper_lib/*.py`
- `bash -n Upkeeper ChimneySweep FlameOn lib/upkeeper/*.bash tools/*.sh tests/*.bash testruns/*.sh Upkeeper.conf configurations/default.conf orchestration/backlog.sh orchestration/backlog_loop.sh`
- `tools/check_public_docs.sh --quick`
- `tools/validate_upkeeper.sh --quick`
- `tools/run_tests.sh`
- `git diff --check`

## Issues #744-#740: Prompt Scope And Architecture Guard Batch

Status: completed locally; pending PR/CI on `backlog/20260601-prompt-scope-architecture`

Goal:
- close the next five high-priority time-savings bugs by making prompt-pass
  work proportional to task risk, measuring and slimming prompt payloads,
  downshifting recovery model fan-out defaults, retiring the `compile_prompt`
  wrapper override, and adding architecture lint coverage for ownership and
  hot-loop regressions
- preserve full-strength all-pass/full-doctrine behavior for explicit
  operator requests and high-risk files
- keep all fixes deterministic and local; do not launch backend Codex

Constraints:
- no live backend Codex validation
- preserve selected-target and log-review safety contracts while moving prompt
  behavior into module-owned code
- make compatibility knobs visible in config, help/docs, release notes, and
  quick validation

Files likely touched:
- `Upkeeper`
- `Upkeeper.conf`
- `configurations/default.conf`
- `lib/upkeeper/codex_io.bash`
- `lib/upkeeper/prompt_compile.bash`
- `lib/upkeeper/fallback_orchestration.bash`
- `lib/upkeeper/fallback_screen.bash`
- `tools/validate_upkeeper.sh`
- new architecture lint tooling and focused tests
- docs, help mirror, README/release notes as needed

Validation:
- `bash -n Upkeeper ChimneySweep FlameOn lib/upkeeper/*.bash tools/*.sh tests/*.bash testruns/*.sh Upkeeper.conf configurations/default.conf orchestration/backlog.sh orchestration/backlog_loop.sh`
- focused task profile, fallback prompt-pass, prompt payload, and architecture
  lint tests
- `tools/check_public_docs.sh --quick`
- `tools/validate_upkeeper.sh --quick`
- `tools/run_tests.sh`
- `git diff --check`

## Issues #749-#745: Task Budget And Parallel Validation Batch

Status: completed locally; pending PR/CI on `backlog/20260531-222954`

Goal:
- close the next five high-priority time-savings bugs by adding a deterministic
  task-size profile, model-contact budgets, Codex execution timeouts, and
  parallel validation/test execution
- keep full-strength behavior available for high-risk or explicitly overridden
  runs while giving routine work cheaper defaults
- make validation phase timing and test timing visible enough to catch future
  wall-clock regressions

Constraints:
- no backend Codex validation
- preserve serial test execution as a debugging fallback
- keep model-contact budget enforcement configurable and evidence-producing
- keep docs/help/release notes aligned for operator-visible knobs

Files likely touched:
- `Upkeeper`
- `Upkeeper.conf`
- `configurations/default.conf`
- `lib/upkeeper/codex_io.bash`
- `lib/upkeeper/prompt_compile.bash`
- `orchestration/backlog.sh`
- `.github/workflows/ci.yml`
- `tools/run_tests.sh`
- `tools/run_validation_phases.sh`
- `tools/validate_upkeeper.sh`
- `tests/`
- docs, release notes, and focused validator contracts

Validation:
- `bash -n Upkeeper ChimneySweep FlameOn lib/upkeeper/*.bash tools/*.sh tests/*.bash testruns/*.sh Upkeeper.conf configurations/default.conf orchestration/backlog.sh orchestration/backlog_loop.sh`
- focused model timeout/contact-budget tests
- `tools/run_tests.sh`
- `tools/run_validation_phases.sh`
- `tools/check_public_docs.sh --quick`
- `git diff --check`
- `tools/validate_upkeeper.sh --quick`

## Issues #754-#750: High-Priority Time-Savings Batch

Status: completed locally; pending PR/CI

Goal:
- close the next five high-priority time-savings bugs by reducing idle waits,
  duplicate CI blocking, FlameOn preamble parsing, and repeated Lattice process
  startup
- keep the fixes deterministic and local; do not launch backend Codex
- preserve fail-closed validation and merge behavior for high-risk paths

Constraints:
- no backend Codex validation
- keep compatibility defaults visible and documented
- avoid broad refactors beyond the five targeted bugs

Files likely touched:
- `orchestration/backlog_loop.sh`
- `orchestration/backlog.sh`
- `FlameOn`
- `lib/upkeeper/automation_obligations.bash`
- `lib/upkeeper/launcher_full_burn.bash`
- `lib/upkeeper/lattice.bash`
- `lib/upkeeper/cycle_cleanup_signals.bash`
- `tools/upkeeper_lattice.py`
- docs, release notes, focused tests, and validator contracts

Validation:
- `python3 -m py_compile tools/upkeeper_lattice.py`
- `bash tests/flameon_test.bash`
- focused backlog/Lattice service tests through `tools/validate_upkeeper.sh --quick`
- `bash -n Upkeeper ChimneySweep FlameOn lib/upkeeper/*.bash tools/*.sh tests/*.bash testruns/*.sh Upkeeper.conf configurations/default.conf orchestration/backlog.sh orchestration/backlog_loop.sh`
- `tools/check_public_docs.sh --quick`
- `tools/validate_upkeeper.sh --quick`
- `set -e; for test_script in tests/*.bash; do bash "$test_script"; done`
- `git diff --check`

## Run BOM And Stable Identifier Namespace

Status: completed locally; pending PR/CI

Goal:
- close issue #218 by defining a public run bill-of-materials contract and
  stable local Upkeeper identifier namespace
- make the namespace privacy-safe by default so future tools can reference
  cycles, runs, targets, prompts, backups, artifacts, and validations without
  scraping raw logs or exposing local paths
- add validation so the docs and compatibility surfaces do not drift silently

Constraints:
- no backend Codex validation
- define the schema and namespace first; do not build a runtime exporter in
  this slice
- keep Lattice and local runtime evidence supporting rather than authoritative

Files likely touched:
- `docs/run-bom-identifiers.md`
- README, compatibility, Lattice, preservation, roadmap, release notes
- `tools/validate_upkeeper.sh`

Validation:
- `bash -n Upkeeper ChimneySweep FlameOn lib/upkeeper/*.bash tools/*.sh tests/*.bash testruns/*.sh Upkeeper.conf configurations/default.conf orchestration/backlog.sh`
- `tools/check_public_docs.sh --quick`
- `tools/validate_upkeeper.sh --smoke`
- `tools/validate_upkeeper.sh --quick`
- `set -e; for test_script in tests/*.bash; do bash "$test_script"; done`
- `git diff --check`

## Lattice Provenance And Evidence Packages

Status: completed; issue #219 closed

Goal:
- close issue #219 by defining a portable provenance and evidence-package
  export surface for Lattice cycles
- start with a local JSON package proposal before considering RO-Crate or
  BagIt envelopes
- keep exports local, deterministic, and privacy-safe by default

Constraints:
- no backend Codex validation
- no heavy new export dependency in the first slice
- preserve the existing JSONL export/import contract and Lattice custody rules

Files likely touched:
- `docs/decisions/0005-provenance-and-evidence-package-exports.md`
- README, Lattice, preservation, compatibility, roadmap, release notes
- `docs/decisions/README.md`
- `tools/validate_upkeeper.sh`

Validation:
- `bash -n Upkeeper ChimneySweep FlameOn lib/upkeeper/*.bash tools/*.sh tests/*.bash testruns/*.sh Upkeeper.conf configurations/default.conf orchestration/backlog.sh`
- `tools/check_public_docs.sh --quick`
- `tools/validate_upkeeper.sh --smoke`
- `tools/validate_upkeeper.sh --quick`
- `set -e; for test_script in tests/*.bash; do bash "$test_script"; done`
- `git diff --check`

## Run Taxonomy, Observability, And Cost Accounting Surface

Status: completed; issue #223 closed

Goal:
- close issue #223 by defining a local run taxonomy plus observability/cost
  accounting surface that proves the wrapper is saving time and reducing risk
- start with a local JSONL or summary export instead of a full OpenTelemetry
  dependency
- keep the taxonomy and metrics local, structured, and privacy-safe by default

Constraints:
- no backend Codex validation
- no heavyweight telemetry dependency in the first slice
- preserve the existing cycle.summary/run.finish log vocabulary and Lattice
  evidence model

Files likely touched:
- `docs/decisions/0006-run-taxonomy-observability-and-cost-accounting.md`
- README, Lattice, preservation, compatibility, roadmap, release notes
- `docs/decisions/README.md`
- `tools/validate_upkeeper.sh`

Validation:
- `bash -n Upkeeper ChimneySweep FlameOn lib/upkeeper/*.bash tools/*.sh tests/*.bash testruns/*.sh Upkeeper.conf configurations/default.conf orchestration/backlog.sh`
- `tools/check_public_docs.sh --quick`
- `tools/validate_upkeeper.sh --smoke`
- `tools/validate_upkeeper.sh --quick`
- `set -e; for test_script in tests/*.bash; do bash "$test_script"; done`
- `git diff --check`

## Adapter And Plugin Contract With Side-Effect Declarations

Status: completed; issue #225 closed

Goal:
- close issue #225 by defining a bounded adapter/plugin contract for future
  Upkeeper integrations
- require each adapter to declare inputs, outputs, side effects, network use,
  file-write scope, secret needs, Lattice events, failure modes, and
  validation expectations
- keep future integrations reviewable without turning Upkeeper into one giant
  shell brain

Constraints:
- no backend Codex validation
- no heavy plugin runtime or service in the first slice
- preserve the core wrapper's authority boundaries and local-first defaults

Files likely touched:
- `docs/decisions/0007-adapter-plugin-contract-with-side-effect-declarations.md`
- README, authority, compatibility, roadmap, release notes
- `docs/decisions/README.md`
- `tools/validate_upkeeper.sh`

Validation:
- `bash -n Upkeeper ChimneySweep FlameOn lib/upkeeper/*.bash tools/*.sh tests/*.bash testruns/*.sh Upkeeper.conf configurations/default.conf orchestration/backlog.sh`
- `tools/check_public_docs.sh --quick`
- `tools/validate_upkeeper.sh --smoke`
- `tools/validate_upkeeper.sh --quick`
- `set -e; for test_script in tests/*.bash; do bash "$test_script"; done`
- `git diff --check`

## Human Review Packet Format For Cycle Output

Status: completed; issue #226 closed

Goal:
- close issue #226 by defining a concise human review packet for each
  meaningful cycle
- start as a generated markdown or JSON summary for one cycle before wiring it
  to Lattice/export commands later
- keep the packet concise, operator-readable, and explicit about what is safe
  or unsafe to publish

Constraints:
- no backend Codex validation
- no heavy export dependency in the first slice
- preserve the separation between transcripts, internal Lattice rows, and
  operator-facing review packets

Files likely touched:
- `docs/decisions/0008-human-review-packet-format-for-cycle-output.md`
- README, preservation, compatibility, roadmap, release notes
- `docs/decisions/README.md`
- `tools/validate_upkeeper.sh`

Validation:
- `bash -n Upkeeper ChimneySweep FlameOn lib/upkeeper/*.bash tools/*.sh tests/*.bash testruns/*.sh Upkeeper.conf configurations/default.conf orchestration/backlog.sh`
- `tools/check_public_docs.sh --quick`
- `tools/validate_upkeeper.sh --smoke`
- `tools/validate_upkeeper.sh --quick`
- `set -e; for test_script in tests/*.bash; do bash "$test_script"; done`
- `git diff --check`

## Kirk Protocol Closed-Loop Auditor

Status: completed locally; pending PR/CI

Goal:
- close issue #401 by making control-plane audit findings persistent lineage
  records rather than one-cycle observations
- classify unknown audit finding classes as promotion-required until a stable
  classifier, `KP-###` invariant, and fixture exist

## Issue #650: Bug-Report-Only Stale Quota Custody Before Triage

Status: completed locally; pending PR/CI after push

Goal:
- stop direct `--max-cover --bug-report-only` stale-after-reset quota blocks
  from collapsing into a generic fallback-chain exit before target triage
- make the last-run/operator-facing reason quota-specific and leave durable
  local bug-report custody without launching backend Codex
- cover the path with deterministic local validation only

Constraints:
- no backend Codex validation
- preserve normal fallback behavior for non-reporting mutation paths unless the
  quota stop is the specific no-triage stale-snapshot case
- keep bug-report-only and audit-only source-mutation guarantees intact

Files likely touched:
- `Upkeeper`
- `lib/upkeeper/codex_io.bash`
- `lib/upkeeper/operator_status.bash`
- focused tests and validator coverage
- public docs/help/release notes if operator-visible text changes

Validation:
- `bash -n Upkeeper lib/upkeeper/*.bash tools/*.sh tests/*.bash testruns/*.sh Upkeeper.conf configurations/default.conf`
- focused bug-report/quota tests
- `tools/run_tests.sh`
- `git diff --check`
- `tools/validate_upkeeper.sh --quick`

## Issue #651: ChimneySweep Review Proposal Context And Result Mapping

Status: completed locally; pending PR/CI after push

Goal:
- make ChimneySweep `--workflow=review` consume the latest wrapper-owned
  proposal comment or fail closed before backend launch
- stop review-stage `blocked` comments from surfacing as an ambiguous clean
  `WORK_DONE` cycle result
- keep comment/review stages source-read-only while making the prompt contract
  explicit about read-only validation limits

Constraints:
- preserve the staged comment/review/apply workflow and existing issue comment
  transport through wrapper-owned draft extraction/posting
- avoid broad GitHub/private-issue exposure changes outside the wrapper-owned
  staged comment artifact
- no live backend Codex validation

Files likely touched:
- `Upkeeper`
- `lib/upkeeper/codex_io.bash`
- `lib/upkeeper/prompt_compile.bash`
- focused tests and quick-validator coverage
- operator docs and release notes if the fail-closed/result-mapping behavior is
  operator-visible

Validation:
- `bash -n Upkeeper lib/upkeeper/*.bash tools/*.sh tests/*.bash testruns/*.sh Upkeeper.conf configurations/default.conf`
- focused ChimneySweep issue-workflow contract tests
- `tools/run_tests.sh`
- `git diff --check`
- `tools/validate_upkeeper.sh --quick`
- give backlog, FlameOn, ChimneySweep, and merge stewardship the same fast
  pre-model control-plane guard without forcing backend Codex work

## Issue #722: CI Dependency Probe Instead Of Blanket Apt Install

Status: completed locally; pending PR/CI after push

Goal:
- replace the unconditional CI `apt-get install` of stock runner packages with a
  shared dependency probe that installs only missing nonstandard tools
- fail clearly when an expected `ubuntu-latest` runner command is absent rather
  than silently broad-installing around runner-image drift
- make the dependency setup contract visible in local tests, validator checks,
  and dependency docs

Constraints:
- keep CI deterministic and no-quota
- preserve age coverage for full-burn launcher dependency validation
- avoid requiring privileged package installs during local validation

Files likely touched:
- `.github/workflows/ci.yml`
- `tools/` helper and focused test coverage
- `tools/check_public_docs.sh`
- `tools/validate_upkeeper.sh`
- `docs/dependencies.md`
- `change_notes_2026.md`

Validation:
- `bash -n Upkeeper lib/upkeeper/*.bash tools/*.sh tests/*.bash testruns/*.sh Upkeeper.conf configurations/default.conf`
- `bash tests/ci_dependency_setup_test.bash`
- `tools/check_public_docs.sh --quick`
- `tools/run_tests.sh`
- `tools/validate_upkeeper.sh --quick`
- `git diff --check`

## Issue #723: Multi-Field JSON Extraction On Hot Paths

Status: completed locally; pending PR/CI after push

Goal:
- add a safe helper that extracts multiple fields from one wrapper-owned JSON
  value in one parse instead of repeated same-object `jq` calls
- replace the repeated extraction clusters called out in `Upkeeper`,
  `lib/upkeeper/codex_io.bash`, and `orchestration/backlog.sh`
- keep existing null/boolean behavior while preserving tabs/newlines safely

Constraints:
- no backend Codex validation
- avoid `eval` for assignment
- keep malformed JSON visibly fail-closed because the inputs are wrapper-owned

Files likely touched:
- `lib/upkeeper/runtime_format_json.bash`
- `Upkeeper`
- `lib/upkeeper/codex_io.bash`
- `orchestration/backlog.sh`
- focused tests and validator coverage if needed
- release notes if the helper changes hot-path behavior materially

Validation:
- `bash -n Upkeeper lib/upkeeper/*.bash tools/*.sh tests/*.bash testruns/*.sh Upkeeper.conf configurations/default.conf orchestration/backlog.sh`
- focused JSON helper and hot-path regression tests
- `tools/run_tests.sh`
- `tools/validate_upkeeper.sh --quick`
- `git diff --check`

Constraints:
- no backend Codex validation
- keep clean no-op fast and local; lineage writes must be optional and ignored
  runtime state
- reuse the existing audit and launcher rails instead of adding a parallel
  control-plane tool

Files likely touched:
- `tools/upkeeper_control_plane_audit.py`
- `lib/upkeeper/launcher_full_burn.bash`
- `FlameOn`
- `ChimneySweep`
- `orchestration/backlog.sh`
- focused tests, docs, validator contracts, and release notes

Validation:
- `python3 -m py_compile tools/upkeeper_control_plane_audit.py`
- `bash tests/control_plane_audit_test.bash`
- `bash tests/flameon_test.bash`
- `bash tests/chimneysweep_test.bash`
- `bash -n Upkeeper ChimneySweep FlameOn lib/upkeeper/*.bash tools/*.sh tests/*.bash testruns/*.sh Upkeeper.conf configurations/default.conf orchestration/backlog.sh`
- `tools/check_public_docs.sh --quick`
- `tools/validate_upkeeper.sh --quick`
- `set -e; for test_script in tests/*.bash; do bash "$test_script"; done`
- `git diff --check`

## Kirk Protocol Invariant Registry

Status: merged in PR #638

Goal:
- close issue #400 by turning the control-plane audit policy layer into stable
  `KP-###` invariants with operator-readable failure explanations
- capture before/after audit snapshots for staging, validation, and merge
  stewardship without backend work
- keep historical May 2026 anomaly classes represented as deterministic quick
  fixtures

Constraints:
- no backend Codex validation and no live issue work
- keep clean no-op snapshots local, private, and pre-model
- do not broaden auto-clean behavior beyond the explicit safe cleanup table

Files likely touched:
- `tools/upkeeper_control_plane_audit.py`
- `tests/control_plane_audit_test.bash`
- `orchestration/backlog.sh`
- `docs/kirk-invariants.md`
- `tools/validate_upkeeper.sh`
- README/operator docs and release notes

Validation:
- `python3 -m py_compile tools/upkeeper_control_plane_audit.py`
- `bash tests/control_plane_audit_test.bash`
- `bash -n Upkeeper lib/upkeeper/*.bash tools/*.sh tests/*.bash testruns/*.sh Upkeeper.conf configurations/default.conf orchestration/backlog.sh`
- `tools/check_public_docs.sh --quick`
- `tools/validate_upkeeper.sh --quick`
- `set -e; for test_script in tests/*.bash; do bash "$test_script"; done`
- `git diff --check`

## Control-Plane Audit Remediation

Status: completed locally; pending PR/CI

Goal:
- close issue #399 by adding a deterministic policy and remediation layer on
  top of the control-plane audit inventory
- clean only explicitly safe local scratch artifacts before staging, including
  literal root `$db` sidecars and Python bytecode caches
- fail closed or write automation obligations for local-evidence source
  boundary violations and unsafe root artifacts

Constraints:
- no backend Codex validation and no live issue work
- never delete or rewrite tracked source from the audit tool
- keep the clean no-op path local, fast, and pre-model

Files likely touched:
- `tools/upkeeper_control_plane_audit.py`
- `tests/control_plane_audit_test.bash`
- `orchestration/backlog.sh`
- `tools/validate_upkeeper.sh`
- README/operator docs and release notes

Validation:
- `python3 -m py_compile tools/upkeeper_control_plane_audit.py`
- `bash tests/control_plane_audit_test.bash`
- `bash -n Upkeeper lib/upkeeper/*.bash tools/*.sh tests/*.bash testruns/*.sh Upkeeper.conf configurations/default.conf orchestration/backlog.sh`
- `tools/check_public_docs.sh --quick`
- `tools/validate_upkeeper.sh --quick`
- `set -e; for test_script in tests/*.bash; do bash "$test_script"; done`
- `git diff --check`

## Control-Plane Audit Inventory

Status: completed locally; pending PR/CI

Goal:
- close issue #398 by adding a deterministic no-backend control-plane inventory
  that counts observed repo/runtime state before model work
- detect tracked local-evidence artifacts such as literal root `$db`,
  `runtime/`, logs, transcripts, manifests, locks, and postmortem evidence
- emit stable JSON plus concise operator text and cover clean/dirty fixtures in
  quick validation

Constraints:
- no backend Codex validation and no network/GitHub calls
- report/inventory first; do not auto-remediate in this slice
- keep the clean path fast enough for no-op health checks

Files likely touched:
- `tools/upkeeper_control_plane_audit.py`
- `tests/control_plane_audit_test.bash`
- `tools/validate_upkeeper.sh`
- README/operator docs and release notes

Validation:
- `python3 -m py_compile tools/upkeeper_control_plane_audit.py`
- `bash tests/control_plane_audit_test.bash`
- `tools/validate_upkeeper.sh --quick`
- `tools/check_public_docs.sh --quick`
- `git diff --check`

## Quota Guardrail Telemetry Custody

Status: completed locally; pending PR/CI

Goal:
- stop anomaly custody from opening prior-run bug obligations for managed
  `quota.guardrails` deferred/partial-decision telemetry
- preserve real quota-related hard failures, PAGE errors, nonzero exits, and
  stale-quota obligations as the durable owners for quota health problems
- close issue #486 with deterministic validation for the exact warning shape

Constraints:
- no backend Codex validation
- do not demote `quota.identity_guardrail decision=stop` or unrelated quota
  errors
- keep the change inside anomaly custody classification and validation

Files likely touched:
- `tools/upkeeper_anomaly_custody.py`
- `tools/validate_upkeeper.sh`
- `change_notes_2026.md`

Validation:
- `python3 -m py_compile tools/upkeeper_anomaly_custody.py`
- `tools/validate_upkeeper.sh --quick`
- `git diff --check`

## Quoted Prior-Run Fixture Custody

Status: completed locally; pending PR/CI

Goal:
- stop anomaly custody from opening prior-run obligations for timestamped
  historical log snippets echoed through `Upkeeper: primary:`
- preserve live `PAGE`/`[ERROR]` custody when the line is actual wrapper output,
  not backend/model/source text quoting old evidence
- close issues #495 and #496 once deterministic validation proves the exact
  quoted prior-run snippets are non-actionable

Constraints:
- no backend Codex validation
- do not suppress standalone live prior-run anomalies
- keep the existing expected-fixture and quoted-source filters narrow

Files likely touched:
- `tools/upkeeper_anomaly_custody.py`
- `tools/validate_upkeeper.sh`
- `change_notes_2026.md`

Validation:
- `python3 -m py_compile tools/upkeeper_anomaly_custody.py`
- `tools/validate_upkeeper.sh --quick`
- `git diff --check`

## Nonzero Launcher Footer Custody

Status: completed locally; pending PR/CI

Goal:
- stop backlog job-summary footer lines such as `outcome/results: Upkeeper
  exited with status 3` from reopening duplicate prior-run anomaly obligations
  after the structured `cycle.exit`/`run.finish` evidence has already been
  coalesced under a terminal-failure owner
- keep standalone nonzero launcher exits actionable when there is no nearby
  owned terminal failure
- close issue #505 once deterministic validation proves the footer is owned

Constraints:
- no backend Codex validation
- do not hide standalone launcher failures that lack nearby owner evidence
- preserve owner obligation evidence by recording the coalesced footer excerpt

Files likely touched:
- `tools/upkeeper_anomaly_custody.py`
- `tools/validate_upkeeper.sh`
- `change_notes_2026.md`

Validation:
- `python3 -m py_compile tools/upkeeper_anomaly_custody.py`
- `tools/validate_upkeeper.sh --quick`
- `git diff --check`

## Expected Fixture Page Context

Status: completed locally; pending PR/CI

Goal:
- keep passing negative-test fixture output from looking like live pageable
  wrapper failures in interactive backlog output
- add a machine-readable fixture tag so triage can distinguish expected test
  evidence from current-cycle failures
- preserve unqualified `PAGE [ERROR]` output for real wrapper/control-plane
  failures

Constraints:
- do not hide the original fixture evidence
- do not rely on future log lines for live-stream classification
- keep anomaly custody behavior unchanged for stored logs

Files likely touched:
- `orchestration/backlog.sh`
- `tools/validate_upkeeper.sh`
- operator docs and release notes

Validation:
- `bash -n Upkeeper lib/upkeeper/*.bash tools/*.sh tests/*.bash testruns/*.sh Upkeeper.conf configurations/default.conf orchestration/backlog.sh`
- `tools/validate_upkeeper.sh --quick`
- `set -e; for test_script in tests/*.bash; do bash "$test_script"; done`
- `tools/check_public_docs.sh --quick`
- `git diff --check`

## Full Validator Quota-State Isolation

Status: merged in PR #631

Goal:
- keep `tools/validate_upkeeper.sh --full` deterministic on machines with live
  quota cooldown markers or stop-level quota state
- preserve explicit quota/fallback contract tests that intentionally exercise
  quota guardrails
- prevent validation-owned child Upkeeper dry-runs from sleeping or stopping on
  operator-local quota state

Constraints:
- no backend Codex validation
- do not change normal Upkeeper dry-run quota behavior outside the validator
- keep full validation bounded and local

Files likely touched:
- `tools/validate_upkeeper.sh`
- README/operator validation docs
- release notes

Validation:
- `bash -n Upkeeper lib/upkeeper/*.bash tools/*.sh tests/*.bash testruns/*.sh Upkeeper.conf configurations/default.conf orchestration/backlog.sh`
- `tools/validate_upkeeper.sh --quick`
- `tools/validate_upkeeper.sh --full --profile`
- `set -e; for test_script in tests/*.bash; do bash "$test_script"; done`
- `tools/check_public_docs.sh --quick`
- `git diff --check`

Result:
- validator-owned Upkeeper dry-runs now use explicit quota guardrail and
  cooldown bypasses
- file-manifest full validation includes a future quota marker fixture and the
  audit-only dry-run still completes through the no-quota validation path
- explicit quota/fallback tests still exercise real guardrail behavior with
  their own fixtures

## Quota Hibernation Retired-Branch Exit

Status: merged in PR #629

Goal:
- stop backlog quota hibernation from holding a local branch after its upstream
  backlog PR branch has been merged or deleted by another worktree
- preserve the no-backend/no-network hibernation path by checking only local git
  branch/upstream refs
- print a plain operator reason and exit cleanly so the checkout can be synced
  or cleaned instead of sleeping until quota reset

Constraints:
- no backend Codex validation
- do not poll GitHub or fetch while hibernating
- do not change normal quota block handling for active branches

Files likely touched:
- `orchestration/backlog.sh`
- `tools/validate_upkeeper.sh`
- operator docs, compatibility notes, and release notes

Validation:
- `bash -n Upkeeper lib/upkeeper/*.bash tools/*.sh tests/*.bash testruns/*.sh Upkeeper.conf configurations/default.conf orchestration/backlog.sh`
- `tools/validate_upkeeper.sh --smoke`
- `tools/validate_upkeeper.sh --quick`
- `set -e; for test_script in tests/*.bash; do bash "$test_script"; done`
- `tools/check_public_docs.sh --quick`
- `git diff --check`

Result:
- fake-clock hibernation still sleeps until the reset grace on active branches
- a backlog branch with a configured but missing local upstream ref exits
  hibernation before sleeping and prints
  `action=exit_for_merged_or_deleted_branch`

## Docs-Only Fast Path

Status: completed locally; pending PR/CI

Goal:
- close issue #330 by making the common docs-only edit path locally
  scriptable without backend Codex, GitHub CLI, GitHub polling, or extra fetches
- keep docs-only validation narrow: public-doc checks, smoke validation, and
  diff whitespace only
- give CI and operators one shared docs-only classifier instead of separate
  hand-maintained allowlists

Constraints:
- no backend Codex validation
- no `gh`, `curl`, `wget`, or `git fetch` inside the docs-only helper
- fail closed to the broader path when changed-file scope cannot be proven
  locally

Files likely touched:
- `tools/docs_only_fast_path.sh`
- `.github/workflows/ci.yml`
- `tools/validate_upkeeper.sh`
- README, dependency/release docs, operator guide, and release notes

Validation:
- `bash -n Upkeeper lib/upkeeper/*.bash tools/*.sh tests/*.bash testruns/*.sh Upkeeper.conf configurations/default.conf orchestration/backlog.sh`
- `tools/docs_only_fast_path.sh --classify-only --paths-from <fixture>`
- `tools/docs_only_fast_path.sh --validate --paths-from <fixture>`
- `set -e; for test_script in tests/*.bash; do bash "$test_script"; done`
- `tools/check_public_docs.sh --quick`
- `tools/validate_upkeeper.sh --quick`
- `git diff --check`

Result:
- docs-only classifier accepts README/docs/prompt paths and rejects mixed
  source/tool paths
- implementation branch still fails closed to broad validation because it
  changes workflow and tool code

## Anomaly Custody Fixture Suppression

Status: completed locally

Goal:
- stop prior-run anomaly custody from reopening quoted backend fixture text that
  Upkeeper already reclassified as `quoted_backend_source_fixture`
- treat backlog-temp negative-test lines from transcript and pre-contact tests
  as expected fixture output when their matching tests pass
- recognize already-resolved source-cycle owner obligations so old blocked
  cycles do not reappear as fresh incident rollups
- close the GitHub bugs created by the over-eager classifier once the
  deterministic rule and validation are in place

Constraints:
- no backend Codex validation
- do not hide live `PAGE` or `[ERROR]` lines without deterministic fixture,
  quote, or resolved-owner evidence
- preserve the resolved local obligation records for auditability

Files likely touched:
- `tools/upkeeper_anomaly_custody.py`
- `orchestration/backlog.sh`
- `tools/validate_upkeeper.sh`
- operator docs and release notes

Validation:
- `python3 -m py_compile tools/upkeeper_anomaly_custody.py`
- `tools/validate_upkeeper.sh --quick`
- `tools/check_public_docs.sh --quick`
- `git diff --check`
- current loop-log anomaly-custody replay reports `actionable=0`

Result:
- current loop-log replay produced no actionable findings from the interrupted
  fixture/quote residue

## Startup Gate Status Metadata Drift

Status: completed locally

Goal:
- prevent startup-anomaly self-repair from keeping the gate unresolved merely
  because allowed Upkeeper-suite edits changed the volatile porcelain status
  byte count

Constraints:
- preserve path-level changed-file enforcement for disallowed paths
- keep branch, head, and index-tree control-state checks intact

Files touched:
- `lib/upkeeper/worktree_state.bash`
- `tests/wrapper_contract_test.bash`
- release notes

Validation:
- focused wrapper-contract regression
- full quick validation before merge

Result:
- allowed central wrapper edits no longer emit
  `startup_anomaly.gate_violation control_state_changed key='status_lines'`

## Batch Validation State Isolation

Status: completed locally

Goal:
- stop backlog batch validation from inheriting live automation-obligation state
  into unit-test fixtures
- make ChimneySweep clean-queue tests ignore ambient `UPKEEPER_OBLIGATION_DIR`
  unless a fixture explicitly opts into an obligation root
- prevent quoted diagnostic command text containing `[ERROR]` or `PAGE` from
  becoming new anomaly custody while repair prompts inspect prior failures
- reconcile duplicate blocked obligations created by the failed self-repair loop

Constraints:
- no backend Codex validation
- preserve the existing live obligation evidence until deterministic
  reconciliation can resolve it
- keep validation isolation local to harnesses and batch validation, not normal
  production launcher state

Files likely touched:
- `Upkeeper`
- `orchestration/backlog.sh`
- `tests/chimneysweep_test.bash`
- `tools/validate_upkeeper.sh`
- operator docs and release notes

Validation:
- `bash -n Upkeeper lib/upkeeper/*.bash tools/*.sh tests/*.bash testruns/*.sh Upkeeper.conf configurations/default.conf orchestration/backlog.sh`
- `UPKEEPER_OBLIGATION_DIR=runtime/upkeeper-obligations bash tests/chimneysweep_test.bash`
- isolated backlog batch-validation unit-test replay with live
  `UPKEEPER_OBLIGATION_DIR` exported
- `set -e; for test_script in tests/*.bash; do bash "$test_script"; done`
- `tools/validate_upkeeper.sh --quick`
- `tools/check_public_docs.sh --quick`
- `git diff --check`

Result:
- local validation passed
- duplicate blocked obligations from the interrupted loop were reconciled
- the proven-fixed batch-validation, BLOCKED, and quoted diagnostic PAGE
  obligations were moved to resolved local state

## Duplicate Obligation Issue Filing Circuit Breaker

Status: completed locally

Goal:
- stop repeated local machine-health obligations from filing many GitHub bugs
  for the same underlying failure family
- make local reconciliation collapse system-level failures by class, reason,
  target, and repair target instead of volatile per-cycle fingerprints
- make already-linked obligations collapse by specific issue title and issue
  number instead of keeping volatile evidence fingerprints open separately
- make the obligation issue-report bridge reuse an existing open GitHub issue
  with the same operator-facing title before creating another issue
- preserve durable evidence by moving duplicate local records to resolved state
  with duplicate metadata rather than deleting evidence

Constraints:
- no backend Codex validation
- do not lose existing local obligation evidence
- keep issue creation wrapper-owned and deterministic
- keep GitHub writes out of validation fixtures; use fake `gh` commands

Files likely touched:
- `lib/upkeeper/automation_obligations.bash`
- `tools/validate_upkeeper.sh`
- `docs/scripts/upkeeper.md`
- `docs/compatibility.md`
- `change_notes_2026.md`
- `lib/upkeeper/help_selection.bash`
- `orchestration/backlog.sh`

Validation:
- `bash -n Upkeeper lib/upkeeper/*.bash tools/*.sh tests/*.bash testruns/*.sh Upkeeper.conf configurations/default.conf orchestration/backlog.sh`
- `tools/validate_upkeeper.sh --quick`
- `tools/check_public_docs.sh --quick`
- `git diff --check`

## Backlog Wrapper Failure Catchment

Status: completed locally; consolidated on `backlog/20260524-201224`

Goal:
- make the backlog launcher record a durable obligation when its child
  `./Upkeeper` process exits nonzero before Upkeeper can write its own clean
  final state
- capture bounded local child-output evidence outside the model path, dedupe
  repeated failures, and route the next cycle to the likely wrapper owner file
- preserve known blocked and quota exits while making unexpected child exits
  impossible to lose between loop iterations
- preserve a child-owned native obligation, such as
  `codex_exec_empty_transcript`, instead of filing a duplicate outer catchment
  record for the same failed cycle

Constraints:
- no backend Codex validation
- keep the catchment deterministic, pre-model, and local
- store only bounded output evidence in private local obligation state
- do not widen normal issue selection or merge behavior when the child exits
  successfully
- reconcile repeated system-level obligations by failure class and repair
  target, not by the issue number later attached to one duplicate

Files likely touched:
- `orchestration/backlog.sh`
- `tests/backlog_wrapper_failure_obligation_test.bash`
- `tools/validate_upkeeper.sh`
- operator docs and release notes

Validation:
- `bash -n Upkeeper lib/upkeeper/*.bash tools/*.sh tests/*.bash testruns/*.sh Upkeeper.conf configurations/default.conf orchestration/backlog.sh`
- `bash tests/backlog_wrapper_failure_obligation_test.bash`
- `tools/validate_upkeeper.sh --quick`
- `tools/check_public_docs.sh --quick`
- `git diff --check`

## Parallel Backlog Worker Lease Primitive

Status: completed locally; consolidated on `backlog/20260524-201224`

Goal:
- make progress on issue #367 by defining the safe first slice for future
  parallel backlog workers
- add a deterministic local lease registry so synthetic workers cannot claim the
  same issue or predicted target before any backend work starts
- keep live parallel worker launch out of scope until lease, worktree, PR, quota,
  and cleanup contracts have local proof

Constraints:
- no backend Codex calls
- do not alter the default single-worker backlog launcher behavior
- do not touch the active loop checkout
- keep the primitive local and no-GitHub-write for this first slice

Files likely touched:
- `tools/backlog_parallel_leases.py`
- `tests/backlog_parallel_leases_test.bash`
- `docs/decisions/0002-parallel-backlog-workers.md`
- `docs/scripts/upkeeper.md`
- `docs/compatibility.md`
- `README.md`
- `tools/validate_upkeeper.sh`
- `change_notes_2026.md`

Validation:
- `bash -n Upkeeper lib/upkeeper/*.bash tools/*.sh tests/*.bash testruns/*.sh Upkeeper.conf configurations/default.conf orchestration/backlog.sh`
- `bash tests/backlog_parallel_leases_test.bash`
- `tools/validate_upkeeper.sh --quick`
- `tools/check_public_docs.sh --quick`
- `git diff --check`

## Prior-Run Incident Rollups

Status: completed locally; consolidated on `backlog/20260524-201224`

Goal:
- advance issue #390 by preventing one source-cycle control-plane failure from
  becoming many sibling prior-run anomaly obligations and GitHub issues
- add a deterministic incident rollup for same-cycle hard anomaly cascades while
  preserving individual signal evidence inside the rollup record
- keep isolated warnings and exact repeated fingerprints on the existing cheap
  custody path

Constraints:
- no backend Codex validation
- preserve the obligation-first launcher contract
- keep rollup decisions local, bounded, and based only on recent loop-log
  evidence

Files likely touched:
- `tools/upkeeper_anomaly_custody.py`
- `tools/validate_upkeeper.sh`
- `lib/upkeeper/automation_obligations.bash`
- `lib/upkeeper/help_selection.bash`
- `change_notes_2026.md`

Validation:
- `bash -n Upkeeper lib/upkeeper/*.bash tools/*.sh tests/*.bash testruns/*.sh Upkeeper.conf configurations/default.conf orchestration/backlog.sh`
- `python3 -m py_compile tools/upkeeper_anomaly_custody.py`
- `tools/validate_upkeeper.sh --quick`
- `tools/check_public_docs.sh --quick`
- `git diff --check`

## Previous-Run Startup Residue Custody

Status: completed locally; pending PR/CI

Goal:
- close issue #429 by preventing already-custodied previous-run/startup
  anomaly residue from reappearing as fresh startup-gate warning noise
- keep genuinely new previous-run anomaly evidence mandatory until it has local
  custody
- make operator output distinguish known local custody from new active residue

Constraints:
- no backend Codex calls
- keep the clean/no-op path deterministic and local
- do not hide new anomalies that do not have a matching local obligation or
  custody acknowledgment

Files likely touched:
- `lib/upkeeper/previous_run_anomalies.bash`
- `lib/upkeeper/help_selection.bash`
- `tools/validate_upkeeper.sh`
- `docs/scripts/upkeeper.md`
- `change_notes_2026.md`

Validation:
- `bash -n Upkeeper lib/upkeeper/*.bash tools/*.sh tests/*.bash testruns/*.sh Upkeeper.conf configurations/default.conf orchestration/backlog.sh`
- `set -e; for test_script in tests/*.bash; do bash "$test_script"; done`
- `tools/validate_upkeeper.sh --source-contracts`
- `tools/validate_upkeeper.sh --quick`
- `tools/check_public_docs.sh --quick`
- `git diff --check`

Result:
- known current-root previous-run and startup-gate residue now logs as
  `previous_run.known_anomaly_residue`
- source-cycle matching keeps new uncustodied prior-run evidence on the
  startup-gate path

## Status Marker Parser Crash Hardening

Status: completed locally; consolidated on `backlog/20260524-201224`

Goal:
- stop prior-run anomaly repair from repeating PAGE churn when backend Codex
  exits before producing an `UPKEEPER_STATUS` marker
- repair the entrypoint-only status-marker parser override so it calls the
  shared marker parser with the required status contract arguments
- make marker parser and assignment handling tolerate malformed internal calls
  without shell `set -u` crashes

Constraints:
- no backend Codex validation
- keep status-marker acceptance rules unchanged for valid transcripts
- preserve the existing obligation and anomaly custody flow; only remove the
  wrapper crash that prevents normal failure classification

Files likely touched:
- `Upkeeper`
- `lib/upkeeper/report_analysis.bash`
- focused wrapper/status-marker tests
- versioned operator notes

Validation:
- `bash -n Upkeeper lib/upkeeper/*.bash tools/*.sh tests/*.bash testruns/*.sh Upkeeper.conf configurations/default.conf orchestration/backlog.sh`
- `bash tests/bug_fix_batch_280_281_265_test.bash`
- `tools/validate_upkeeper.sh --quick`
- `git diff --check`

## Per-Bug Source Contract Gate

Status: completed locally; pending PR/CI

Goal:
- repair the current PR #473 blocker where a too-long `log_line` call passed
  per-bug validation but failed later batch validation/CI
- make the backlog per-bug commit path run a cheap source-contract gate for
  Upkeeper source changes before staging and pushing
- repair the PR-local issue-fix obligation binding crash that used the wrong
  Python scan-directory variable before Codex could start
- preserve the low-cost loop path by avoiding full quick validation on every
  per-bug commit

Constraints:
- no backend Codex validation
- keep the source-contract check deterministic and local
- do not slow unchanged docs or non-source commits with broad validation

Files likely touched:
- `Upkeeper`
- `orchestration/backlog.sh`
- `tools/validate_upkeeper.sh`
- operator docs and release notes

Validation:
- `bash -n Upkeeper lib/upkeeper/*.bash tools/*.sh tests/*.bash testruns/*.sh Upkeeper.conf configurations/default.conf orchestration/backlog.sh`
- `set -e; for test_script in tests/*.bash; do bash "$test_script"; done`
- `tools/validate_upkeeper.sh --source-contracts`
- `tools/validate_upkeeper.sh --quick`
- `tools/check_public_docs.sh --quick`
- `git diff --check`

## Descriptive Automation Obligation Issue Titles

Status: completed and merged

Goal:
- close issue #455 by making prior-run anomaly obligation issue names
  deterministic, evidence-specific, and less duplicative
- preserve script-owned issue filing; no model call should decide the title
- keep existing generic/open obligation records repairable by deriving a
  better report title from their stored evidence

Constraints:
- no backend Codex calls
- keep title generation short, redacted, and based only on local obligation
  fields or bounded evidence excerpts
- preserve manually specific issue titles while replacing generic umbrella or
  prior-run placeholders

Files likely touched:
- `tools/upkeeper_anomaly_custody.py`
- `lib/upkeeper/automation_obligations.bash`
- `tools/validate_upkeeper.sh`
- `docs/scripts/upkeeper.md`
- `change_notes_2026.md`

Validation:
- `bash -n Upkeeper FlameOn ChimneySweep lib/upkeeper/*.bash tools/*.sh tests/*.bash testruns/*.sh Upkeeper.conf configurations/default.conf orchestration/backlog.sh orchestration/watch-pr.sh`
- `set -e; for test_script in tests/*.bash; do bash "$test_script"; done`
- `tools/validate_upkeeper.sh --quick`
- `tools/check_public_docs.sh --quick`
- `git diff --check`

## Lattice Degraded-Mode Ownership

Status: completed and merged

Goal:
- close issue #430 by making optional `lattice.unavailable` degraded mode
  classified and owned instead of an anonymous detail hash
- preserve optional Lattice behavior when `UPKEEPER_LATTICE_REQUIRED=0` while
  making the fallback evidence and owner contract clear in live logs and
  recovery rows
- extend local Lattice validation so the unsafe/unavailable fixture proves the
  warning has reason, owner, and replacement-evidence fields

Constraints:
- no backend Codex calls
- keep raw Lattice failure detail redacted; only bounded summaries and reason
  classes can reach logs
- preserve fail-closed behavior when `UPKEEPER_LATTICE_REQUIRED=1`

Files likely touched:
- `lib/upkeeper/lattice.bash`
- `tests/lattice_test.bash`
- `docs/lattice.md`
- `docs/security.md`
- `README.md`
- `tools/validate_upkeeper.sh`
- `change_notes_2026.md`

Validation:
- `bash -n Upkeeper lib/upkeeper/*.bash tools/*.sh tests/*.bash testruns/*.sh Upkeeper.conf configurations/default.conf orchestration/backlog.sh`
- `bash tests/lattice_test.bash`
- `tools/validate_upkeeper.sh --quick`
- `tools/check_public_docs.sh --quick`
- `git diff --check`

## Preservation Policy And Artifact Privacy

Status: completed locally; pending PR/CI

Goal:
- close issue #220 by defining preservation policy, evidence temperature, and
  artifact privacy classes for Upkeeper evidence
- make the policy part of the tracked security, Lattice, and compatibility
  contract
- add deterministic validation so the policy cannot silently drift

Constraints:
- no backend Codex calls
- document existing evidence handling without weakening privacy defaults
- keep private local evidence out of committed artifacts by default

Files likely touched:
- `docs/preservation-policy.md`
- `docs/security.md`
- `docs/lattice.md`
- `docs/compatibility.md`
- `README.md`
- `docs/risk-register.md`
- `tools/check_public_docs.sh`
- `tools/validate_upkeeper.sh`
- `change_notes_2026.md`

Validation:
- `tools/check_public_docs.sh --quick`
- `tools/validate_upkeeper.sh --smoke`
- `bash -n Upkeeper lib/upkeeper/*.bash tools/*.sh tests/*.bash testruns/*.sh Upkeeper.conf configurations/default.conf orchestration/backlog.sh orchestration/watch-pr.sh`
- `tools/validate_upkeeper.sh --quick`
- `set -e; for test_script in tests/*.bash; do bash "$test_script"; done`
- `git diff --check`

## Threat Model And Degraded-Mode Doctrine

Status: completed locally; pending PR/CI

Goal:
- close issue #221 by documenting Upkeeper's explicit threat model,
  degraded-mode behavior, and override rules
- make the doctrine part of the tracked security and compatibility contract
- add deterministic validation so the contract cannot silently drift

Constraints:
- no backend Codex calls
- document existing doctrine without weakening runtime safety gates
- keep override authority local and operator-visible; Codex cannot override
  safety blocks

Files likely touched:
- `docs/security.md`
- `docs/compatibility.md`
- `README.md`
- `docs/risk-register.md`
- `tools/check_public_docs.sh`
- `tools/validate_upkeeper.sh`
- `change_notes_2026.md`

Validation:
- `tools/check_public_docs.sh --quick`
- `tools/validate_upkeeper.sh --smoke`
- `bash -n Upkeeper lib/upkeeper/*.bash tools/*.sh tests/*.bash testruns/*.sh Upkeeper.conf configurations/default.conf orchestration/backlog.sh orchestration/watch-pr.sh`
- `tools/validate_upkeeper.sh --quick`
- `set -e; for test_script in tests/*.bash; do bash "$test_script"; done`
- `git diff --check`

## Stale Quota Evidence Custody

Status: completed and merged

Goal:
- close issue #419 by making expired-reset stale quota evidence visible
  machine health instead of an ignorable burn-bypass warning
- record a structured, deduplicated automation obligation when stale quota
  evidence cannot be reconciled before continuing
- retire that obligation automatically once current non-stale quota evidence is
  observed

Constraints:
- no backend Codex calls
- keep quota evidence private and redact raw session paths from obligations
- preserve burn-mode ability to continue only after non-perfect health is
  recorded
- keep repeated stale evidence to one fingerprinted obligation

Files likely touched:
- `orchestration/backlog.sh`
- `tests/backlog_stale_quota_obligation_test.bash`
- `tools/validate_upkeeper.sh`
- operator-facing docs/help/release notes

Validation:
- `bash -n Upkeeper lib/upkeeper/*.bash tools/*.sh tests/*.bash testruns/*.sh Upkeeper.conf configurations/default.conf orchestration/backlog.sh`
- `bash tests/backlog_stale_quota_obligation_test.bash`
- `tools/check_public_docs.sh --quick`
- `tools/validate_upkeeper.sh --quick`
- `git diff --check`

## Batch Validation Retry Guard

Status: completed and merged

Goal:
- close issue #413 by preventing repeated identical batch-validation failures
  from rerunning the whole merge validation suite on the same branch/head
- keep the first failure evidence in a structured automation obligation
- make the next identical retry fail closed from local custody state with a
  clear retry fingerprint and repair-obligation message

Constraints:
- no backend Codex calls
- keep retry detection deterministic and private under the backlog state root
- remove stale retry markers when branch/head or command context changes
- preserve the existing fail-closed validation exit status

Files likely touched:
- `orchestration/backlog.sh`
- `tests/backlog_batch_validation_obligation_test.bash`
- `tools/validate_upkeeper.sh`
- `change_notes_2026.md`

Validation:
- `bash -n Upkeeper lib/upkeeper/*.bash tools/*.sh tests/*.bash testruns/*.sh Upkeeper.conf configurations/default.conf orchestration/backlog.sh`
- `bash tests/backlog_batch_validation_obligation_test.bash`
- `tools/validate_upkeeper.sh --quick`
- `git diff --check`

## Local PR Check Watcher

Status: completed and merged

Goal:
- close issue #402 with a deterministic local PR-check watcher for backlog and
  manual restart boundaries
- support explicit PR numbers and current-branch PR inference without backend
  Codex or repository mutation
- make backlog print the watcher command after creating or pushing PR updates

Constraints:
- no backend Codex calls
- validation must fake `gh` instead of requiring live GitHub network
- keep output stable enough for humans and later assistive tooling

Files likely touched:
- `orchestration/watch-pr.sh`
- `orchestration/backlog.sh`
- `tests/watch_pr_test.bash`
- `tools/validate_upkeeper.sh`
- operator-facing docs/release notes

Validation:
- `bash -n Upkeeper lib/upkeeper/*.bash tools/*.sh tests/*.bash testruns/*.sh Upkeeper.conf configurations/default.conf orchestration/backlog.sh`
- `bash tests/watch_pr_test.bash`
- `tools/check_public_docs.sh --quick`
- `tools/validate_upkeeper.sh --quick`
- `git diff --check`

## Serious Finding Repro Fixtures

Status: completed and merged

Goal:
- close issue #139 by making serious security/data-integrity/control-plane
  findings require deterministic repro proof or an explicit non-repro rationale
- add GitHub issue and PR checklist hooks so new serious findings do not remain
  prose-only
- add quick-validator coverage for the policy and templates

Constraints:
- no backend Codex calls
- keep the contract lightweight enough for docs-only and governance changes
- allow explicit non-repro rationale when reproducing a finding would be unsafe
  or too destructive

Files likely touched:
- `docs/negative-space-testing.md`
- `docs/release-checklist.md`
- `.github/ISSUE_TEMPLATE/*`
- `.github/pull_request_template.md`
- `tools/validate_upkeeper.sh`
- `change_notes_2026.md`

Validation:
- `tools/check_public_docs.sh --quick`
- `tools/validate_upkeeper.sh --smoke`
- `tools/validate_upkeeper.sh --quick`
- `git diff --check`

## After-Action Review Contract

Status: completed locally; pending PR/CI

Goal:
- close issue #335 by making after-action review a first-class Upkeeper
  contract instead of a failure-only debrief habit
- update P27, operator docs, and the PR template to capture outcome, what went
  right, what went wrong, waste, next improvement, and reusable learning
- add quick-validator coverage so the required shape cannot silently drift

Constraints:
- no backend Codex calls
- keep after-action review concise; do not require tracked docs for every run
- preserve `P27: not applicable` for routine edits with no reusable lesson

Files likely touched:
- `prompts/p27-educational-debrief-review.md`
- `.github/pull_request_template.md`
- `docs/public-documentation-policy.md`
- `docs/scripts/upkeeper.md`
- `README.md`
- `tools/validate_upkeeper.sh`
- `change_notes_2026.md`

Validation:
- `tools/check_public_docs.sh --quick`
- `tools/validate_upkeeper.sh --smoke`
- `tools/validate_upkeeper.sh --quick`
- `git diff --check`

## Backlog Local-Ahead Branch Guard

Status: completed and merged

Goal:
- close issue #416 by ensuring clean local commits on an active backlog PR
  branch are pushed before PR check or merge decisions
- fail closed with a clear branch-state summary when the branch is dirty,
  missing its remote ref, or diverged from origin
- prevent batch merge from reasoning from green checks on an older remote head

Constraints:
- no backend Codex calls
- preserve dirty local work instead of pushing ambiguous state
- keep detection local and deterministic with Git refs and ahead/behind counts

Files likely touched:
- `orchestration/backlog.sh`
- `tests/backlog_local_ahead_guard_test.bash`
- `tools/validate_upkeeper.sh`
- operator-facing docs/release notes

Validation:
- `bash -n Upkeeper lib/upkeeper/*.bash tools/*.sh tests/*.bash testruns/*.sh Upkeeper.conf configurations/default.conf orchestration/backlog.sh`
- `bash tests/backlog_local_ahead_guard_test.bash`
- `tools/check_public_docs.sh --quick`
- `tools/validate_upkeeper.sh --quick`
- `git diff --check`

## Batch Validation Failure Obligations

Status: completed locally; pending PR/CI

Goal:
- close issue #412 by making local backlog batch-validation failures durable
  machine-health obligations
- preserve the failed phase, command, exit code, bounded output tail,
  fingerprint, likely owner path, and required validation proof
- ensure the next unattended backlog invocation repairs the validation failure
  before merge retry or fresh GitHub issue work

Constraints:
- keep the mechanism local, deterministic, and pre-model
- deduplicate repeated identical validation failures by stable fingerprint
- preserve existing fail-closed merge behavior when validation fails

Files likely touched:
- `orchestration/backlog.sh`
- `tests/backlog_batch_validation_obligation_test.bash`

Validation:
- `bash -n Upkeeper lib/upkeeper/*.bash tools/*.sh tests/*.bash testruns/*.sh Upkeeper.conf configurations/default.conf orchestration/backlog.sh`
- `bash tests/backlog_batch_validation_obligation_test.bash`
- `tools/validate_upkeeper.sh --quick`
- `tools/check_public_docs.sh --quick`
- `git diff --check`

## Backlog Merge Steward

Status: completed and merged

Goal:
- close issue #385 with a deterministic local merge steward for already-green
  backlog PRs
- refuse unsafe PR, check, branch, and worktree states before merging
- drive or report the clean-sheet state needed before the next backlog loop

Constraints:
- no backend Codex calls
- never rewrite or delete dirty user work
- use the guarded `CODEX_ALLOW_PR_MERGE=<pr>` merge path for real merges
- keep tests fixture-driven with fake `gh`/Git state

Files likely touched:
- `tools/backlog_merge_steward.py`
- `tests/backlog_merge_steward_test.bash`

Validation:
- `bash -n Upkeeper lib/upkeeper/*.bash tools/*.sh tests/*.bash testruns/*.sh Upkeeper.conf configurations/default.conf`
- `bash tests/backlog_merge_steward_test.bash`

## Backlog Stop Triage

Status: completed and merged

Goal:
- close issue #384 with a local no-backend triage command for stopped backlog
  loops
- emit both machine-readable restart status and a plain operator summary
- cover known stopped-loop classes with deterministic fixtures

Constraints:
- no backend Codex calls
- GitHub PR/check metadata is optional; local evidence must be enough for
  common restart decisions
- unknown or contradictory local evidence must fail closed and leave visible
  obligation evidence instead of declaring a restart safe

Files likely touched:
- `tools/backlog_triage.py`
- `tests/backlog_triage_test.bash`

Validation:
- `bash -n Upkeeper lib/upkeeper/*.bash tools/*.sh tests/*.bash testruns/*.sh Upkeeper.conf configurations/default.conf`
- `bash tests/backlog_triage_test.bash`

## Negative-Space Validation Contract

Status: completed and merged

Goal:
- close issue #230 by making negative-space testing a first-class validation
  contract
- document the major "must not happen" invariants Upkeeper depends on
- add a deterministic quick-validator check that those invariants stay tied to
  no-backend local tests, fixtures, or enforcement points

Constraints:
- do not add live backend Codex validation
- keep the clean no-op and quick validation paths cheap
- do not claim fuzzing or broad mutation testing; this is a catalog and proof
  index for concrete local negative fixtures

Files likely touched:
- `docs/negative-space-testing.md`
- `README.md`
- `docs/scripts/upkeeper.md`
- `docs/security.md`
- `docs/compatibility.md`
- `tools/validate_upkeeper.sh`
- `change_notes_2026.md`
- `PLANS.md`

Validation:
- `bash -n Upkeeper lib/upkeeper/*.bash tools/*.sh tests/*.bash testruns/*.sh Upkeeper.conf configurations/default.conf`
- `set -e; for test_script in tests/*.bash; do bash "$test_script"; done`
- `tools/validate_upkeeper.sh --quick`
- `tools/check_public_docs.sh --quick`
- `git diff --check`

## Lattice Custody Authority Policy

Status: completed and merged

Goal:
- close issue #138 by documenting and validating that Lattice is supporting
  evidence, not sole custody authority, for audit and breadcrumb decisions while
  listed Lattice integrity blockers remain open
- prove current breadcrumb/audit custody code keeps fallback log, transcript,
  obligation, and failure-queue evidence available without requiring Lattice
- preserve Lattice as useful long-memory evidence without letting it become the
  only source for control-plane custody

Constraints:
- no backend Codex validation
- keep current Lattice runtime behavior unchanged
- make the policy public and machine-checked

Files likely touched:
- `docs/lattice.md`
- `docs/scripts/upkeeper.md`
- `docs/compatibility.md`
- `tools/validate_upkeeper.sh`
- `change_notes_2026.md`
- `PLANS.md`

Validation:
- `bash -n Upkeeper lib/upkeeper/*.bash tools/*.sh tests/*.bash testruns/*.sh Upkeeper.conf configurations/default.conf`
- `set -e; for test_script in tests/*.bash; do bash "$test_script"; done`
- `tools/validate_upkeeper.sh --quick`
- `tools/check_public_docs.sh --quick`
- `git diff --check`

## Breadcrumb Severity Gate

Status: completed and merged

Goal:
- close issue #137 by making unresolved high/critical breadcrumb custody affect
  normal Upkeeper rotation
- keep the enforcement deterministic and pre-model
- build on the local breadcrumb custody records from issue #124

Constraints:
- preserve explicit `--target-file` and issue-fix pins
- keep low/medium breadcrumbs warning/custody-only by default
- do not rescan large logs on the clean startup path; read current open custody
  records instead

Files likely touched:
- `Upkeeper`
- `lib/upkeeper/breadcrumb_gate.bash`
- `tools/audit_upkeeper_breadcrumbs.py`
- `tools/validate_upkeeper.sh`
- `docs/scripts/upkeeper.md`
- `docs/compatibility.md`
- `change_notes_2026.md`
- `PLANS.md`

Validation:
- `bash -n Upkeeper lib/upkeeper/*.bash tools/*.sh tests/*.bash testruns/*.sh Upkeeper.conf configurations/default.conf`
- `tools/validate_upkeeper.sh --quick`
- `tools/validate_upkeeper.sh --full`
- `tools/check_public_docs.sh --quick`
- `git diff --check`

## Audit-Only Mode

Status: completed and merged

Goal:
- close issue #132 by making audit-only/no-fix a first-class invocation surface
- reuse the existing bug-report-only source-mutation guard and draft artifact
  path instead of creating a second read-only workflow
- document aliases and prove the mode records audit intent without allowing
  tracked source mutation

Constraints:
- preserve existing `--bug-report-only`, `--file-bug-only`, and
  `--report-bug-only` behavior
- do not launch real backend Codex during validation
- keep audit-only reports under ignored runtime evidence

Files likely touched:
- `Upkeeper`
- `lib/upkeeper/codex_io.bash`
- `lib/upkeeper/help_selection.bash`
- `tools/validate_upkeeper.sh`
- `docs/scripts/upkeeper.md`
- `docs/compatibility.md`

Validation:
- `bash -n Upkeeper lib/upkeeper/*.bash tools/*.sh tests/*.bash testruns/*.sh Upkeeper.conf configurations/default.conf`
- `tools/validate_upkeeper.sh --quick`
- `tools/check_public_docs.sh --quick`
- `./Upkeeper --help`
- `git diff --check`

## Breadcrumb Custody Audit

Status: completed locally; pending PR/CI

Goal:
- close issue #124 with a deterministic local breadcrumb audit command
- turn weak suspicious log/transcript clues into stable open/resolved/suppressed
  local JSON records
- add quick validation coverage and operator docs for the custody contract

Constraints:
- keep breadcrumb records ignored local runtime evidence
- avoid backend Codex and GitHub I/O
- reuse existing anomaly-custody classifications where practical, but keep this
  audit command focused and deterministic

Files likely touched:
- `tools/audit_upkeeper_breadcrumbs.py`
- `tools/validate_upkeeper.sh`
- `lib/upkeeper/help_selection.bash`
- `docs/scripts/upkeeper.md`

Validation:
- `bash -n Upkeeper lib/upkeeper/*.bash tools/*.sh tests/*.bash testruns/*.sh Upkeeper.conf configurations/default.conf`
- `tools/validate_upkeeper.sh --quick`
- `set -e; for test_script in tests/*.bash; do bash "$test_script"; done`
- `tools/check_public_docs.sh --quick`
- `./Upkeeper --help`
- `git diff --check`

## Embedded Behavior Table Contracts

Status: completed locally; pending PR/CI

Goal:
- close issue #106 by adding deterministic drift checks for high-risk embedded
  tables and classifiers
- cover startup anomaly changed-path allowlists, source-safe exclusions,
  command-kind classifiers, review-module ids, and Lattice pass-code mappings
- document the operator-visible ownership boundary for these tables

Constraints:
- keep checks no-quota and local to validation
- do not extract runtime helpers until fixtures prove the drift surface
- preserve current operator behavior and source-safe selection semantics

Files likely touched:
- `tools/validate_upkeeper.sh`
- `docs/scripts/upkeeper.md`
- `docs/compatibility.md`

Validation:
- `bash -n Upkeeper lib/upkeeper/*.bash tools/*.sh tests/*.bash testruns/*.sh Upkeeper.conf configurations/default.conf`
- `tools/validate_upkeeper.sh --quick`
- `set -e; for test_script in tests/*.bash; do bash "$test_script"; done`
- `tools/check_public_docs.sh --quick`
- `git diff --check`

## Quota And Session Fixtures

Status: completed locally; pending PR/CI

Goal:
- close issue #104 by naming reusable validation quota/session JSONL fixtures
- cover current, stale, wrong-model, malformed, empty, nonfinite, and
  missing-field cases without reading real operator CODEX_HOME data
- reuse named fixtures in existing validation where practical

Constraints:
- keep fixtures generated under validator temp roots only
- preserve existing quota/session parser behavior and diagnostics
- do not launch real backend Codex

Files likely touched:
- `lib/upkeeper/quota_state.bash`
- `tools/validate_upkeeper.sh`
- `change_notes_2026.md`
- `PLANS.md`

Validation:
- `bash -n Upkeeper lib/upkeeper/*.bash tools/*.sh tests/*.bash testruns/*.sh Upkeeper.conf configurations/default.conf`
- `tools/validate_upkeeper.sh --quick`
- `set -e; for test_script in tests/*.bash; do bash "$test_script"; done`
- `tools/check_public_docs.sh --quick`
- `git diff --check`

## Shell Assignment Helper Fixtures

Status: completed locally; pending PR/CI

Goal:
- close issue #103 by adding focused tests for jq-generated shell assignment
  emitters before any reuse extraction
- cover malformed JSON, bad prefixes, missing/null fields, arrays/objects,
  spaces, quotes, newlines, and shell metacharacters
- prove emitted assignments preserve values without executing embedded shell
  text

Constraints:
- do not extract a shared helper until tests prove the current quoting contract
- keep coverage local and no-quota
- preserve current assignment function names, output format, and return
  semantics

Files likely touched:
- `tests/wrapper_contract_test.bash`
- `change_notes_2026.md`
- `PLANS.md`

Validation:
- `bash -n Upkeeper lib/upkeeper/*.bash tools/*.sh tests/*.bash testruns/*.sh Upkeeper.conf configurations/default.conf`
- `bash tests/wrapper_contract_test.bash`
- `set -e; for test_script in tests/*.bash; do bash "$test_script"; done`
- `tools/validate_upkeeper.sh --quick`
- `git diff --check`

## Validation Dry-Run Helper

Status: completed locally; pending PR/CI

Goal:
- close issue #101 by consolidating repeated fake Upkeeper dry-run environment
  setup inside `tools/validate_upkeeper.sh`
- preserve stdout/stderr separation, return codes, log paths, transcript paths,
  active-lock isolation, and no-backend dry-run defaults
- keep the helper local to validation until another harness has a concrete
  contract need for it

Constraints:
- do not change runtime Upkeeper behavior
- keep per-fixture override hooks explicit for tests that intentionally vary
  CODEX_HOME, health state, active locks, metadata verbosity, or log rotation
- do not launch real backend Codex

Files likely touched:
- `tools/validate_upkeeper.sh`
- `change_notes_2026.md`
- `PLANS.md`

Validation:
- `bash -n Upkeeper lib/upkeeper/*.bash tools/*.sh tests/*.bash testruns/*.sh Upkeeper.conf configurations/default.conf`
- `tools/validate_upkeeper.sh --quick`
- `tools/validate_upkeeper.sh --full`
- `git diff --check`

## Review Module Registry

Status: completed locally; pending PR/CI

Goal:
- close issue #99 by moving P24-P30 review-module ids, aliases, prompt paths,
  titles, and help summaries into one narrow registry
- keep CLI normalization, prompt loading, help output, validation, config
  defaults, and symlinked-client behavior unchanged
- make future P31+ module additions require fewer scattered case-block edits

Constraints:
- preserve existing public flags, aliases, prompt paths, log lines, and dry-run
  behavior
- keep the registry shell-only and deterministic before backend Codex starts
- do not add a generic utility module or broaden review-module semantics

Files likely touched:
- `Upkeeper`
- `lib/upkeeper/review_modules.bash`
- `lib/upkeeper/codex_io.bash`
- `lib/upkeeper/prompt_compile.bash`
- `lib/upkeeper/help_selection.bash`
- `lib/upkeeper/README.md`
- `docs/scripts/upkeeper.md`
- `docs/compatibility.md`
- `tools/validate_upkeeper.sh`
- `change_notes_2026.md`
- `PLANS.md`

Validation:
- `bash -n Upkeeper lib/upkeeper/*.bash tools/*.sh tests/*.bash testruns/*.sh Upkeeper.conf configurations/default.conf`
- `set -e; for test_script in tests/*.bash; do bash "$test_script"; done`
- `tools/check_public_docs.sh --quick`
- `tools/validate_upkeeper.sh --quick`
- `tools/validate_upkeeper.sh --full`
- `git diff --check`

## Closed Obligation Issue Links

Status: completed locally; pending PR/CI

Goal:
- prevent open automation obligations from treating closed GitHub issues as
  valid custody
- preserve stale closed links as evidence while creating a fresh issue for the
  still-open obligation
- fail closed if an existing linked issue cannot be verified during GitHub-write
  sync

Constraints:
- keep local-only issue report generation available when GitHub writing is
  explicitly disabled
- avoid backend Codex; this is deterministic wrapper/bridge behavior
- validate with a fake `gh` command before touching live runs

Files likely touched:
- `lib/upkeeper/automation_obligations.bash`
- `tools/validate_upkeeper.sh`
- `docs/scripts/upkeeper.md`
- `lib/upkeeper/help_selection.bash`
- `change_notes_2026.md`
- `PLANS.md`

Validation:
- `bash -n Upkeeper lib/upkeeper/*.bash tools/*.sh tests/*.bash testruns/*.sh Upkeeper.conf configurations/default.conf`
- `tools/check_public_docs.sh --quick`
- `tools/validate_upkeeper.sh --quick`
- `set -e; for test_script in tests/*.bash; do bash "$test_script"; done`
- `git diff --check`

## Anomaly Custody Issue Ownership

Status: completed locally; pending PR/CI

Goal:
- stop prior-run anomaly obligations from treating umbrella issue #418 as their
  own open repair issue
- keep model-emitted Python fixture snippets from becoming live PAGE anomalies
  when the wrapper is quoting backend transcript content
- ensure obligation issue-report sync can migrate existing local records away
  from stale umbrella links into specific issue-ready records

Constraints:
- do not launch real backend Codex during validation
- preserve local-only report generation when GitHub issue writing is disabled
- keep repeated-fingerprint coalescing and expected negative-test detection
  intact

Files likely touched:
- `tools/upkeeper_anomaly_custody.py`
- `lib/upkeeper/automation_obligations.bash`
- `tools/validate_upkeeper.sh`
- `docs/scripts/upkeeper.md`
- `change_notes_2026.md`
- `PLANS.md`

Validation:
- `bash -n Upkeeper lib/upkeeper/*.bash tools/*.sh tests/*.bash testruns/*.sh Upkeeper.conf configurations/default.conf`
- `set -e; for test_script in tests/*.bash; do bash "$test_script"; done`
- `tools/check_public_docs.sh --quick`
- `tools/validate_upkeeper.sh --quick`
- `git diff --check`

## Fallback And Postmortem Guardrail Contract

Status: completed locally; pending PR/CI

Goal:
- close issue #95 by making fallback and postmortem recovery rules explicit
- document when fallback is allowed, when it is forbidden, whether it may
  mutate files, dirty-worktree behavior, child limits, disablement switches,
  quota/spend protections, evidence separation, and success criteria
- bind the documented contract with deterministic local validation so future
  behavior changes cannot silently drift

Constraints:
- do not launch real backend Codex during validation
- preserve existing fallback behavior unless documentation reveals a missing
  local guard that must be enforced
- keep clean no-op and status paths deterministic and pre-model

Files likely touched:
- `Upkeeper.conf`
- `configurations/default.conf`
- `lib/upkeeper/help_selection.bash`
- `docs/security.md`
- `docs/compatibility.md`
- `docs/scripts/upkeeper.md`
- `tools/validate_upkeeper.sh`
- `change_notes_2026.md`
- `PLANS.md`

Validation:
- `bash -n Upkeeper lib/upkeeper/*.bash tools/*.sh tests/*.bash testruns/*.sh Upkeeper.conf configurations/default.conf`
- `set -e; for test_script in tests/*.bash; do bash "$test_script"; done`
- `tools/check_public_docs.sh --quick`
- `tools/validate_upkeeper.sh --smoke`
- `tools/validate_upkeeper.sh --quick`
- `git diff --check`

## Authority Model And Control Ledger

Status: completed and merged

Goal:
- close issue #216 by adding tracked authority, capability, and control-ledger
  docs for the Upkeeper control plane
- make wrapper/model/operator authority explicit for target selection, source
  writes, shell execution, quota spend, backup restore, evidence pruning,
  GitHub issue effects, Lattice writes, and local evidence reads
- add deterministic validation that the docs and key control ids remain present

Constraints:
- document existing behavior first; do not invent unimplemented runtime gates
- keep this local and no-quota: docs plus static validation only
- keep Lattice described as evidence, not sole custody authority

Files likely touched:
- `docs/authority.md`
- `docs/capability-profiles.md`
- `docs/control-ledger.md`
- `docs/security.md`
- `docs/compatibility.md`
- `README.md`
- `tools/validate_upkeeper.sh`
- `change_notes_2026.md`
- `PLANS.md`

Validation:
- `tools/check_public_docs.sh --quick`
- `tools/validate_upkeeper.sh --smoke`
- `tools/validate_upkeeper.sh --quick`
- `git diff --check`

## Operator Status Commands

Status: completed and merged

Goal:
- close issue #90 with a scoped first version of pre-model operator status
  commands
- add human-readable and JSON status surfaces for wrapper version, repo state,
  config, last logged run, open local failure/obligation evidence, active lock,
  quota snapshot state, and basic dependency availability
- keep all status commands deterministic, local-only, and backend-free

Constraints:
- do not launch real backend Codex or acquire the active run lock for status
- keep output stable enough for scripts while avoiding raw transcript/session
  parsing beyond bounded local evidence
- document the JSON schema as a first-version local status contract

Files likely touched:
- `Upkeeper`
- `lib/upkeeper/codex_io.bash`
- `lib/upkeeper/help_selection.bash`
- `lib/upkeeper/operator_status.bash`
- `docs/scripts/upkeeper.md`
- `docs/compatibility.md`
- `change_notes_2026.md`
- `tests/wrapper_contract_test.bash`
- `tools/validate_upkeeper.sh`
- `PLANS.md`

Validation:
- `bash -n Upkeeper lib/upkeeper/*.bash tools/*.sh tests/*.bash testruns/*.sh Upkeeper.conf configurations/default.conf`
- `bash tests/wrapper_contract_test.bash`
- `tools/check_public_docs.sh --quick`
- `tools/validate_upkeeper.sh --quick`
- `./Upkeeper --status`
- `./Upkeeper --json-status`
- `./Upkeeper --last-run`
- `./Upkeeper --open-failures`
- `./Upkeeper --quota-status`
- `./Upkeeper --doctor`
- `git diff --check`

## Lattice Run-Value Rows

Status: completed and merged

Goal:
- close issue #80 by adding first-class normalized Lattice rows for run value
- preserve what changed, validation evidence, risk/finding notes, pass outcomes,
  cycle status, and evidence source without transcript scraping
- keep existing cycle, pass, import, export, and query behavior backward
  compatible

Constraints:
- local SQLite only; no backend Codex, GitHub, or network surface
- malformed or missing value markers must be rejected or skipped as evidence,
  not fatal to otherwise valid cycle recording
- avoid storing raw selected paths in the new value text field; use file joins
  or hashed evidence for path-oriented values

Files likely touched:
- `tools/upkeeper_lattice.py`
- `tests/lattice_test.bash`
- `docs/lattice.md`
- `change_notes_2026.md`
- `PLANS.md`

Validation:
- `python3 -m py_compile tools/upkeeper_lattice.py`
- `bash -n tests/lattice_test.bash`
- `bash tests/lattice_test.bash`
- `tools/check_public_docs.sh --quick`
- `tools/validate_upkeeper.sh --quick`
- `git diff --check`

## Platform Support Boundary

Status: completed and merged

Goal:
- close issue #93 by making supported operator platforms explicit
- document why macOS CI remains deferred
- make validation report the platform boundary and fail clearly on unsupported
  kernels

Constraints:
- do not claim macOS/native Windows support before the wrapper and validation
  harness are proven there
- keep the current Linux/GNU CI path unchanged
- preserve no-real-backend validation behavior

Files touched:
- `docs/dependencies.md`
- `tools/validate_upkeeper.sh`
- `change_notes_2026.md`
- `PLANS.md`

Validation:
- `bash -n tools/validate_upkeeper.sh`
- `tools/validate_upkeeper.sh --deps`
- `tools/check_public_docs.sh --quick`
- `tools/validate_upkeeper.sh --smoke`
- `git diff --check`

## Log-Line Field Builder Cleanup

Status: completed locally; pending PR/CI

Goal:
- close issue #77 by replacing risky long `log_line` source call sites with
  readable field fragments while preserving the emitted log fields
- centralize repeated startup-anomaly unresolved logging
- add deterministic validation so long log call sites do not drift back

Constraints:
- preserve existing log keys, order, redaction, and operator-visible behavior
- keep the change deterministic and local; no backend Codex validation
- avoid broad logging semantics changes outside source maintainability

Files likely touched:
- `Upkeeper`
- `lib/upkeeper/*.bash`
- `tools/validate_upkeeper.sh`
- `tests/data_protection_redaction_test.bash`
- `change_notes_2026.md`
- `PLANS.md`

Validation:
- `bash -n Upkeeper lib/upkeeper/*.bash tools/*.sh tests/*.bash testruns/*.sh Upkeeper.conf configurations/default.conf`
- `set -e; for test_script in tests/*.bash; do bash "$test_script"; done`
- `tools/validate_upkeeper.sh --quick`
- `git diff --check`

## Tracked-Only Target Selection

Status: completed and merged

Goal:
- close issue #75 by adding a backward-compatible knob for normal target
  selection to exclude non-ignored untracked files
- keep the default tracked-plus-untracked behavior unchanged
- preserve `--target-file` as the strongest one-cycle pin, including for safe
  non-ignored untracked files

Constraints:
- do not change `.upkeeperignore`, git-ignore, symlink, runtime, or source-safe
  boundaries
- keep manifest and enumerate selection deterministic and pre-model
- update operator-facing help, docs, compatibility notes, and local validation

Files likely touched:
- `Upkeeper`
- `lib/upkeeper/codex_io.bash`
- `lib/upkeeper/file_manifest.bash`
- `lib/upkeeper/help_selection.bash`
- `tools/validate_upkeeper.sh`
- `Upkeeper.conf`
- `configurations/default.conf`
- `docs/scripts/upkeeper.md`
- `docs/compatibility.md`
- `change_notes_2026.md`
- `PLANS.md`

Validation:
- `bash -n Upkeeper lib/upkeeper/*.bash tools/*.sh tests/*.bash testruns/*.sh Upkeeper.conf configurations/default.conf`
- `tools/validate_upkeeper.sh --quick`
- `tools/check_public_docs.sh --quick`
- `./Upkeeper --help`
- `git diff --check`

## Wait Plane Logging

Status: completed and merged

Goal:
- make long-running backlog and Upkeeper output say which execution plane is
  waiting: LLM/backend, GitHub checks, quota reset, local validation, or
  obligation repair
- preserve specific owner-heartbeat state instead of replacing it with generic
  `owner_process_alive` messages during long Codex/backend waits
- include elapsed wait metadata so later speed/cost work can identify which
  plane consumed time

Constraints:
- keep this deterministic and pre-model; logging must not add backend calls
- preserve existing owner-lease semantics and duplicate-run safety
- keep live output ordinary enough for an operator to read without opening
  private logs

Files likely touched:
- `orchestration/backlog.sh`
- `Upkeeper`
- `lib/upkeeper/progress_logging.bash`
- `tools/validate_upkeeper.sh`
- `docs/scripts/upkeeper.md`
- `change_notes_2026.md`
- `PLANS.md`

Validation:
- `bash -n Upkeeper lib/upkeeper/*.bash tools/*.sh tests/*.bash testruns/*.sh Upkeeper.conf configurations/default.conf orchestration/backlog.sh`
- `set -e; for test_script in tests/*.bash; do bash "$test_script"; done`
- `tools/check_public_docs.sh --quick`
- `tools/validate_upkeeper.sh --quick`
- `git diff --check`

## PR440 Stabilization And Return To Issue Work

Status: completed locally; pending PR/CI

Goal:
- get PR #440 from obligation-remediation churn to a mergeable, validated
  control-plane patch
- close the stale operator-guide validation failure from the `v1.2.33` bump
- prevent the `except Exception as exc:` source fixture PAGE line from being
  reopened by prior-run anomaly custody after live output already reclassifies it
- preserve the obligation-first contract while restoring a clean baseline so
  later backlog loops can return to ordinary GitHub issue fixes

Constraints:
- do not launch live backend Codex validation
- keep real PAGE/ERROR wrapper failures visible
- do not silently delete local obligation evidence
- update public operator docs and release notes for operator-visible behavior

Files touched:
- `tools/upkeeper_anomaly_custody.py`
- `lib/upkeeper/automation_obligations.bash`
- `tools/validate_upkeeper.sh`
- `tools/upkeeper_lattice.py`
- `tests/lattice_test.bash`
- `docs/scripts/upkeeper.md`
- `change_notes_2026.md`
- `PLANS.md`

Validation:
- `bash -n Upkeeper lib/upkeeper/*.bash tools/*.sh tests/*.bash testruns/*.sh Upkeeper.conf configurations/default.conf orchestration/backlog.sh`
- `set -e; for test_script in tests/*.bash; do bash "$test_script"; done`
- `tools/check_public_docs.sh --quick`
- `tools/validate_upkeeper.sh --quick`
- `git diff --check`

## X99 Obligation Churn Hardening

Status: completed locally; pending PR/CI

Goal:
- prevent one blocked automation obligation from consuming an entire bounded
  backlog loop after repeated unsuccessful repair attempts
- stop prior-run anomaly custody from treating model-emitted shell/test fixture
  snippets as fresh PAGE/ERROR evidence
- remove repeated backlog-local artifact warnings for the default backlog log
  and transcript directories
- reconcile stale local obligations that are deterministically obsolete after
  the repaired detector or current operator guide state

Constraints:
- keep obligation checks deterministic, local, and pre-model
- do not delete unresolved evidence; move deterministic false positives or
  obsolete findings to resolved custody with explicit reasons
- do not launch real backend Codex validation
- keep machine-health obligations ahead of ordinary GitHub issue work

Files likely touched:
- `orchestration/backlog.sh`
- `lib/upkeeper/automation_obligations.bash`
- `tools/upkeeper_anomaly_custody.py`
- `tools/validate_upkeeper.sh`
- `lib/upkeeper/help_selection.bash`
- `docs/scripts/upkeeper.md`
- `change_notes_2026.md`
- `PLANS.md`

Validation:
- `bash -n Upkeeper lib/upkeeper/*.bash tools/*.sh tests/*.bash testruns/*.sh Upkeeper.conf configurations/default.conf orchestration/backlog.sh`
- `set -e; for test_script in tests/*.bash; do bash "$test_script"; done`
- `tools/validate_upkeeper.sh --quick`
- `tools/validate_upkeeper.sh --full`
- `tools/validate_upkeeper.sh --smoke`
- `tools/stress_upkeeper_corpus.sh --local`
- `tools/check_public_docs.sh --quick`
- `./Upkeeper --help`
- `./Upkeeper --version`
- `git diff --check`

## Obligation Issue Report Bridge

Status: completed locally; pending PR/CI

Goal:
- make every current-root automation obligation produce a deterministic
  issue-ready report before normal backlog issue selection
- explain why the x99 failures stayed in local obligation custody instead of
  becoming detailed issue reports
- keep GitHub issue creation wrapper-owned and opt-in while making local issue
  reports mandatory by default
- deduplicate reports by obligation id/fingerprint and update the existing
  obligation record with report path and optional GitHub issue metadata

Constraints:
- do not require backend Codex or bug-report-only mode for system-level
  obligation reports
- preserve local evidence and redact absolute root/home paths in generated
  report text
- keep GitHub writes off unless the wrapper operator explicitly enables them
- add deterministic validation that does not touch the network

Files likely touched:
- `orchestration/backlog.sh`
- `lib/upkeeper/automation_obligations.bash`
- `tools/validate_upkeeper.sh`
- `lib/upkeeper/help_selection.bash`
- `docs/scripts/upkeeper.md`
- `docs/compatibility.md`
- `change_notes_2026.md`
- `PLANS.md`

Validation:
- `bash -n Upkeeper lib/upkeeper/*.bash tools/*.sh tests/*.bash testruns/*.sh Upkeeper.conf configurations/default.conf orchestration/backlog.sh`
- `tools/validate_upkeeper.sh --quick`
- `tools/check_public_docs.sh --quick`
- `tools/validate_upkeeper.sh --smoke`
- `tools/validate_upkeeper.sh --full`
- `set -e; for test_script in tests/*.bash; do bash "$test_script"; done`
- `git diff --check`

## Live Output Fixture Reclassification And Obligation Reset

Status: completed locally; pending PR CI

Goal:
- stop backend-emitted shell/test snippets that quote `[WARN]`, `[ERROR]`,
  `PAGE`, block markers, or startup-anomaly text from becoming fresh live
  PAGE errors or prior-run anomaly obligations
- sync the operator guide and release notes after the wrapper version bump to
  `v1.2.32`
- after the source fix is committed, perform an evidence-preserving reset of
  remaining local open obligations so the next loop starts from a clean
  post-bridge epoch

Constraints:
- preserve real runtime failures such as tracebacks and wrapper errors as
  ERROR/PAGE output
- keep the reset local and evidence-preserving; do not silently delete JSON
  obligation records
- do not launch live backend Codex for validation

Files likely touched:
- `Upkeeper`
- `tools/upkeeper_anomaly_custody.py`
- `lib/upkeeper/automation_obligations.bash`
- `tools/validate_upkeeper.sh`
- `docs/scripts/upkeeper.md`
- `change_notes_2026.md`
- `PLANS.md`

Validation:
- `bash -n Upkeeper lib/upkeeper/*.bash tools/*.sh tests/*.bash testruns/*.sh Upkeeper.conf configurations/default.conf orchestration/backlog.sh`
- `UPKEEPER_INTERNAL_LIVE_OUTPUT_CUSTODY_FILTER_SELF_TEST=1 UPKEEPER_CONFIG_DISABLE=1 ./Upkeeper`
- `python3 -m py_compile tools/upkeeper_anomaly_custody.py`
- `tools/validate_upkeeper.sh --quick`
- `set -e; for test_script in tests/*.bash; do bash "$test_script"; done`
- `tools/check_public_docs.sh --quick`
- `./Upkeeper --version`
- `./Upkeeper --help`
- `git diff --check`

## Automation Obligation Reconciliation Preflight

Status: completed locally

Goal:
- add a deterministic, pre-model reconciliation pass over open automation
  obligations immediately after backlog branch checkout and before PR, merge,
  quota, or issue-selection gates
- collapse duplicate current-root obligations into one active owner while
  preserving every duplicate as resolved evidence that points to that owner
- keep foreign-root obligations deferred and visible, not selected or deleted
- make repeated loop cycles constantly condense/upkeep the obligation queue
  before spending model work

Constraints:
- do not launch real backend Codex validation
- use only stable local fields and bounded evidence; no LLM judgment
- only resolve duplicates when their root, kind, reason, target, issue, and
  stable fingerprint/group key match
- never delete obligation evidence as part of reconciliation

Files likely touched:
- `lib/upkeeper/automation_obligations.bash`
- `orchestration/backlog.sh`
- `tools/validate_upkeeper.sh`
- `docs/scripts/upkeeper.md`
- `lib/upkeeper/help_selection.bash`
- `change_notes_2026.md`
- `PLANS.md`

Validation:
- `bash -n Upkeeper lib/upkeeper/*.bash tools/*.sh tests/*.bash testruns/*.sh Upkeeper.conf configurations/default.conf orchestration/backlog.sh`
- `set -e; for test_script in tests/*.bash; do bash "$test_script"; done`
- `tools/validate_upkeeper.sh --quick`
- `tools/validate_upkeeper.sh --full`
- `tools/stress_upkeeper_corpus.sh --local`
- `tools/check_public_docs.sh --quick`
- `./Upkeeper --help`
- `./Upkeeper --version`
- `git diff --check`

Completed in this patch:
- Added deterministic open-obligation reconciliation before PR, merge, quota,
  or issue-selection gates.
- Preserved duplicate obligation evidence under `resolved/` while updating the
  active owner with occurrence and reconciliation metadata.
- Kept foreign-root obligations visible but deferred to their owning checkout.
- Added local validation for duplicate coalescing, foreign-root preservation,
  selection after reconciliation, and private-helper field stripping.

## Automation Obligation Root Boundary

Status: completed locally

Goal:
- keep central Upkeeper from selecting stale automation obligations whose
  recorded root belongs to a temp fixture or another checkout
- preserve current-root obligation ordering and legacy empty-root compatibility
- expose deferred foreign-root counts in local selection metadata

Constraints:
- do not launch real backend Codex validation
- keep selection deterministic and pre-model
- do not delete local evidence merely because it belongs to another root

Files likely touched:
- `lib/upkeeper/automation_obligations.bash`
- `tools/validate_upkeeper.sh`
- `change_notes_2026.md`
- `PLANS.md`

Validation:
- `bash -n Upkeeper lib/upkeeper/*.bash tools/*.sh tests/*.bash testruns/*.sh Upkeeper.conf configurations/default.conf orchestration/backlog.sh`
- `tools/validate_upkeeper.sh --quick`
- `git diff --check`

Completed in this patch:
- Filtered current-root obligation selection while preserving legacy empty-root
  compatibility.
- Added `deferred_foreign_root_count` to selection output and a distinct
  `foreign_root_deferred` all-foreign status.
- Added deterministic validation for mixed current/foreign and all-foreign
  obligation sets.

## Anomaly Custody Coalescing And Obligation Commit Ownership

Status: completed locally

Goal:
- stop prior-run anomaly custody from opening a new obligation every time the
  same warning/error class appears with a new cycle id, run hash, or timestamp
- preserve occurrence counts and last-seen evidence on the stable obligation
  instead of letting local obligations flood normal work
- make blocked partial-work commits identify local automation obligations by id
  when there is no real GitHub issue number

Constraints:
- do not launch real backend Codex validation
- keep the scanner deterministic, local, and cheap before issue selection
- preserve visibility for genuinely new anomaly classes

Files likely touched:
- `tools/upkeeper_anomaly_custody.py`
- `orchestration/backlog.sh`
- `tools/validate_upkeeper.sh`
- `docs/scripts/upkeeper.md`
- `change_notes_2026.md`
- `PLANS.md`

Validation:
- `bash -n Upkeeper lib/upkeeper/*.bash tools/*.sh tests/*.bash testruns/*.sh Upkeeper.conf configurations/default.conf orchestration/backlog.sh`
- `tools/validate_upkeeper.sh --quick`
- `tools/check_public_docs.sh --quick`
- `git diff --check`

Completed in this patch:
- Added stable anomaly fingerprints that strip cycle/run/hash/temp-path noise.
- Made repeated open findings update occurrence counts and last-seen evidence
  on the existing obligation.
- Stopped `automation.obligation.open` log lines from creating secondary
  prior-run obligations.
- Fixed blocked partial-work commit messages for local automation obligations.

## Prior-Run Anomaly Custody

Status: completed locally

Goal:
- add a deterministic backlog preflight that scans recent loop output before
  normal issue selection and detects deviations from the healthy unattended-run
  shape, not only pre-characterized signatures
- write each actionable prior-run anomaly into local custody and open an
  automation obligation so the next Upkeeper pass repairs, classifies, or
  preserves it before new backlog issue work
- keep expected negative-test fixtures local and non-actionable only when their
  surrounding test success line proves they are fixture output
- preserve a cheap no-backend fast path and make the operator output state
  plainly whether anomaly custody found nothing or selected a remediation task

Constraints:
- do not launch real backend Codex validation while implementing this change
- keep the scanner deterministic, local, and safe against raw private evidence
  leakage by using bounded excerpts and runtime-only custody files
- avoid GitHub issue writes in the scanner; issue filing or source repair
  remains work for the selected repair pass

Files likely touched:
- `tools/upkeeper_anomaly_custody.py`
- `orchestration/backlog.sh`
- `lib/upkeeper/automation_obligations.bash`
- `tools/validate_upkeeper.sh`
- `lib/upkeeper/help_selection.bash`
- `docs/scripts/upkeeper.md`
- `change_notes_2026.md`
- `PLANS.md`

Validation:
- `bash -n Upkeeper lib/upkeeper/*.bash tools/*.sh tests/*.bash testruns/*.sh Upkeeper.conf configurations/default.conf orchestration/backlog.sh`
- `tools/validate_upkeeper.sh --quick`
- `tools/check_public_docs.sh --quick`
- `git diff --check`

Completed in this patch:
- Added a deterministic prior-run anomaly custody scanner for recent backlog
  loop output.
- Wired backlog preflight to open local automation obligations for actionable
  deviations before normal GitHub issue selection.
- Preserved bounded evidence packets through obligation selection and repair
  prompt generation.
- Documented and validated the new custody contract, including expected
  negative-test fixture handling.

## Issue 125 Rotation Marker Temp Hardening

Status: completed locally

Goal:
- close the remaining log-rotation marker temp-file path that could follow a
  precreated symlink during marker refresh
- keep the existing live `Upkeeper.log` no-follow append guard and rotation
  snapshot/truncate guard unchanged
- add deterministic local validation proving a symlinked marker temp path is
  rejected without modifying the outside target

Constraints:
- do not contact GitHub or launch real backend Codex validation
- keep the patch focused on issue `#125` log-path filesystem integrity
- preserve existing rotation marker semantics for trusted regular marker files

Files likely touched:
- `lib/upkeeper/log_rotation.bash`
- `tools/validate_upkeeper.sh`
- `docs/security.md`
- `change_notes_2026.md`
- `PLANS.md`

Validation:
- `bash -n Upkeeper lib/upkeeper/*.bash tools/*.sh tests/*.bash testruns/*.sh Upkeeper.conf configurations/default.conf`
- `tools/validate_upkeeper.sh --quick`
- `tools/check_public_docs.sh --quick`
- `git diff --check`

Completed in this patch:
- Replaced shell-redirection rotation marker reads/writes with a no-follow
  descriptor helper.
- Made marker refresh fail closed when the predictable temp path already exists,
  including when it is a symlink.
- Added focused regression coverage for the symlinked marker temp path and
  updated security docs plus 2026 change notes.

## Backlog Model Fixture Output Classification

Status: completed locally

Goal:
- fix issue `#428` so model-emitted `printf` fixture text containing
  timestamped `[WARN] startup_anomaly.gate` content is not rendered as a
  pageable wrapper/control-plane error
- preserve `PAGE [ERROR]` rendering for real wrapper/control-plane error lines
- keep deterministic local formatter validation for the existing echoed
  `ERROR:` case and the new `printf` warning fixture
- keep the backlog default-environment validation deterministic when the
  caller exports backlog overrides
- keep autoshelve validation isolated from any live user-level backlog owner
  lock state
- keep fallback-target tests isolated from inherited postmortem directory
  overrides
- keep fallback screen tests isolated from inherited wrapper log-file
  overrides

Constraints:
- do not contact GitHub or launch real backend Codex validation
- keep the formatter distinction local and narrow to transcript command text
- avoid weakening real wrapper/control-plane error visibility

Files likely touched:
- `orchestration/backlog.sh`
- `tools/validate_upkeeper.sh`
- `tests/bug_fix_batch_271_266_265_test.bash`
- `tests/bug_fix_batch_278_test.bash`
- `change_notes_2026.md`
- `PLANS.md`

Validation:
- `bash -n Upkeeper lib/upkeeper/*.bash tools/*.sh tests/*.bash testruns/*.sh Upkeeper.conf configurations/default.conf orchestration/backlog.sh`
- `tools/validate_upkeeper.sh --quick`
- `git diff --check`

## Manifest Path Safety Validation Alignment

Status: completed locally

Goal:
- align full validation with issue `#118` manifest path hardening so fixtures
  write custom manifests under safe runtime-local paths
- add deterministic coverage that unsafe manifest paths are rejected unless the
  explicit unsafe override is active
- update operator-facing manifest path docs for the unsafe override

Constraints:
- do not launch real backend Codex validation
- keep manifest selection deterministic and pre-model
- preserve the runtime guard; fix the stale tests instead of weakening safety

Files likely touched:
- `tools/validate_upkeeper.sh`
- `lib/upkeeper/help_selection.bash`
- `docs/scripts/upkeeper.md`
- `change_notes_2026.md`
- `PLANS.md`

Validation:
- `bash -n Upkeeper lib/upkeeper/*.bash tools/*.sh tests/*.bash testruns/*.sh Upkeeper.conf configurations/default.conf orchestration/backlog.sh`
- `tools/validate_upkeeper.sh --full`
- `tools/check_public_docs.sh --quick`
- `./Upkeeper --help`
- `git diff --check`

## Lattice Backup-First Provenance Repair

Status: completed locally

Goal:
- restore `recover --backup-first` provenance so the backup copy includes the
  recovery source and its pre-recovery backup artifact reference
- keep post-recovery local Git imports out of the backup DB, preserving the
  before/after recovery boundary
- unblock PR `#411` after an autoshelved control-plane patch removed the
  backup-side artifact reference

Constraints:
- do not launch real backend Codex validation
- keep recovery backup creation local and deterministic
- preserve the existing Lattice backup test contract

Files likely touched:
- `tools/upkeeper_lattice.py`
- `change_notes_2026.md`
- `PLANS.md`

Validation:
- `bash tests/lattice_test.bash`
- `bash -n Upkeeper lib/upkeeper/*.bash tools/*.sh tests/*.bash testruns/*.sh Upkeeper.conf configurations/default.conf orchestration/backlog.sh`
- `tools/validate_upkeeper.sh --quick`
- `git diff --check`

## Arg0 Cleanup Ownership Marker Alignment

Status: completed locally

Goal:
- align full validation and operator docs with issue `#121` behavior: stale
  `codex-arg0*` directories are deleted only when a trusted Upkeeper/Codex
  marker proves wrapper ownership
- keep unmarked matching directories out of the live arg0 root by quarantining
  them instead of deleting their contents
- unblock PR `#411` after the issue `#121` fix changed runtime behavior but
  left the validation contract expecting the old delete-any-match path

Constraints:
- do not launch real backend Codex validation
- keep the cleanup pre-model and deterministic
- preserve the no-recursion safety boundary for unknown or nested arg0 contents

Files likely touched:
- `lib/upkeeper/arg0_preflight.bash`
- `tools/validate_upkeeper.sh`
- `lib/upkeeper/help_selection.bash`
- `docs/scripts/upkeeper.md`
- `change_notes_2026.md`
- `PLANS.md`

Validation:
- `bash -n Upkeeper lib/upkeeper/*.bash tools/*.sh tests/*.bash testruns/*.sh Upkeeper.conf configurations/default.conf orchestration/backlog.sh`
- `tools/validate_upkeeper.sh --full`
- `tools/check_public_docs.sh --quick`
- `./Upkeeper --help`
- `git diff --check`

## Session Store Fail-Closed Alignment

Status: completed locally

Goal:
- align full validation, docs, and focused tests with issue `#128` behavior:
  owned weak-mode `$CODEX_HOME/sessions` directories fail closed instead of
  being chmod-repaired by Upkeeper
- keep the unpredictable session-store write probe and symlink rejection
  contracts intact
- clear PR `#410` CI after the preserved partial `#128` change

Constraints:
- do not launch real backend Codex validation
- keep local environment failures deterministic and pre-model
- document the operator-visible behavior change in current docs and notes

Files likely touched:
- `lib/upkeeper/session_store_preflight.bash`
- `tools/validate_upkeeper.sh`
- `tests/lattice_test.bash`
- `tests/session_store_preflight_test.bash`
- `docs/scripts/upkeeper.md`
- `docs/compatibility.md`
- `docs/security.md`
- `lib/upkeeper/help_selection.bash`
- `change_notes_2026.md`
- `PLANS.md`

Validation:
- `bash -n Upkeeper lib/upkeeper/*.bash tools/*.sh tests/*.bash testruns/*.sh Upkeeper.conf configurations/default.conf orchestration/backlog.sh`
- `bash tests/session_store_preflight_test.bash`
- `for test_script in tests/*.bash; do bash "$test_script"; done`
- `tools/validate_upkeeper.sh --full`
- `tools/check_public_docs.sh --quick`
- `./Upkeeper --help`
- `git diff --check`

## Backlog Batch Merge Validation Stop

Status: completed locally

Goal:
- ensure a failed local batch validation stops PR merge and cleanup even when
  the merge helper is invoked from a Bash conditional
- make the quick validator's interactive-stdio probe test a fresh launcher
  process instead of inheriting the parent backlog watch-mode state

Constraints:
- do not launch backend Codex validation
- keep validation deterministic and local

Files likely touched:
- `orchestration/backlog.sh`
- `tools/validate_upkeeper.sh`
- `change_notes_2026.md`
- `PLANS.md`

Validation:
- `bash -n Upkeeper lib/upkeeper/*.bash tools/*.sh tests/*.bash testruns/*.sh Upkeeper.conf configurations/default.conf orchestration/backlog.sh`
- `tools/validate_upkeeper.sh --quick`
- `git diff --check`

## Backlog Validation Gate And Lattice Snapshot Privacy Repair

Status: completed locally

Goal:
- make backlog per-bug and batch validation failures stop the commit path even
  when the commit helper is invoked from an `if` condition
- repair the issue `#141` Lattice snapshot change so opt-in worktree path
  inventory remains HMAC-only while still supporting cycle-local round-trip
  checks and delta event recording
- unblock PR `#410` by fixing the current `tests/lattice_test.bash` failure

Constraints:
- do not launch real backend Codex validation
- keep raw worktree path inventory out of `worktree_snapshot_paths`
- keep the backlog PR-check gate stopping before new issue selection when CI
  fails
- add deterministic local validation so this commit-gate regression cannot
  silently return

Files likely touched:
- `orchestration/backlog.sh`
- `tools/upkeeper_lattice.py`
- `tools/validate_upkeeper.sh`
- `change_notes_2026.md`
- `PLANS.md`

Validation:
- `bash -n Upkeeper lib/upkeeper/*.bash tools/*.sh tests/*.bash testruns/*.sh Upkeeper.conf configurations/default.conf orchestration/backlog.sh`
- `bash tests/lattice_test.bash`
- `tools/validate_upkeeper.sh --quick`
- `tools/check_public_docs.sh --quick`
- `git diff --check`

## Backend Usage Limit Cooldown

Status: completed locally

Goal:
- classify backend "usage limit" startup exits as quota exhaustion instead of a
  missing status-marker contract failure
- write a hard local quota cooldown marker from the backend-provided reset time
  so unattended backlog loops stop retrying the exhausted model
- make backlog honor hard backend usage-limit markers even when burn-mode quota
  guardrail bypass is enabled
- avoid opening target-repair automation obligations for machine-local backend
  quota exhaustion

Constraints:
- keep the detection deterministic and local to wrapper transcript/session
  evidence
- do not launch real backend Codex validation
- preserve existing missing-marker failures for empty successful output and
  other malformed model responses
- keep normal burn-mode quota bypass behavior for soft projected quota
  guardrails

Files likely touched:
- `Upkeeper`
- `lib/upkeeper/status_session.bash`
- `lib/upkeeper/quota_block_markers.bash`
- `lib/upkeeper/automation_obligations.bash`
- `orchestration/backlog.sh`
- `tools/validate_upkeeper.sh`
- `docs/scripts/upkeeper.md`
- `lib/upkeeper/help_selection.bash`
- `change_notes_2026.md`
- `PLANS.md`

Validation:
- `bash -n Upkeeper lib/upkeeper/*.bash tools/*.sh tests/*.bash testruns/*.sh Upkeeper.conf configurations/default.conf orchestration/backlog.sh`
- focused fake-backend usage-limit validation through `tools/validate_upkeeper.sh --quick`
- `tools/check_public_docs.sh --quick`
- `git diff --check`

## Backlog Live Output Attention Emphasis

Status: completed locally

Goal:
- make interactive backlog `PAGE` lines visually harder to miss by coloring the
  timestamp red, and coloring/blinking both the block and `PAGE` marker text
- strengthen interactive `PAGE` lines by rendering the timestamp as bright white
  on a red background, making the non-error payload text bright white, and
  highlighting the `ERROR` text inside `[ERROR]` with the same red/blink style
  as the `PAGE` marker
- make interactive backlog `--FYI--` lines color the timestamp orange and color
  the marker text bold orange
- add local-only green job start/finish summary blocks so operators can see
  what the current cycle is doing and how it ended without model involvement
- defer issue-targeted no-change cycles locally so already-addressed issues do
  not repeat forever on the same backlog branch
- keep loop logs and non-color output free of ANSI sequences for scripts and
  assistive tooling

Constraints:
- preserve `BACKLOG_ALERT_COLOR` and `BACKLOG_ALERT_BLINK`
- keep blink off timestamps
- keep green job summaries deterministic and local to the launcher
- preserve open GitHub issues when a no-change cycle is only branch-local
  evidence
- keep the existing visual block and marker taxonomy

Files likely touched:
- `orchestration/backlog.sh`
- `tools/validate_upkeeper.sh`
- `docs/scripts/upkeeper.md`
- `lib/upkeeper/help_selection.bash`
- `change_notes_2026.md`
- `PLANS.md`

Validation:
- `bash -n orchestration/backlog.sh tools/validate_upkeeper.sh lib/upkeeper/help_selection.bash`
- `bash -n Upkeeper lib/upkeeper/*.bash tools/*.sh tests/*.bash testruns/*.sh Upkeeper.conf configurations/default.conf orchestration/backlog.sh`
- `tools/validate_upkeeper.sh --quick`
- `tools/check_public_docs.sh --quick`
- `git diff --check`

## Lattice Redacted JSONL Import Guard

Status: completed locally

Goal:
- restore default JSONL import rejection for any row carrying `path-sha256:`
  redacted path markers
- reject malformed or truncated redacted path markers as sensitive instead of
  requiring a syntactically complete 64-hex token before default imports fail
- keep explicit `--anonymized-archive` as the opt-in path for importing
  anonymized exports

Constraints:
- keep the fix local to Lattice import/redaction detection
- do not launch backend Codex validation
- preserve normal full-length redacted-token detection behavior

Files likely touched:
- `tools/upkeeper_lattice.py`
- `change_notes_2026.md`
- `PLANS.md`

Validation:
- `python3 -m py_compile tools/upkeeper_lattice.py`
- `bash tests/lattice_test.bash`
- `git diff --check`

## Lattice Unanchored Source Record Identity Guard

Status: completed locally

Goal:
- keep imported line/source evidence idempotent when it has a deterministic
  path/line/hash identity
- prevent unrelated local wrapper observations with no path, no line, and no
  raw/parsed hash from collapsing into one `source_records` row
- add deterministic regression coverage for unanchored source observations

Constraints:
- keep the fix local and focused on Lattice source-record identity
- do not launch backend Codex validation
- preserve the newly repaired bounded Lattice unavailable logging path

Files likely touched:
- `tools/upkeeper_lattice.py`
- `tests/lattice_test.bash`
- `change_notes_2026.md`
- `PLANS.md`

Validation:
- `python3 -m py_compile tools/upkeeper_lattice.py`
- `bash tests/lattice_test.bash`
- `git diff --check`

## Backlog Autoshelve Local Remediation

Status: completed locally

Goal:
- prevent backlog loops from autoshelving dirty Upkeeper control-plane fixes and
  then continuing on stale wrapper code
- preserve unrelated dirty local work on the autoshelve branch while promoting
  wrapper/source/test/docs changes that are part of the local remediation bundle
  back onto the active backlog branch automatically
- keep Lattice unavailable terminal/log output bounded while preserving the full
  doctor/init payload in private local recovery evidence

Constraints:
- keep the remediation deterministic, local-only, and pre-model
- do not launch backend Codex validation
- fail closed only when the local control-plane transplant cannot be applied
  cleanly, and leave the autoshelve branch as evidence
- avoid logging raw Lattice JSON walls to normal terminal/watch output

Files likely touched:
- `orchestration/backlog.sh`
- `lib/upkeeper/lattice.bash`
- `tools/validate_upkeeper.sh`
- `tests/lattice_test.bash`
- `docs/scripts/upkeeper.md`
- `lib/upkeeper/help_selection.bash`
- `change_notes_2026.md`
- `PLANS.md`

Validation:
- `bash -n Upkeeper lib/upkeeper/*.bash tools/*.sh tests/*.bash testruns/*.sh Upkeeper.conf configurations/default.conf orchestration/backlog.sh`
- `for test_script in tests/*.bash; do bash "$test_script"; done`
- `tools/check_public_docs.sh --quick`
- `tools/validate_upkeeper.sh --quick`
- `tools/validate_upkeeper.sh --smoke`
- `./Upkeeper --help`
- `git diff --check`

## Lattice Source Record Identity And Outcome Compatibility

Status: completed locally

Goal:
- recover the latest failed loop by fixing the Lattice integrity failure around
  report-only review outcome parsing
- finish the local `source_records` identity work so repeated imported evidence
  can update an existing row without collapsing unrelated wrapper observations
- preserve the documented final-prose `REVIEWED_*` compatibility contract while
  still rejecting quoted, fenced, or prose-only outcome examples

Constraints:
- keep the fix local and deterministic; do not launch backend Codex validation
- keep runtime recovery files, logs, transcripts, manifests, and SQLite files
  as local evidence only
- avoid broad schema churn beyond the existing additive `source_records`
  identity columns

Files likely touched:
- `tools/upkeeper_lattice.py`
- `tests/lattice_test.bash`
- `change_notes_2026.md`
- `PLANS.md`

Validation:
- `python3 -m py_compile tools/upkeeper_lattice.py`
- `bash tests/lattice_test.bash`
- `bash -n Upkeeper lib/upkeeper/*.bash tools/*.sh tests/*.bash testruns/*.sh Upkeeper.conf configurations/default.conf`
- `for test_script in tests/*.bash; do bash "$test_script"; done`
- `tools/check_public_docs.sh --quick`
- `tools/validate_upkeeper.sh --quick`
- `tools/validate_upkeeper.sh --smoke`
- `git diff --check`

## Model Output Redaction Boundary

Status: completed

Goal:
- fix issue `#292` by treating model-derived transcript/status/review text as
  tainted before it reaches operator logs or terminal progress
- keep protected raw transcript artifacts available for local evidence while
  default summaries use redacted classes, HMAC path labels, and safe snippets
- cover live output, transcript signals, review summaries, terminal finales, and
  malformed status-marker candidate logs

Constraints:
- do not remove raw protected transcripts or full diagnostic modes
- keep wrapper-owned structured fields useful for operators
- avoid broad rewrites; add a reusable redaction helper and apply it at sinks
- add deterministic no-backend validation with fake secrets, private paths, and
  model prose

Files likely touched:
- `lib/upkeeper/runtime_foundation.bash`
- `lib/upkeeper/transcript_output.bash`
- `lib/upkeeper/report_analysis.bash`
- `Upkeeper`
- `tools/validate_upkeeper.sh`
- `change_notes_2026.md`
- `PLANS.md`

Validation:
- `bash -n Upkeeper lib/upkeeper/*.bash tools/*.sh tests/*.bash testruns/*.sh Upkeeper.conf configurations/default.conf`
- focused transcript/review redaction validator checks
- `tools/validate_upkeeper.sh --quick`
- `git diff --check`
- `for test_script in tests/*.bash; do bash "$test_script"; done`
- `tools/check_public_docs.sh --quick`
- `tools/validate_upkeeper.sh --smoke`

## Backlog Visual Status Block

Status: completed locally; pending PR/CI

Goal:
- add a single visual block column to backlog watch output so loose terminal
  watching can classify state by peripheral color before reading the marker text
- keep the plain marker column for scripts, logs, and assistive tooling
- preserve `PAGE` blink/red behavior while adding logical colors for `OK`,
  `INFO`, `--FYI--`, `RUN`, `ACTION`, `WAIT`, `WORKER`, and `HEALTH`

Constraints:
- do not add ANSI color to the mirrored loop log
- keep `NO_COLOR`, `BACKLOG_ALERT_COLOR`, and `BACKLOG_ALERT_BLINK` semantics
- keep old timestamped/marked log lines parseable during transition

Validation:
- `bash -n orchestration/backlog.sh tools/validate_upkeeper.sh`
- `tools/validate_upkeeper.sh --quick`
- `tools/check_public_docs.sh --quick`
- `tools/validate_upkeeper.sh --smoke`
- `for test_script in tests/*.bash; do bash "$test_script"; done`
- `./Upkeeper --help`
- `./Upkeeper --version`
- `git diff --check`

## Backlog Local Supervisor Lease

Status: completed

Goal:
- make `orchestration/backlog.sh` safe to invoke repeatedly while one primary
  backlog owner holds the checkout
- keep the primary loop alive through local waits such as PR checks and quota
  hibernation instead of requiring a human restart
- let secondary invocations perform a cheap local duplicate/health check, exit
  cleanly when the owner is healthy, and reclaim the owner lease when it is
  stale

Constraints:
- keep the supervisor local-only, deterministic, and no-backend
- preserve the existing PID/start-tick protection against stale PID reuse
- make heartbeat updates truthful by checking the recorded owner identity before
  each refresh
- preserve the interactive watch-mode operator experience while preventing
  concurrent checkout mutation

Files likely touched:
- `orchestration/backlog.sh`
- `tools/validate_upkeeper.sh`
- `change_notes_2026.md`
- `PLANS.md`

Validation:
- `bash -n Upkeeper lib/upkeeper/*.bash tools/*.sh tests/*.bash testruns/*.sh Upkeeper.conf configurations/default.conf orchestration/backlog.sh`
- `for test_script in tests/*.bash; do bash "$test_script"; done`
- `tools/validate_upkeeper.sh --quick`
- `git diff --check`

## Worktree Snapshot Privacy And Status Marker Recovery

Status: completed

Goal:
- fix issue `#303` by making Lattice worktree snapshots count dirty paths by
  default without persisting raw dirty/untracked path inventory
- recover final `UPKEEPER_STATUS` markers when the only defect is harmless
  inline markdown backticks, avoiding repeated `MISSING_STATUS_MARKER` loop
  stops after completed model work

Constraints:
- keep raw path inventory opt-in and store HMACs/classes rather than raw paths
- do not link opt-in worktree snapshot rows to raw `files`/`file_paths` entries
- keep ambiguous, code-fenced, punctuated, quoted, and multiple-marker final
  lines rejected
- use focused tests plus quick validation for fast loop restart readiness

Files likely touched:
- `lib/upkeeper/status_session.bash`
- `lib/upkeeper/worktree_state.bash`
- `tools/upkeeper_lattice.py`
- `tests/bug_fix_batch_280_281_265_test.bash`
- `tests/lattice_test.bash`
- `docs/lattice.md`
- `change_notes_2026.md`
- `PLANS.md`

Validation:
- `bash tests/bug_fix_batch_280_281_265_test.bash`
- `bash tests/wrapper_contract_test.bash`
- `bash tests/lattice_test.bash`
- `tools/validate_upkeeper.sh --quick`
- `git diff --check`

## Lattice Git Status XY Preservation

Status: completed

Goal:
Fix issue `#246` by making Lattice preserve the two-column Git porcelain XY
status for live metadata and worktree snapshots, including leading-space
unstaged-only states.

Constraints:
- Use raw `git status --porcelain=v1 -z` parsing for machine status data.
- Preserve current stored display convention where spaces become `_` in
  candidate/live metadata.
- Keep raw snapshot status evidence intact for replay and delta calculations.
- Work in an isolated worktree so normal backlog loops can use the main
  checkout.

Files likely touched:
- `tools/upkeeper_lattice.py`
- `tests/lattice_test.bash`
- `change_notes_2026.md`
- `PLANS.md`

Validation:
- `bash tests/lattice_test.bash`
- `tools/validate_upkeeper.sh --quick`
- `git diff --check`

## Lattice JSONL Conflict Detection

Status: completed

Goal:
Fix issue `#247` so `import-jsonl` never treats a same-logical-key,
different-payload row as a duplicate. Incoming row hashes must be validated
first, and only an existing payload hash that matches the incoming semantic
payload may count as a duplicate.

Constraints:
- Preserve idempotent replay of identical JSONL exports.
- Preserve existing conflict reporting through `lattice_import_conflicts`.
- Keep the fix deterministic and local; no backend Codex validation.
- Work in an isolated worktree while the backlog loop owns the main checkout.

Files likely touched:
- `tools/upkeeper_lattice.py`
- `tests/lattice_test.bash`
- `change_notes_2026.md`
- `PLANS.md`

Validation:
- `bash tests/lattice_test.bash`
- `tools/validate_upkeeper.sh --quick`
- `git diff --check`

## Backlog Spark Burn Defaults

Status: completed

Goal:
Flip the backlog launcher back to the Spark quota bucket for reset-window bug
burn-down runs, including bypass of stale local quota evidence that would
otherwise defer before the first post-reset backend call can refresh quota state.

Constraints:
- Keep the change limited to backlog launcher defaults and matching public notes.
- Preserve operator overrides for model, reasoning effort, and quota thresholds.
- Do not weaken machine-health, backup, or normal local validation checks.

Files likely touched:
- `orchestration/backlog.sh`
- `tools/validate_upkeeper.sh`
- `lib/upkeeper/help_selection.bash`
- `docs/scripts/upkeeper.md`
- `change_notes_2026.md`
- `PLANS.md`

Validation:
- `bash -n orchestration/backlog.sh tools/validate_upkeeper.sh lib/upkeeper/help_selection.bash`
- `tools/validate_upkeeper.sh --quick`
- `git diff --check`

## Backlog Pageable Alert Markers

Status: completed

Goal:
Add an operator-visible second-column alert taxonomy to backlog watch output so
normal worker command failures, quota waits, blocked/deferred issues, health
checks, and true operator-pageable failures are visually and scriptably distinct.

Constraints:
- Keep `loop.log` plain text and parseable; color must be terminal-only.
- Preserve the interactive watch-mode stdin cutoff and live mirroring behavior.
- Treat `PAGE` as the only "human/system attention now" class.
- Keep recent-activity parsing compatible with old timestamped logs and new
  timestamp-plus-marker logs.

Files likely touched:
- `orchestration/backlog.sh`
- `tools/validate_upkeeper.sh`
- `lib/upkeeper/help_selection.bash`
- `docs/scripts/upkeeper.md`
- `change_notes_2026.md`
- `PLANS.md`

Validation:
- `bash -n Upkeeper lib/upkeeper/*.bash tools/*.sh tests/*.bash testruns/*.sh Upkeeper.conf configurations/default.conf orchestration/backlog.sh`
- `tools/check_public_docs.sh --quick`
- `tools/validate_upkeeper.sh --quick`
- `git diff --check`

## Quota Metadata Redaction

Status: completed

Goal:
Fix issue `#300` by reducing quota/session metadata exposure in operator logs,
quota cooldown markers, postmortem context, and related Lattice-facing
validation.

Constraints:
- Keep the patch narrow to quota/privacy surfaces and deterministic local
  validation.
- Preserve quota guardrail decisions and startup-anomaly review behavior.
- Default behavior should minimize durable quota/account detail exposure, while
  explicit verbose/debug mode may retain fuller protected local diagnostics.

Files likely touched:
- `Upkeeper`
- `lib/upkeeper/quota_block_markers.bash`
- `lib/upkeeper/postmortem_context.bash`
- `lib/upkeeper/aux_codex.bash`
- `tests/quota_block_markers_test.bash`
- `tests/lattice_test.bash`
- `docs/scripts/upkeeper.md`
- `docs/security.md`
- `change_notes_2026.md`
- `PLANS.md`

Validation:
- `bash -n Upkeeper lib/upkeeper/*.bash tools/*.sh tests/*.bash testruns/*.sh Upkeeper.conf configurations/default.conf`
- `for test_script in tests/*.bash; do bash "$test_script"; done`
- `tools/check_public_docs.sh --quick`
- `tools/validate_upkeeper.sh --quick`
- `git diff --check`

## Quota Hibernation For Backlog Loops

Status: completed

Goal:
Fix issue `#383` by making the backlog launcher hibernate on valid quota
guardrail stops instead of letting a quota-constrained Upkeeper child terminate
the parent loop.

Constraints:
- Keep the behavior deterministic and no-backend while hibernating.
- Preserve fail-closed behavior for malformed or unsafe hibernation inputs.
- Keep operator output plain: blocked bucket, reset time, wake time, and reason.
- Do not touch the live `/main` backlog checkout; this work is isolated in a
  separate worktree.

Files likely touched:
- `orchestration/backlog.sh`
- `tools/validate_upkeeper.sh`
- `docs/scripts/upkeeper.md`
- `change_notes_2026.md`
- `PLANS.md`

Validation:
- `bash -n Upkeeper lib/upkeeper/*.bash tools/*.sh tests/*.bash testruns/*.sh Upkeeper.conf configurations/default.conf orchestration/backlog.sh`
- focused backlog quota hibernation validation
- `tools/check_public_docs.sh --quick`
- `tools/validate_upkeeper.sh --quick`
- `git diff --check`

## Prompt Rough Edge Lint

Status: completed

Goal:
Fix issue `#91` by cleaning known public prompt rough edges and adding a
deterministic banned-phrase guard.

Constraints:
- Keep the patch narrow to prompt wording and local validation.
- Do not restructure the large prompt files in this pass.
- Preserve prompt behavior while removing obvious incomplete/typo text.

Files likely touched:
- `prompts/default-review.md`
- `prompts/caretaking_23_items.md`
- `tools/validate_upkeeper.sh`
- `change_notes_2026.md`
- `PLANS.md`

Validation:
- `tools/check_public_docs.sh --quick`
- `tools/validate_upkeeper.sh --quick`
- `git diff --check`

## Client Link Tools

Status: completed

Goal:
Fix issue `#89` by adding safe client install, update, uninstall, and doctor
helpers for the central-first symlink workflow.

Constraints:
- Keep helpers no-backend and deterministic.
- Refuse overwriting existing client files unless the operator explicitly opts
  into the unsafe action.
- Prefer local `.git/info/exclude` ignores over tracked client-repo churn.
- Avoid touching the root wrapper while the active backlog PR is touching it.

Files likely touched:
- `tools/upkeeper_client_link_common.sh`
- `tools/install_client_link.sh`
- `tools/update_client_link.sh`
- `tools/uninstall_client_link.sh`
- `tools/doctor_upkeeper.sh`
- `tests/client_link_tools_test.bash`
- `README.md`
- `docs/scripts/upkeeper.md`
- `change_notes_2026.md`
- `PLANS.md`

Validation:
- `bash -n Upkeeper lib/upkeeper/*.bash tools/*.sh tests/*.bash testruns/*.sh Upkeeper.conf configurations/default.conf`
- `for test_script in tests/*.bash; do bash "$test_script"; done`
- `tools/check_public_docs.sh --quick`
- `tools/validate_upkeeper.sh --quick`
- `git diff --check`

## Governance Docs

Status: completed

Goal:
Fix issue `#88` by adding tracked governance docs for ownership, durable
decisions, and high-impact risks.

Constraints:
- Documentation-only; no runtime behavior changes.
- Keep roles lightweight and suitable for a maintainer-led project.
- Capture the seed decisions and risks from the issue in tracked source.

Files likely touched:
- `docs/ownership.md`
- `docs/decisions/README.md`
- `docs/decisions/0001-upkeeper-baseline-contracts.md`
- `docs/risk-register.md`
- `README.md`
- `tools/validate_upkeeper.sh`
- `change_notes_2026.md`
- `PLANS.md`

Validation:
- `tools/check_public_docs.sh --quick`
- `tools/validate_upkeeper.sh --quick`
- `git diff --check`

## Release-Readiness Docs

Status: completed

Goal:
Fix issue `#87` by adding first-class tracked release-readiness entry points:
product requirements, roadmap, release checklist, and known issues.

Constraints:
- Keep this documentation-only; do not change runtime behavior.
- Link release/readiness docs from README so future runs can find them without
  private chat history.
- Add cheap validator coverage for document presence and README links.

Files likely touched:
- `docs/prd.md`
- `docs/roadmap.md`
- `docs/release-checklist.md`
- `docs/known-issues.md`
- `README.md`
- `tools/validate_upkeeper.sh`
- `change_notes_2026.md`
- `PLANS.md`

Validation:
- `tools/check_public_docs.sh --quick`
- `tools/validate_upkeeper.sh --quick`
- `git diff --check`

## jq Dependency Guidance

Status: completed

Goal:
Fix issue `#86` by making the `jq` dependency decision explicit, adding
portable install guidance, and pointing missing-dependency diagnostics at the
tracked dependency docs.

Constraints:
- Keep `jq` required for now because runtime JSON bridge code and validation
  fixtures still use it directly.
- Do not refactor JSON assignment bridges to Python in this patch.
- Preserve no-quota validation behavior.

Files likely touched:
- `docs/dependencies.md`
- `docs/security.md`
- `README.md`
- `lib/upkeeper/codex_io.bash`
- `tools/validate_upkeeper.sh`
- `change_notes_2026.md`
- `PLANS.md`

Validation:
- `bash -n Upkeeper lib/upkeeper/*.bash tools/*.sh tests/*.bash testruns/*.sh Upkeeper.conf configurations/default.conf`
- `for test_script in tests/*.bash; do bash "$test_script"; done`
- `tools/validate_upkeeper.sh --deps`
- `tools/check_public_docs.sh --quick`
- `tools/validate_upkeeper.sh --quick`
- `git diff --check`

## Fault-Injection Injector Catalog

Status: completed

Goal:
Fix issue `#85` by documenting deterministic injector mechanisms, flakiness
bans, and the stress-corpus boundary for P31 fault-injection work.

Constraints:
- Documentation-only behavior clarification; no new runtime injection harness in
  this patch.
- Keep P31 reserved and unwired as a review module.
- Preserve the split between focused single-surface fault injection and
  multi-repo stress-corpus shape coverage.

Files likely touched:
- `docs/fault-injection-scenarios.md`
- `docs/stress-corpus.md`
- `prompts/p31-fault-injection-review.md`
- `tools/validate_upkeeper.sh`
- `change_notes_2026.md`
- `PLANS.md`

Validation:
- `tools/check_public_docs.sh --quick`
- `tools/validate_upkeeper.sh --quick`
- `git diff --check`

## First Fault-Injection Fixtures

Status: completed

Goal:
Fix issue `#84` by adding the first deterministic no-quota fault-injection
fixtures and a reusable wrapper log-invariant checker.

Constraints:
- Do not run real backend Codex or spend quota.
- Keep scenarios in local validation, with explicit control/injection/recovery
  shape and oracle classes.
- Avoid live backlog PR overlap in `Upkeeper`, `lib/upkeeper/file_manifest.bash`,
  and `tools/upkeeper_lattice.py`.

Files likely touched:
- `tools/validate_upkeeper.sh`
- `tools/check_upkeeper_log_invariants.py`
- `docs/fault-injection-scenarios.md`
- `docs/stress-corpus.md`
- `change_notes_2026.md`
- `PLANS.md`

Validation:
- `bash -n Upkeeper lib/upkeeper/*.bash tools/*.sh tests/*.bash testruns/*.sh Upkeeper.conf configurations/default.conf`
- `for test_script in tests/*.bash; do bash "$test_script"; done`
- `tools/check_public_docs.sh --quick`
- `tools/validate_upkeeper.sh --quick`
- `tools/validate_upkeeper.sh --full`
- `git diff --check`

## Fault-Injection Scenario Registry

Status: completed

Goal:
Fix issue `#83` by adding a tracked fault-injection scenario registry with
stable ids, required registry columns, FMEA-style priority fields, and deferred
initial rows for the major Upkeeper fault surfaces.

Constraints:
- Keep this as a documentation/registry contract, not executable injection
  implementation.
- Use stable ids that a future Lattice import can consume without guessing.
- Add validator checks for required columns, priority fields, and required
  surface coverage.

Files likely touched:
- `docs/fault-injection-scenarios.md`
- `README.md`
- `prompts/p31-fault-injection-review.md`
- `tools/validate_upkeeper.sh`
- `change_notes_2026.md`
- `PLANS.md`

Validation:
- `tools/check_public_docs.sh --quick`
- `tools/validate_upkeeper.sh --quick`
- `git diff --check`

## Fault-Injection Review Contract

Status: completed

Goal:
Fix issue `#82` by adding the future P31 fault-injection review contract as a
tracked prompt artifact with explicit fault model, oracle, containment, and
recovery-proof requirements.

Constraints:
- Do not wire `--review-module=p31` in this patch; that is separate
  implementation work after the numbering decision.
- Keep the prompt deterministic and bounded: not fuzzing, not mutation testing,
  and not source-mutating test-the-tests behavior.
- Add validator coverage for the mandatory contract terms so the design does
  not drift before wiring.

Files likely touched:
- `prompts/p31-fault-injection-review.md`
- `prompts/README.md`
- `README.md`
- `tools/validate_upkeeper.sh`
- `change_notes_2026.md`
- `PLANS.md`

Validation:
- `tools/check_public_docs.sh --quick`
- `tools/validate_upkeeper.sh --quick`
- `git diff --check`

## Review Module Numbering Compatibility

Status: completed

Goal:
Fix issue `#81` by documenting that P29 remains reuse harvesting, P30 remains
Stark Protocol hardening, and future fault-injection work should use P31 or a
new non-breaking named module instead of reusing the public P29 flag.

Constraints:
- Preserve existing `--p29`, `--review-module=p29`, and reuse-harvesting aliases.
- Do not implement the fault-injection module in this decision patch.
- Keep README, operator guide, prompt index, compatibility docs, validation,
  and release notes aligned.

Files likely touched:
- `README.md`
- `docs/compatibility.md`
- `docs/scripts/upkeeper.md`
- `prompts/README.md`
- `tools/validate_upkeeper.sh`
- `change_notes_2026.md`
- `PLANS.md`

Validation:
- `tools/check_public_docs.sh --quick`
- `tools/validate_upkeeper.sh --smoke`
- `tools/validate_upkeeper.sh --quick`
- `./Upkeeper --help`
- `git diff --check`

## Wrapper Contract Focused Tests

Status: completed

Goal:
Fix issue `#76` by moving several critical wrapper contracts into focused,
independently runnable no-backend tests instead of relying only on the monolithic
validator body.

Constraints:
- Avoid files currently owned by the live backlog branch (`Upkeeper`,
  `lib/upkeeper/file_manifest.bash`, and `tools/upkeeper_lattice.py`).
- Keep new tests runnable through `bash tests/*.bash` without backend quota,
  network, or wrapper dry-runs.
- Preserve validator coverage while delegating covered contracts to the focused
  test script.

Files likely touched:
- `tests/wrapper_contract_test.bash`
- `tools/validate_upkeeper.sh`
- `change_notes_2026.md`
- `PLANS.md`

Validation:
- `bash -n Upkeeper lib/upkeeper/*.bash tools/*.sh tests/*.bash testruns/*.sh Upkeeper.conf configurations/default.conf`
- `bash tests/wrapper_contract_test.bash`
- `for test_script in tests/*.bash; do bash "$test_script"; done`
- `tools/validate_upkeeper.sh --quick`
- `tools/validate_upkeeper.sh --full`
- `tools/check_public_docs.sh --quick`
- `git diff --check`

## Quick Validation Boundary

Status: completed

Goal:
Fix issue `#68` by making `tools/validate_upkeeper.sh --quick` a fast bounded
static/fixture gate instead of running the heavier wrapper dry-run integration
suite, while keeping full no-quota coverage available under `--full`.

Constraints:
- Preserve `--full` as the deterministic release/CI integration gate with no
  real backend Codex calls.
- Keep `--quick` useful for local edit-loop/release preflight work and free of
  unbounded wrapper dry-runs.
- Add explicit bounded-check support so timeout failures name the specific
  validation check that exceeded its budget.
- Update CI/docs/help/release notes so operators know which mode is fast and
  which mode is comprehensive.

Files likely touched:
- `tools/validate_upkeeper.sh`
- `.github/workflows/ci.yml`
- `README.md`
- `docs/scripts/upkeeper.md`
- `docs/dependencies.md`
- `docs/stress-corpus.md`
- `lib/upkeeper/help_selection.bash`
- `change_notes_2026.md`
- `PLANS.md`

Validation:
- `bash -n Upkeeper lib/upkeeper/*.bash tools/*.sh tests/*.bash testruns/*.sh Upkeeper.conf configurations/default.conf`
- `tools/validate_upkeeper.sh --smoke`
- `tools/validate_upkeeper.sh --quick`
- `tools/validate_upkeeper.sh --full`
- `tools/check_public_docs.sh --quick`
- `git diff --check`

## Startup Anomaly Watch Summary

Status: completed

Goal:
Replace normal terminal bursts of repeated `previous_run.anomaly` warnings with
one operator-readable startup anomaly summary while preserving detailed prior-run
and state evidence for prompt context and diagnostic verbosity.

Constraints:
- Keep startup anomaly gating fail-closed; this is an output-shaping fix, not a
  demotion of machine-health obligations.
- Preserve full local evidence in existing logs/state files and in
  `PREVIOUS_RUN_ANOMALIES` so the self-review prompt still receives concrete
  anomaly detail.
- Emit per-anomaly replays only for diagnostic terminal modes, not ordinary
  backlog watch output.
- Add deterministic validation so the same warning-burst regression cannot come
  back unnoticed.

Files likely touched:
- `lib/upkeeper/previous_run_anomalies.bash`
- `tools/validate_upkeeper.sh`
- `tools/stress_upkeeper_corpus.sh`
- `lib/upkeeper/help_selection.bash`
- `docs/scripts/upkeeper.md`
- `change_notes_2026.md`
- `PLANS.md`

Validation:
- `bash -n Upkeeper lib/upkeeper/*.bash tools/*.sh tests/*.bash testruns/*.sh Upkeeper.conf configurations/default.conf`
- `tools/validate_upkeeper.sh --quick`
- `tools/stress_upkeeper_corpus.sh --local`
- `tools/check_public_docs.sh --quick`
- `git diff --check`

## P30 Stark Protocol Review Module

Status: completed

Goal:
Add P30 as a first-class opt-in review module for permanent hardening: each
observed weakness must either be removed, guarded by deterministic validation,
documented as an invariant, or left as an explicit blocked follow-up instead of
being allowed to fail the same way again.

Constraints:
- Treat P30 as public operator behavior, not just a local prompt file.
- Keep it opt-in through review-module flags while including it in full-burn
  and max-cover review-module bundles.
- Preserve existing P24-P29 behavior and aliases.
- Keep deterministic local validation no-quota and make P30 wiring
  non-regressible through help, docs, prompt, Lattice, completion, launcher, and
  test checks.

Files likely touched:
- `Upkeeper`
- `lib/upkeeper/codex_io.bash`
- `lib/upkeeper/prompt_compile.bash`
- `lib/upkeeper/help_selection.bash`
- `lib/upkeeper/lattice.bash`
- `tools/upkeeper_lattice.py`
- `tools/validate_upkeeper.sh`
- `tools/check_public_docs.sh`
- `prompts/p30-stark-protocol-review.md`
- `prompts/README.md`
- `README.md`
- `docs/scripts/upkeeper.md`
- `docs/compatibility.md`
- `docs/public-documentation-policy.md`
- `FlameOn`
- `ChimneySweep`
- `completions/upkeeper.bash`
- `testruns/all_p_modules_once.sh`
- `testruns/all_p_modules_600s.sh`
- `tests/chimneysweep_test.bash`
- `tests/flameon_test.bash`
- `tests/lattice_test.bash`
- `change_notes_2026.md`
- `PLANS.md`

Validation:
- `bash -n Upkeeper lib/upkeeper/*.bash tools/*.sh tests/*.bash testruns/*.sh Upkeeper.conf configurations/default.conf`
- `for test_script in tests/*.bash; do bash "$test_script"; done`
- `tools/check_public_docs.sh --quick`
- `tools/validate_upkeeper.sh --quick`
- `./Upkeeper --help`
- `./Upkeeper --version`
- `git diff --check`

## Pre-Contact Backup Machine Bootstrap And Fail-Closed Hardening

Status: completed

Goal:
Keep selected-target pre-contact backup fail-closed by default unless encrypted
backup is available, require an explicit unsafe operator override before any
plaintext backup path can run, and add a portable machine-local bootstrap plus
early preflight so missing age prerequisites stop live cycles before issue
selection.

Constraints:
- Keep the patch focused on the pre-contact backup contract surfaced by issue
  `#289` plus the resulting machine-health bootstrap gap.
- Preserve encrypted age backups and existing restore behavior.
- Allow plaintext backups only through an explicit unsafe opt-in, with an
  additional high-confidence sensitive-content gate before writing `.bak`
  artifacts.
- Keep private age identities and machine-local recipients out of tracked repo
  config while making the bootstrap path central for symlinked clients.
- Fail live mutating cycles closed before issue selection when required backup
  prerequisites are missing, and classify that state as machine-health/operator
  setup instead of an in-progress target-file issue fix.
- Update operator-visible defaults, bootstrap docs, compatibility notes, and
  release notes in the same committed state because plain `./Upkeeper` runs
  without `age` now stop before backend launch.

Files likely touched:
- `Upkeeper`
- `lib/upkeeper/precontact_backup.bash`
- `lib/upkeeper/automation_obligations.bash`
- `lib/upkeeper/help_selection.bash`
- `orchestration/backlog.sh`
- `Upkeeper.conf`
- `configurations/default.conf`
- `tools/upkeeper_precontact_bootstrap.sh`
- `tests/precontact_backup_test.bash`
- `docs/scripts/upkeeper.md`
- `docs/security.md`
- `docs/dependencies.md`
- `docs/compatibility.md`
- `change_notes_2026.md`
- `PLANS.md`

Validation:
- `bash -n Upkeeper lib/upkeeper/*.bash tools/*.sh tests/*.bash testruns/*.sh Upkeeper.conf configurations/default.conf`
- `bash tests/precontact_backup_test.bash`
- `for test_script in tests/*.bash; do bash "$test_script"; done`
- `./Upkeeper --help`
- `tools/check_public_docs.sh --quick`
- `tools/validate_upkeeper.sh --quick`
- `git diff --check`

## Backlog Dirty-Worktree Autoshelve

Status: completed

Goal:
Let `orchestration/backlog.sh` preserve unrelated local wrapper work
automatically before issue work starts, so a live backlog loop can recover from
operator-side dirty state without sweeping that state into the next issue
commit.

Constraints:
- Preserve the per-cycle clean-baseline rule; no new issue run should begin on
  top of an uncommitted dirty tree.
- Do not auto-open a PR blindly from a backlog branch, because that can stack
  unrelated backlog fixes into the wrong review.
- Keep the preservation path local and explicit: capture the dirty state in a
  dedicated shelve branch, then return to the original branch clean.
- Add deterministic local validation for the autoshelve path.

Files likely touched:
- `orchestration/backlog.sh`
- `tools/validate_upkeeper.sh`
- `change_notes_2026.md`
- `PLANS.md`

Validation:
- `bash -n Upkeeper lib/upkeeper/*.bash tools/*.sh tests/*.bash testruns/*.sh Upkeeper.conf configurations/default.conf orchestration/backlog.sh orchestration/backlog_loop.sh`
- `for test_script in tests/*.bash; do bash "$test_script"; done`
- `tools/check_public_docs.sh --quick`
- `tools/validate_upkeeper.sh --quick`
- `git diff --check`

## Lattice Export Privacy And Import Roundtrip

Status: completed

Goal:
Keep the new privacy-default `export-jsonl` / `import-jsonl` contract for
issues `#304` and `#305` without breaking deterministic local lattice
roundtrip validation or leaving the backlog PR dirty against current `main`.

Constraints:
- Default exports should stay privacy-preserving for ordinary operator use.
- Roundtrip/import-rebuild validation should explicitly request path disclosure
  when it needs full-fidelity structural replay.
- Structural classifier fields such as `source_kind` must not be path-redacted.
- Refresh the focused lattice docs, release notes, and backlog branch state so
  the PR no longer carries already-merged launcher churn.

Files likely touched:
- `tools/upkeeper_lattice.py`
- `tests/lattice_test.bash`
- `docs/lattice.md`
- `change_notes_2026.md`
- `PLANS.md`

Validation:
- `bash -n Upkeeper lib/upkeeper/*.bash tools/*.sh tests/*.bash testruns/*.sh Upkeeper.conf configurations/default.conf`
- `bash tests/lattice_test.bash`
- `for test_script in tests/*.bash; do bash "$test_script"; done`
- `tools/check_public_docs.sh --quick`
- `tools/validate_upkeeper.sh --quick`
- `git diff --check`

## Backlog Interactive TTY Input Hardening

Status: completed

Goal:
Stop unattended backlog output from being able to turn into interactive shell
input, and stop issue-target inference from handing excluded runtime artifacts
to Upkeeper as explicit review targets.

Constraints:
- Auto-detach direct `backlog.sh` invocations attached to an interactive stdin,
  stdout, or stderr unless an operator explicitly opts out for a one-shot
  diagnostic run.
- Provide a safe loop launcher that detaches stdin and records backlog output in
  a private log file instead of streaming model/status text into the terminal.
- Keep issue-target handling compatible for valid explicit repo files while
  rejecting obvious runtime/log/.git targets before preselection.
- Refresh operator docs, release notes, and deterministic local validation.
- Keep the full symlinked-client wrapper/migration behavior out of this hotfix;
  this change only hardens the central backlog launcher path.

Files likely touched:
- `orchestration/backlog.sh`
- `orchestration/backlog_loop.sh`
- `lib/upkeeper/codex_io.bash`
- `tools/upkeeper_lattice.py`
- `tools/validate_upkeeper.sh`
- `tools/stress_upkeeper_corpus.sh`
- `docs/scripts/upkeeper.md`
- `change_notes_2026.md`
- `PLANS.md`

Validation:
- `bash -n Upkeeper lib/upkeeper/*.bash tools/*.sh tests/*.bash testruns/*.sh Upkeeper.conf configurations/default.conf orchestration/backlog.sh orchestration/backlog_loop.sh`
- `tools/validate_upkeeper.sh --quick`
- `bash tests/lattice_test.bash`
- `tools/stress_upkeeper_corpus.sh --local`
- `tools/check_public_docs.sh --quick`
- `git diff --check`

## Backlog Interactive Watch Mode

Status: completed

Goal:
Make direct interactive backlog use safe and operator-friendly by keeping live
output visible in the terminal while cutting off stdin feedback, and by making
repeat invocations attach to the already-running backlog job for the same repo
instead of acting like a new run.

Constraints:
- Preserve the original safety goal: no interactive stdin should remain
  attached to a live backlog cycle unless an operator explicitly opts out.
- Keep a fully detached path available through `orchestration/backlog_loop.sh`
  and an explicit launcher mode override.
- Make repeated interactive invocations explain that another backlog run already
  owns the checkout and show that run's activity instead of failing opaquely.
- Refresh operator docs, release notes, and deterministic local validation for
  the new default behavior.

Files likely touched:
- `orchestration/backlog.sh`
- `orchestration/backlog_loop.sh`
- `tools/validate_upkeeper.sh`
- `docs/scripts/upkeeper.md`
- `change_notes_2026.md`
- `PLANS.md`

Validation:
- `bash -n Upkeeper lib/upkeeper/*.bash tools/*.sh tests/*.bash testruns/*.sh Upkeeper.conf configurations/default.conf orchestration/backlog.sh orchestration/backlog_loop.sh`
- `for test_script in tests/*.bash; do bash "$test_script"; done`
- `tools/check_public_docs.sh --quick`
- `tools/validate_upkeeper.sh --quick`
- `git diff --check`

## Backlog Timestamped Watch Feed And Lattice Doctor Probe

Status: completed

Goal:
Keep direct backlog loop watching human-readable and machine-safe by giving the
live terminal/feed log a local ISO timestamp in column 1, while restoring
`tools/upkeeper_lattice.py doctor` to a single JSON document after its internal
probe started printing command JSON.

Constraints:
- Preserve safe interactive watch mode: stdin stays cut off, output stays live,
  and the private loop log remains the followable source of truth.
- Timestamp both wrapper-generated lines and raw child-process lines without
  double-prefixing lines that already begin with an ISO timestamp.
- Keep recent-activity parsing compatible with old raw loop logs and new
  timestamped loop logs.
- Keep `doctor` output machine-readable; internal self-probes must not leak
  command output onto stdout.

Files likely touched:
- `orchestration/backlog.sh`
- `orchestration/backlog_loop.sh`
- `lib/upkeeper/file_manifest.bash`
- `lib/upkeeper/help_selection.bash`
- `tools/upkeeper_lattice.py`
- `tools/validate_upkeeper.sh`
- `tests/lattice_test.bash`
- `docs/scripts/upkeeper.md`
- `change_notes_2026.md`
- `PLANS.md`

Validation:
- `bash -n Upkeeper lib/upkeeper/*.bash tools/*.sh tests/*.bash testruns/*.sh Upkeeper.conf configurations/default.conf orchestration/backlog.sh orchestration/backlog_loop.sh`
- `bash tests/lattice_test.bash`
- `for test_script in tests/*.bash; do bash "$test_script"; done`
- `tools/check_public_docs.sh --quick`
- `tools/validate_upkeeper.sh --quick`
- `git diff --check`

Completed in this patch:
- Timestamped direct backlog watch notices and stream output, plus detached
  loop-wrapper log output, while avoiding duplicate prefixes on existing
  timestamped lines.
- Updated backlog recent-activity parsing and validator probes for timestamped
  loop logs.
- Restored single-document Lattice `doctor` JSON output and aligned the
  colon-bearing target test with the current rejected-substitution contract.
- Refreshed operator-facing docs/help/release notes and the manifest validator
  contract for repo-relative manifest paths.

## Disk Preflight Prompt and Log Redaction

Status: completed

Goal:
Stop disk-space startup anomaly handling from sending raw paths, probe paths,
and mount metadata to the model while preserving actionable local diagnostics
for operators.

Constraints:
- Keep the fix narrow to the disk-preflight and prompt-compilation flow.
- Preserve the startup anomaly gate and operator-facing low-space signal.
- Keep raw prompt notes limited to safe labels and percentages only.
- Keep local log evidence useful, but default path and mount fields to hashes
  unless an explicit diagnostic mode is enabled.
- Add deterministic local validation for both the prompt contract and the local
  log contract.

Files likely touched:
- `lib/upkeeper/disk_preflight.bash`
- `lib/upkeeper/help_selection.bash`
- `tools/validate_upkeeper.sh`
- `docs/scripts/upkeeper.md`
- `change_notes_2026.md`
- `PLANS.md`

Validation:
- `bash -n Upkeeper lib/upkeeper/*.bash tools/*.sh tests/*.bash testruns/*.sh Upkeeper.conf configurations/default.conf`
- `for test_script in tests/*.bash; do bash "$test_script"; done`
- `git diff --check`
- `tools/validate_upkeeper.sh --quick`

Completed in this patch:
- Redacted disk-preflight path, probe-path, and mount log fields by default,
  while allowing raw shell-quoted values only in explicit diagnostic modes.
- Reduced `DISK_SPACE_PROMPT_NOTE` to label-and-percentage-only anomaly notes
  so startup prompts no longer leak local mount/path metadata to the model.
- Added deterministic quick-validation coverage for the new disk-preflight log
  and prompt-note contracts, and refreshed the mirrored operator docs.

## Import-Upkeeper-Log Parsed Field Redaction

Status: completed

Goal:
Stop `lattice import-upkeeper-log` from persisting sensitive parsed log fields
into `source_records.parsed_json` and adjacent normalized cycle fields when raw
line import is disabled.

Constraints:
- Keep the patch narrow to the lattice importer and its focused validation.
- Preserve useful lifecycle import fields needed for sparse replay and status
  reconstruction.
- Default to allowlisting safe parsed fields instead of trying to redact every
  possible sensitive key after storage.
- Keep validation deterministic and local.

Files likely touched:
- `tools/upkeeper_lattice.py`
- `tests/lattice_test.bash`
- `change_notes_2026.md`
- `PLANS.md`

Validation:
- `bash -n Upkeeper lib/upkeeper/*.bash tools/*.sh tests/*.bash testruns/*.sh Upkeeper.conf configurations/default.conf`
- `for test_script in tests/*.bash; do bash "$test_script"; done`
- `git diff --check`
- `tools/validate_upkeeper.sh --quick`

Completed in this patch:
- Limited imported `source_records.parsed_json` for Upkeeper log rows to a
  small safe allowlist instead of storing full parsed key/value payloads.
- Stopped `import-upkeeper-log` from backfilling sensitive normalized cycle
  fields such as selected paths, finish reasons, model/mode, and config-file
  values from log text.
- Added a focused lattice test proving sensitive parsed keys are dropped while
  sparse lifecycle status reconstruction still works.

## Default Prompt Replacement Authority Removal

Status: completed

Goal:
Remove the last conflicting replacement-target instruction from the default
prompt so compiled prompt text no longer reintroduces unbacked replacement
authority after the wrapper has established selected-target isolation.

Constraints:
- Preserve replacement selection only for prompt contexts that truly do not
  include `WRAPPER_PRESELECTED_REVIEW_TARGET`.
- Preserve `STOPPED_ON_BLOCKER` guidance for preselected-target cycles.
- Add deterministic local validation so the unconditional replacement wording
  cannot drift back into `prompts/default-review.md`.

Files likely touched:
- `prompts/default-review.md`
- `tools/validate_upkeeper.sh`
- `change_notes_2026.md`
- `PLANS.md`

Validation:
- `bash -n Upkeeper lib/upkeeper/*.bash tools/*.sh tests/*.bash testruns/*.sh Upkeeper.conf configurations/default.conf`
- `for test_script in tests/*.bash; do bash "$test_script"; done`
- `git diff --check`
- `tools/validate_upkeeper.sh --quick`

Completed in this patch:
- Removed the unconditional "select the next oldest eligible file" wording from
  the default prompt's physical/safety exception branch.
- Made replacement selection explicitly conditional on the absence of
  `WRAPPER_PRESELECTED_REVIEW_TARGET`.
- Added quick validation that fails if the default prompt regains unconditional
  replacement-target authority.

## Private Artifact Umask At Entry

Status: completed

Goal:
Set a private process umask before config loading or runtime artifact creation
so filesystem sinks default to owner-only permissions even on permissive host
umask settings.

Constraints:
- Apply the change at the main `Upkeeper` entrypoint before other executable
  statements that may create files or directories.
- Keep the fix broad and low-risk; do not refactor every individual artifact
  sink in the same patch.
- Add deterministic local validation that fails if the entrypoint loses the
  private umask contract.

Files likely touched:
- `Upkeeper`
- `tools/validate_upkeeper.sh`
- `change_notes_2026.md`
- `PLANS.md`

Validation:
- `bash -n Upkeeper lib/upkeeper/*.bash tools/*.sh tests/*.bash testruns/*.sh Upkeeper.conf configurations/default.conf`
- `for test_script in tests/*.bash; do bash "$test_script"; done`
- `git diff --check`
- `tools/validate_upkeeper.sh --quick`

Completed in this patch:
- Set `umask 077` at the top of the `Upkeeper` entrypoint before config loading
  and runtime state preparation.
- Added quick validation that locks the early-entry private-umask contract in
  source so permissive-host regressions fail locally.

## Target-Isolated Write Boundary For Preselected Cycles

Status: completed

Goal:
Remove prompt-authorized multi-file write scope from normal preselected review
cycles so selected-target pre-contact backup coverage matches the model write
authority actually granted for the cycle.

Constraints:
- Keep non-selected repository files readable for context during a selected-file
  review.
- Keep replacement target selection wrapper-owned and fail closed through
  `BLOCKED` reporting when additional edits are required.
- Avoid broad backup-scope expansion in this fix; treat selected-target-only
  write authority as the binding isolation contract.
- Keep validation deterministic and local.

Files likely touched:
- `lib/upkeeper/help_selection.bash`
- `tests/precontact_backup_test.bash`
- `change_notes_2026.md`
- `PLANS.md`

Validation:
- `bash -n Upkeeper lib/upkeeper/*.bash tools/*.sh tests/*.bash testruns/*.sh Upkeeper.conf configurations/default.conf`
- `for test_script in tests/*.bash; do bash "$test_script"; done`
- `git diff --check`
- `tools/validate_upkeeper.sh --quick`

Completed in this patch:
- Made the preselected-target prompt block explicitly binding for
  selected-target-only writes.
- Allowed read-only contextual inspection of non-selected repository files while
  requiring `BLOCKED` plus `ADDITIONAL_FILES_NEEDED:` when a correct fix would
  require extra file edits.
- Declared any later paired-edit prompt/module guidance subordinate to the
  selected-target backup boundary.

## Log Self-Review Target Boundary

Status: completed

Goal:
Remove the remaining log-self-review prompt exception that let a cycle patch
unselected Upkeeper control-plane files even though only the selected target
had pre-contact backup coverage.

Constraints:
- Keep current-cycle log review mandatory.
- Preserve log-review reporting for wrapper defects discovered during the cycle.
- Require follow-up wrapper-selected work instead of same-pass unselected
  self-repair for control-plane files.
- Keep validation deterministic and local.

Files likely touched:
- `lib/upkeeper/prompt_compile.bash`
- `tools/validate_upkeeper.sh`
- `change_notes_2026.md`
- `PLANS.md`

Validation:
- `bash -n Upkeeper lib/upkeeper/*.bash tools/*.sh tests/*.bash testruns/*.sh Upkeeper.conf configurations/default.conf`
- `for test_script in tests/*.bash; do bash "$test_script"; done`
- `git diff --check`
- `tools/validate_upkeeper.sh --quick`

Completed in this patch:
- Removed the last log-self-review permission to repair unselected Upkeeper
  control-plane files during a selected-target cycle.
- Required `BLOCKED` reporting with the affected repo-relative path when log
  review finds a wrapper defect outside the selected target.
- Added quick validation that locks the stricter prompt contract in source.

## Pre-Contact Backup Log Path Redaction

Status: completed

Goal:
Stop pre-contact backup runtime logs from writing the raw selected relative
target path while claiming the path was redacted.

Constraints:
- Keep protected metadata and restore behavior intact.
- Preserve enough runtime evidence to correlate backup and restore activity
  without exposing the raw target name.
- Cover create and adjacent failure/restore logging paths together so the same
  leak does not survive in neighboring branches.
- Keep validation deterministic and local.

Files likely touched:
- `lib/upkeeper/precontact_backup.bash`
- `tests/precontact_backup_test.bash`
- `change_notes_2026.md`
- `PLANS.md`

Validation:
- `bash -n Upkeeper lib/upkeeper/*.bash tools/*.sh tests/*.bash testruns/*.sh Upkeeper.conf configurations/default.conf`
- `for test_script in tests/*.bash; do bash "$test_script"; done`
- `git diff --check`
- `tools/validate_upkeeper.sh --quick`

Completed in this patch:
- Replaced raw selected-target paths in pre-contact backup create, failure, and
  restore log paths with a stable `target_hash`.
- Kept `path_redacted=1` aligned with reality by removing the raw repo-relative
  target path from those log lines.
- Added deterministic tests proving create and restore logs no longer leak the
  selected relative path.

## Sensitive Target Denylist Before Prompt Launch

Status: completed

Goal:
Fail closed on common secret-bearing target paths before pre-contact backup,
prompt compilation, or backend launch can treat them as ordinary review files.

Constraints:
- Keep the deny gate independent of `.upkeeperignore`.
- Trigger before prompt compilation and regardless of whether backup mode later
  resolves to off, plain, or age.
- Start with deterministic path-pattern coverage for common secret-bearing
  files; do not depend on broad entropy scanning in this patch.
- Keep validation deterministic and local.

Files likely touched:
- `lib/upkeeper/precontact_backup.bash`
- `tests/precontact_backup_test.bash`
- `change_notes_2026.md`
- `PLANS.md`

Validation:
- `bash -n Upkeeper lib/upkeeper/*.bash tools/*.sh tests/*.bash testruns/*.sh Upkeeper.conf configurations/default.conf`
- `for test_script in tests/*.bash; do bash "$test_script"; done`
- `git diff --check`
- `tools/validate_upkeeper.sh --quick`

Completed in this patch:
- Added a built-in sensitive-target denylist to pre-contact target validation
  for common secret-bearing paths such as `.env*`, credential dotfiles,
  kubeconfig, SSH private key names, and private-key extensions.
- Made the deny gate run before prompt compilation and backend launch even when
  pre-contact backup mode is later disabled.
- Added deterministic local coverage for the denylist through
  `tests/precontact_backup_test.bash`.

## Restore Mode Applied After Rename

Status: completed

Goal:
Keep temporary restore files private at `0600` until the final restore rename,
then apply the restored file mode to the destination path.

Constraints:
- Preserve randomized restore temp names under the destination directory.
- Preserve content-hash verification before rename.
- Apply the recorded destination mode only after the final move succeeds.
- Keep validation deterministic and local.

Files likely touched:
- `lib/upkeeper/precontact_backup.bash`
- `tests/precontact_backup_test.bash`
- `change_notes_2026.md`
- `PLANS.md`

Validation:
- `bash -n Upkeeper lib/upkeeper/*.bash tools/*.sh tests/*.bash testruns/*.sh Upkeeper.conf configurations/default.conf`
- `for test_script in tests/*.bash; do bash "$test_script"; done`
- `git diff --check`
- `tools/validate_upkeeper.sh --quick`

Completed in this patch:
- Moved restore-mode application from the temporary restore file to the final
  destination after rename.
- Kept the restore temp file on the safer private mode created by `mktemp`
  until the move completes.
- Added deterministic local coverage that inspects the temp-file mode at the
  rename boundary and the final restored destination mode.

## Security Hardening Batch: Fallback Chain Token

Status: in_progress

Goal:
Bind fallback handoff inheritance to an unguessable child token plus parent lock
identity so nested fallback cycles cannot be forged through env-only metadata.

Constraints:
- Keep fallback behavior compatible for normal handoff cases.
- Preserve the same fallback-stop and screen-fallback invocation paths.
- Keep token generation local to runtime and avoid command-line persistence.

Files likely touched:
- `lib/upkeeper/runtime_foundation.bash`
- `lib/upkeeper/active_lock.bash`
- `lib/upkeeper/fallback_orchestration.bash`
- `lib/upkeeper/fallback_screen.bash`

Validation:
- `tools/validate_upkeeper.sh --quick`
- `git diff --check`

## Security Hardening Batch: Lattice DB Safety

Status: in_progress

Goal:
Close remaining high-severity Lattice filesystem-safety gaps by hardening DB path
checking consistently before SQLite open across wrapper command surfaces.

Constraints:
- Preserve `--allow-unsafe-db` escape-hatch semantics.
- Keep behavior deterministic and fail-closed by default for unsafe DB paths.
- Keep ordinary command and recovery code paths aligned under the same safety policy.
- Minimize behavior changes to Lattice path-safety scope.

Files likely touched:
- `tools/upkeeper_lattice.py`
- `PLANS.md`

Validation:
- `tools/validate_upkeeper.sh --quick` (or equivalent targeted local checks)
- `git diff --check`

## Docs-Only Validation Fast Path

Status: completed

Goal:
Cut the end-to-end cost of docs-only changes such as the README airlock update
by avoiding duplicate CI runs and by keeping docs-only validation on the smoke
path instead of the broader quick integration path.

Constraints:
- Preserve `--quick` as the broad deterministic gate for runtime and mixed
  changes.
- Keep docs-only CI no-quota and local-first.
- Avoid duplicate branch-push and pull-request CI for the same PR iteration.
- Keep public docs and validation guidance aligned with the cheaper docs-only
  path.

Files likely touched:
- `.github/workflows/ci.yml`
- `AGENTS.md`
- `README.md`
- `docs/dependencies.md`
- `docs/scripts/upkeeper.md`
- `tools/check_public_docs.sh`
- `change_notes_2026.md`
- `PLANS.md`

Validation:
- `tools/check_public_docs.sh --quick`
- `tools/validate_upkeeper.sh --quick`
- `git diff --check`

Completed in this patch:
- Limited CI `push` runs to `main` so PR branches no longer pay for duplicate
  branch-push and pull-request workflows.
- Added a docs-only CI classifier that runs `tools/validate_upkeeper.sh --smoke`
  instead of `--quick`.
- Updated AGENTS and public docs so docs-only local validation uses the smoke
  path.

## No-Op Trust Contract

Status: completed

Goal:
Document the binding unattended-run contract: machine health outranks workload,
no prior automation failure may escape oversight, and the perfect healthy run is
a correct fast no-op that exits without backend work when nothing remains to
repair.

Constraints:
- Keep this as a documentation and decision-contract change only.
- Do not weaken the existing obligation-first launcher behavior.
- Make the AGENTS guidance explicit enough that future design arguments with the
  maintainer treat the contract as a hard constraint.
- Keep public docs understandable without private chat context.

Files likely touched:
- `AGENTS.md`
- `README.md`
- `docs/scripts/upkeeper.md`
- `docs/compatibility.md`
- `change_notes_2026.md`
- `PLANS.md`

Validation:
- `tools/check_public_docs.sh --quick`
- `tools/validate_upkeeper.sh --quick`
- `git diff --check`

Completed in this patch:
- Added the trust/no-op contract to `AGENTS.md`.
- Documented the operator-facing contract in README, compatibility notes, and
  the Upkeeper operator guide.
- Added 2026 release-note coverage for the contract.

## Fallback Postmortem Exit Propagation

Status: completed

Goal:
Prevent successful fallback/postmortem recovery from being reported as a
synthetic `FALLBACK_CHAIN_EXIT` failure solely because `run_postmortem_sequence`
forced a non-zero return after successful report and hardening phases.

Constraints:
- Preserve non-zero returns for missing postmortem markers, quota/environment
  skips, and failed report or hardening phases.
- Preserve fallback child exit propagation as the final recovery outcome.
- Keep validation local and deterministic.

Files likely touched:
- `lib/upkeeper/postmortem_sequence.bash`
- `tools/validate_upkeeper.sh`
- `docs/scripts/upkeeper.md`
- `docs/compatibility.md`
- `change_notes_2026.md`
- `PLANS.md`

Validation:
- `bash -n Upkeeper lib/upkeeper/*.bash tools/*.sh tests/*.bash testruns/*.sh Upkeeper.conf configurations/default.conf`
- `for test_script in tests/*.bash; do bash "$test_script"; done`
- `tools/check_public_docs.sh --quick`
- `tools/validate_upkeeper.sh --quick`
- `git diff --check`

Completed in this patch:
- Made successful postmortem sequences return the fallback child exit instead of
  forcing `7`.
- Added quick validation for successful report-plus-hardening marker flow.
- Updated operator docs, compatibility notes, and release notes for the outcome
  propagation contract.

## Prompt Pass Coverage Enforcement

Status: completed

Goal:
Fail closed when an `--prompt-pass=all` run finishes without parseable pass
coverage evidence, so automation obligations and launcher loops do not treat a
coverage-blind final report as clean.

Constraints:
- Preserve additive `UPKEEPER_PASS_RESULT` behavior for normal runs.
- Keep malformed pass-result lines as rejected Lattice evidence instead of
  silently counting them as clean coverage.
- Accept common Markdown decoration around `UPKEEPER_PASS_RESULT` lines so the
  parser matches real model output.
- Keep validation local and deterministic; do not run backend Codex validation.

Files likely touched:
- `Upkeeper`
- `lib/upkeeper/report_analysis.bash`
- `tools/validate_upkeeper.sh`
- `README.md`
- `docs/scripts/upkeeper.md`
- `docs/compatibility.md`
- `docs/lattice.md`
- `change_notes_2026.md`
- `PLANS.md`

Validation:
- `bash -n Upkeeper lib/upkeeper/*.bash tools/*.sh tests/*.bash testruns/*.sh Upkeeper.conf configurations/default.conf`
- `for test_script in tests/*.bash; do bash "$test_script"; done`
- `tools/check_public_docs.sh --quick`
- `tools/validate_upkeeper.sh --quick`
- `git diff --check`

Completed in this patch:
- Made `review_pass_coverage_json` count real `UPKEEPER_PASS_RESULT` lines,
  including common Markdown-decorated forms.
- Added a shared prompt-pass coverage gate that logs expected/present/missing
  counts and fails closed for incomplete or unavailable all-pass evidence.
- Made `Upkeeper` override a reported clean status to `BLOCKED` when
  `--prompt-pass=all` coverage is missing or incomplete.
- Added quick validation for decorated pass-result parsing and the fail-closed
  all-pass enforcement path.
- Updated public docs, compatibility notes, Lattice notes, and 2026 change
  notes for the new enforcement contract.

## Launcher Model Override Expansion

Status: completed

Goal:
Make the shared Upkeeper model override contract cover the Spark quota bucket
used for dogfood runs, and let FlameOn/ChimneySweep accept direct model flags
instead of requiring operators to remember launcher-specific environment
variables.

Constraints:
- Preserve existing `5.5_xhigh` behavior.
- Keep launchers on named Upkeeper override specs so every staged backend
  invocation receives the same locked model/effort pair.
- Keep unsupported model/effort pairs fail-closed before backend launch.
- Keep validation local and deterministic.

Files likely touched:
- `lib/upkeeper/codex_io.bash`
- `lib/upkeeper/launcher_full_burn.bash`
- `FlameOn`
- `ChimneySweep`
- `completions/upkeeper.bash`
- `tests/flameon_test.bash`
- `tests/chimneysweep_test.bash`
- `tools/validate_upkeeper.sh`
- `README.md`
- `docs/scripts/upkeeper.md`
- `docs/compatibility.md`
- `change_notes_2026.md`

Validation:
- `bash -n Upkeeper lib/upkeeper/*.bash tools/*.sh tests/*.bash testruns/*.sh Upkeeper.conf configurations/default.conf`
- `for test_script in tests/*.bash; do bash "$test_script"; done`
- `tools/check_public_docs.sh --quick`
- `tools/validate_upkeeper.sh --quick`
- `git diff --check`

Completed in this patch:
- Added `5.3-codex-spark_xhigh` as a supported shared Upkeeper model override.
- Added model/effort shortcut parsing to FlameOn and ChimneySweep.
- Updated Bash completion, launcher tests, help text, operator docs,
  compatibility notes, and release notes for the new override surface.

## Local Validation Speed Layer

Status: completed

Goal:
Add a local-only speed layer that shortens edit-loop feedback without removing
any existing quick/full validation coverage.

Constraints:
- Keep `--quick` and `--full` behavior intact as the broad deterministic gates.
- Do not launch real backend Codex work.
- Make timings visible so future optimization work is evidence-driven.
- Keep docs and compatibility notes aligned with the new validation surface.

Files likely touched:
- `tools/validate_upkeeper.sh`
- `README.md`
- `docs/scripts/upkeeper.md`
- `docs/dependencies.md`
- `docs/compatibility.md`
- `change_notes_2026.md`
- `PLANS.md`

Validation:
- `tools/validate_upkeeper.sh --smoke --profile`
- `bash -n Upkeeper lib/upkeeper/*.bash tools/*.sh tests/*.bash testruns/*.sh Upkeeper.conf configurations/default.conf`
- `for test_script in tests/*.bash; do bash "$test_script"; done`
- `tools/check_public_docs.sh --quick`
- `tools/validate_upkeeper.sh --quick`
- `git diff --check`

Completed in this patch:
- Added `tools/validate_upkeeper.sh --smoke` as the fast local edit-loop gate.
- Added `--profile` timing output for validation checks without changing
  coverage.
- Kept review-module, config-file, manifest, issue-workflow, Lattice, and
  failure-path fixtures in `--quick`/`--full`.
- Updated README, operator docs, dependency docs, compatibility notes, and
  release notes for the new validation workflow.

## Automation Obligation Framework

Status: completed

Goal:
Add one shared Upkeeper-owned automation accounting framework so root Upkeeper,
FlameOn, ChimneySweep, and future derivatives all write the same durable run
ledger and unresolved-obligation records. Focused launchers should supply
identity and policy only; they should not own separate state formats.

Constraints:
- Keep the framework local and deterministic under ignored `runtime/` state.
- Do not require GitHub, Lattice, or backend Codex to record run/obligation
  evidence.
- Preserve existing launcher behavior while adding shared identity fields.
- Make non-zero cycle exits create durable obligations with enough target and
  launcher context for later reconciliation work.
- Keep validation no-quota and local.

Files likely touched:
- `Upkeeper`
- `FlameOn`
- `ChimneySweep`
- `lib/upkeeper/automation_obligations.bash`
- `lib/upkeeper/cycle_cleanup_signals.bash`
- `lib/upkeeper/launcher_full_burn.bash`
- `lib/upkeeper/help_selection.bash`
- `lib/upkeeper/README.md`
- `tools/validate_upkeeper.sh`
- `tests/flameon_test.bash`
- `tests/chimneysweep_test.bash`
- `docs/scripts/upkeeper.md`
- `docs/compatibility.md`
- `docs/security.md`
- `change_notes_2026.md`
- `PLANS.md`

Validation:
- `bash -n Upkeeper lib/upkeeper/*.bash tools/*.sh tests/*.bash testruns/*.sh Upkeeper.conf configurations/default.conf`
- `for test_script in tests/*.bash; do bash "$test_script"; done`
- `tools/check_public_docs.sh --quick`
- `tools/validate_upkeeper.sh --quick`
- `git diff --check`

Completed in this patch:
- Added `lib/upkeeper/automation_obligations.bash` as the shared local
  automation run and obligation record owner.
- Wired Upkeeper cycle start/finish to write durable run records and create
  unresolved obligations for non-zero cycle exits.
- Added shared launcher identity/policy fields so FlameOn and ChimneySweep use
  the same framework instead of separate state formats.
- Made FlameOn and ChimneySweep reconcile open obligations before normal
  bug-finding or GitHub issue selection, passing the selected obligation to
  Upkeeper as a locked target plus wrapper-generated prompt file.
- Added successful selected-obligation resolution so a clean non-dry-run cycle
  moves the obligation from `open` to `resolved`.
- Extended quick validation with a local fixture that proves run records are
  finalized, a blocked ChimneySweep-style cycle opens one obligation, the
  selector/prompt-file handoff works, and a clean selected-obligation cycle
  resolves it.
- Updated help, operator docs, compatibility notes, security notes, module
  ownership docs, tests, and 2026 change notes.

## Run-Set System Catch-Up

Status: completed

Goal:
Fix system issues exposed by the live ChimneySweep run set after issue 128:
owned `$CODEX_HOME/sessions` directories with weak inherited permissions should
be repaired before probing instead of stranding all later runs, and review
summary logs should preserve the wrapper-selected target when the model final
message omits it.

Constraints:
- Preserve the session preflight stdout contract: `ok` or one compact failure
  reason.
- Keep rejecting symlinked, non-directory, and wrong-owner session stores before
  any write probe.
- Do not let the review-summary parser invent a selected file from unrelated
  final-message prose; only use the wrapper's locked target as fallback when the
  parsed selected file is absent.
- Keep validation local and deterministic; do not run backend Codex validation.

Files likely touched:
- `lib/upkeeper/session_store_preflight.bash`
- `lib/upkeeper/report_analysis.bash`
- `tools/validate_upkeeper.sh`
- `docs/scripts/upkeeper.md`
- `docs/security.md`
- `docs/compatibility.md`
- `change_notes_2026.md`
- `PLANS.md`

Validation:
- `bash -n Upkeeper lib/upkeeper/*.bash tools/*.sh tests/*.bash testruns/*.sh Upkeeper.conf configurations/default.conf`
- `for test_script in tests/*.bash; do bash "$test_script"; done`
- `tools/check_public_docs.sh --quick`
- `tools/validate_upkeeper.sh --quick`
- `git diff --check`

Completed in this patch:
- Repaired owned weak-mode `$CODEX_HOME/sessions` directories to `0700` through
  an `O_NOFOLLOW` directory descriptor before the write probe runs.
- Kept symlink, non-directory, wrong-owner, and still-unsafe session stores as
  pre-backend local-environment failures.
- Made review-summary logging fall back to `RUN_SELECTED_REVIEW_PATH` when the
  final model message has an outcome but omits the selected file.
- Added quick validation for owned session-store permission repair and selected
  file fallback logging.
- Updated operator docs, compatibility notes, security notes, and 2026 change
  notes.

## Issue 128 Session Store Probe Hardening

Status: completed

Goal:
Fail closed before probing `$CODEX_HOME/sessions` when the session store path is
unsafe, and replace the predictable truncating probe file with an unpredictable
private probe directory.

Constraints:
- Start from the issue-inferred selected file,
  `lib/upkeeper/session_store_preflight.bash`.
- Preserve the current caller contract: `codex_session_store_write_check` prints
  `ok` or one compact failure reason on stdout.
- Reject a final sessions path that is a symlink, not a directory, not owned by
  the current user, or group/other writable before creating probe files.
- Keep validation deterministic and local; do not run backend Codex validation.

Files likely touched:
- `lib/upkeeper/session_store_preflight.bash`
- `tools/validate_upkeeper.sh`
- `docs/scripts/upkeeper.md`
- `docs/security.md`
- `docs/compatibility.md`
- `change_notes_2026.md`
- `PLANS.md`

Validation:
- `bash -n Upkeeper lib/upkeeper/*.bash tools/*.sh tests/*.bash testruns/*.sh Upkeeper.conf configurations/default.conf`
- `for test_script in tests/*.bash; do bash "$test_script"; done`
- `tools/check_public_docs.sh --quick`
- `tools/validate_upkeeper.sh --quick`
- `git diff --check`

Completed in this patch:
- Added a session-store safety check that rejects symlink, non-directory,
  wrong-owner, and group/other-writable `$CODEX_HOME/sessions` paths before the
  write probe.
- Replaced the predictable truncating marker file with an unpredictable
  `mktemp -d` probe directory and child probe file.
- Added quick validation proving the normal probe cleans up, a preexisting
  predictable marker symlink is not followed or removed, and unsafe session
  directories fail before probing.
- Updated operator docs, compatibility, security notes, and 2026 change notes.

## Issue 127 Symlink Target Escape Hardening

Status: completed

Goal:
Fail closed when explicit targets, automatic selection, manifest generation, or
Lattice candidate diagnostics encounter repo paths that are symlinks, especially
symlinks pointing outside the repository.

Constraints:
- Start from the issue-inferred selected file, `lib/upkeeper/help_selection.bash`.
- Keep the source-safe target boundary deterministic and local before Codex
  launch; do not use backend Codex validation.
- Reject symlinks before stat, read, hash, prompt selection, or candidate
  reporting can follow them.
- Use no-follow sample reads and repo-root containment checks for selected
  source files.
- Preserve existing operator-visible status markers, log keys, and selection
  precedence.

Files likely touched:
- `lib/upkeeper/help_selection.bash`
- `lib/upkeeper/file_manifest.bash`
- `tools/upkeeper_lattice.py`
- `tools/validate_upkeeper.sh`
- `docs/security.md`
- `docs/compatibility.md`
- `change_notes_2026.md`
- `PLANS.md`

Validation:
- `bash -n Upkeeper lib/upkeeper/*.bash tools/*.sh tests/*.bash testruns/*.sh Upkeeper.conf configurations/default.conf`
- `for test_script in tests/*.bash; do bash "$test_script"; done`
- `tools/check_public_docs.sh --quick`
- `tools/validate_upkeeper.sh --quick`
- `tools/validate_upkeeper.sh --full`
- `tools/stress_upkeeper_corpus.sh --local`
- `git diff --check`

Completed in this patch:
- Added no-follow source-safe file helpers for selected target validation and
  automatic candidate filtering in `lib/upkeeper/help_selection.bash`.
- Rejected symlink paths during manifest generation in
  `lib/upkeeper/file_manifest.bash`.
- Made Lattice current candidate diagnostics report symlinks as excluded instead
  of treating followed targets as eligible.
- Added quick validation covering explicit, enumerate, manifest, and Lattice
  behavior for a tracked symlink that points outside the repo.
- Updated security, compatibility, and release-note documentation for the
  tightened source-safe boundary.

## Force-Added Git-Ignored Target Guardrail

Status: completed

Goal:
Reject paths that match Git ignore rules from Upkeeper explicit target selection,
normal script/tool rotation, manifest generation, and Lattice/max-cover
candidates even when those paths were force-added to Git.

Constraints:
- Preserve the documented source-safe target boundary for both explicit
  `--target-file` and automatic selection.
- Keep the fix deterministic and local; do not use backend Codex validation.
- Apply the same `git check-ignore --no-index` semantics at every directly
  related source/candidate surface.
- Add a temp-repo regression check for a force-added ignored executable.

Files likely touched:
- `lib/upkeeper/help_selection.bash`
- `lib/upkeeper/file_manifest.bash`
- `tools/upkeeper_lattice.py`
- `tools/validate_upkeeper.sh`
- `change_notes_2026.md`
- `PLANS.md`

Validation:
- `bash -n Upkeeper lib/upkeeper/*.bash tools/*.sh tests/*.bash testruns/*.sh Upkeeper.conf configurations/default.conf`
- `tools/validate_upkeeper.sh --quick`
- `tools/check_public_docs.sh --quick`
- `git diff --check`

Completed in this patch:
- Switched Git ignore checks for selected targets to `git check-ignore
  --no-index` so force-added ignored paths are treated as ignored.
- Filtered Git-ignored paths out of normal selection, manifest generation, and
  Lattice/max-cover candidate diagnostics.
- Added quick validation with a force-added ignored executable fixture covering
  explicit, enumerate, manifest, and Lattice paths.

## ChimneySweep Issue-Fix Launcher

Status: completed

Goal:
Add a repo-root `ChimneySweep` launcher that is allowed to diverge from
`FlameOn`: `FlameOn` remains the high-coverage bug-finding burn tool, while
`ChimneySweep` is the scripted issue-fix queue runner.

Constraints:
- All GitHub issue listing, classification, and ranking happens in deterministic
  shell/Python before any backend Codex process can start.
- A clean open-issue queue exits successfully-for-automation with code 25.
- Security-class issues always outrank data-integrity issues; data-integrity
  issues outrank the general issue queue. Repeated scheduled runs should keep
  working the current highest-priority class until that class is resolved.
- The selected issue is locked before launch and passed to Upkeeper explicitly;
  Upkeeper must not reselect a different issue after `ChimneySweep` has ranked
  the queue.
- Keep normal Upkeeper quota, startup, target-selection, pre-contact backup,
  fallback, postmortem, and evidence handling for the actual model run.
- Do not run real backend Codex validation locally.

Files likely touched:
- `ChimneySweep`
- `Upkeeper`
- `lib/upkeeper/codex_io.bash`
- `lib/upkeeper/prompt_compile.bash`
- `lib/upkeeper/help_selection.bash`
- `completions/upkeeper.bash`
- `tests/chimneysweep_test.bash`
- `tests/flameon_test.bash`
- `tools/validate_upkeeper.sh`
- `tools/check_public_docs.sh`
- `README.md`
- `docs/scripts/upkeeper.md`
- `docs/compatibility.md`
- `change_notes_2026.md`

Validation:
- `bash -n Upkeeper FlameOn ChimneySweep lib/upkeeper/*.bash tools/*.sh tests/*.bash testruns/*.sh Upkeeper.conf configurations/default.conf completions/*.bash`
- `bash tests/chimneysweep_test.bash`
- `bash tests/flameon_test.bash`
- `tools/check_public_docs.sh --quick`
- `tools/validate_upkeeper.sh --quick`
- `git diff --check`

Completed in this patch:
- Added `ChimneySweep` with deterministic GitHub issue ranking, clean-queue
  exit code 25, dry-run output, and Bash completion.
- Added Upkeeper `--fix-issue=NUMBER` / `UPKEEPER_FIX_ISSUE` so deterministic
  launchers can lock one issue before normal Upkeeper model launch.
- Kept `FlameOn` as the bug-finding burn launcher and documented the divergence
  between FlameOn and ChimneySweep.
- Updated tests, validation, public docs, compatibility notes, CI syntax checks,
  and v1.2.6 release notes.

## Log Path Symlink Hardening

Status: completed

Goal:
Reject unsafe `Upkeeper.log` paths before the first wrapper log write so a
contaminated checkout cannot redirect log appends through symlinks or other
non-regular files.

Constraints:
- Keep the guard in the runtime/logging owner loaded by root `Upkeeper`.
- Fail closed before `cycle.start` if the log path is a symlink, non-regular
  file, hard-linked file, or not owned by the current user.
- Preserve explicit `CODEX_LOG_FILE` behavior for normal regular user-owned log
  files.
- Use deterministic dry-run validation only; do not launch real backend Codex.
- Update operator-visible docs, compatibility notes, and 2026 change notes with
  the security behavior.

Files likely touched:
- `Upkeeper`
- `.gitignore`
- `lib/upkeeper/runtime_foundation.bash`
- `lib/upkeeper/progress_logging.bash`
- `lib/upkeeper/log_rotation.bash`
- `lib/upkeeper/transcript_output.bash`
- `lib/upkeeper/postmortem_sequence.bash`
- `tools/validate_upkeeper.sh`
- `docs/scripts/upkeeper.md`
- `docs/compatibility.md`
- `docs/security.md`
- `change_notes_2026.md`

Validation:
- `bash -n Upkeeper lib/upkeeper/*.bash tools/*.sh tests/*.bash testruns/*.sh Upkeeper.conf configurations/default.conf`
- `for test_script in tests/*.bash; do bash "$test_script"; done`
- `tools/check_public_docs.sh --quick`
- `tools/validate_upkeeper.sh --quick`
- `git diff --check`

Completed in this patch:
- Added a no-follow log append guard that rejects symlink, non-regular,
  hard-linked, wrong-owner, and symlink-parent log paths before writing.
- Updated startup log write preflight, normal `log_line` output, log-rotation
  notices, transcript summaries, and postmortem summaries to use guarded appends.
- Added quick validation for a symlinked-client `Upkeeper.log` attack fixture
  and kept the lattice wrapper test independent of operator home writability.
- Ignored rotated `Upkeeper.log.*.zip` evidence archives so log rotation cannot
  leave commit-visible local artifacts.
- Bumped Upkeeper to v1.2.7 and updated help, operator docs, compatibility,
  security docs, and 2026 change notes.

## Launcher Full-Burn Defaults

Status: completed

Goal:
Make the repo-root automation launchers stress the complete Upkeeper safety and
review surface by default, while keeping plain `./Upkeeper` as the compatibility
entrypoint.

Constraints:
- Apply the stronger defaults to both `FlameOn` and `ChimneySweep`.
- Do not add an opt-out flag; these launchers are the dogfood/stress paths.
- Require Lattice and encrypted pre-contact backup before backend launch.
- Pin the Codex sandbox mode for launcher runs.
- Spend quota down to the provider floor for these launcher runs by forcing
  quota stop floors and buffers to zero, bypassing wrapper quota guardrail
  stops, and bypassing stale cooldown markers.
- Keep `ChimneySweep` issue selection deterministic and pre-model, with the
  selected issue target still locked by `--fix-issue=NUMBER`.
- Request full prompt pass coverage plus P24-P29 modules for `ChimneySweep`
  repair runs without letting target selection drift away from the locked issue.
- Do not launch real backend Codex validation while making the patch.

Files likely touched:
- `FlameOn`
- `ChimneySweep`
- `lib/upkeeper/launcher_full_burn.bash`
- `tests/flameon_test.bash`
- `tests/chimneysweep_test.bash`
- `tools/validate_upkeeper.sh`
- `README.md`
- `docs/scripts/upkeeper.md`
- `docs/compatibility.md`
- `docs/dependencies.md`
- `.github/workflows/ci.yml`
- `change_notes_2026.md`
- `PLANS.md`

Validation:
- `bash -n Upkeeper lib/upkeeper/*.bash tools/*.sh tests/*.bash testruns/*.sh Upkeeper.conf configurations/default.conf`
- `bash tests/flameon_test.bash`
- `bash tests/chimneysweep_test.bash`
- `tools/check_public_docs.sh --quick`
- `tools/validate_upkeeper.sh --quick`
- `git diff --check`

Completed in this patch:
- Added the shared `launcher_full_burn.bash` helper and loaded it through the
  explicit module map.
- Made `FlameOn` and `ChimneySweep` force required Lattice, required encrypted
  age pre-contact backup, and `--sandbox workspace-write` before backend launch.
- Made `ChimneySweep` request `--prompt-pass=all` plus all P24-P29 review
  modules for the issue it locks before launch.
- Extended dry-run output, focused tests, quick validation, README, operator
  docs, security docs, compatibility notes, and v1.2.8 release notes.
- Documented `age` as the live full-burn launcher dependency, added it to CI,
  and recorded the local public-recipient setup flow.
- Made full-burn launcher quota behavior spend-to-zero for both five-hour and
  weekly buckets, including bypass of wrapper quota guardrail stops and existing
  quota-cooldown markers.
- Kept local validation fixtures on plain Upkeeper defaults even when the
  validator itself is launched from a full-burn environment.

## ChimneySweep Staged Issue Workflow

Status: completed

Goal:
Exercise issue repair end to end while keeping deterministic queue selection
outside the model: comment first, review that comment with a fresh model, then
apply the fix in a third model instantiation.

Constraints:
- Keep issue selection scripted and pre-model.
- Keep comment/review stages read-only against tracked source.
- Let the apply stage actually work the bug and patch source.
- Keep full-burn launcher defaults on every stage.
- Preserve a one-stage apply workflow for compatibility and focused debugging.

Files likely touched:
- `ChimneySweep`
- `Upkeeper`
- `lib/upkeeper/codex_io.bash`
- `lib/upkeeper/prompt_compile.bash`
- `lib/upkeeper/help_selection.bash`
- `completions/upkeeper.bash`
- `tests/chimneysweep_test.bash`
- `README.md`
- `docs/scripts/upkeeper.md`
- `docs/compatibility.md`
- `docs/security.md`
- `change_notes_2026.md`

Validation:
- `bash -n Upkeeper FlameOn ChimneySweep lib/upkeeper/*.bash tools/*.sh tests/*.bash testruns/*.sh Upkeeper.conf configurations/default.conf completions/*.bash`
- `bash tests/chimneysweep_test.bash`
- `tools/check_public_docs.sh --quick`
- `tools/validate_upkeeper.sh --quick`
- `git diff --check`

Completed in this patch:
- Added `--issue-workflow-stage=comment|review|apply` to Upkeeper issue-fix
  cycles.
- Made comment and review stages leave issue comments and fail if tracked source
  mutates.
- Made ChimneySweep default to `comment-review-apply` and added workflow options
  for all stage subsets.
- Extended completion, tests, docs, compatibility notes, security notes, and
  v1.2.9 release notes.

## Genie Protocol GitHub Boundary

Status: completed

Goal:
Keep backend Codex out of direct GitHub I/O while preserving the full
ChimneySweep comment, review, and apply workflow.

Constraints:
- The wrapper may fetch issue state, comments, labels, and later post issue
  comments or other GitHub side effects.
- Backend Codex gets wrapper-fetched issue evidence and local artifact paths
  only.
- Backend Codex must not inherit GitHub token environment variables.
- Backend Codex must not have a normal `gh` command path or a normal `gh`
  config directory.
- The boundary must have deterministic validation that tries to break out before
  any real LLM launch.

Files likely touched:
- `Upkeeper`
- `lib/upkeeper/codex_io.bash`
- `lib/upkeeper/prompt_compile.bash`
- `tools/validate_upkeeper.sh`
- `README.md`
- `docs/scripts/upkeeper.md`
- `docs/compatibility.md`
- `docs/security.md`
- `change_notes_2026.md`

Validation:
- `bash -n Upkeeper lib/upkeeper/codex_io.bash lib/upkeeper/prompt_compile.bash tools/validate_upkeeper.sh`
- `tools/validate_upkeeper.sh --quick`
- `tools/check_public_docs.sh --quick`
- `git diff --check`

Completed in this patch:
- Added the Genie Protocol backend launch environment in `codex_io.bash`.
- Scrubbed GitHub token/API environment variables from backend Codex child
  processes.
- Added per-run blocker stubs for `gh`, `curl`, `wget`, and `hub`, plus an empty
  per-run `GH_CONFIG_DIR`.
- Forced comment/review issue-workflow backend launches into
  `--sandbox read-only` and moved issue-comment handoff to a final-message draft
  block extracted by the wrapper after validation.
- Kept wrapper-owned `gh issue comment --body-file` relay outside that backend
  child environment.
- Added a validation fixture that injects fake host GitHub tools and token
  variables, then proves the backend command sees only the brokered blockers.
- Updated prompts, docs, compatibility notes, security notes, and v1.2.9 release
  notes.

## Pre-Contact Selected-Target Backups

Status: completed

Goal:
Create a local no-root/no-sudo backup of the shell-selected review target before
the selected-target prompt block is compiled or any backend Codex process can
start.

Constraints:
- Keep the default vault outside the repository and never write the vault path
  into logs, prompts, transcripts, or Lattice evidence.
- Support plain local backups as recovery aids, but mark them unprotected from
  same-user deletion.
- Support age public-recipient encryption without requiring, reading, or logging
  private identities during backup creation.
- Fail closed before backend launch when required backup creation is unavailable
  or fails.
- Keep replacement target authority in the wrapper; the prompt must tell Codex
  to report BLOCKED rather than selecting an unbacked replacement target.
- Do not implement privileged vaults, sudo/root helpers, chattr, fs-verity,
  systemd services, or a custom Landlock launcher in this slice.

Files likely touched:
- `Upkeeper`
- `Upkeeper.conf`
- `configurations/default.conf`
- `lib/upkeeper/precontact_backup.bash`
- `lib/upkeeper/help_selection.bash`
- `lib/upkeeper/README.md`
- `tools/upkeeper_precontact_restore.sh`
- `tools/validate_upkeeper.sh`
- `tests/precontact_backup_test.bash`
- `docs/security.md`
- `docs/dependencies.md`
- `docs/scripts/upkeeper.md`
- `docs/compatibility.md`
- `README.md`
- `change_notes_2026.md`

Validation:
- `bash -n Upkeeper lib/upkeeper/*.bash tools/*.sh tests/*.bash testruns/*.sh Upkeeper.conf configurations/default.conf`
- `for test_script in tests/*.bash; do bash "$test_script"; done`
- `tools/check_public_docs.sh --quick`
- `tools/validate_upkeeper.sh --quick`
- `git diff --check`

Completed in this patch:
- Added `lib/upkeeper/precontact_backup.bash` and loaded it before prompt
  compilation so selected targets are hashed and backed up before Codex receives
  the `WRAPPER_PRESELECTED_REVIEW_TARGET` block.
- Added plain and age backup modes, required/fail-closed behavior, redacted
  success/failure logs, per-path retention, and conservative restore by opaque
  backup id.
- Kept symlinked client invocation working while rejecting symlink selected
  targets for this first backup slice.
- Updated prompt rules so impossible/unsafe selected targets require `BLOCKED`
  instead of model-chosen replacement targets.
- Updated operator docs, dependency docs, security docs, compatibility notes,
  stress corpus expectations, tests, validation, and v1.2.5 release notes.

## Bug Report And Issue-Fix Modes

Status: completed

Goal:
Add explicit Upkeeper modes for no-fix bug reporting and for issue-driven repair
of the oldest prioritized open bug, then make `FlameOn` default to bug-report
mode instead of applying source fixes.

Constraints:
- `--bug-report-only` must tell Codex not to edit, touch, format, or otherwise
  mutate tracked source while still allowing local read-only investigation and
  deterministic repro commands.
- `FlameOn` stays thin and continues to invoke Upkeeper rather than duplicating
  wrapper behavior.
- `--fix-next-issue` should select open GitHub issues by priority label order:
  `security`, then `data-integrity`, then `bug`, oldest first within each label.
- Issue-fix mode may require `gh`; normal Upkeeper and bug-report-only mode
  must not make `gh` a hard runtime dependency.
- Do not run real backend Codex validation in local tests.
- Update help, docs, compatibility notes, completions, validation, and annual
  change notes because this changes operator-facing behavior.

Files likely touched:
- `Upkeeper`
- `FlameOn`
- `Upkeeper.conf`
- `configurations/default.conf`
- `completions/upkeeper.bash`
- `lib/upkeeper/codex_io.bash`
- `lib/upkeeper/prompt_compile.bash`
- `lib/upkeeper/report_analysis.bash`
- `lib/upkeeper/status_session.bash`
- `lib/upkeeper/help_selection.bash`
- `tools/validate_upkeeper.sh`
- `README.md`
- `docs/scripts/upkeeper.md`
- `docs/compatibility.md`
- `change_notes_2026.md`

Validation:
- `bash -n Upkeeper FlameOn lib/upkeeper/*.bash tools/*.sh tests/*.bash testruns/*.sh Upkeeper.conf configurations/default.conf completions/*.bash`
- `for test_script in tests/*.bash; do bash "$test_script"; done`
- `tools/check_public_docs.sh --quick`
- `tools/validate_upkeeper.sh --quick`
- `tools/validate_upkeeper.sh --full`
- `git diff --check`

Completed in this patch:
- Added `--bug-report-only` plus `--file-bug-only` and `--report-bug-only`
  aliases, with prompt rules that forbid source fixes/touches and a post-run
  source mutation fingerprint guard for non-dry-run cycles.
- Made `FlameOn` pass `--bug-report-only` by default while remaining a thin
  `--model-override=5.5_xhigh --max-cover` wrapper.
- Added `--fix-next-issue` plus `--fix-oldest-bug`, selecting open GitHub
  issues by `security`, then `data-integrity`, then `bug`, oldest first, and
  deriving a starting target file from issue text when possible.
- Added `REVIEWED_AND_REPORTED` as a parsed review outcome for issue-filed or
  issue-ready report cycles.
- Extended docs, help, config defaults, completion, compatibility notes, change
  notes, and local validation coverage.

## Upkeeper Lattice

Status: completed

Goal:
Add a local SQLite-backed evidence ledger for file-affecting Upkeeper activity,
with deterministic query/import/export/backup/recovery surfaces and wrapper
hooks that preserve current live source-safe target selection.

Constraints:
- Default DB is local ignored runtime state:
  `runtime/upkeeper-lattice/lattice.sqlite3`.
- Use Python stdlib `sqlite3`; no daemon, service, ORM, package manifest,
  default network access, or GitHub token storage.
- Keep source-safe live eligibility authoritative. Lattice records and scores
  evidence, but it must not replace current selection by stale DB rows.
- Preserve `UPKEEPER_STATUS` and `UPKEEPER_LOG_REVIEW`; add
  `UPKEEPER_PASS_RESULT` as optional parseable evidence.

Files likely touched:
- `Upkeeper`
- `Upkeeper.conf`
- `configurations/default.conf`
- `lib/upkeeper/lattice.bash`
- `lib/upkeeper/help_selection.bash`
- `lib/upkeeper/prompt_compile.bash`
- `lib/upkeeper/report_analysis.bash`
- `lib/upkeeper/cycle_cleanup_signals.bash`
- `tools/upkeeper_lattice.py`
- `tools/validate_upkeeper.sh`
- `tests/lattice_test.bash`
- `docs/lattice.md`
- `README.md`
- `docs/scripts/upkeeper.md`
- `docs/compatibility.md`
- `docs/dependencies.md`
- `prompts/default-review.md`
- `change_notes_2026.md`

Validation:
- `bash -n Upkeeper lib/upkeeper/*.bash tools/*.sh tests/*.bash testruns/*.sh Upkeeper.conf configurations/default.conf`
- `bash tests/lattice_test.bash`
- `tools/validate_upkeeper.sh --quick`
- `git diff --check`

Completed notes:
- GitHub reconciliation remains a Phase 2 opt-in surface.
- Automatic inferred/suspected regression correlation from reopened tool failures
  remains a future hardening item; Phase 1 records manual and pass-marker
  regression evidence.

## Lattice Git Import Hardening

Status: completed

Goal:
Make `tools/upkeeper_lattice.py import-git` safe for first population and
accidental reruns by preserving one fact per commit/path/status change and by
keeping rename lineage attached to later changes on the renamed path.

Constraints:
- Preserve the existing schema version unless a true incompatible migration is
  required.
- Keep the importer local-only and NUL-safe.
- Keep live source-safe eligibility authoritative; Git history remains evidence
  only.
- Repair existing duplicate Git file-change evidence during normal `init`
  without requiring a separate operator migration command.

Files likely touched:
- `tools/upkeeper_lattice.py`
- `tests/lattice_test.bash`
- `docs/lattice.md`
- `change_notes_2026.md`

Validation:
- `bash tests/lattice_test.bash`
- `tools/validate_upkeeper.sh --quick`
- `tools/check_public_docs.sh --quick`
- `git diff --check`

Current status:
- Reproduced duplicate `git_file_changes` rows after two `import-git` runs.
- Added an idempotent Git file-change guard, init-time duplicate repair,
  renamed-path lineage resolution, file-history alias lookup, tests, public
  docs, and v1.2.1 release notes.
- Validation passed: `bash -n Upkeeper lib/upkeeper/*.bash tools/*.sh
  tests/*.bash testruns/*.sh Upkeeper.conf configurations/default.conf`,
  `for test_script in tests/*.bash; do bash "$test_script"; done`,
  `tools/check_public_docs.sh --quick`, `tools/validate_upkeeper.sh --quick`,
  `./Upkeeper --version`, `./Upkeeper --help`, and `git diff --check`.

## FlameOn Max-Cover Launcher

Status: completed

Goal:
Add a repo-root `FlameOn` launcher for high-coverage smoke/burn runs without
retyping Upkeeper's long max-coverage flag set, backed by testable Upkeeper and
Lattice selection surfaces.

Constraints:
- Keep `FlameOn` as a thin launcher. Reusable behavior belongs in Upkeeper flags
  and Lattice selection modes.
- Respect Upkeeper quota guardrails. The launcher must not bypass quota checks
  or run backend validation during local tests.
- Limit `FlameOn` verbosity flags to `--silent`, `--basic`, and `--debug1`,
  matching `CODEX_TERMINAL_VERBOSITY` values.
- Add an opt-in backup-queue path without changing the default failure queue.
- Keep live source safety authoritative even when max-cover selection uses a
  broader current tracked-file candidate pool than normal script/tool rotation.

Files likely touched:
- `FlameOn`
- `Upkeeper`
- `Upkeeper.conf`
- `configurations/default.conf`
- `completions/upkeeper.bash`
- `lib/upkeeper/codex_io.bash`
- `lib/upkeeper/help_selection.bash`
- `lib/upkeeper/lattice.bash`
- `tools/upkeeper_lattice.py`
- `tests/*.bash`
- `tools/validate_upkeeper.sh`
- `tools/check_public_docs.sh`
- `.github/workflows/ci.yml`
- `README.md`
- `docs/scripts/upkeeper.md`
- `docs/compatibility.md`
- `docs/lattice.md`
- `change_notes_2026.md`

Validation:
- `bash -n Upkeeper FlameOn lib/upkeeper/*.bash tools/*.sh tests/*.bash testruns/*.sh Upkeeper.conf configurations/default.conf`
- `for test_script in tests/*.bash; do bash "$test_script"; done`
- `tools/check_public_docs.sh --quick`
- `tools/validate_upkeeper.sh --quick`
- `git diff --check`

Completed in this patch:
- Added root `FlameOn` as a thin max-cover launcher over Upkeeper with only
  `--silent`, `--basic`, `--debug1`, `-backup_queue`, and `--backup-queue`
  operator flags.
- Added `--max-cover` / `UPKEEPER_MAX_COVER` so Upkeeper can force all P1-P23
  passes, append P24-P29, and request Lattice max-cover target ranking.
- Added Lattice `selection-candidates --mode max-cover`, ranking current tracked
  source-safe text files by unrun pass coverage, least-covered pass count, and
  oldest mtime.
- Added optional Bash completion for Upkeeper and FlameOn.
- Updated operator docs, compatibility notes, release notes, CI syntax coverage,
  public-doc checks, unit tests, and quick/full validation.

Validation run:
- `bash -n Upkeeper FlameOn lib/upkeeper/*.bash tools/*.sh tests/*.bash testruns/*.sh Upkeeper.conf configurations/default.conf completions/*.bash`
- `python3 -m py_compile tools/upkeeper_lattice.py`
- `for test_script in tests/*.bash; do bash "$test_script"; done`
- `tools/check_public_docs.sh --quick`
- `tools/validate_upkeeper.sh --quick`
- `tools/validate_upkeeper.sh --full`
- `git diff --check`

## P29 Reuse System Hardening

Status: completed

Goal:
Harden P29 from a reuse prompt into a stronger reuse-system contract without
starting the larger registry and helper-extraction refactors in the same patch.

Completed in this patch:
- Add explicit boundaries between P12 local duplication review and P29
  project-wide reusable asset review.
- Add wrong-abstraction rollback rules, shell reuse safety gates, command reuse
  policy, registry preference, command recipe harvesting, reusable data-table
  coverage, ShellCheck policy, and reuse-debt output requirements.
- Add a reusable asset ownership map to `lib/upkeeper/README.md`.
- Extend local validation and public-doc checks so the P29 hardening contract
  cannot silently disappear.

Future P29 priority queue:
- P29-1: add or simulate a narrow review-module registry for ids, aliases,
  prompt paths, titles, and help summaries.
- P29-2: refactor `tools/validate_upkeeper.sh` review-module checks into
  metadata arrays and loops.
- P29-3: add a validation helper for fake Upkeeper environment setup while
  preserving captured exit codes and redirections.
- P29-4: add dependency-list drift validation between docs, validation, and
  runtime preflight checks.
- P29-5: add tests before extracting `codex_io.bash` jq assignment scaffolding.
- P29-6: add shared fixtures or fixture writers for quota/session JSONL cases.
- P29-7: add prompt-module structure validation so future modules do not repeat
  wiring pain.
- P29-8: inspect embedded Python data tables and regexes as reusable assets,
  especially startup anomaly allowlists and command-kind classifiers.

Validation:
- `bash -n Upkeeper lib/upkeeper/*.bash tools/*.sh tests/*.bash`
- `tools/check_public_docs.sh`
- `tools/validate_upkeeper.sh --quick`
- `git diff --check`

## Upkeeper Ignore Firebreak

Status: completed

Goal:
Add a first-class `.upkeeperignore` selection/spend firewall so Upkeeper can
exclude tracked or untracked text that should not receive model upkeep cycles,
independent of whether Git tracks it.

Constraints:
- Preserve `.gitignore` behavior and hard exclusions for `.git/`, `runtime/`,
  and `Upkeeper.log`.
- Keep explicit `--target-file` as the strongest normal operator pin, but reject
  `.upkeeperignore` paths by default unless a future force contract is added.
- Apply the same ignore firebreak to normal selection, manifest-backed
  selection, Lattice max-cover candidates, failure-queue eligibility, and
  explicit targets.
- Do not run real backend Codex validation.
- Update docs, compatibility notes, config defaults, validation, and annual
  change notes because this changes public target-selection behavior.

Files likely touched:
- `.upkeeperignore`
- `Upkeeper`
- `Upkeeper.conf`
- `configurations/default.conf`
- `lib/upkeeper/file_manifest.bash`
- `lib/upkeeper/help_selection.bash`
- `tools/upkeeper_lattice.py`
- `tools/validate_upkeeper.sh`
- `tests/lattice_test.bash`
- `README.md`
- `docs/scripts/upkeeper.md`
- `docs/compatibility.md`
- `docs/lattice.md`
- `docs/security.md`
- `change_notes_2026.md`

Validation:
- `bash -n Upkeeper lib/upkeeper/*.bash tools/*.sh tests/*.bash testruns/*.sh Upkeeper.conf configurations/default.conf`
- `python3 -m py_compile tools/upkeeper_lattice.py`
- `for test_script in tests/*.bash; do bash "$test_script"; done`
- `tools/check_public_docs.sh --quick`
- `tools/validate_upkeeper.sh --quick`
- `tools/validate_upkeeper.sh --full`
- `tools/stress_upkeeper_corpus.sh --local`
- `git diff --check`

## P29 Reuse Harvesting Review Module

Status: completed

Goal:
Add P29 as an opt-in review module that finds and applies bounded reuse
improvements for helpers, fixtures, prompt language, documentation blocks,
command idioms, validation patterns, and local assets.

Constraints:
- Preserve the existing P1-P23 default repertoire and P24-P28 opt-in behavior.
- Keep `--prompt-pass=all` unchanged; P29 is enabled only by review-module flags
  or config.
- Do not run real backend Codex validation.
- Keep selection filters distinct from review-module prompts.
- Update public docs, help text, compatibility notes, prompt index, validation,
  version, and annual change notes in the same patch.

Files likely touched:
- `Upkeeper`
- `lib/upkeeper/codex_io.bash`
- `lib/upkeeper/prompt_compile.bash`
- `lib/upkeeper/help_selection.bash`
- `prompts/p29-reuse-harvesting-review.md`
- `prompts/README.md`
- `README.md`
- `AGENTS.md`
- `docs/scripts/upkeeper.md`
- `docs/compatibility.md`
- `docs/public-documentation-policy.md`
- `tools/check_public_docs.sh`
- `tools/validate_upkeeper.sh`
- `testruns/all_p_modules_600s.sh`
- `testruns/all_p_modules_once.sh`
- `change_notes_2026.md`

Validation:
- `bash -n Upkeeper lib/upkeeper/*.bash tools/*.sh tests/*.bash testruns/*.sh Upkeeper.conf configurations/default.conf`
- `for test_script in tests/*.bash; do bash "$test_script"; done`
- `tools/check_public_docs.sh --quick`
- `tools/validate_upkeeper.sh --quick`
- `tools/validate_upkeeper.sh --full`
- `git diff --check`

## P29 Contract Alignment

Status: completed

Goal:
Align the P29 prompt and alias surface exactly with the handoff contract after
the first P29 implementation landed.

Constraints:
- Do not add an actual reuse refactor in this patch.
- Preserve the existing P29 runtime wiring and no-backend validation behavior.
- Keep docs, version, annual change notes, and validation aligned.

Files likely touched:
- `Upkeeper`
- `docs/scripts/upkeeper.md`
- `change_notes_2026.md`
- `lib/upkeeper/codex_io.bash`
- `prompts/p29-reuse-harvesting-review.md`
- `tools/validate_upkeeper.sh`

Validation:
- `bash -n Upkeeper lib/upkeeper/*.bash tools/*.sh tests/*.bash`
- `tools/check_public_docs.sh`
- `tools/validate_upkeeper.sh --quick`
- `git diff --check`

## PR 340/341 Catch-Up And CI Repair

Status: in_progress

Goal:
Catch up the open security/lattice stack onto one mergeable branch by carrying
forward the latest committed lattice fix, repairing the broken default
`CODEX_MODE` parsing path, and fixing the CI docs-only classifier so pull
requests classify change scope from an available base commit.

Constraints:
- Preserve the original committed queue work already present on the stacked
  branches.
- Do not touch the large uncommitted automation churn in the original checkout.
- Keep validation local-first and deterministic before any push/merge.
- Prefer one surviving merge branch over rescuing both open PR branches.

Files likely touched:
- `PLANS.md`
- `lib/upkeeper/codex_io.bash`
- `.github/workflows/ci.yml`
- `change_notes_2026.md`

Validation:
- `bash -n Upkeeper lib/upkeeper/*.bash tools/*.sh tests/*.bash testruns/*.sh Upkeeper.conf configurations/default.conf`
- `for test_script in tests/*.bash; do bash "$test_script"; done`
- `git diff --check`
- `tools/validate_upkeeper.sh --quick`

## Dirty Checkout Reconciliation After PR 342 Merge
- Status: completed
- Goal: salvage still-valuable uncommitted fixes from `/home/joe/projects/Upkeeper/main` onto clean merged `main` without replaying stale lattice catch-up churn.
- Constraints: preserve original dirty checkout untouched; do not reintroduce superseded lattice harness regressions from PR 342; keep operator-visible docs aligned with security behavior changes.
- Likely files: `Upkeeper`, fallback/active-lock/precontact/quota/session/status modules, security docs/prompts, targeted tests, and selective validator/lattice test updates.
- Validation: `bash -n Upkeeper lib/upkeeper/*.bash tools/*.sh tests/*.bash testruns/*.sh Upkeeper.conf configurations/default.conf`; `for test_script in tests/*.bash; do bash "$test_script"; done`; `git diff --check`; `tools/validate_upkeeper.sh --quick`
- Outcome: salvaged the fallback, lock inheritance, precontact backup, quota-marker, session-store, status-marker, startup-anomaly, and issue-fix hardening work from the dirty checkout; preserved the already-merged PR 342 lattice and CI repairs while selectively carrying over only the additional lattice regression coverage that still applied; repaired copied regressions in fallback contract creation, restore-temp cleanup, and lattice test globals before promoting the salvage set to a clean validated branch state.

## Bug Report Only Local Draft And GitHub Write Gate

Status: completed

Goal:
Turn `--bug-report-only` into a wrapper-owned local draft workflow instead of a
soft prompt hint, so confirmed findings default to durable local issue drafts
and backend GitHub writes stay blocked unless the operator explicitly allows
issue creation.

Constraints:
- Preserve the existing Genie Protocol boundary that blocks direct backend
  network tooling by default.
- Keep normal issue-workflow comment/review posting behavior unchanged because
  the wrapper, not backend Codex, owns that path.
- Update only the operator-facing help/docs needed for the changed contract;
  broader README housekeeping can wait.

Files likely touched:
- `Upkeeper`
- `PLANS.md`
- `change_notes_2026.md`
- `docs/scripts/upkeeper.md`
- `lib/upkeeper/codex_io.bash`
- `lib/upkeeper/help_selection.bash`
- `lib/upkeeper/prompt_compile.bash`
- `tests/bug_report_only_test.bash`
- `tools/validate_upkeeper.sh`

Validation:
- `bash -n Upkeeper lib/upkeeper/*.bash tools/*.sh tests/*.bash testruns/*.sh Upkeeper.conf configurations/default.conf`
- `bash tests/bug_report_only_test.bash`
- `for test_script in tests/*.bash; do bash "$test_script"; done`
- `git diff --check`
- `tools/check_public_docs.sh --quick`
- `tools/validate_upkeeper.sh --quick`

## ChimneySweep Obligation Target Remap And Reopen Suppression

Status: completed

Goal:
- stop ChimneySweep obligation-repair loops when an open obligation points `--target-file` at an ineligible runtime fixture or other control-plane evidence path
- suppress duplicate open-obligation records when the selected obligation immediately fails again with the same poisoned explicit target

Constraints:
- keep normal obligation repair locked to a deterministic repo-local control-plane target
- preserve existing eligible obligation target behavior
- avoid introducing a second broad target-selection policy; only guard the poisoned explicit-target replay path

Files likely touched:
- `ChimneySweep`
- `lib/upkeeper/automation_obligations.bash`
- `tests/chimneysweep_test.bash`
- `change_notes_2026.md`

Validation:
- `bash -n Upkeeper lib/upkeeper/*.bash tools/*.sh tests/*.bash testruns/*.sh Upkeeper.conf configurations/default.conf`
- `for test_script in tests/*.bash; do bash "$test_script"; done`
- `git diff --check`
- `tools/validate_upkeeper.sh --quick`

Rollout notes:
- eligible stored obligation targets should keep their existing `--target-file`
- poisoned runtime/.git-style obligation targets should remap to the launcher control-plane file instead of reopening the same loop

## Backlog Wrench Batch Throughput Rebalance

Status: in progress

Goal:
- make `orchestration/backlog.sh` chew through backlog issues faster by moving heavy validation and CI waiting from every single bug to the batch boundary
- preserve clean-trunk quality by keeping the strong validation and PR merge gate before the batch merges

Constraints:
- keep one shared backlog PR / branch model
- keep per-bug runs cheap enough to stack fixes instead of serializing on GitHub CI
- preserve operator-visible progress logging so long local validation windows do not look like silent hangs
- keep the current `#319` dirty-state fingerprint fix on the backlog branch while changing the wrench behavior around it

Files likely touched:
- `PLANS.md`
- `orchestration/backlog.sh`
- `change_notes_2026.md`
- `lib/upkeeper/codex_io.bash`

Validation:
- `bash -n Upkeeper ChimneySweep FlameOn lib/upkeeper/*.bash tools/*.sh tests/*.bash testruns/*.sh Upkeeper.conf configurations/default.conf orchestration/backlog.sh`
- `for test_script in tests/*.bash; do bash "$test_script"; done`
- `tools/check_public_docs.sh --quick`
- `git diff --check`
- `tools/validate_upkeeper.sh --quick`

## Allowlisted CODEX_MODE Tuple Parsing

Status: completed

Goal:
- stop `CODEX_MODE` from accepting arbitrary extra option tokens beyond the sandbox tuple in both the primary wrapper and auxiliary Codex path

Constraints:
- preserve supported sandbox tuples `--sandbox workspace-write` and `--sandbox read-only`
- keep existing clear failure messages for missing dashes and dangerous bypass modes
- keep auxiliary blocked-marker behavior aligned with the primary parser policy

Files likely touched:
- `lib/upkeeper/codex_io.bash`
- `lib/upkeeper/aux_codex.bash`
- `tools/validate_upkeeper.sh`
- `tests/aux_codex_test.bash`
- `change_notes_2026.md`

Validation:
- `bash -n Upkeeper ChimneySweep lib/upkeeper/*.bash tools/*.sh tests/*.bash testruns/*.sh Upkeeper.conf configurations/default.conf`
- `for test_script in tests/*.bash; do bash "$test_script"; done`
- `git diff --check`
- `tools/validate_upkeeper.sh --quick`

## Issue-Fix Private Issue Packet Gate

Status: completed

Goal:
- stop issue-fix mode from sending raw private GitHub issue title/body/comment text into model prompts and durable artifacts by default
- preserve deterministic wrapper-side issue selection and inferred-target extraction before Codex starts

Constraints:
- keep `--fix-next-issue`, `--fix-issue`, and issue-workflow stage selection behavior intact
- preserve an explicit escape hatch for operators who intentionally want the private issue packet exposed to the model
- keep operator docs/config surface aligned with the new default gate

Files likely touched:
- `PLANS.md`
- `Upkeeper.conf`
- `change_notes_2026.md`
- `configurations/default.conf`
- `docs/scripts/upkeeper.md`
- `lib/upkeeper/codex_io.bash`
- `lib/upkeeper/prompt_compile.bash`
- `tests/bug_fix_batch_271_266_265_test.bash`
- `tools/validate_upkeeper.sh`

Validation:
- `bash -n Upkeeper ChimneySweep FlameOn lib/upkeeper/*.bash tools/*.sh tests/*.bash testruns/*.sh Upkeeper.conf configurations/default.conf`
- `for test_script in tests/*.bash; do bash "$test_script"; done`
- `git diff --check`
- `tools/check_public_docs.sh --quick`
- `tools/validate_upkeeper.sh --quick`

## Postmortem Evidence Redaction And Private Storage

Status: completed

Goal:
- stop postmortem paths from copying full last messages by default, stop teeing raw report prose into terminal/log output, and keep raw auxiliary environment evidence out of default plaintext summaries

Constraints:
- preserve deterministic postmortem sequencing and existing marker contracts
- keep enough metadata for operators to understand sequence status and locate private artifacts
- store postmortem artifacts under private dirs/files with `0700`/`0600` permissions

Files likely touched:
- `lib/upkeeper/postmortem_sequence.bash`
- `lib/upkeeper/postmortem_context.bash`
- `lib/upkeeper/aux_codex.bash`
- `tools/validate_upkeeper.sh`
- `change_notes_2026.md`

Validation:
- `bash -n Upkeeper ChimneySweep lib/upkeeper/*.bash tools/*.sh tests/*.bash testruns/*.sh Upkeeper.conf configurations/default.conf`
- `for test_script in tests/*.bash; do bash "$test_script"; done`
- `git diff --check`
- `tools/validate_upkeeper.sh --quick`

## Deferred Data-Protection Issue Burn-Down

Status: completed

Goal:
- clear issues #309, #311, #312, and #314 as one deliberate multi-file repair
- stop normal logs, prompts, startup-anomaly summaries, and Lattice artifact
  references from exposing raw prompt paths, changed paths, or stable content
  hashes
- keep private local diagnostics and restore integrity checks available without
  making those details model-visible by default

Constraints:
- preserve target isolation, pre-contact backup restore safety, startup-anomaly
  gate behavior, and existing Lattice import/export compatibility where feasible
- use keyed HMACs or boolean content-change signals for operator-facing equality
  evidence
- reject control characters in path-like operator inputs before they can reach
  log records

Files likely touched:
- `PLANS.md`
- `Upkeeper`
- `lib/upkeeper/runtime_foundation.bash`
- `lib/upkeeper/transcript_artifacts.bash`
- `lib/upkeeper/codex_io.bash`
- `lib/upkeeper/help_selection.bash`
- `lib/upkeeper/prompt_compile.bash`
- `lib/upkeeper/startup_anomaly_state.bash`
- `lib/upkeeper/worktree_state.bash`
- `lib/upkeeper/precontact_backup.bash`
- `tools/upkeeper_lattice.py`
- focused tests and operator docs
- `change_notes_2026.md`

Validation:
- `bash -n Upkeeper lib/upkeeper/*.bash tools/*.sh tests/*.bash testruns/*.sh Upkeeper.conf configurations/default.conf`
- `for test_script in tests/*.bash; do bash "$test_script"; done`
- `tools/check_public_docs.sh --quick`
- `git diff --check`
- `tools/validate_upkeeper.sh --quick`

## Backlog Watch Prompt Ownership

Status: completed locally; pending PR/CI

Goal:
- stop interactive backlog watch mode from returning the operator's shell prompt
  before the timestamp/color formatter has drained all child-process output
- preserve current terminal watching, loop-log mirroring, visual block markers,
  duplicate-owner behavior, and detached mode

Constraints:
- do not require a backend Codex call or GitHub network access for the focused
  regression check
- keep stdin cut off from the child run so accidental terminal input cannot be
  consumed as commands or prompt content
- preserve the child run's exit status through the watch wrapper

Files likely touched:
- `orchestration/backlog.sh`
- `tools/validate_upkeeper.sh`
- `docs/scripts/upkeeper.md`
- `lib/upkeeper/help_selection.bash`
- `change_notes_2026.md`

Validation:
- `bash -n Upkeeper lib/upkeeper/*.bash tools/*.sh tests/*.bash testruns/*.sh Upkeeper.conf configurations/default.conf orchestration/backlog.sh`
- `tools/validate_upkeeper.sh --quick`
- `tools/validate_upkeeper.sh --full`
- `tools/check_public_docs.sh --quick`
- `git diff --check`

## Structured Policy Decisions

Status: in progress

Goal:
- close issue #222 by introducing a small tracked policy-decision schema that
  records local control-plane decisions as data instead of only prompt prose
- add a shell helper that can emit and validate schema-v1 decisions without a
  new dependency beyond existing `jq`
- document which fields are stable and how future runtime gates should use the
  schema before backend contact

Constraints:
- keep this as the first narrow schema and validation contract, not a broad
  policy engine or OPA-style dependency
- do not launch real backend Codex during validation
- preserve the current authority, capability-profile, and control-ledger docs

Files likely touched:
- `Upkeeper`
- `lib/upkeeper/policy_decisions.bash`
- `lib/upkeeper/README.md`
- `docs/policy-decisions.md`
- `docs/capability-profiles.md`
- `docs/control-ledger.md`
- `docs/security.md`
- `docs/compatibility.md`
- `README.md`
- `tests/policy_decisions_test.bash`
- `tools/validate_upkeeper.sh`
- `tools/check_public_docs.sh`
- `change_notes_2026.md`

Validation:
- `bash -n Upkeeper lib/upkeeper/*.bash tools/*.sh tests/*.bash testruns/*.sh Upkeeper.conf configurations/default.conf orchestration/backlog.sh orchestration/watch-pr.sh`
- `bash tests/policy_decisions_test.bash`
- `tools/check_public_docs.sh --quick`
- `tools/validate_upkeeper.sh --quick`
- `set -e; for test_script in tests/*.bash; do bash "$test_script"; done`
- `git diff --check`

## Compatibility Promise For Schemas And Contracts

Status: in progress

Goal:
- close issue #228 by defining explicit compatibility classes for Upkeeper
  schemas, prompt contracts, docs/help, and Lattice import/export outputs
- document schema-version, migration, deprecation-warning, public-example, and
  Lattice import/export expectations in the binding compatibility surface
- add deterministic validation so the compatibility promise cannot drift out of
  public docs silently

Constraints:
- documentation and validation only; do not change runtime schema behavior in
  this patch
- keep backward-compatible behavior as the default
- avoid broad validation or backend Codex calls

Files likely touched:
- `docs/compatibility.md`
- `docs/lattice.md`
- `docs/public-documentation-policy.md`
- `prompts/README.md`
- `README.md`
- `tools/check_public_docs.sh`
- `tools/validate_upkeeper.sh`
- `change_notes_2026.md`

Validation:
- `tools/check_public_docs.sh --quick`
- `tools/validate_upkeeper.sh --smoke`
- `tools/validate_upkeeper.sh --quick`
- `git diff --check`

## Backlog Quality Gates

Status: in progress

Goal:
- prevent the backlog launcher from stacking new issue work while the current
  backlog PR is red or still unvalidated
- catch Python syntax regressions during per-bug validation instead of waiting
  for batch CI
- give Lattice issue fixes a focused local coverage gate before recording them
  as completed fixes
- make documented unit-test commands fail fast so an earlier failing test cannot
  be masked by later passing commands
- reconcile the issue #166 active-lock hardening with local full-validation
  fixtures so safe dry-runs use repo-runtime lock paths and release their
  ownership markers
- preserve custom validation log sinks while keeping custom log rotation and
  archive pruning blocked unless explicitly authorized and marker-anchored
- make PR-check hibernation explain the true current CI position from local
  `gh`/`jq` metadata, including active check and Actions step, instead of
  repeating an undifferentiated pending line

Constraints:
- do not launch real backend Codex during validation
- preserve the existing light/full validation mode split while making the light
  path catch cheap deterministic regressions
- keep the default unattended path conservative, with explicit environment
  overrides only for manual operator intervention

Files likely touched:
- `orchestration/backlog.sh`
- `.github/workflows/ci.yml`
- `lib/upkeeper/active_lock.bash`
- `tools/validate_upkeeper.sh`
- `docs/scripts/upkeeper.md`
- `lib/upkeeper/help_selection.bash`
- `docs/dependencies.md`
- `docs/release-checklist.md`
- `AGENTS.md`
- `change_notes_2026.md`

Validation:
- `bash -n Upkeeper lib/upkeeper/*.bash tools/*.sh tests/*.bash testruns/*.sh Upkeeper.conf configurations/default.conf orchestration/backlog.sh`
- `set -e; for test_script in tests/*.bash; do bash "$test_script"; done`
- `tools/check_public_docs.sh --quick`
- `git diff --check`
- `tools/validate_upkeeper.sh --quick`
- `tools/validate_upkeeper.sh --full`

## Successive Loop Failure Catchment

Status: completed locally; consolidated on `backlog/20260524-201224`

Goal:
- keep one backend failure from fanning into several independent prior-run
  obligations on the next loop
- classify backend context-window failures as their own repairable control-plane
  problem instead of generic missing-status noise
- keep failure transcript evidence bounded in live output so later custody and
  repair prompts do not re-ingest large transcript tails
- treat quoted `log_line_parts` source snippets as backend fixture echoes, not
  live wrapper PAGE failures

Constraints:
- work in a side branch while the active backlog loop owns the main worktree
- do not launch real backend Codex validation
- preserve durable obligations for real non-zero exits; only coalesce companion
  log lines into the owning terminal-failure obligation

Files likely touched:
- `orchestration/backlog.sh`
- `lib/upkeeper/transcript_output.bash`
- `tools/upkeeper_anomaly_custody.py`
- `lib/upkeeper/automation_obligations.bash`
- `tests/backlog_wrapper_failure_obligation_test.bash`
- `tools/validate_upkeeper.sh`
- `docs/scripts/upkeeper.md`
- `docs/compatibility.md`
- `change_notes_2026.md`

Validation:
- `bash -n Upkeeper lib/upkeeper/*.bash tools/*.sh tests/*.bash testruns/*.sh Upkeeper.conf configurations/default.conf orchestration/backlog.sh`
- `bash tests/backlog_wrapper_failure_obligation_test.bash`
- `tools/validate_upkeeper.sh --quick`
- `tools/check_public_docs.sh --quick`
- `git diff --check`

## Source Rights Metadata Model

Status: completed locally; consolidated on `backlog/20260524-201224`

Goal:
- close issue #224 by defining a tracked source sensitivity, rights, and reuse
  metadata model for OSINT and citation artifacts
- connect that model to the existing preservation, security, compatibility, and
  public documentation surfaces
- add deterministic validation so the required labels and reuse fields cannot
  silently drift out of tracked docs

Constraints:
- documentation and validation only; do not add runtime storage or backend
  Codex behavior in this patch
- keep defaults conservative: missing or unknown source-rights metadata denies
  risky prompt, export, upload, archive, and public evidence actions
- no real backend Codex validation

Files likely touched:
- `docs/source-rights-metadata.md`
- `docs/preservation-policy.md`
- `docs/security.md`
- `docs/compatibility.md`
- `docs/risk-register.md`
- `README.md`
- `tools/check_public_docs.sh`
- `tools/validate_upkeeper.sh`
- `change_notes_2026.md`

Validation:
- `bash -n Upkeeper lib/upkeeper/*.bash tools/*.sh tests/*.bash testruns/*.sh Upkeeper.conf configurations/default.conf orchestration/backlog.sh`
- `tools/check_public_docs.sh --quick`
- `tools/validate_upkeeper.sh --smoke`
- `tools/validate_upkeeper.sh --quick`
- `git diff --check`

Result:
- Added the tracked source-rights metadata policy, linked it from the public
  policy docs, and added public-doc plus quick-validator drift checks.

## Committed Diff Whitespace Validation

Status: completed; merged in PR #865

Goal:
- close issue #864 by making the normal CI whitespace phase inspect the
  committed PR or push range, rather than only a clean working tree
- retain local staged and unstaged whitespace checks for developer validation
- share the ref-aware behavior with the existing docs-only fast path

Constraints:
- fail clearly when a caller provides an unavailable committed base or head;
  never replace that expected range with an empty working-tree check
- preserve the no-network, no-backend local validation contract
- cover real Git fixtures, including committed defects, clean ranges, missing
  revisions, and local unstaged defects

Files likely touched:
- `tools/run_validation_phases.sh`
- `tools/docs_only_fast_path.sh`
- `.github/workflows/ci.yml`
- a focused shared validation helper and integration test
- `tools/validate_upkeeper.sh`

Validation:
- focused real-Git diff-whitespace integration test
- `bash -n Upkeeper lib/upkeeper/*.bash tools/*.sh tests/*.bash testruns/*.sh Upkeeper.conf configurations/default.conf`
- `tools/run_tests.sh`
- `git diff --check`
- `tools/validate_upkeeper.sh --quick`

## Conservative CI Change Classification

Status: implemented locally; PR pending

Goal:
- close issue #866 by ensuring only an explicit, editorial docs allowlist can
  take the reduced CI gate
- make every operational/configuration/test/prompt/policy/unknown path take
  full deterministic validation
- expose and test the validation gate selected from the classifier result

Constraints:
- retain a cheap no-network docs-only path for narrowly descriptive material
- do not treat filename extensions, all docs, tests, or all shell/config files
  as evidence of low operational risk
- preserve CI concurrency and no-real-backend validation behavior

Files likely touched:
- `lib/upkeeper/change_scope.bash`
- `tools/docs_only_fast_path.sh`
- `.github/workflows/ci.yml`
- `tools/validate_upkeeper.sh`
- public docs describing the CI validation lanes

Validation:
- deterministic classifier/gate and backlog-authority cases for editorial and
  operational paths, including the no-library fallback classifier
- `bash -n Upkeeper lib/upkeeper/*.bash tools/*.sh tests/*.bash testruns/*.sh Upkeeper.conf configurations/default.conf`
- `tools/run_tests.sh`
- `tools/check_public_docs.sh --quick`
- `tools/validate_upkeeper.sh --quick`
- `git diff --check`

## Validator Fixture Reader Cleanup

Status: in progress

Goal:
- close issue #868 by ensuring the autoshelve validator fixture owns, terminates,
  and reaps its intentional active-reader process
- make a surviving fixture process a deterministic contract failure

Constraints:
- retain the active-reader race coverage and its bounded timing behavior
- do not weaken timeouts or use operator state as a fixture
- preserve failure-path cleanup as well as the successful path

Validation:
- reproduce the former escaped reader under quick validation
- `tools/validate_upkeeper.sh --quick`
- `tools/run_tests.sh`
- `git diff --check`
