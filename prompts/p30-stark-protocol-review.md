# P30 Stark Protocol Review

Purpose:
P30 turns each useful failure, near miss, or fragile recovery path into durable
hardening. It is the "same weakness cannot get us twice" review module: if a
weakness is found, the run must either remove it, add a deterministic guard, add
a focused regression test or validator check, document the new invariant, or
name the exact follow-up that is blocked by the current write boundary.

Core rule:
Every iteration must harden the system. Do not stop at "the operator can avoid
that next time" when the wrapper, launcher, docs, prompt, validator, test
harness, or compatibility contract can make the repeat path impossible or
visible before damage.

## Scope and Boundaries

Use P30 when the weakness can recur in future runs without a durable local
guard, documentation update, or reproducible validation.

Out of scope for P30:

- exploratory quality improvements with no recurrence risk
- purely style-only cleanup that does not reduce repeat failures
- changes that would require a central behavior redesign beyond the selected-file
  boundary

Applicability:
Run P30 when the selected file touches any of these:
- automation obligations or prior failed-cycle recovery
- backlog, FlameOn, ChimneySweep, loop, or full-burn launchers
- quota, fallback, Lattice, manifest, target selection, backup, restore,
  sandbox, issue workflow, prompt compilation, transcript, or log handling
- operator-visible contracts, compatibility, public docs, help text, release
  notes, or prompt-module behavior
- deterministic validation, local tests, stress corpus fixtures, or CI checks
- any bug or design weakness that could recur without a hard guard

P30 is especially applicable after:
- a manual recovery step that should become scripted
- a run that failed before the selected issue was worked
- an issue that had to be deferred because a control-plane invariant was absent
- a fix whose safety depends on remembering tribal knowledge
- a bug caused by stale local state, missing local setup, unsafe interactive
  behavior, incomplete validation, or drift between docs/help/runtime

Permanent hardening test:
Before reporting `WORK_DONE`, answer these:

1. What exact weakness class was exposed?
2. Can the same weakness stop, corrupt, leak, loop, misroute, or confuse a
   later cycle in the same way?
3. Is there a pre-model local check that can catch it?
4. Is there a deterministic test, validator assertion, stress-corpus fixture, or
   CI check that can make the fix non-regressible?
5. Is an operator-visible contract now clearer in help, docs, compatibility
   notes, release notes, or prompt language?
6. Does the fix belong in central Upkeeper rather than a client repo workaround?
7. Does the change preserve the clean no-op path and avoid adding backend quota
   or expensive scans to healthy empty runs?
8. If the selected-file boundary prevents the durable fix, is the follow-up
   specific enough for the next run to repair without rediscovery?

If the answer to 2 is yes and 3, 4, 5, or 8 can be satisfied in scope, do that
hardening before final status.

Allowed hardening moves:
- add a local fail-closed preflight before backend launch
- add or tighten a validator assertion
- add a focused unit test, fixture, or stress-corpus case
- make an unsafe state an automation obligation with a repair target
- replace "operator should remember" guidance with executable bootstrap,
  recovery, or repair behavior
- update docs/help/compatibility/release notes so the contract is public
- make hidden state visible in ordinary terminal output
- add an explicit warning or blocked state rather than silently continuing
- narrow a launcher, selection, backup, or prompt authority path so the same
  weakness cannot bypass the intended gate

Hard boundaries:
- Do not turn P30 into broad perfectionism. Apply the smallest permanent guard
  that blocks the demonstrated weakness class.
- Do not add live backend calls, network dependency, or expensive scans to the
  healthy no-op path without an explicit operator-visible reason.
- Do not patch a client repo when the weakness is central Upkeeper behavior.
- Do not create noisy checks that make operators ignore real failures.
- Do not mark the issue fixed if the repeat path remains open and untracked.

Relationship to neighboring modules:
P25 checks contract and intent compliance.

P26 checks public documentation clarity.

P28 harvests cheap deterministic tests and fixtures.

P29 extracts reusable project knowledge.

P30 requires the final hardening barrier: the fix should leave a durable guard,
test, validator assertion, documented invariant, obligation path, or explicit
blocked follow-up so the same weakness cannot silently recur.

## Verification Guidance

- make the recurring weakness visible in a local check, validator assertion, or
  stress fixture
- when feasible, run the smallest reproducible validation proving the new guard
  is present
- if the fix is blocked, document one deterministic follow-up with owner and
  trigger boundary

Required output:
When P30 applies, include this concise block in the final response:

```text
P30 Stark Protocol:
- Weakness class:
- Permanent hardening:
- Non-regression evidence:
- Remaining repeat path:
```

If the selected-file or task boundary blocks the hardening, include:

```text
P30 Stark Protocol:
- Blocked:
- Required follow-up:
- Repeat risk until fixed:
```

If P30 does not apply, include:

```text
P30: not applicable
```

P30 does not invent a final Upkeeper status. Continue to use the normal
`WORK_DONE`, `NO_CHANGES`, or `STOPPED_ON_BLOCKER` status contract.

## Output Contract

When P30 applies, include the exact `P30 Stark Protocol:` section with:

- weakness class
- permanent hardening
- non-regression evidence
- repeat path status

If blocked, include the `blocked` form and exact follow-up requirement.
