# Upkeeper Roadmap

This roadmap is a tracked planning surface, not a promise of delivery dates.
Use it to keep release direction visible without relying on chat history.

## Now

- Keep unattended local loops observable, non-destructive, and easy to stop.
- Reduce recurring blockers in backlog and burn-cycle automation.
- Keep no-quota validation fast enough for normal edit loops.
- Harden evidence boundaries for logs, transcripts, runtime state, Lattice, and
  pre-contact backup.
- Keep review-module numbering and public docs stable.

## Next

- Expand deterministic fault-injection coverage from the first implemented
  `FI-###` scenarios.
- Convert recurring operator lessons into focused tests, validators, or docs.
- Continue reducing Lattice integrity blockers before treating it as a custody
  authority.
- Improve release-readiness reporting so the repo can explain what changed,
  what remains risky, and what validation proved.
- Add focused schema-gated typed-signal fixtures for the highest-risk existing
  boundaries: LLM status/action parsing, runtime obligations, and bug-report
  draft blocks.
- Build a live parallel backlog-worker supervisor on the accepted local lease
  primitive, including isolated worktree creation, independent PRs, remote
  visibility, quota sharing, and cleanup.

## Later

- Decide whether Bash remains the long-term implementation shell or whether a
  staged Python migration is justified.
- Define plugin or adapter boundaries for tools that should integrate with
  Upkeeper without becoming part of the core wrapper.
- Add broader cross-platform proof only after the Linux contract is stable.
- Consider a typed non-shell config profile after current Bash config behavior
  is fully documented and compatibility-safe.

## Defer Until Explicitly Planned

- Hosted execution.
- Background daemons or services.
- Real backend stress runs by default.
- Publishing local runtime evidence automatically.
- Treating Lattice as authoritative custody before open integrity blockers are
  resolved.
