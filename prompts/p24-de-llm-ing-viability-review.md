# P24 De-LLM-ing Viability Review

Use this as an Upkeeper `--prompt-file` add-on when you want an explicit P24
review of LLM/Codex boundaries on top of the built-in maintenance prompt.

This add-on does not replace the existing Upkeeper review repertoire. Follow the
normal selected-file rule and all normal applicable P1-P23 instructions. In
addition, run this P24 pass only when the selected file invokes, supervises,
prompts, parses, classifies, summarizes, recovers from, or otherwise depends on
LLM/Codex behavior.

If the selected file has no meaningful LLM/Codex boundary, state
`P24: not applicable` and proceed with the normal applicable P1-P23 review only.

## P24 - De-LLM-ing Viability Review

Goal:

Find behavior currently handled by an LLM that can be moved into deterministic
local code with no loss of operator-facing function and without material new
runtime cost, service dependency, framework overhead, or maintenance burden.
The intended cost ceiling is explicit: without material new runtime cost.

Core principle:

Do not replace an LLM path because local code feels purer. Prefer local code
only when the input contract is stable, the output contract is stable, the cases
are finite enough to fixture-test, and the resulting behavior preserves the
operator-visible contract.

### Applicability Triggers

Run this pass when the selected file or its directly paired files contain or
control any of the following:

- `codex exec` invocation
- fallback model launch
- postmortem or hardening model launch
- prompt compilation or pruning
- prompt templates or model-facing instructions
- transcript capture, filtering, or summarization
- model response status-marker parsing
- session JSONL diagnostics
- review summary parsing
- LLM-generated report handling
- incident classification based on model output
- local recovery from malformed model output

Likely Upkeeper targets include:

- `lib/upkeeper/aux_codex.bash`
- `lib/upkeeper/codex_io.bash`
- `lib/upkeeper/fallback_screen.bash`
- `lib/upkeeper/postmortem_sequence.bash`
- `lib/upkeeper/prompt_compile.bash`
- `lib/upkeeper/report_analysis.bash`
- `lib/upkeeper/status_session.bash`
- `lib/upkeeper/transcript_output.bash`
- `prompts/default-review.md`
- `prompts/caretaking_23_items.md`

### 1. LLM Boundary Inventory

Identify every model call, prompt contract, transcript stream, model-produced
marker, model-produced report, model-produced summary, or model-dependent
decision in or directly paired with the selected file.

For each boundary, record:

- caller or producer
- local artifact or stream path, if any
- expected input shape
- expected output shape
- current fallback when output is missing, malformed, stale, or ambiguous
- operator-visible logs, terminal output, exit reasons, or files affected

Do not inventory unrelated model use elsewhere in the repo unless it is part of
the selected file's direct call path.

### 2. Determinism Test

For each LLM/Codex boundary, decide whether the behavior is localizable.

A boundary is a good local-code candidate only when most of these are true:

- inputs have a stable source and stable syntax
- outputs have a stable, parseable contract
- accepted states are finite or strongly enumerable
- malformed states can be represented in fixtures
- the desired behavior is classification, parsing, formatting, routing,
  preflight, reporting, or guardrail enforcement
- the replacement can be implemented with existing repo tools and helpers
- focused fixtures can prove both normal and malformed paths

A boundary is not a good candidate when most of these are true:

- the task is open-ended code review
- symptoms are ambiguous and require judgement across unknown code
- root cause depends on project-specific design intent
- the output is a remediation plan rather than a contract field
- local rules would be brittle, incomplete, or likely to hide important context
- replacing the LLM would require a service, daemon, database, network call,
  heavyweight framework, broad rewrite, or fragile parser

### 3. No-Loss Requirement

Any de-LLM-ing change must preserve operator-facing behavior.

Check for preservation of:

- terminal output level and wording where operators depend on it
- `Upkeeper.log` event names, keys, and exit reasons
- status marker contracts
- transcript retention and high-signal summaries
- quota and fallback guardrails
- postmortem evidence paths
- symlinked-client behavior
- compatibility with current docs and help text
- failure visibility for malformed or missing artifacts

If preservation is not clear, do not apply the change. Report it as a possible
future candidate with the missing proof.

### 4. Cost Ceiling

Prefer the repo's existing local implementation style:

- Bash helpers already sourced by `Upkeeper`
- existing Python snippets for structured parsing when Bash would be brittle
- `jq` where the repo already uses it for JSON contracts
- local files and fixtures under the existing validation harness

Do not add:

- daemons or background services
- databases or persistent servers
- network calls
- heavyweight frameworks
- broad language rewrites
- new runtime dependencies for a narrow parsing or classification task

### 5. Local-First Candidates

Prefer local code for:

- status-marker parsing
- transcript filtering
- review-summary field extraction
- known incident classification
- quota and environment preflight decisions
- empty transcript and missing artifact classification
- active-lock, parent-loop, and lifecycle guardrails
- local report skeletons or bug-record stubs
- prompt pruning based on known prompt sections
- selected-file facts already known before model launch
- repeated log/anomaly diagnosis from stable `Upkeeper.log` keys

### 6. Keep-LLM Candidates

Keep LLM-backed behavior for:

- open-ended code review
- ambiguous root-cause analysis
- project-specific design judgement
- prioritizing remediation when evidence is incomplete
- explaining unfamiliar code to an operator
- deciding whether a possible change is desirable rather than merely parseable
- broad hardening plans where local cases are not yet enumerable

### 7. Verification Requirement

Any P24 fix must add focused verification unless the change is documentation-only.

Prefer fixtures that prove:

- a valid model-produced artifact is parsed or classified the same way as before
- malformed or decorated output is handled explicitly
- missing output preserves the existing fallback behavior
- terminal/log evidence remains visible
- no backend model call is added for the replacement

If you cannot add a fixture in the current change, state why and report the gap
as residual risk.

### Output Contract

In the final response, include a compact P24 section when this pass is
applicable:

- `P24 applicability`: applicable or not applicable, with the specific trigger
- `LLM/Codex boundaries inspected`: concise list
- `localizable candidates found`: include applied fixes and deferred candidates
- `candidates intentionally left LLM-backed`: include why
- `verification`: fixtures or checks added/run
- `residual risks`: anything not proven

If a localizable candidate is found but not changed, explain the blocker: missing
fixture surface, unclear no-loss proof, heavy implementation cost, or not enough
evidence.

### Final Marker Discipline

Continue to obey the base Upkeeper final marker contract. This add-on changes
review scope only when applicable; it does not change the required final
`UPKEEPER_STATUS` marker behavior.
