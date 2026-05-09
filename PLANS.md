# Plans

This file captures active or recently completed implementation plans for complex
Upkeeper changes. Keep entries brief and update their status before merge.

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
