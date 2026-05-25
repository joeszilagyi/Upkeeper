# Upkeeper Source Rights Metadata

Source rights metadata classifies outside material before Upkeeper treats it as
prompt context, local evidence, export material, public issue text, or citation
support. It is the legal and ethical analog of `.upkeeperignore`: locally
readable material is not automatically prompt-safe, export-safe, or
public-evidence-safe.

This document defines the public vocabulary. Runtime storage for these records
may be added later, but the labels and field names below are the tracked source
of truth for source-rights reviews.

## Source Sensitivity Labels

Canonical sensitivity labels:

- public
- local-private
- secret-adjacent
- credential-bearing
- PII-bearing
- paid-access
- license-restricted
- prompt-safe
- prompt-unsafe
- export-safe
- export-unsafe

| Label | Meaning | Default effect |
| --- | --- | --- |
| `public` | The source is intentionally public and can be accessed without local-only credentials or private operator context. | Metadata may usually be stored, but quoting, export, upload, archiving, and public evidence still depend on rights and terms. |
| `local-private` | The source is local operator material, private notes, local captures, private exports, or material not meant for publication. | Keep private; do not upload, publicly quote, or include in public evidence packets without explicit sanitization. |
| `secret-adjacent` | The source is near secrets, private identities, tokens, customer data, private keys, or other material where accidental exposure would be harmful. | Treat as prompt-unsafe and export-unsafe by default; keep out of public docs, issues, and evidence packets. |
| `credential-bearing` | The source contains credentials, tokens, private keys, session secrets, passwords, signing material, or private age identities. | Do not prompt, upload, export, archive, or quote; rotate real secrets if they were exposed. |
| `PII-bearing` | The source contains personally identifiable information, private identities, customer details, or person-specific sensitive data. | Keep local and minimized; prompt, export, or public use requires explicit privacy review and sanitization. |
| `paid-access` | The source was obtained through subscription, paywall, licensed database, member account, or restricted account access. | Store metadata only by default; do not store full text, upload, export, or publicize full content unless terms allow it. |
| `license-restricted` | Copyright, license, database rights, reuse terms, or contract terms restrict copying, redistribution, or derived evidence packets. | Store only allowed metadata and bounded notes unless the license explicitly permits more. |
| `prompt-safe` | The source may be sent to the configured backend model for the specific purpose recorded in the run. | This does not make it export-safe, public-safe, or quote-safe. |
| `prompt-unsafe` | The source must not be placed in a backend prompt, transcript, or model-visible artifact. | Use local metadata, hashes, ids, or operator-written summaries instead. |
| `export-safe` | The source may be exported outside the local runtime boundary under the recorded rights and destination. | This does not make it public-safe or unrestricted. |
| `export-unsafe` | The source must not be copied to JSONL exports, public evidence packets, issue comments, PRs, or external storage. | Keep local metadata only, or use redacted summaries if allowed. |

Labels are cumulative. For example, a source can be both `public` and
`license-restricted`, or both `paid-access` and `prompt-unsafe`. A permissive
label never cancels a restrictive label. When labels conflict, the more
restrictive handling rule wins.

## Rights And Reuse Fields

Canonical source-rights fields:

| Field | Values | Meaning |
| --- | --- | --- |
| `may_store_metadata` | `yes`, `no`, `unknown` | Whether Upkeeper may store bibliographic metadata, source URL, title, publisher, access date, hashes, or short operator notes. |
| `may_store_full_text` | `yes`, `no`, `unknown` | Whether Upkeeper may store the complete source text or complete captured artifact in local runtime evidence. |
| `may_quote` | `yes`, `no`, `unknown`, `bounded` | Whether Upkeeper may quote short excerpts in issues, PRs, docs, or evidence packets. `bounded` means only a short, purpose-limited excerpt. |
| `may_upload` | `yes`, `no`, `unknown` | Whether Upkeeper may upload the source or derived artifact to GitHub, a remote issue tracker, object storage, or another external service. |
| `may_export` | `yes`, `no`, `unknown`, `redacted-only` | Whether Upkeeper may include the source in JSONL, archive, or report exports. |
| `may_summarize` | `yes`, `no`, `unknown`, `local-only` | Whether Upkeeper may write a summary. `local-only` means the summary must stay out of prompts and public artifacts. |
| `may_use_for_wikipedia_citation` | `yes`, `no`, `unknown` | Whether the source may support a Wikipedia-style citation workflow. This is separate from uploading source text. |
| `may_include_in_public_evidence_packet` | `yes`, `no`, `unknown`, `metadata-only` | Whether the source may appear in a public packet supporting an issue, PR, release note, or audit. |
| `may_archive` | `yes`, `no`, `unknown`, `metadata-only` | Whether Upkeeper may preserve a copy for later recovery or audit instead of keeping only metadata. |
| `robots_or_terms_restriction` | `none`, `robots`, `terms`, `robots-and-terms`, `unknown`, `custom` | Whether robots.txt, site terms, contract terms, or source-specific instructions restrict collection, reuse, export, or archiving. |

The field names are stable vocabulary. Future stored records should add a
schema id, source identity, reviewed timestamp, reviewer, access method, license
summary, terms summary, and evidence notes without renaming these fields.

## Default Deny Rules

Unknown source rights are not permission. When metadata is missing, stale, or
contradictory, the default decision is:

- metadata storage may be allowed only for minimal source identity needed to
  avoid losing custody, such as URL, title, publisher, access date, or stable
  hash
- full-text storage is denied
- prompt inclusion is denied
- upload is denied
- export is denied
- public evidence packet inclusion is denied
- archiving is denied
- quoting is denied except for separately reviewed short fair-use style
  snippets where the operator writes the public text directly
- Wikipedia citation use is denied until the source is public, stable enough to
  cite, and compatible with the destination policy

`credential-bearing`, `secret-adjacent`, and unreviewed `PII-bearing` sources
force `prompt-unsafe` and `export-unsafe` handling. `paid-access` and
`license-restricted` sources default to metadata-only handling unless the
recorded terms explicitly allow more. `public` sources still need rights review
before full-text storage, upload, export, archive, or public evidence reuse.

## OSINT And Citation Workflow

For OSINT and citation work, separate these decisions:

- Can Upkeeper know this source exists?
- Can Upkeeper store metadata about it?
- Can Upkeeper send any of it to a backend model?
- Can Upkeeper preserve raw text locally?
- Can Upkeeper summarize it, and where may that summary go?
- Can Upkeeper quote it publicly?
- Can Upkeeper export or upload it?
- Can Upkeeper use it as a citation without redistributing the source?
- Can Upkeeper include it in a public evidence packet?

Wikipedia-style citation use requires a source that is public or otherwise
citable under the destination rules, with enough stable metadata for a reader
to verify it independently. It does not justify uploading full text from a
paid-access or license-restricted source.

## Example Metadata Record

```json
{
  "schema": "upkeeper.source_rights.v1",
  "source_id": "source-sha256:example",
  "labels": ["public", "license-restricted", "prompt-safe", "export-unsafe"],
  "may_store_metadata": "yes",
  "may_store_full_text": "no",
  "may_quote": "bounded",
  "may_upload": "no",
  "may_export": "redacted-only",
  "may_summarize": "yes",
  "may_use_for_wikipedia_citation": "yes",
  "may_include_in_public_evidence_packet": "metadata-only",
  "may_archive": "metadata-only",
  "robots_or_terms_restriction": "terms",
  "reviewed_at": "2026-05-24T00:00:00Z",
  "notes": "Use citation metadata and operator-written summary; do not export source text."
}
```

## Relationship To Preservation Policy

`docs/preservation-policy.md` classifies Upkeeper artifacts after evidence has
entered local custody. Source rights metadata classifies outside material before
Upkeeper decides whether the material may enter prompts, exports, archives, or
public evidence at all.

Promotion still requires the artifact to become `public-safe` under the
preservation policy. A source-rights record can say that a summary or citation
is allowed; it does not automatically make raw local evidence public-safe.

## Policy Drift

Changes that alter source sensitivity labels, rights fields, prompt/export
defaults, citation reuse, public evidence packet rules, archiving, or
robots/terms handling should update this file, `docs/preservation-policy.md`,
`docs/security.md`, `docs/compatibility.md`, and deterministic validation in
the same patch.
