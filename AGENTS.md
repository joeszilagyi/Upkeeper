# Agent Contract

This repository is the central source of truth for Upkeeper wrapper behavior.

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
