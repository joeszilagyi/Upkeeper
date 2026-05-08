# P25 Contract And Intent Compliance Review

Use this as an Upkeeper review module when you want an explicit check that the
selected file still fits Upkeeper's documented contracts, architecture,
compatibility rules, and maintainability goals.

This module does not replace normal selected-file review. Follow the normal
selected-file rule and all normal applicable P1-P24 instructions. In addition,
run P25 when the selected file touches operator-visible behavior, wrapper
contracts, module ownership, dependency assumptions, validation, docs, prompts,
logs, markers, exit codes, symlink behavior, or central/client boundaries.

If the selected file has no meaningful contract or intent surface, state
`P25: not applicable` and proceed with the normal applicable review only.

## P25 - Contract And Intent Compliance Review

Goal:

Check whether the selected file's current behavior is compliant with Upkeeper's
documented requirements, compatibility contract, module design discipline,
central-first rule, dependency policy, validation expectations, and operator
experience goals.

This is a contract-driven review, not a taste-driven refactor pass. Do not
rewrite code merely because another shape seems cleaner. Apply a change only
when there is concrete contract drift, missing validation, missing docs, unsafe
operator behavior, misplaced ownership, or unnecessary machinery that conflicts
with the documented project direction.

### Source Contracts To Check

Use these as governing references when relevant:

- `AGENTS.md`
- `Upkeeper.conf`
- `configurations/default.conf`
- `docs/compatibility.md`
- `docs/dependencies.md`
- `docs/stress-corpus.md`
- `docs/scripts/upkeeper.md`
- `lib/upkeeper/README.md`
- `README.md`
- current-year root `change_notes_YYYY.md`
- `tools/validate_upkeeper.sh`
- root `Upkeeper` help and version behavior
- prompt files under `prompts/`

Do not inventory every governing document if the selected file has a narrow
surface. Inspect the contracts directly relevant to the selected file.

### 1. Central-First Compliance

Verify the selected file follows Upkeeper's central-first rule.

Check whether:

- wrapper behavior belongs in the central Upkeeper repo
- symlinked clients keep resolving central modules, prompts, and docs
- client repos are not asked to track wrapper churn merely to receive central
  behavior
- local runtime artifacts remain ignored evidence, not source

Flag contract drift when a change pushes central wrapper behavior into client
repos or makes symlinked invocation weaker.

### 2. Backward Compatibility

Verify documented operator-visible behavior stays compatible.

Check:

- CLI flags and aliases
- environment knobs and meanings
- exit code meanings
- status marker names and values
- parseable `Upkeeper.log` events and key/value fields
- runtime paths and artifact locations
- validation entrypoints
- prompt-file behavior from symlinked clients

Adding fields or optional flags is normally compatible. Removing fields,
renaming keys, changing value types, changing exit meanings, or breaking old
documented flags is contract drift unless a safety/security/impossibility reason
is documented.

### 3. Simplicity And Maintainability

Verify the implementation uses the smallest sufficient mechanism.

Prefer:

- small reusable Bash helpers
- existing local commands
- focused Python parsers where shell parsing would be brittle
- fixtures in the existing validation harness
- deterministic local code for stable parsing, classification, formatting,
  routing, preflight, and guardrail enforcement

Question:

- new runtime dependencies
- new services, daemons, databases, or background systems
- broad rewrites for narrow behavior
- helper duplication where a local contract already exists
- over-fragmentation that creates more load-order or ownership risk than it
  removes

### 4. Module Ownership

Verify the selected file lives in the right ownership boundary.

Check whether:

- root `Upkeeper` stays focused on orchestration
- parsing, formatting, preflight, process handling, prompt assembly, artifact
  handling, and status parsing live in the module that owns that concern
- new helpers are reusable where reuse would reduce coupling or validation cost
- module load-order assumptions remain clear

Do not split code only for aesthetics. Split or extract only when it reduces
real coupling, removes meaningful duplication, clarifies a contract, or makes a
behavior easier to verify.

### 5. Dependency Discipline

Verify dependency assumptions are documented and validated.

If the selected file adds or starts assuming a command, tool, package, platform,
or external behavior, check whether:

- `docs/dependencies.md` is updated
- `tools/validate_upkeeper.sh --deps` covers it when appropriate
- runtime preflight behavior is clear
- docs/help/change notes are updated when operator-facing

Do not add fake package manifests just to satisfy GitHub dependency display.

### 6. Validation Discipline

Verify contract-sensitive behavior has focused validation.

Behavior usually needs validation when it affects:

- malformed input handling
- missing files or unreadable artifacts
- process state or parent-loop control
- quota state
- active locks
- symlink resolution
- prompt module loading
- status marker parsing
- log event shape
- exit reasons
- operator-facing docs/help

Prefer fixtures that prove both normal and malformed paths.

### 7. Operator Evidence

Verify failures stay visible and diagnosable.

Check whether:

- terminal output uses the right verbosity tier
- WARN and ERROR lines are not hidden in quiet mode
- `cycle.exit` is written on terminal paths
- log keys stay parseable
- summaries report what was wrong, what changed, and what was verified
- runtime evidence paths are logged when useful

### 8. Release-Note Discipline

Verify operator-facing changes update release notes and docs.

If the selected file changes behavior, defaults, prompt contracts, logging,
selection, quota, fallback, validation, dependency expectations, or operator
ergonomics, check whether the current year's root `change_notes_YYYY.md` and
paired docs/help need updates.

### 9. Prompt And Marker Contracts

For prompt-facing files, verify model and wrapper contracts remain aligned.

Check:

- final `UPKEEPER_STATUS` marker behavior
- `UPKEEPER_LOG_REVIEW` behavior
- postmortem markers
- review outcome wording
- pass coverage expectations
- transcript filtering assumptions
- prompt-file, review-module, and config-file ordering
- config defaults versus CLI override behavior

### 10. Vision Alignment

Verify the selected file moves Upkeeper toward being safer, more local, more
inspectable, more modular, and easier to operate.

Good P25 findings are specific:

- "this new env knob is undocumented and unvalidated"
- "this changed a log key shape used by parsers"
- "this helper duplicates an existing marker parser"
- "this belongs in central Upkeeper, not a client repo"
- "this adds a dependency without updating dependency docs or validation"
- "this terminal path can miss `cycle.exit`"

Avoid vague findings like:

- "this could be more elegant"
- "this file is long"
- "this should be rewritten in another language"
- "this should use a larger framework"

### Output Contract

In the final response, include a compact P25 section when this module is
applicable:

- `P25 applicability`: applicable or not applicable, with the specific trigger
- `governing contracts inspected`: concise list
- `compliant areas`: what already matches the contract
- `contract drift found`: concrete findings, if any
- `changes applied`: focused fixes, if any
- `deferred compliance risks`: risks not fixed in this pass
- `verification`: checks run

If contract drift is found but not changed, explain the blocker: missing proof,
unsafe scope, unclear ownership, heavy implementation cost, or not enough
evidence.

### Final Marker Discipline

Continue to obey the base Upkeeper final marker contract. This module changes
review scope only when applicable; it does not change the required final
`UPKEEPER_STATUS` marker behavior.
