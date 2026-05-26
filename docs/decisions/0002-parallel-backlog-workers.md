# 0002 Parallel Backlog Workers

Status: proposed

## Context

The normal backlog launcher intentionally owns one checkout, one branch, one PR,
one runtime root, and one active owner record. That is the safe default, but it
caps throughput when the operator wants several cheaper workers to handle
independent issues at the same time.

Manual parallel loops are unsafe because separate shells can pick the same issue,
dirty the same checkout, create ambiguous PR ownership, or exhaust quota without
a shared view of worker state.

## Decision

Parallel backlog work must start with a deterministic lease registry before any
backend launch. The first accepted primitive is local-only:

- `tools/backlog_parallel_leases.py` records worker leases under the backlog
  state root in `parallel-workers/leases.json`.
- A lease owns an issue number and, when known, a predicted target file.
- A second worker cannot claim the same issue or target while a lease is active.
- Leases expire by time-to-live and can be released after merge, deferral, or
  operator cleanup.
- A worker lease cannot use the main checkout or a worktree nested inside it.
- The command prints a compact status table for supervisors and deterministic
  key/value results for scripts.

This does not yet launch multiple workers. A future supervisor can layer worktree
creation, branch/PR creation, GitHub-visible lease publication, quota sharing,
and cleanup on this primitive.

## Consequences

- The default backlog path remains single-worker and conservative.
- The first parallel-worker invariant is locally testable without backend Codex
  and without GitHub writes.
- Future live parallel mode must still add remote visibility before unattended
  distributed use; local leases alone are sufficient only for one machine.
- The compatibility surface for this first slice is the lease command's
  issue/target conflict behavior, checkout isolation rule, expiration behavior,
  release command, and status table.
