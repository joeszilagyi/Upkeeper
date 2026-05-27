# Kirk Protocol Invariant Registry

This registry is the tracked naming surface for control-plane invariants that
must remain true before Upkeeper spends backend quota, stages source, validates a
batch, or merges a backlog PR. Stable ids use `KP-###` and are mirrored by
`tools/upkeeper_control_plane_audit.py`.

Every invariant has a description, severity, evidence source, remediation
policy, and deterministic fixture coverage. New anomaly classes should attach to
an existing invariant when the policy is the same, or add a new `KP-###` row
when the operator action or evidence source is materially different.

| id | description | severity | evidence source | remediation policy | quick fixture coverage |
| --- | --- | --- | --- | --- | --- |
| `KP-001` | Local evidence artifacts must not become tracked source. | high | `git ls-files`, tracked source-boundary classes | Block before staging and create an automation obligation. | tracked root `$db`; tracked `runtime/` manifest; tracked `Upkeeper.log`; tracked transcripts; tracked postmortems |
| `KP-002` | Only explicitly listed untracked scratch artifacts may be auto-cleaned. | medium | `git status`, safe cleanup table | Clean local scratch, re-audit, and leave non-listed artifacts untouched. | untracked root `$db`; Python bytecode cache |
| `KP-003` | Unknown local-evidence-like root artifacts must fail closed. | high | root artifact classification from `git status` or `git ls-files` | Block or create an automation obligation until reviewed. | root `debug.log` fixture |
| `KP-004` | Open obligations and deferred issue records must stay visible before new work. | high | runtime obligation inventory and optional state-root inventory | Report existing custody and avoid treating the queue as clean. | open automation obligation fixture |
| `KP-005` | Pageable error and nonzero terminal evidence must map to actionable custody. | high | recent loop log `cycle.exit` and `PAGE [ERROR]` markers | Create an obligation or require explicit expected-fixture classification. | fake nonzero cycle exit; fake `PAGE [ERROR]` contradiction |
| `KP-006` | Active owner lock evidence must be visible before concurrent writers run. | medium | runtime active-lock inventory | Report active lock and require owner verification. | active lock fixture |
| `KP-007` | Before/after audit snapshots must preserve resolved and remaining invariant state. | medium | audit snapshot delta | Write snapshot evidence around staging, validation, and merge phases. | before/after safe-cleanup snapshot fixture |
| `KP-008` | Unknown control-plane finding classes must become permanent classifiers before they can resolve. | high | policy dispatch and lineage records | Block, create an obligation, and require classifier/invariant/fixture promotion. | injected future finding class fixture |

## Snapshot Boundaries

The backlog launcher records local no-backend control-plane snapshots around:

- backlog branch sync before anomaly/obligation selection
- pre-staging source-boundary audit, with before/after remediation delta
- batch validation, including failed-validation snapshots
- merge stewardship before validation and after local main cleanup

Snapshot files live under the local backlog state root and are machine-local
evidence. They must not be committed.

## Closed-Loop Lineage

The audit can write local lineage records under
`runtime/upkeeper-control-plane-lineage` or a caller-provided lineage root. Each
record preserves first seen, last seen, source cycle, classifier version,
invariant id, remediation decision, and resolution state. Known findings can be
resolved when they disappear from a later audit. Unknown finding classes remain
`promotion_required` until source adds the classifier, invariant registry entry,
and deterministic fixture that make the class permanent.

## Historical Escaped Classes

The quick audit fixture suite keeps the following May 2026 escaped classes
non-regressible:

- literal root `$db` scratch artifacts entering or approaching source
- Python bytecode cache residue appearing in the worktree
- tracked runtime/log/transcript/postmortem evidence
- false clean runs despite `PAGE [ERROR]` or nonzero `cycle.exit` evidence
- active locks and open obligations being present before normal work
- unsafe root evidence-like files such as `debug.log`
