# 0005 Provenance and Evidence-Package Exports for Lattice Cycles

Status: accepted

## Context

Lattice already stores evidence about cycles, but the operator still lacks a
portable, cycle-scoped package that explains provenance without scraping prose
logs or forcing a heavy dependency graph into the first pass.

The desired shape is recognizable to existing provenance ecosystems:

- W3C PROV style entities, activities, and agents
- OpenLineage style jobs, runs, datasets, and facets
- RO-Crate or BagIt style portable evidence bundles

The missing product decision is the local export contract for one cycle. The
package needs to preserve provenance and evidence relationships while staying
private-operator by default, local-only, and light enough to implement without
a new external service.

The export surface is related to, but distinct from, the JSONL import/export
contract in `docs/lattice.md`. JSONL remains Lattice's portable row exchange
surface. The cycle evidence package is the portable graph export for one cycle.

## Decision

Upkeeper accepts a cycle evidence-package export surface with
`upkeeper export-cycle --cycle-id X --format json` as the first implementation
slice.

The JSON export is the normative design surface for issue #219:

- it is local-only
- it is private-operator by default
- it does not require backend Codex
- it does not require a heavy new dependency
- it packages one cycle's provenance graph and evidence refs in one portable
  JSON document

Future `--format ro-crate` and `--format bagit` options may wrap the same
underlying graph, but they must not change the provenance meaning of the
records. They are envelope formats, not different authority models.

The provenance graph should map the cycle's durable objects into the familiar
entity/activity/agent model:

| Class | Examples |
| --- | --- |
| entities | selected file, compiled prompt, backup artifact, transcript, final response, diff/test output |
| activities | target selection, pre-contact backup, backend run, validation, restore, export |
| agents | wrapper, model/backend, human operator |

The minimal JSON package schema is:

```json
{
  "schema_version": 1,
  "package_ref": "upk:artifact:<sha256>",
  "cycle_ref": "upk:cycle:<cycle_id>",
  "run_ref": "upk:run:<cycle_run_hash>",
  "format": "json",
  "model": "prov",
  "entities": [],
  "activities": [],
  "agents": [],
  "provenance_edges": [],
  "evidence_refs": [],
  "privacy": "private-operator"
}
```

The example is illustrative, not a committed runtime output. A future emitter
may flesh out node and edge fields, but the schema version, ref semantics, and
privacy class remain the design contract for the first slice.

Each package should preserve stable `upk:` ids where possible instead of raw
paths or command text. It may reference the selected target, prompt, backup,
transcript, response, validation, and diff/test artifacts as separate graph
nodes or refs, but it should not expose raw secret-bearing paths in identifier
segments.

## Consequences

- Operators get a portable provenance package for a cycle without giving up the
  existing Lattice row model.
- Future tools can export or inspect provenance without scraping prose logs.
- The first implementation can stay dependency-light and local-only.
- JSONL export/import stays the canonical portable row exchange surface; the
  cycle evidence package is a separate graph export surface.
- Future RO-Crate and BagIt work can reuse the same underlying graph instead of
  inventing a second provenance vocabulary.

## Implementation Sequence

1. Add fixtures that validate the provenance vocabulary, the package schema
   fields, and the local-only no-backend export contract.
2. Emit a private local JSON evidence package for `upkeeper export-cycle
   --cycle-id X --format json` using hashes, HMACs, and `upk:` refs for the
   package and graph nodes.
3. Add optional RO-Crate or BagIt envelope formats only after the JSON export
   shape is stable.
4. Add read-only inspection helpers or importers only after the package schema
   has been validated locally.
5. Track any future public-safe or networked export path in a separate issue if
   it ever becomes necessary.

## Closure Boundary

This decision closes issue #219 by defining the provenance and
evidence-package export surface for Lattice cycles. The first contract is a
local JSON export proposal, and the future RO-Crate or BagIt formats are
explicitly follow-up envelope work.
