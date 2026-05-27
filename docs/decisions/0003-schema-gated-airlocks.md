# 0003 Schema-Gated Typed-Signal Airlocks

Status: accepted

## Context

Upkeeper crosses several boundaries where untrusted or semi-trusted text can
otherwise look like authority: backend model summaries, GitHub issue text, bug
report drafts, logs, transcripts, runtime obligation JSON, config inputs,
target paths, and generated command text.

The existing wrapper already uses pieces of this pattern. Examples include
status marker parsing, structured policy decision records, automation
obligations, Lattice row versions, target selection checks, and issue-workflow
packet shaping. The missing product decision was the shared vocabulary and the
minimum rule for future boundary work.

## Decision

Upkeeper will use `schema-gated typed-signal boundary` as the umbrella term for
trust-boundary transitions where raw text or local evidence can affect wrapper
authority. Within that umbrella:

- `airlock parser` means the narrow parser that accepts producer input and
  emits either a typed record or a rejection reason.
- `validated normalized record` means the only shape a downstream authority
  path may consume.
- `limited downstream actuator` means the code that performs a side effect or
  control-plane decision after validation.
- `policy enforcement point`, `capability boundary`, and `command/data
  separation` remain useful descriptions for specific enforcement sites.

The canonical flow is:

```text
untrusted or semi-trusted producer
  -> airlock parser
  -> validated normalized record
  -> limited downstream actuator
```

Raw producer text may be preserved as bounded evidence, but it must not become
authority by string coincidence. For example, a quoted `[ERROR]`, a markdown
code block that looks like a shell command, or a GitHub issue sentence that
names a target path is evidence until a local parser accepts it as a typed
record for a specific actuator.

## Threat Model And Failure Classes

The design is meant to reduce these concrete failure classes:

- Prompt or prose injection that asks a downstream stage to exceed its
  capability profile.
- Marker confusion where quoted log or source text contains tokens such as
  `[ERROR]`, `PAGE`, `UPKEEPER_STATUS`, or `BLOCKED`.
- Schema drift where missing, renamed, or mistyped fields are treated as
  absence instead of invalid input.
- Path or command injection through target names, shell snippets, markdown
  fences, JSON strings, or issue titles.
- Stale evidence replay where old cycle state affects a new run without a
  current owner, source cycle, or expiry rule.
- Capability laundering where diagnostic evidence becomes a write, GitHub,
  merge, prune, quota, or target-selection decision.
- Silent overreach from helper tools that accept more authority than their
  caller intended to grant.

## Boundary Inventory

| Boundary | Current shape | Accepted typed-signal direction | Policy |
| --- | --- | --- | --- |
| LLM final text to wrapper status/action | Status marker and review-summary parsing, with local validation for known markers. | A status outcome record with schema id, selected target, changed paths, outcome, blocked reason, and parser rejection evidence. | Always-on before status, issue, merge, or obligation decisions. |
| Issue body/comment text to prompt evidence and workflow state | ChimneySweep and issue-fix paths fetch evidence and redact private packet fields by default. | An issue evidence packet with issue number, URL/title hashes, labels, stage, body exposure flag, and source-safe excerpt boundaries. | Always-on before backend launch or GitHub side effects. |
| Bug-report draft blocks to GitHub issue creation | Obligation issue reports and bug-report-only output are parsed before public issue creation. | A bug-report draft record with title, body, labels, target, owning obligation or finding id, and public-safe evidence excerpts. | Always-on before GitHub writes. |
| Transcript/log imports to Lattice rows | Lattice uses row versions and payload hashes; logs still contain mixed human and machine text. | Import records with row type, row version, logical key, payload hash, source cycle, and explicit raw-evidence privacy class. | Always-on for imports; diagnostic-only for raw trace display. |
| Runtime obligations to launcher decisions | Obligation JSON records drive repair priority and issue reporting. | Obligation records with kind, severity, target, repair target, owner cycle/run hash, evidence list, resolution state, and duplicate key. | Always-on before workload selection, validation routing, or merge stewardship. |
| Config/env files to shell behavior | Shell-sourced config is trusted local input only and documented as unsafe for hostile input. | Future non-shell profiles should use a typed config record with schema version, trusted source path, allowed keys, and compatibility class. | Diagnostic-only until a non-shell profile exists; shell config remains trusted local input, not hostile-safe. |
| Target selection and target substitution evidence | The wrapper owns deterministic selection, explicit target pins, unsafe target rejection, and retarget denial. | A target authority record with normalized path, root, safe path class, git status, mtime, source selector, and substitution rejection reason. | Always-on before backend contact and before accepting changed-path claims. |
| Generated commands/scripts before execution | Wrapper commands are local code; backend commands run through the configured sandbox. | Generated wrapper-side commands require a purpose, allowed cwd, env exposure class, write scope, and quoting strategy before execution. | Always-on for wrapper-owned generated scripts; diagnostic-only for backend sandbox command telemetry unless a wrapper actuator will reuse it. |

## Always-On Vs Diagnostic-Only Policy

Use an always-on schema gate when the accepted record can authorize any of
these actions:

- contact backend Codex
- write tracked source
- retarget work
- restore or prune evidence
- spend or bypass quota
- file, update, or close a GitHub issue or PR
- write Lattice rows that later drive custody
- select an obligation for repair
- mark validation, PR checks, or merge readiness as passed

Use diagnostic-only parsing when the output is advisory, local-only, or
observability-only and cannot authorize a side effect. Diagnostic parsing may
still log rejection evidence, create a research issue, or feed tests, but it
must not block a healthy run unless the same input also crosses an always-on
authority boundary.

## Implementation Sequence

1. Close Issue #365 with this design note, tracked links, and validation that
   protects the terminology and boundary inventory.
2. Add explicit schema ids and negative fixtures to the three highest-risk
   already-active boundaries: LLM status/action, runtime obligations, and
   bug-report draft blocks.
3. Normalize transcript/log import records before they can affect Lattice
   custody, while preserving raw evidence only as private evidence.
4. Add target authority records for selected-target handoff and changed-path
   acceptance, then reject target-substitution evidence through that record.
5. Evaluate a typed non-shell config profile only after current shell-sourced
   config compatibility remains fully documented and validated.
6. Move any future generated wrapper-side command path behind an explicit
   command record before it can run.

Each implementation slice should add the smallest useful positive and negative
fixtures before changing runtime authority. Future work should file focused
implementation issues instead of reopening this research slice.

## Test Strategy And Negative Fixtures

The minimum useful schema tests are local and no-backend:

- Positive fixtures that contain the smallest accepted record for each schema.
- Missing `schema_version`, unknown schema id, wrong field type, unknown enum,
  and extra required-authority fields.
- Quoted marker text such as `[ERROR]`, `PAGE`, `UPKEEPER_STATUS`, and
  `BLOCKED` inside human prose.
- Markdown fences, shell metacharacters, JSON escape sequences, path traversal,
  symlink-like paths, and newline-bearing target strings.
- Stale cycle ids, unknown owner ids, duplicate obligation keys, missing
  evidence lists, and inconsistent target fields.
- Capability escalation attempts such as a diagnostic record asking to write
  source, contact GitHub, merge a PR, or bypass quota.

The normal proof path is `tools/validate_upkeeper.sh --quick` plus focused
`tests/*.bash` or Python fixtures. These checks must remain deterministic and
must not launch real backend Codex.

## Risks And Non-Goals

Risks:

- Over-schema can make maintenance slower or more brittle than the boundary
  deserves.
- A schema validates shape, not truth. The actuator still needs capability
  checks, source-state checks, and validation.
- A poorly designed compatibility story can turn schema hardening into a
  breaking change for operators or existing evidence.

Non-goals:

- This decision does not make shell-sourced config safe for hostile input.
- This decision does not make Lattice an authoritative custody source.
- This decision does not replace Codex sandboxing, local validation, backups,
  human review, or GitHub branch protection.
- This decision does not require every log line to become JSON.
- This decision does not implement live runtime schemas for every boundary in
  one patch.

## Closure Boundary

This decision closes the research/design scope from issue #365 by accepting the
terminology, boundary inventory, always-on policy, implementation sequence, and
negative-fixture strategy. Runtime implementation remains incremental and
should be tracked through focused follow-up issues when a specific boundary is
changed.

## Consequences

- Future authority-boundary work has a shared vocabulary and a default
  decision rule.
- Public docs can distinguish raw evidence, diagnostic parsing, and accepted
  authority records.
- Quick validation now protects the existence of this design contract, but it
  does not claim that every listed boundary is fully implemented.
