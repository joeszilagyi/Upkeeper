# P28 Unit Test Harvesting Review

Use this as an Upkeeper review module when you want useful discoveries to turn
into durable local tests or fixtures instead of being rediscovered by later LLM
cycles.

P28 is for deterministic behavior. It is not a command to add tests for their
own sake. It applies when the selected-file review finds a real bug, explores a
reusable command or fixture shape, touches parsing/validation/ingestion logic,
or can cheaply convert a model-discovered fact into a local check that runs
without backend model quota.

This module does not replace normal selected-file review. Follow the normal
selected-file rule and all normal applicable P1-P27 instructions. In addition,
run P28 when the selected file touches deterministic logic that can be checked
locally.

If the selected file has no practical deterministic test surface, state
`P28: not applicable` and proceed with the normal applicable review only.

## P28 - Unit Test Harvesting Review

Goal:

Convert useful discoveries into the smallest durable local test, fixture, or
validation check that protects the behavior without spending future LLM cycles.

Useful discoveries include:

- a bug fixed during this review
- a reusable exploratory command that proved behavior
- malformed input that should stay rejected
- a parser, importer, exporter, selector, marker reader, transcript reader, log
  reader, session reader, CLI, or config validator edge case
- an operator-visible contract that can be checked locally
- repeated LLM work that could become a deterministic fixture

### Required Decision

When P28 applies, ask this before finishing:

Would a small local test or fixture make this behavior cheaper to verify next
time than asking a future model to rediscover it?

If yes, implement the test or fixture unless there is a concrete reason not to.
If no, say why.

Binding trigger:

If a problem is found, or a reusable way to try/test something is explored, or a
local deterministic test would make future verification cheaper than repeating
the same LLM-assisted action, then implement the local coverage, document the
protected contract, run the relevant validation, and finish with the project
documentation requirements satisfied.

### Good Test Targets

Prefer local tests for:

- CLI argument parsing and rejection
- environment-variable validation
- transcript filtering and status-marker parsing
- review-summary parsing
- quota/session JSONL parsing
- active-lock and startup-anomaly guardrails
- tool-failure queue markers
- fallback artifact parsing
- public documentation checks
- prompt/module flag wiring
- symlinked client behavior
- parser/ingest behavior against normal and malformed fixtures

These are good targets because they have stable inputs, stable outputs, and
cheap fixture shapes.

### Bad Test Targets

Do not add tests for:

- open-ended code review judgment
- broad design preference
- model reasoning quality
- ambiguous root-cause analysis without stable evidence
- timing behavior that would be flaky without significant machinery
- network, daemon, database, service, or backend-model behavior unless the repo
  already has a cheap local fake for it

Do not add a framework, service, or large dependency just to claim coverage.
Start with the smallest useful local check.

### Implementation Rules

When adding coverage:

1. Prefer the repo's existing validation path before creating new tooling.
2. Keep tests local, deterministic, isolated, and backend-quota-free.
3. Use small fixtures for normal and malformed paths when fixtures are cheaper
   than mocks or live services.
4. Name the checked contract clearly enough that a maintainer can tell what
   behavior is protected.
5. Wire the test into normal project validation if it should prevent release
   regressions.
6. Document operator-facing behavior when the tested contract is public.
7. Do not create noisy or brittle tests that future maintainers will ignore.

For Upkeeper itself, prefer adding focused checks to
`tools/validate_upkeeper.sh` or `tools/check_public_docs.sh` first. If fixture
coverage grows large enough, split fixtures into a tracked `tests/fixtures/`
tree later.

### No-Choice Exception

It is acceptable to leave behavior untested when local testing would be more
expensive or brittle than the protected behavior. The final response must say
why, using concrete terms such as:

- no stable input/output contract
- backend model judgment required
- test would require a heavyweight new dependency
- no safe local fake exists yet
- behavior is already covered by a directly relevant local test

### Output Contract

When P28 applies, include a compact P28 section in the final response:

- `P28 applicability`: applicable or not applicable, with the trigger
- `Bug or reusable discovery`: what made a test worth considering
- `Coverage added`: test, fixture, or validation check added
- `Validation run`: exact local command
- `Behavior now protected`: the contract covered locally
- `Left untested`: any remaining behavior and why

If P28 does not apply, include:

`P28: not applicable`

### Final Marker Discipline

The final response must still include exactly one normal Upkeeper final marker:

- `UPKEEPER_STATUS: WORK_DONE`
- `UPKEEPER_STATUS: BLOCKED`

Do not invent a P28-specific final status marker.
