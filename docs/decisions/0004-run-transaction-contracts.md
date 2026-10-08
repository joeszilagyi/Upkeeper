# 0004 Run Transaction, Rollback, and Replay Contracts

Status: accepted

## Context

Upkeeper already emits cycle start, cycle summary, cycle exit, run finish,
selected-target backup, validation, and Lattice evidence. What was missing was
the durable contract that explains a single agent run as a transaction:

1. prepare
2. select target
3. snapshot and/or backup
4. launch backend under a declared capability profile
5. capture observed side effects
6. classify diff/output
7. verify
8. commit, rollback, or leave for human review
9. record the transaction

Without that contract, future helper commands such as `upkeeper explain` and
`upkeeper replay` risk becoming a second ad hoc lifecycle vocabulary instead of
sharing the same state machine, evidence links, and authority boundaries that
the wrapper already uses.

The transaction contract is related to, but distinct from, the run BOM contract
in `docs/run-bom-identifiers.md`. The BOM names evidence objects. The
transaction contract names the lifecycle for one cycle and the helper commands
that inspect or verify it.

## Decision

Upkeeper treats each agent run as a bounded transaction with three durable
resolution classes:

- `commit`: accept the tracked result and record it as the durable outcome for
  the cycle.
- `rollback`: revert wrapper-owned tentative changes from the current cycle and
  preserve the evidence for later repair or review.
- `human_review`: stop after validation, keep the patch or evidence, and leave
  the final decision to the operator.

The transaction lifecycle is:

```text
prepare -> select target -> snapshot/backup -> launch backend -> capture side effects -> classify diff/output -> verify -> resolve -> record
```

Each stage has a narrow contract:

| Stage | Contract |
| --- | --- |
| prepare | Normalize config, queue state, quota state, and authority inputs before any backend launch. |
| select target | Choose one deterministic target or honor a stronger explicit target pin. |
| snapshot/backup | Create the selected-target backup or the documented equivalent pre-contact protection before the prompt grants backend authority. |
| launch backend | Build the backend packet, capability profile, and sandbox boundary for one cycle. |
| capture side effects | Record observed writes, changed paths, outputs, and failure markers as local evidence. |
| classify diff/output | Decide whether the cycle is clean, fixed, blocked, needs human review, or produced a regression. |
| verify | Run the local proof steps that justify the recorded outcome. |
| resolve | Commit, rollback, or leave for human review without silently inventing a fourth state. |
| record | Write the durable transaction evidence and link it to the cycle and run identifiers. |

Rollback means wrapper-owned rollback, not a silent rewrite of operator-owned
history. It may clean up tentative scratch output, revert wrapper-created source
changes, or remove temporary artifacts that belong to the current cycle. It does
not erase durable source history, does not invent new authority, and does not
pretend that already-published GitHub or Git state can be rewound without an
explicit follow-up commit.

Replay means local reconstruction and verification of the recorded transaction
packet. The default replay contract is read-only and no-quota:

- `upkeeper explain --cycle-id X` reads the recorded transaction evidence and
  produces a bounded human-readable explanation.
- `upkeeper replay --cycle-id X` reconstructs the recorded transaction packet
  and compares the observed outputs, selection, backup, and verification
  evidence against the stored record.
- `upkeeper reproduce-selection --cycle-id X` reruns only the deterministic
  selection phase from the recorded source state and filters.
- `upkeeper verify-backup --backup-id X` checks backup presence, permissions,
  and restore-readiness.
- `upkeeper verify-diff --cycle-id X` checks the recorded diff or changed-path
  claim against the stored transaction evidence.

Replay does not silently relaunch backend Codex, does not silently rewrite
tracked source, and does not introduce a hidden live-rerun mode. A future live
re-execution command would need its own explicit contract and review.

The schema design for future transaction records is:

```json
{
  "schema_version": 1,
  "transaction_ref": "upk:artifact:<sha256>",
  "cycle_ref": "upk:cycle:<cycle_id>",
  "run_ref": "upk:run:<cycle_run_hash>",
  "stage_sequence": [
    "prepare",
    "select_target",
    "snapshot_backup",
    "launch_backend",
    "capture_side_effects",
    "classify_diff_output",
    "verify",
    "resolve",
    "record"
  ],
  "selection_ref": "upk:target:<repo_hash>:<path_hash>:<content_hash>",
  "backup_ref": "upk:backup:<backup_id>",
  "validation_refs": ["upk:validation:<validation_id>"],
  "output_refs": ["upk:artifact:<sha256>"],
  "resolution": "commit",
  "privacy": "private-operator"
}
```

The example is illustrative, not a committed runtime output. The transaction
record may be serialized as an artifact and indexed by `upk:` references later,
but the runtime helper contract is still a design contract until a future
emitter exists.

## Consequences

- Operators get one shared vocabulary for cycle explanation, replay,
  selection reproduction, backup verification, diff verification, commit,
  rollback, and human review.
- Future runtime helpers can be implemented without inventing a second
  lifecycle model.
- The transaction contract stays compatible with the run BOM namespace by
  reusing the existing `upk:` reference vocabulary instead of adding a new
  identifier kind.
- A future live rerun or apply-style replay command must be added explicitly
  rather than smuggled in under the replay name.
- Validation can now point at a durable contract instead of at chat history or
  terminal scrollback.

## Implementation Sequence

1. Add focused fixtures that validate the transaction lifecycle vocabulary,
   replay contract, and command contract before any runtime helper exists.
2. Emit a private local transaction record when a future cycle needs durable
   replay evidence, using hashes/HMACs and `upk:` refs rather than raw paths.
3. Teach `upkeeper explain` and `upkeeper replay` to consume the record without
   granting new write authority.
4. Add `reproduce-selection`, `verify-backup`, and `verify-diff` helpers as
   read-only verification commands before any live re-execution mode is
   considered.
5. Track any live rerun or apply-style command in a separate issue and
   decision if it ever becomes necessary.

## Closure Boundary

This decision closes issue #217 by defining the run transaction model and the
helper-command contract for explain, replay, selection reproduction, backup
verification, and diff verification. Runtime helpers remain future work, and
the contract intentionally stays read-only until a later implementation slice
adds the corresponding commands.
