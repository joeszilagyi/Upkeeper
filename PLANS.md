# Plans

This file captures active or recently completed implementation plans for complex
Upkeeper changes. Keep entries brief and update their status before merge.

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
