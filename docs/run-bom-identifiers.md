# Upkeeper Run BOM And Identifier Namespace

Upkeeper already emits cycle ids, run hashes, path HMACs, prompt hashes,
artifact hashes, backup ids, and Lattice rows. This contract defines the shared
names for those references so future tools can reason about a run without
scraping prose logs or exposing raw local paths.

Status: schema-v1 design contract. This document closes issue #218 by defining
the namespace and run bill of materials. It does not yet add a runtime BOM
exporter; future implementation work should preserve this vocabulary and add
deterministic fixtures before any exported schema becomes authoritative.

## Identifier Namespace

Every durable Upkeeper reference should use this shape:

```text
upk:<kind>:<segment>[:<segment>...]
```

Rules:

- `upk` is the namespace prefix.
- `<kind>` is lowercase ASCII and identifies the referenced object class.
- Segments are stable ids, hashes, or HMACs, never raw local paths, secrets,
  issue body text, prompt text, transcript text, or command text.
- Segments should use lowercase hex, URL-safe tokens, or existing cycle ids
  that already appear in wrapper logs.
- A record may preserve raw private evidence separately, but public or portable
  references should carry only the namespaced id plus a privacy class.
- Unknown `upk:<kind>` values are invalid unless a tracked compatibility note
  or schema version introduces them.

Canonical kinds:

| Identifier | Meaning | Required segment source |
| --- | --- | --- |
| `upk:cycle:<cycle_id>` | One wrapper cycle, using the existing cycle id emitted in log lines. | Existing `CYCLE_ID`. |
| `upk:run:<cycle_run_hash>` | A privacy-safe cycle execution identity. | Existing `run_hash`/`CYCLE_RUN_HASH`. |
| `upk:repo:<repo_hash>` | A repository identity without raw path disclosure. | HMAC or hash of the normalized repo root identity used by the wrapper. |
| `upk:target:<repo_hash>:<path_hash>:<content_hash>` | The selected target at a specific content state. | Repo hash, repo-relative path HMAC/hash, and selected-file content hash. |
| `upk:backup:<backup_id>` | A selected-target pre-contact backup or restore metadata record. | Backup sidecar id or privacy-safe backup record id. |
| `upk:prompt:<sha256>` | A prompt source, compiled prompt, or prompt packet digest. | SHA-256 of the public-safe or private prompt material according to artifact policy. |
| `upk:artifact:<sha256>` | A transcript, log excerpt, report, export, recovery record, or other artifact. | SHA-256 of the artifact bytes or redacted artifact payload. |
| `upk:validation:<validation_id>` | A local validation invocation or validation result group. | Stable validator id, command hash, or fixture id. |
| `upk:config:<config_hash>` | Effective config source or config snapshot identity. | Hash/HMAC of the trusted local config source or normalized config snapshot. |

Identifier stability is scoped to the source material. If a selected target's
content changes, its `upk:target` id changes because the content hash changes.
If a raw transcript is redacted before export, the raw artifact and redacted
artifact should use different `upk:artifact` ids.

## Run BOM Schema V1

A run bill of materials is a compact JSON-compatible record that names the
inputs, authority boundaries, outputs, and validation evidence for one cycle.
The minimum stable shape is:

```json
{
  "schema_version": 1,
  "bom_id": "upk:artifact:<sha256>",
  "cycle": {
    "cycle_id": "20260527T120000-0700-12345",
    "cycle_ref": "upk:cycle:20260527T120000-0700-12345",
    "run_ref": "upk:run:<cycle_run_hash>"
  },
  "wrapper": {
    "version": "v1.x.y",
    "entrypoint_ref": "upk:artifact:<sha256>",
    "module_refs": ["upk:artifact:<sha256>"]
  },
  "config": {
    "config_ref": "upk:config:<config_hash>",
    "profile": "default",
    "override_refs": []
  },
  "prompts": {
    "source_refs": ["upk:prompt:<sha256>"],
    "compiled_prompt_ref": "upk:prompt:<sha256>",
    "review_modules": []
  },
  "selected_target": {
    "target_ref": "upk:target:<repo_hash>:<path_hash>:<content_hash>",
    "path_hash": "<path_hash>",
    "content_hash": "<content_hash>"
  },
  "backup": {
    "backup_ref": "upk:backup:<backup_id>",
    "encrypted": true
  },
  "backend": {
    "backend_profile": "codex",
    "model": "gpt-5.3-codex-spark",
    "reasoning_effort": "xhigh",
    "command_shape_ref": "upk:artifact:<sha256>"
  },
  "capability": {
    "capability_profile": "backend-codex-default-review",
    "policy_decision_refs": []
  },
  "validation": {
    "validation_refs": ["upk:validation:<validation_id>"],
    "commands": []
  },
  "outputs": {
    "artifact_refs": ["upk:artifact:<sha256>"],
    "changed_target_refs": []
  },
  "privacy": {
    "artifact_privacy_class": "private-operator",
    "raw_evidence_exported": false
  }
}
```

The example is illustrative, not a committed runtime output. A future exporter
may omit unavailable optional arrays, but it must preserve field meanings and
types for schema version 1 once emitted.

## Required BOM Sections

| Section | Purpose | Minimum content |
| --- | --- | --- |
| `schema_version` | Compatibility boundary. | Numeric value `1`. |
| `bom_id` | Identity of the BOM record itself. | `upk:artifact:<sha256>` for the serialized BOM. |
| `cycle` | Connects the BOM to wrapper logs and local evidence. | `cycle_id`, `cycle_ref`, `run_ref`. |
| `wrapper` | Explains which wrapper implementation ran. | Version plus entrypoint and module artifact refs or hashes. |
| `config` | Names trusted local config input. | Config ref, profile, and one-cycle override refs when present. |
| `prompts` | Names prompt sources and compiled prompt evidence. | Prompt refs, compiled prompt ref, review module ids. |
| `selected_target` | Names selected target without raw path disclosure. | Target ref, path hash, content hash. |
| `backup` | Connects target authority to pre-contact protection. | Backup ref when a backup is required or created. |
| `backend` | Captures backend launch shape without leaking raw command text. | Backend profile, model, effort, command-shape ref. |
| `capability` | Ties run authority to capability policy. | Capability profile and policy decision refs when available. |
| `validation` | Records proof that was run after work. | Validation refs and command names or command-shape refs. |
| `outputs` | Names generated evidence and changed targets. | Artifact refs and changed target refs. |
| `privacy` | Declares whether raw evidence left local custody. | Artifact privacy class and raw evidence export flag. |

## Privacy And Preservation

Run BOMs are evidence indexes. They should prefer stable ids, hashes, HMACs,
schema versions, command shapes, and bounded public-safe summaries. They should
not embed raw transcripts, full prompts, secret-bearing config, private issue
body text, raw local paths, private age identities, tokens, or unbounded command
output.

Default run BOM privacy is `private-operator`. A BOM can become `public-safe`
only when all referenced excerpts and summaries have been deliberately written
or redacted for publication. A BOM that references secret-adjacent material is
not public-safe merely because it uses hashes; the privacy class must describe
the referenced evidence set, not just the BOM JSON shape.

## Compatibility Rules

Schema-v1 field names, field types, identifier kinds, and identifier segment
meanings are stable once a runtime exporter emits them. Adding optional fields
is compatible when old readers can ignore them. Renaming fields, changing a
kind's segment order, changing enum meanings, or removing required sections
requires a new schema version or a documented compatibility shim.

The namespace is intentionally narrower than arbitrary URIs. Do not add `upk:`
identifiers for raw local filesystem paths, GitHub URLs, private issue text, or
backend commands. Those are evidence values; the identifier should point to a
normalized record or artifact digest.

## Relationship To Lattice

Lattice can store these ids as evidence references, but a BOM does not make
Lattice authoritative custody. Runtime logs, obligations, backups, transcripts,
Git state, and validation evidence remain the fallback proof until a future
policy explicitly promotes a Lattice-derived decision.

Future Lattice import/export rows should use `upk:` ids when they need to link
cycles, runs, targets, prompts, backups, artifacts, or validations across
tables or exports.

## Future Implementation Sequence

1. Add focused fixtures that validate the namespace grammar and schema-v1
   section names before any exporter exists.
2. Emit a private local BOM JSON artifact at `cycle.exit` for dry-run and live
   cycles, using hashes/HMACs for all path-bearing material.
3. Teach Lattice imports to reference the BOM id and core `upk:` ids without
   changing Lattice custody authority.
4. Add operator commands or helper modes to explain a cycle from a BOM, verify
   the selected target hash, verify the backup id, and list validation refs.
5. Consider public-safe BOM export only after redaction and source-rights
   checks prove that raw private evidence is not being published.

## Non-Goals

- This contract does not implement `upkeeper explain`, replay, restore, or
  export commands.
- This contract does not make raw local evidence public.
- This contract does not replace Git, PR checks, local validation, selected
  target backups, policy decisions, or Lattice integrity checks.
- This contract does not require every log line to be JSON.

## Closure Boundary

This document closes the design scope of issue #218 by defining the run BOM
schema-v1 shape and stable `upk:` identifier namespace. Runtime emission,
explain/replay helpers, and public-safe export should be tracked as separate
implementation issues.
