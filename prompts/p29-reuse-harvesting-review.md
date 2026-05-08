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
- Residual risk:

If P29 does not apply, include:

P29: not applicable

Final marker:
P29 does not invent a final Upkeeper status. Continue to use the normal
Upkeeper final marker.
