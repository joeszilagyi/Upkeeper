# Upkeeper Decision Log

This directory records durable product and architecture choices. Decision files
should be short, dated when useful, and linked from related docs when the choice
changes operator behavior.

## Format

Each decision should include:

- Status: proposed, accepted, superseded, or retired.
- Context: what pressure or ambiguity caused the decision.
- Decision: the chosen contract.
- Consequences: compatibility, validation, security, or operator impact.

## Current Decisions

- [0001 Upkeeper baseline contracts](0001-upkeeper-baseline-contracts.md):
  trusted shell-sourced config, central-first symlink model, no real backend in
  validation by default, ignored local runtime evidence, fallback/postmortem
  safety boundaries, and local quota snapshot parsing.
- [0002 Parallel backlog workers](0002-parallel-backlog-workers.md):
  proposed local lease registry for isolated backlog workers before any live
  parallel backend launcher exists.
- [0003 Schema-gated typed-signal airlocks](0003-schema-gated-airlocks.md):
  accepted vocabulary and implementation sequence for turning raw evidence
  into validated records before it can drive wrapper authority.
