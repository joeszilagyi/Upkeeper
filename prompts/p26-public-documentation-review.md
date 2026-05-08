# P26 Public Documentation And Readability Review

Use this as an Upkeeper review module when you want an explicit check that a
selected file is understandable as public project material.

Assume every release, patch, prompt change, help-text change, comment change,
and operator-facing behavior change may be read by a public developer, operator,
security reviewer, future maintainer, or automated agent with no private chat
history. The repository should explain itself from tracked source.

Treat the current checked-in state as the delivered product, not a draft waiting
for the real documentation later. Small patches can still leave the project
clear, confident, and current.

This module does not replace normal selected-file review. Follow the normal
selected-file rule and all normal applicable P1-P25 instructions. In addition,
run P26 when the selected file touches documentation, code comments, prompt
contracts, help output, README text, release notes, validation messages, log
messages, error messages, examples, operator guides, module docs, or public
policy.

If the selected file has no documentation, comment, public wording, or
operator-facing explanation surface, state `P26: not applicable` and proceed
with the normal applicable review only.

## P26 - Public Documentation And Readability Review

Goal:

Check whether the selected file is documented clearly enough that a reasonable
developer, hacker, amateur operator, future maintainer, or digital operator can
understand the important intent without needing private context.

This is not a demand for classroom explanations of basic language mechanics.
Do not explain what a `for` loop is, what `if` means, or what every simple
assignment does. Focus on intent, contracts, surprising behavior, operator
impact, safety boundaries, and how the file fits the system.

### Source Policy To Check

Use these as governing references when relevant:

- `docs/public-documentation-policy.md`
- `README.md`
- `Upkeeper.conf`
- `configurations/default.conf`
- `docs/scripts/upkeeper.md`
- `docs/compatibility.md`
- `docs/dependencies.md`
- `docs/stress-corpus.md`
- `lib/upkeeper/README.md`
- `prompts/README.md`
- current-year root `change_notes_YYYY.md`
- root `Upkeeper` help and version behavior
- `tools/check_public_docs.sh`
- `tools/validate_upkeeper.sh`

Do not inventory every document if the selected file has a narrow surface.
Inspect the policy and the directly paired docs/comments that explain the
selected file.

### 1. Public-By-Default Release Standard

Treat the selected file and any paired release note as public-facing.

Check whether:

- a public reader can tell what changed and why
- the file sounds like current product documentation, not a pending placeholder
- release notes describe operator impact, not only commit mechanics
- help text, README text, and docs agree with the implementation
- examples are realistic and do not rely on hidden local state
- version references are current when a committed wrapper state changes
- Git-tracked docs explain the behavior without requiring chat history

Flag drift when a change only makes sense if someone remembers an earlier
conversation.

### 2. Human And Digital Operator Clarity

Check whether the wording is easy to follow for both people and agents.

Prefer:

- direct sentences
- concrete nouns
- explicit ownership and intent
- stable names for flags, env vars, files, markers, and logs
- short examples that show real invocation shape
- comments that explain why a helper exists or what boundary it protects

Avoid:

- placeholder prose
- private shorthand
- legalistic or committee-style wording
- fake precision such as arbitrary subsection codes
- LLM-only phrasing that sounds formal but hides the actual behavior
- vague references like "this", "that", or "the thing" when a concrete name is
  available

The target style is practical public engineering writing.

### 3. Code Comment Level

Review comments in the selected file at the same standard.

Good comments explain:

- what a function intends to own
- why a guardrail exists
- why a non-obvious branch is safe
- what external contract a parser, marker, log line, or exit code preserves
- what a helper deliberately does not do

Bad comments:

- narrate obvious syntax
- repeat the function name without adding intent
- preserve stale design claims after behavior changes
- hide uncertainty behind formal prose
- mention future work without a tracked reason or clear boundary

If the code is self-explanatory, do not add noise. If the intent is not obvious
from names and structure, add or tighten a short comment.

### 4. Documentation Flow

Check whether related docs form a path a reader can follow.

For Upkeeper, the normal path is:

- root `README.md` for project purpose and layout
- `docs/scripts/upkeeper.md` for operator behavior and flags
- `docs/compatibility.md` for stable public contracts
- `docs/dependencies.md` for external tools
- `lib/upkeeper/README.md` for module ownership
- prompt files for review-module contracts
- config files for scheduled-run defaults
- current-year root `change_notes_YYYY.md` for release impact

Flag drift when the implementation changes but the path above still describes
the old behavior or omits the new public surface.

### 5. No Overbuilt Documentation

Do not make docs verbose just to look rigorous.

Prefer the smallest explanation that lets a reader understand:

- purpose
- inputs
- outputs
- safety boundary
- operator-visible effect
- how to verify the behavior

Avoid long internal taxonomy, numbered legalese, or nested policy prose when a
plain paragraph or short bullet list is enough.

### 6. Local Tooling

Use existing local checks when they apply:

- `tools/check_public_docs.sh`
- `tools/validate_upkeeper.sh --quick`
- `git diff --check`
- direct `./Upkeeper --help` comparison when help text changes

Do not claim the tool proves writing quality in full. The tool catches obvious
drift; this P26 review supplies the judgment for selected-file clarity.

### 7. Fix Standard

When P26 finds a problem, apply the smallest useful fix.

Good fixes include:

- updating stale help/docs/release notes
- adding a one-sentence function or module intent comment
- removing placeholder wording
- replacing formal-but-empty prose with concrete behavior
- adding a missing README or prompt index entry
- adding validation for public docs drift when the rule is deterministic

Do not rewrite large docs only for style. Preserve accurate existing wording
when it is already understandable.

### Output Contract

When P26 applies, include a short section in the final response:

- `P26 applicability`
- public docs/comments inspected
- clarity or currency gaps found
- changes applied, if any
- local checks run
- residual public-doc risk, if any

If P26 does not apply, include:

`P26: not applicable`

### Final Marker Discipline

The final response must still include exactly one normal Upkeeper final marker:

- `UPKEEPER_STATUS: WORK_DONE`
- `UPKEEPER_STATUS: NO_CHANGES`
- `UPKEEPER_STATUS: BLOCKED`

Do not invent a P26-specific final status marker.
