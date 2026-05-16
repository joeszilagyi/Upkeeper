# Upkeeper Known Issues

This file is the tracked release-readiness view of unresolved risk. GitHub
issues remain the source for detailed discussion, ownership, and closure.

## Current Major Risk Areas

- Lattice integrity is still being repaired. Do not treat Lattice as sole
  custody authority until open Lattice data-integrity blockers are resolved.
- Parallel backlog execution is not implemented. Run one active backlog worker
  per checkout unless using isolated worktrees with explicit human supervision.
- Cross-platform support is proven primarily on Linux. Other platforms need
  tracked validation before being treated as supported.
- Bash remains the runtime implementation language. A Python migration may be
  useful later, but it needs a staged compatibility plan.
- `jq` remains required for current runtime JSON bridges and validation
  fixtures.
- Fault-injection coverage exists but is early. The registry tracks more
  scenarios than are currently implemented.

## Operational Caveats

- Machine health outranks workload. Pre-contact backup, obligation, startup
  anomaly, dependency, or dirty-worktree failures should be repaired or
  preserved before selecting new issue work.
- Local runtime evidence is intentionally private and should not be committed.
- Symlinked clients should pick up central wrapper behavior through the central
  `Upkeeper` entrypoint rather than tracked client wrapper copies.

## Keeping This File Current

Update this file when a risk affects release readiness, operator expectations,
or whether future automation can safely trust a subsystem. Do not duplicate
every GitHub issue; summarize the release-relevant risk and link through the
issue tracker or related docs when detail is needed.
