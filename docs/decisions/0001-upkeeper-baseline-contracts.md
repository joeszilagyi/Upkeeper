# 0001 Upkeeper Baseline Contracts

Status: accepted

## Context

Upkeeper has several contracts that were already enforced through code, docs, or
operator practice, but they were spread across README, AGENTS, change notes, and
private review history. The project needs one durable decision record for these
baseline choices.

## Decision

Upkeeper accepts these baseline contracts:

- Shell-sourced config is trusted local input only. Operators may use
  `Upkeeper.conf`, `configurations/default.conf`, explicit config files, and
  machine-local env files, but they must not treat untrusted config as safe.
- The central-first symlink model is the default propagation mechanism. Client
  repositories should use a local symlink to the central `Upkeeper` entrypoint
  instead of tracked wrapper copies.
- Validation does not run real Codex backend work by default. CI and local
  validation use dry-runs, fake Codex fixtures, parser fixtures, and stress
  corpus local mode.
- Local runtime evidence is ignored by Git and is not source: `runtime/`,
  `Upkeeper.log`, transcripts, manifests, locks, postmortems, and Codex session
  files stay local unless a future policy explicitly says otherwise.
- Fallback and postmortem flows must preserve workload boundaries, avoid unsafe
  source mutation, and stop visibly when safety prerequisites are missing.
- Quota snapshots are parsed from local `CODEX_HOME` session evidence. They are
  advisory guardrail input, not a remote accounting authority.

## Consequences

- Operators get predictable local behavior without hidden backend work in
  validation.
- Client repos stay cleaner because central wrapper behavior changes in one
  place.
- Runtime and config trust boundaries must remain explicit in docs, validation,
  and error messages.
- Future changes that weaken these contracts need a new decision record or a
  documented superseding decision.
