# 0008 Human Review Packet Format for Cycle Output

Status: accepted

## Context

For Wikipedia and OSINT work, humans need a concise evidence packet, not a raw
log swamp. The packet should be easy to read, easy to sanitize, and explicit
about what is safe or unsafe to publish.

The packet is separate from transcripts and separate from internal Lattice
rows. It should summarize one meaningful cycle without turning the whole run
into a transcript replay.

## Decision

Upkeeper accepts a human review packet format with `upkeeper review-packet --cycle-id X --format markdown` and `upkeeper review-packet --cycle-id X --format json` as the first implementation slice.

The packet is local-only and private-operator by default. It may later be
sanitized into public-safe issue text or public evidence, but the raw packet
should remain a concise operator artifact until it is deliberately promoted.

The packet should answer these questions:

- what changed
- why it changed
- what evidence supports it
- what was not checked
- what failed
- what needs human attention
- what is safe to copy/use publicly
- what is unsafe to publish
- how to restore if needed

The markdown and JSON variants should share the same section vocabulary. A
single packet may be rendered either as prose or as JSON fields, but the meaning
of the fields must stay aligned.

The minimal JSON summary schema is:

```json
{
  "schema_version": 1,
  "packet_ref": "upk:artifact:<sha256>",
  "cycle_ref": "upk:cycle:<cycle_id>",
  "run_ref": "upk:run:<cycle_run_hash>",
  "format": "json",
  "what_changed": [],
  "why_it_changed": [],
  "evidence_supporting_it": [],
  "what_was_not_checked": [],
  "what_failed": [],
  "human_attention": [],
  "safe_to_copy_use_publicly": [],
  "unsafe_to_publish": [],
  "restore_notes": [],
  "privacy": "private-operator"
}
```

The example is illustrative, not a committed runtime output. The packet may be
generated from cycle summary data, local evidence refs, and local validation
results, but it must stay separate from the raw transcript and from internal
Lattice row storage.

The packet should make the operator-facing distinction explicit:

- public-safe text can be copied into issue bodies, reports, or public notes
- unsafe text stays local unless it is deliberately sanitized
- restore instructions stay local unless the operator intentionally promotes
  them

## Consequences

- Operators get a concise evidence packet instead of a raw log swamp.
- Public-safe and unsafe content can be separated before publication.
- The packet stays separate from transcripts and internal Lattice rows while
  still being easy to wire to later export helpers.
- A markdown version is easy to read, and a JSON version is easy to consume by
  future tooling.
- The wrapper can support human review without making every cycle feel like a
  transcript archive.

## Implementation Sequence

1. Add focused fixtures that validate the packet section names and JSON field
   names before any exporter exists.
2. Generate a local markdown or JSON packet for one cycle using local summary
   evidence and validation results.
3. Wire the packet to Lattice or export commands later, once the section
   vocabulary is stable.
4. Keep the public-safe and unsafe-to-publish sections explicit so sanitization
   stays deliberate instead of accidental.
5. Track any future public publication pipeline in a separate issue if it ever
   becomes necessary.

## Closure Boundary

This decision closes issue #226 by defining the human review packet format for
cycle output. The first slice is a local markdown or JSON summary, and the
packet intentionally remains separate from transcripts and internal Lattice
rows until a later export integration is added.
