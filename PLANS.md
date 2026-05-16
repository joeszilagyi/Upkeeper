# Plans

This file captures active or recently completed implementation plans for complex
Upkeeper changes. Keep entries brief and update their status before merge.

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
