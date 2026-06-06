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
- [0004 Run transaction, rollback, and replay contracts](0004-run-transaction-contracts.md):
  accepted lifecycle and helper-command contract for one cycle as a bounded
  transaction with read-only explain/replay helpers.
- [0005 Provenance and evidence-package exports for Lattice cycles](0005-provenance-and-evidence-package-exports.md):
  accepted local JSON evidence-package export contract for one cycle, with
  future RO-Crate and BagIt envelopes as follow-up work.
- [0006 Run taxonomy, observability, and cost accounting surface](0006-run-taxonomy-observability-and-cost-accounting.md):
  accepted local JSONL summary export contract for cycle outcomes, metrics,
  and cost accounting without a full OpenTelemetry dependency.
- [0007 Adapter and plugin contract with side-effect declarations](0007-adapter-plugin-contract-with-side-effect-declarations.md):
  accepted bounded integration contract for future adapters, exporters,
  trackers, feeds, validators, and reporters.
