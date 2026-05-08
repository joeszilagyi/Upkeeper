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

## Release Notes Discipline

- Keep root `change_notes.md` current for notable Upkeeper behavior,
  documentation, default, prompt-contract, quota, fallback, logging, selection,
  or operator-ergonomics changes.
- Any committed `UPKEEPER_VERSION` bump should have a matching dated entry in
  `change_notes.md` unless the version number never existed as a committed
  wrapper state.
- Release-note entries should describe operator-facing impact, not just commit
  mechanics.
