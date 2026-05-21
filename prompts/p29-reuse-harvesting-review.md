# P29 Reuse Harvesting Review

Purpose:
P29 identifies project-wide reusable code, helpers, fixtures, prompt language,
documentation blocks, command idioms, validation patterns, and assets that
should not be rediscovered or rewritten in later Upkeeper cycles. When the reuse
candidate is safe and bounded, P29 applies the extraction or consolidation in
the same run.

Core rule:
Do not merely identify reusable things. Apply the smallest safe reuse
improvement when the candidate has a stable contract, a clear owner location, no
material portability loss, and focused verification.

## Scope and Boundaries

Use P29 when reusable knowledge is:

- repeated across multiple modules, prompts, tests, or docs
- stable in behavior and likely to recur
- safe to consolidate behind one stable owner contract

Out of scope for P29:

- one-off refactors with only one current caller
- abstractions that obscure exit behavior, stdin/stdout contracts, or control flow
- abstractions that exist only to satisfy style preferences
- wrappers that only move one call into another name

What counts as reusable:
- a shell helper used or plausibly needed by multiple modules
- a Python snippet pattern repeated inside Bash heredocs or embedded scripts
- a jq assignment or JSON parsing idiom repeated across functions
- a validation setup pattern repeated in tools/validate_upkeeper.sh
- a log, marker, status, exit-code, or transcript parsing rule used in multiple
  places
- a command wrapper pattern with consistent environment setup
- a prompt paragraph or output contract repeated across prompts
- a fixture shape or test harness setup repeated across tests
- a documentation section that should become a canonical reference rather than
  being restated manually
- a local asset or template that can reduce future hand-built code

What does not count:
- one-off code with only one known use and no credible second use
- abstraction that makes shell flow harder to read
- clever helpers that hide important exit behavior
- changes that add framework, daemon, service, database, network, or dependency
  overhead
- generic "utility dumping ground" functions without a real owner
- consolidation that changes operator-visible behavior without an explicit
  compatibility reason
- churn that only makes the code look neater

Applicability:
Run P29 when the selected file contains any behavior that is repeated, likely to
repeat, or could become a canonical helper, fixture, template, prompt section,
command idiom, or documentation reference.

P29 is especially applicable to:
- lib/upkeeper/*.bash modules
- tools/*.sh validation scripts
- tests/*.bash test harnesses
- prompts/*.md review modules
- docs/scripts/upkeeper.md
- README.md
- public documentation and compatibility docs
- any file that wires review modules, validation, status markers, log parsing,
  transcript parsing, config parsing, temp directories, command dependency
  checks, or prompt assembly

Reuse candidate test:
Before extracting or consolidating, answer all of these:

1. Is the duplicated or reusable thing actually project knowledge, not just
   similar-looking text?
2. Does it have stable inputs?
3. Does it have stable outputs?
4. Is there a clear owner module, prompt, template, doc, or test helper?
5. Will the new reusable asset make future changes cheaper or safer?
6. Can at least one current caller use it now?
7. Is there either a second current caller or a strongly credible future caller?
8. Does the change preserve operator-visible logs, markers, exit codes, help
   text, docs, and validation behavior?
9. Can it be verified locally without backend Codex quota?
10. Is the new abstraction easier to understand than the repeated code it
    replaces?

If the answer to 1, 2, 3, 4, 5, 8, 9, or 10 is no, do not extract. Report it as
deferred or rejected.

## Verification Guidance

- run focused local validation in `tools/validate_upkeeper.sh` when behavior changes
  ownership or check lists
- update or add the smallest relevant test fixture so reuse claims become
  regression-detectable
- ensure the reusable asset appears in the discoverability path noted in
  "Reusable Asset Discovery"

## Output Contract

When P29 applies, report:

- what reusable boundary was chosen
- where ownership moved (module/doc/test path)
- why this is reusable now (with at least one current or credible next caller)
- verification run and hardening signal (validation, test, or fixture result)
- what was intentionally deferred (if any) and why

Application rule:
If a candidate passes the reuse candidate test, apply the smallest safe change:
- create or extend the correct existing helper module
- replace the current caller with the helper
- update a second caller if doing so is low-risk
- add or update validation if behavior is contract-bearing
- update public docs or prompt indexes if operator-visible
- avoid broad repo-wide rewrites in one pass

Preferred owner locations:
- runtime_foundation.bash for generic runtime, logging, terminal, temp, and
  evidence helpers
- runtime_format_json.bash for JSON field and time formatting helpers
- fallback_artifacts.bash for marker, quote, and artifact field helpers
- transcript_artifacts.bash for transcript path, file hash, size, and line-count
  helpers
- config_validation.bash for environment/config numeric validation
- codex_io.bash for CLI, review-module, and Codex invocation boundaries
- prompt_compile.bash for prompt module path and prompt assembly behavior
- tools/validate_upkeeper.sh for release validation and test harness checks
- tests/*.bash only for test-local stubs that must not leak into runtime
- prompts/*.md for reusable review language
- docs/*.md for canonical public behavior descriptions

Hard boundary:
Do not make a generic "utils.bash" dumping ground unless the candidate has no
better owner and the new file has a narrow, named responsibility.

Verification requirement:
Any P29 code change must run focused validation. Prefer:
- bash -n on touched shell files
- tools/validate_upkeeper.sh --quick for wrapper/prompt/help/module changes
- tools/check_public_docs.sh when docs, README, prompts, or help text change
- targeted test scripts under tests/
- git diff --check

If the repo has ShellCheck available, run it on touched shell files or state
that it was unavailable.

Relationship to P12, P24, P25, and P28:
P12 handles local duplication and copy/paste cleanup inside the selected file or
a small directly related file set.

P29 handles project-wide reusable assets and contracts: helper ownership,
discoverability, validation reuse, fixture reuse, prompt reuse, documentation
source-of-truth reuse, command recipe reuse, dependency-list reuse, and reusable
data tables.

If the reusable candidate is currently LLM-dependent, apply P24 reasoning. If
the reusable candidate changes or introduces a helper contract, apply P25
reasoning. If the reusable candidate needs durable local tests or fixtures,
apply P28 reasoning.

Wrong Abstraction Check:
P29 may reject, split, inline, or delete an existing abstraction when the helper
has become worse than local code.

Rollback or reject when:
- the helper has unrelated responsibilities
- the helper has caller-specific flags
- the helper hides exit status behavior
- the helper hides stderr/stdout behavior
- the helper changes pipeline semantics
- the helper has accumulated unrelated conditionals
- the helper name no longer describes one stable contract
- the callers are clearer and safer with local code

Shell Reuse Safety Gates:
Before moving shell code into a reusable helper, prove:

- every caller loads the helper before use
- current-shell versus subshell behavior is preserved
- global variable reads and writes are intentional
- local variables are used unless mutation is part of the contract
- explicit return codes are preserved
- stderr and stdout contracts are preserved
- pipeline and pipefail behavior are preserved
- trap behavior is preserved
- set -e behavior is not accidentally changed
- command arguments remain arrays or direct arguments, not command strings
- eval is not introduced

Command Reuse Rule:
Do not store complex commands in strings. Use functions for reusable command
behavior, arrays for reusable argument lists, and explicit environment
assignment or exported variables in a narrow subshell. Avoid `eval`. Avoid
`sh -c` unless the shell boundary is the point of the test.

Reusable Asset Discovery:
When P29 creates or changes a reusable project asset, update the narrowest
discoverability point:

- lib/upkeeper/README.md for runtime helper ownership
- prompts/README.md for prompt modules
- docs/scripts/upkeeper.md for operator CLI behavior
- docs/compatibility.md for compatible CLI surface
- docs/dependencies.md for dependency categories
- tools/validate_upkeeper.sh for local behavioral validation
- tools/check_public_docs.sh for public docs drift checks

Registry Preference:
When a repeated project-wide list controls behavior, prefer a small registry or
a validation-backed metadata table over scattered hard-coded lists.

Candidate registries include:
- review module ids, aliases, prompt paths, titles, and help summaries
- dependency categories
- reusable prompt-module structural requirements
- stable fixture names
- public documentation anchors

Do not create a registry when two local case blocks are clearer and safer.

Command Recipe Harvesting:
If a reusable asset is a command recipe, prefer making it executable or
validation-backed.

Good homes:
- tools/validate_upkeeper.sh
- tools/check_public_docs.sh
- launcher_examples/
- docs/scripts/upkeeper.md
- README.md

Do not leave important reusable commands only in comments, transcripts, or final
review prose.

Reusable Asset Acceptance Thresholds:
A reuse candidate needs:
- one current caller
- one current second caller, or a named future caller tied to an existing
  module, prompt, doc, validation script, or test
- a stable owner
- a local verification command
- a failure mode that is easier to test after extraction

Reject when the second use is only hypothetical. Reject when the helper name
would be vague. Reject when extraction needs a generic utility file. Reject when
extraction changes shell evaluation order. Reject when repeated local code is
safer because it is visible at the callsite.

Embedded Data Tables And Fixtures:
Treat embedded data tables, allowlists, deny-lists, regexes, and path-prefix
lists as reusable assets when they define project behavior.

When repeated generated test data has stable meaning, either create a named
fixture or a named fixture writer. Do not keep copying inline JSONL or shell
setup when the fixture has a stable contract.

Negative Examples:
Do not create:
- `utils.bash`
- `common.bash`
- `helpers.bash`
- command strings hidden in variables
- helper functions that only call one command with no contract
- wrappers that suppress stderr
- wrappers that erase exit codes
- registry files that are harder to update than the duplicated case blocks
- docs-only reuse claims with no validation when validation is available

ShellCheck Integration Policy:
If ShellCheck is installed, run it on touched shell files. If not installed,
report unavailable. Do not add ShellCheck as a required runtime dependency
unless docs/dependencies.md, compatibility docs, and validation policy are
updated in the same change.

Reuse Debt Output:
When P29 rejects or defers a reuse candidate, include:
- candidate
- reason not applied
- likely owner
- proof needed
- likely validation command

This prevents future runs from rediscovering the same candidate without
context.

Output contract:
When P29 applies, include:

P29 Reuse Harvesting:
- Applicability:
- Reuse candidates inspected:
- Candidate accepted and applied:
- Candidate rejected:
- New or changed reusable asset:
- Callers updated:
- Behavior preserved:
- Verification run:
- Reuse debt:
- Residual risk:

If P29 does not apply, include:

P29: not applicable

Final marker:
P29 does not invent a final Upkeeper status. Continue to use the normal
Upkeeper final marker.
