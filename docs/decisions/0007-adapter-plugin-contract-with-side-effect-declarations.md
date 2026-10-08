# 0007 Adapter and Plugin Contract With Side-Effect Declarations

Status: accepted

## Context

Upkeeper should not become one giant shell brain. Future integrations need to
stay bounded, reviewable, and easy to reason about before they are allowed to
touch wrapper authority.

The intended integration surface includes:

- selector adapter
- backup adapter
- sandbox adapter
- lineage exporter
- citation exporter
- issue tracker adapter
- feed adapter
- validator adapter
- reporter adapter

Each of those adapters can have very different authority needs, so the wrapper
needs a contract that declares side effects instead of assuming them.

## Decision

Upkeeper accepts an adapter/plugin contract where every adapter declares the
same bounded surface before it can integrate with the wrapper:

- inputs
- outputs
- side effects
- network use
- file write scope
- secret needs
- Lattice events emitted
- failure modes
- validation expectations

The declaration is the contract. The wrapper or a later registry may consume
the declaration, but the contract is the same whether the adapter is a pure
selector, a backup writer, a sandbox provider, an exporter, a tracker, a feed
reader, a validator, or a reporter.

The minimal schema-v1 shape is:

```json
{
  "schema_version": 1,
  "adapter_id": "selector-default",
  "adapter_type": "selector_adapter",
  "inputs": [],
  "outputs": [],
  "side_effects": [],
  "network_use": false,
  "file_write_scope": "none",
  "secret_needs": [],
  "lattice_events_emitted": [],
  "failure_modes": [],
  "validation_expectations": [],
  "privacy": "private-operator"
}
```

The example is illustrative, not a committed runtime output. A later registry
or manifest may add lookups, aliases, or richer metadata, but the declared
fields and their meanings are the stable first-pass contract.

The contract is intentionally conservative:

- network use must be explicit
- file-write scope must be explicit
- secret needs must be explicit
- emitted Lattice events must be explicit
- validation expectations must be explicit

This keeps future integrations reviewable and makes it possible to separate a
pure adapter from a side-effectful one without guessing from the name alone.

## Consequences

- Future integrations can be reviewed against declared authority before they
  become part of the wrapper.
- Side-effectful adapters stay bounded instead of hiding behind generic shell
  code.
- A later adapter registry can stay lightweight because the contract already
  names the required fields.
- The adapter surface stays compatible with the local-first wrapper model.
- The wrapper can keep supporting selector, backup, sandbox, exporter,
  tracker, feed, validator, and reporter integrations without becoming a
  monolith.

## Implementation Sequence

1. Add focused fixtures that validate the declared adapter fields and reject
   missing side-effect declarations before any registry exists.
2. Add a narrow adapter manifest or registry helper only after the field
   vocabulary is stable.
3. Keep any richer plugin runtime optional and local-first, not a mandatory
   daemon or hosted service.
4. Track any future networked or distributed plugin system in a separate issue
   if it ever becomes necessary.

## Closure Boundary

This decision closes issue #225 by defining the adapter/plugin contract and
the required side-effect declaration fields for future Upkeeper integrations.
Runtime adapters remain future work; the first slice is the declared contract
and its local validation.
