# 0006 Run Taxonomy, Observability, and Cost Accounting Surface

Status: accepted

## Context

Upkeeper already emits `cycle.start`, `cycle.summary`, `cycle.exit`, `run.start`,
and `run.finish` evidence, plus local Lattice rows and operator-visible logs.
What was missing was a structured local taxonomy for explaining whether the
wrapper is saving time, reducing risk, and reducing manual work rather than
just producing more ceremony.

The desired surface should answer the same local question in a bounded way:

- what kind of run was this
- what cost and risk shape did it have
- what work did the wrapper actually do
- what evidence proves that claim

The acceptance direction explicitly avoids a full OpenTelemetry dependency on
the first pass. The first contract should be a local JSONL or summary export
that can be consumed by operators, Lattice, and validation without network
services or a heavyweight metrics stack.

## Decision

Upkeeper accepts a local run taxonomy plus observability/cost accounting
surface with `upkeeper export-run-summary --cycle-id X --format jsonl` as the
first implementation slice.

The export is local-only and private-operator by default. It should summarize
the cycle using a stable set of taxonomy dimensions and metrics derived from
local wrapper evidence such as `cycle.summary`, `cycle.exit`, `run.finish`,
validation results, and Lattice rows.

The taxonomy dimensions are:

| Dimension | Purpose |
| --- | --- |
| work outcome | Did the run cleanly complete, fix something, or stop without useful progress? |
| safety outcome | Did the run stay within safety guardrails, degrade, or block? |
| data outcome | Did the run stay docs-only, make mechanical edits, or touch source/evidence? |
| operator outcome | Did the run finish self-service, need manual intervention, or require review? |
| backend outcome | Did the backend launch, fail, or fall back to another path? |
| verification outcome | Did validation pass, fail, or not run? |
| cost outcome | Was the cycle cheap, moderate, expensive, or unknown? |
| recoverability outcome | Is the cycle replayable, repairable, restorable, or not recoverable? |

The metrics to capture are:

| Metric | Meaning |
| --- | --- |
| model/backend used | Which backend model or helper handled the cycle. |
| reasoning effort if known | The effective effort tier when the wrapper knows it. |
| backend attempts | How many backend launches or retries occurred. |
| fallback attempts | How many fallback-path attempts occurred. |
| wall time | The cycle's local elapsed time. |
| files reviewed | How many files the run actually inspected. |
| bugs found/fixed/reported | How many issues the run found, fixed, or reported. |
| tests run or harvested | How many tests or validator outputs the run consumed or produced. |
| manual interventions avoided | How much operator time the wrapper saved by keeping the loop local and deterministic. |
| restore events | Whether the run required or verified any restore action. |
| blocked cycles | Whether the run stopped due to safety, quota, or authority blocking. |

The minimal JSONL summary row schema is:

```json
{
  "schema_version": 1,
  "summary_ref": "upk:artifact:<sha256>",
  "cycle_ref": "upk:cycle:<cycle_id>",
  "run_ref": "upk:run:<cycle_run_hash>",
  "format": "jsonl",
  "model": "gpt-5.3-codex-spark",
  "reasoning_effort": "xhigh",
  "backend_attempts": 1,
  "fallback_attempts": 0,
  "wall_time_seconds": 97,
  "taxonomy": {},
  "metrics": {},
  "evidence_refs": [],
  "privacy": "private-operator"
}
```

The example is illustrative, not a committed runtime output. The export may
be a single-row JSONL file or a summary artifact with one row per cycle, but
the schema version, taxonomy vocabulary, metric names, and privacy class are
the compatibility contract for the first slice.

The summary export should prefer stable ids, hashes, and local evidence refs
instead of raw prose log scraping. It may reference `cycle.summary` and
`run.finish` lines, validation rows, and Lattice records as supporting evidence,
but it should not depend on a hosted metrics service or a new telemetry daemon.

## Consequences

- Operators get structured local evidence that Upkeeper is saving time and
  reducing risk instead of only producing raw logs.
- Lattice and local validation can consume a shared taxonomy without a full
  OpenTelemetry dependency.
- The first implementation stays local-only and privacy-safe by default.
- Future dashboards or exports can reuse the same taxonomy and metrics without
  inventing another vocabulary.
- The cost-accounting surface is explicit enough to reason about TCO without
  making the wrapper a metrics platform.

## Implementation Sequence

1. Add focused fixtures that validate the taxonomy dimension names, the metric
   names, and the local-only JSONL summary export contract.
2. Emit a private local summary export for `upkeeper export-run-summary
   --cycle-id X --format jsonl` using hashes or `upk:` refs for the summary and
   cycle links.
3. Teach the wrapper and local evidence consumers to read the summary export
   without requiring a telemetry service.
4. Add richer summary fields only after the initial JSONL shape is stable and
   validated locally.
5. Track any future hosted analytics or OpenTelemetry integration in a separate
   issue if it ever becomes necessary.

## Closure Boundary

This decision closes issue #223 by defining the run taxonomy, observability,
and cost accounting surface. The first contract is a local JSONL summary
export, and the wrapper intentionally stays clear of a full OpenTelemetry
dependency in this slice.
