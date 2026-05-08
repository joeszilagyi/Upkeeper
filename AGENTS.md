# Agent Contract

This repository is the central source of truth for Upkeeper wrapper behavior.

## Repository Layout

- `Upkeeper` is the executable entrypoint and loader for the central wrapper.
- `lib/upkeeper/*.bash` contains sourced runtime modules. Keep module changes
  narrow and respect the load-order notes in `lib/upkeeper/README.md`.
- `prompts/*.md` contains default and opt-in review-module contracts.
- `docs/` contains public operator documentation. `docs/scripts/upkeeper.md`
  mirrors operator-facing help and must stay aligned with `./Upkeeper --help`.
- `tools/` contains deterministic local validation and corpus harnesses.
- `tests/*.bash` contains focused local unit tests.
- `testruns/*.sh` contains operator launchers for repeatable dry-run/live
  scenarios.
- `runtime/`, `Upkeeper.log`, transcripts, manifests, locks, and postmortem
  artifacts are local evidence and must not be committed.

## Planning Rules

- For complex changes, create or update root `PLANS.md` before broad editing.
  A complex change is one that spans multiple runtime modules, changes a public
  contract, changes target selection, changes config semantics, alters fallback
  or quota behavior, or needs more than one meaningful implementation step.
- Keep `PLANS.md` practical: goal, constraints, files likely touched, validation
  commands, rollout/compatibility notes, and current status are enough.
- Small single-file docs or test-only patches do not need a plan unless the user
  asks for one.
- Do not run real backend Codex validation unless the user explicitly requests
  it. Prefer `UPKEEPER_DRY_RUN=1`, fake Codex fixtures, unit tests, and the
  local stress corpus.

## Required Validation Commands

Use the smallest command set that covers the change, and record anything that
could not be run.

For shell/runtime changes in `Upkeeper`, `lib/upkeeper`, `tools`, `tests`,
`testruns`, config files, or launcher examples:

```sh
bash -n Upkeeper lib/upkeeper/*.bash tools/*.sh tests/*.bash testruns/*.sh Upkeeper.conf configurations/default.conf
for test_script in tests/*.bash; do bash "$test_script"; done
git diff --check
tools/validate_upkeeper.sh --quick
```

For docs, prompt, help, release-note, README, AGENTS, compatibility, security,
or public documentation policy changes:

```sh
tools/check_public_docs.sh --quick
tools/validate_upkeeper.sh --quick
git diff --check
```

When `./Upkeeper --help`, `docs/scripts/upkeeper.md`, README examples, prompt
module docs, or operator-visible defaults change, also verify the relevant
operator-facing text directly, for example:

```sh
./Upkeeper --help
./Upkeeper --version
```

For target-selection, manifest, explicit-target, failure-queue, startup-anomaly,
or symlinked-client behavior:

```sh
tools/validate_upkeeper.sh --quick
tools/validate_upkeeper.sh --full
tools/stress_upkeeper_corpus.sh --local
```

The full validator and stress corpus must remain no-quota local validation.
They should not launch real backend Codex work.

## Done Criteria

- The patch is scoped to the requested behavior or documentation change.
- Public docs, help text, compatibility notes, prompt docs, and the current
  year's `change_notes_YYYY.md` are updated when operator-visible behavior
  changes.
- Backward-compatible behavior is preserved unless the same patch documents why
  compatibility is unsafe or impossible.
- New reusable parsing, selection, config, manifest, quota, fallback, or
  transcript behavior has deterministic local validation.
- No `runtime/`, `Upkeeper.log`, transcripts, local manifests, locks, Codex
  session files, or other machine-local evidence is committed.
- Validation commands appropriate to the touched files have passed, or any
  skipped command is named with the reason.

## PR And Git Expectations

- Work on a feature branch and use a PR for changes that are pushed to GitHub.
- Keep commits coherent and explain operator-facing impact in the PR body.
- Wait for CI on the PR before merging.
- After merge, verify local `main` is clean and synced with `origin/main`.
- Delete or prune merged feature branches so the repo returns to a clean sheet.

## Central-First Rule

- Make Upkeeper behavior changes in this repository, primarily in the root
  `Upkeeper` entrypoint and paired `lib/upkeeper` modules.
- Do not patch client repositories just to propagate wrapper behavior, help text,
  prompt text, or operator-guide snapshots.
- Client repositories should run Upkeeper through a local symlink such as:

  ```sh
  ln -s /home/joe/projects/Upkeeper/main/Upkeeper ./Upkeeper.sh
  ```

- Once the central `Upkeeper` entrypoint or paired modules change, symlinked
  clients pick up the new behavior on their next loop without tracked
  client-repo changes.

## Client Repo Boundary

- Keep `Upkeeper.sh`, `Upkeeper.log`, and bootstrapped
  `docs/scripts/upkeeper.md` local to each client checkout.
- Client repos should ignore those local Upkeeper artifacts.
- Do not create, refresh, or version-bump tracked client `docs/scripts/upkeeper.md`
  files merely to match the central wrapper version.
- Only change a client repo when stress testing finds a real project bug,
  project documentation issue, or project-local configuration issue that should
  be tracked independently of Upkeeper.

## Stress Testing Intent

Upkeeper is expected to stress test both itself and client repositories.

- If the failure is in Upkeeper selection, quota handling, prompt contracts,
  fallback behavior, logging, or local wrapper ergonomics, patch this repository.
- If the failure is in the client project's source, tests, validators, or domain
  docs, patch the client project through its normal branch and PR rules.
- If the failure is only stale local wrapper state in a client checkout, fix the
  local symlink or ignored local artifact; do not add tracked client churn.

## Cleanup Discipline

- Treat client `Upkeeper.log`, `runtime/`, and local copied wrappers as evidence
  or machine-local state, not source.
- Before touching a client repo, check whether the requested change belongs in
  central Upkeeper instead.
- When unsure, prefer a central Upkeeper patch plus a local symlink verification.

## Compatibility Discipline

- Keep Upkeeper backward compatible unless there is literally no responsible
  choice, such as a security/safety risk or an external dependency change that
  makes compatibility impossible.
- Treat `docs/compatibility.md` as the binding operator-visible feature surface.
  Preserve that surface through aliases, shims, warnings, or migration paths
  whenever feasible.
- If a breaking change is unavoidable, document the reason, operator impact,
  migration path, and validation coverage in the same committed state.

## Configuration Discipline

- Keep the central default config in root `Upkeeper.conf`.
- Keep reusable named profiles under `configurations/`, with
  `configurations/default.conf` as the basic profile template.
- Do not split the active default into chained config files unless the project
  explicitly changes that contract; one selected config file should define a
  run profile.
- Treat CLI flags as one-cycle overrides over config-file defaults.

## Selection And Manifest Discipline

- Treat `runtime/upkeeper-file-manifest.json` as local runtime state, not source.
  Do not commit generated manifests from client repos or this central checkout.
- Keep normal target selection local and deterministic before Codex starts.
  Manifest refresh, direct enumeration, target-root/depth filters,
  include/exclude globs, ordering, and review-module selection filters should
  not require another model call.
- Preserve `--target-file` as the strongest one-cycle pin. It should override
  the manifest, normal timestamp rotation, local failure queue, and selection
  filters unless the target is physically impossible or unsafe to read.
- Selection review-module filters narrow candidate files only. They do not
  request P24 through P28 prompt modules; use `--review-module`,
  `--review-modules`, or shorthand flags when the prompt module itself is
  wanted.

## Release Notes Discipline

- Keep the current year's root `change_notes_YYYY.md` file current for notable
  Upkeeper behavior, documentation, default, prompt-contract, quota, fallback,
  logging, selection, or operator-ergonomics changes.
- Release notes are annual root files. On the first notable change in a new
  calendar year, start a new root file such as `change_notes_2027.md` instead
  of appending to the previous year.
- Any committed `UPKEEPER_VERSION` bump should have a matching dated entry in
  the current year's `change_notes_YYYY.md` unless the version number never
  existed as a committed wrapper state.
- Release-note entries should describe operator-facing impact, not just commit
  mechanics.

## Public Documentation Discipline

- Treat every committed patch and release as public project material.
- Keep docs, comments, prompts, help text, examples, logs, and release notes
  understandable from tracked source without private chat history.
- Use `docs/public-documentation-policy.md` as the writing and review standard.
- Use P26 for explicit public documentation and comment clarity review.
- Use P27 when a run should leave a concise educational debrief explaining what
  went wrong, why it mattered, how it was fixed, and what to improve.
- Run `tools/check_public_docs.sh` or `tools/validate_upkeeper.sh --quick` when
  public documentation, prompt contracts, help text, or release notes change.
