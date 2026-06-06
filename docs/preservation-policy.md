# Upkeeper Preservation Policy

Upkeeper evidence is operational material, not one undifferentiated archive.
Logs, transcripts, selected-target backups, Lattice rows, JSONL exports,
postmortems, recovery records, obligations, manifests, and local reports have
different privacy risk, recovery value, and retention pressure.

This policy defines evidence temperature, artifact privacy classes, default
handling rules, and recovery expectations. It is a local operator policy unless
a specific artifact is deliberately sanitized and promoted into tracked source
or a public issue. `docs/source-rights-metadata.md` defines the separate
source-rights review used before OSINT or citation material may enter prompts,
exports, archives, or public evidence packets.

## Evidence Temperature

Canonical evidence temperature values:

- hot
- warm
- cold
- frozen
- trashable

| Temperature | Meaning | Default handling |
| --- | --- | --- |
| hot | Needed for the current cycle, immediate restore, or the next mandatory remediation pass. | Keep private, uncompressed, nearby, and protected from pruning until the cycle or obligation resolves. |
| warm | Useful for recent debugging, retry decisions, or short-term anomaly custody. | Keep locally under ignored state; may be compressed or summarized after the immediate window. |
| cold | Retained for audit, release history, reproducibility, or longer-term trend analysis. | Prefer redacted summaries, hashes, stable ids, and bounded samples over raw transcripts or full logs. |
| frozen | Append-only or never mutate in place because it is proof, a schema boundary, a release note, or a durable audit fact. | Preserve as tracked docs/source, append-only local evidence, or immutable-by-convention export; corrections should be additive. |
| trashable | Safe to prune because the durable lesson, summary, fix, or required proof has already been preserved elsewhere. | Delete or rotate on the local cleanup path; do not spend model or review time preserving it. |

Temperature can change. A transcript tail is hot during a failed cycle, warm
while an obligation is open, cold after a bug and validation fixture preserve
the lesson, and trashable after the raw local evidence is no longer needed. A
release note or compatibility rule can be frozen immediately.

## Artifact Privacy Classes

Canonical artifact privacy classes:

- public-safe
- private-operator
- secret-adjacent

| Privacy class | Meaning | Publication rule |
| --- | --- | --- |
| public-safe | May be committed, quoted, shown in PRs, or published because it has been written for public consumption and contains no local private evidence. | Safe to publish after ordinary review. |
| private-operator | May contain local paths, command output, transcript fragments, model/session state, machine state, or sensitive debugging context. | Keep ignored and local unless deliberately summarized or sanitized. |
| secret-adjacent | Must not enter prompts, public docs, committed artifacts, or issue comments because it may contain credentials, private keys, tokens, private identities, customer data, or raw sensitive source. | Do not publish; rotate real secrets if exposed. |

The default class for raw runtime evidence is `private-operator`. An artifact
becomes `public-safe` only after it is intentionally written or sanitized for
tracked source, public docs, PR text, or a GitHub issue. Anything containing or
near credentials, private age identities, tokens, private keys, PII-bearing
data, or customer material is `secret-adjacent` regardless of where it was
found. Paid/private source text and license-restricted source text require
source-rights review before any use beyond metadata.

## Artifact Handling Matrix

| Artifact | Default temperature | Default privacy class | Keep/prune/export rule |
| --- | --- | --- | --- |
| `Upkeeper.log` | warm | private-operator | Keep locally for recent debugging and anomaly custody; rotate or summarize before publication. |
| Backend transcripts | warm | private-operator | Keep under ignored private runtime state; quote only short sanitized excerpts when needed. |
| Selected-target backups | hot | private-operator or secret-adjacent | Keep for immediate restore; encrypted mode is preferred and secret-bearing backups stay private. |
| Backup sidecars and restore metadata | hot | private-operator | Keep with the backup long enough to restore; publish only redacted summaries. |
| Lattice SQLite database rows | warm | private-operator | Keep local as supporting evidence; do not treat as public or sole custody authority. |
| Lattice JSONL exports | cold | private-operator by default | Export with redaction by default; `--include-raw` remains local and sensitive. |
| Cycle evidence packages | cold | private-operator by default | Export portable provenance graphs with stable ids and bounded evidence refs; see `docs/decisions/0005-provenance-and-evidence-package-exports.md`; public-safe only after sanitization and source-rights review. |
| Run summary exports | cold | private-operator by default | Export compact JSONL summaries of cycle outcomes and metrics; see `docs/decisions/0006-run-taxonomy-observability-and-cost-accounting.md`; public-safe only after sanitization. |
| Human review packets | warm | private-operator by default | Keep concise markdown or JSON cycle summaries separate from transcripts and Lattice rows; see `docs/decisions/0008-human-review-packet-format-for-cycle-output.md`; sanitize before public use. |
| Lattice recovery records | warm | private-operator | Keep until the DB or export conflict has explicit repair or custody. |
| Run BOM records | cold | private-operator by default | Prefer `upk:` ids, hashes, HMACs, and schema refs; publish only when all referenced evidence is public-safe. |
| Automation obligations | hot | private-operator | Keep open until repaired, resolved, or filed to GitHub with sanitized issue text. |
| Breadcrumb custody records | warm | private-operator | Keep until resolved or suppressed with a named rationale. |
| Postmortem reports | warm | private-operator | Keep local by default; promote only concise public-safe lessons. |
| Runtime manifests and locks | hot or trashable | private-operator | Use for local coordination only; prune after the coordination window. |
| Release notes and compatibility docs | frozen | public-safe | Commit durable lessons and public operator behavior here instead of raw evidence. |
| Public issue or PR text | frozen | public-safe | Include sanitized findings, repro summaries, and validation proof, not raw private evidence. |

## Redaction, Compression, Export, And Recovery

Redaction should preserve the useful shape of evidence while removing raw local
paths, tokens, private identities, secret values, full transcripts, unbounded
command output, and sensitive source text. Prefer hashes, HMACs, stable ids,
bounded output tails, schema versions, command names, exit codes, and
operator-written summaries.

Compression is appropriate for warm or cold `private-operator` evidence when it
is no longer needed for immediate repair. Do not compress a hot restore backup
or open-obligation evidence in a way that hides the next required action from
the wrapper or operator.

Exports are not automatically public. A default Lattice export is still
operator evidence unless its redaction settings and destination make it
`public-safe`. Any export using raw-text or include-raw options remains
`private-operator` or `secret-adjacent` until separately sanitized.

Repo loss and machine loss have different recovery expectations:

- After repo loss, tracked source, docs, prompts, release notes, and public PR
  history should preserve the durable lessons and behavior contracts.
- After machine loss, ignored runtime evidence may be gone. The system should
  still retain public-safe docs, closed issues, merged PRs, and validation
  fixtures that explain the durable fix.
- If losing private runtime evidence would lose the only proof of a current
  safety obligation, the next cycle should keep that obligation hot or file a
  sanitized issue before considering the work preserved.

## Promotion Rules

Promotion is the act of turning local evidence into durable public-safe source
or issue material. A promotion should answer:

- what happened
- why it mattered
- what was fixed or deferred
- what proof exists
- what evidence remains private
- how to restore or rerun if needed

Raw local evidence should not be promoted wholesale. Preserve the lesson as a
test, validator, doc contract, release note, compatibility rule, issue, or PR
summary. Once that promotion exists and validation proves the relevant behavior,
the raw local artifact can usually cool from warm to cold or trashable.

## Policy Drift

Changes that alter how Upkeeper keeps, prunes, compresses, redacts, exports, or
recovers logs, transcripts, backups, Lattice rows, exports, recovery artifacts,
obligations, postmortems, manifests, or public evidence packets should update
this file, `docs/source-rights-metadata.md`, `docs/security.md`,
`docs/compatibility.md`, and validation coverage in the same patch.
