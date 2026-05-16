# P31 Fault-Injection Review

Status: reserved future review module. This prompt defines the contract for
future P31 fault-injection work, but `--review-module=p31` is not wired yet.
Until that wiring exists, use this file only as a design contract or explicit
`--prompt-file` input.

## Purpose

Use P31 when a wrapper behavior needs deterministic fault-injection proof rather
than another prose-only review. The goal is not to "try a breaker." The goal is
to prove that a named broken condition is contained by an explicit oracle and,
when runtime state is touched, followed by recovery proof.

P31 is not fuzzing, mutation testing, broad chaos engineering, or a request to
mutate tracked source to test the tests. Each scenario must be named,
deterministic, bounded, local, and attached to an expected Upkeeper contract.

## Applicability Gate

Before proposing or editing a scenario, decide whether P31 applies.

P31 applies when all of these are true:

- There is a specific component or function whose assumption can be challenged.
- The injected condition can be represented by a deterministic local fixture,
  fake dependency, malformed artifact, or controlled environment value.
- At least one explicit oracle can prove the wrapper handled the condition.
- Any touched runtime state can either be avoided, isolated, or proven clean in
  a recovery run.

P31 does not apply when the idea is only exploratory breakage, random fuzzing,
non-deterministic timing stress, backend quota spending, broad source mutation,
or a scenario without a clear expected behavior.

If P31 does not apply, write:

```text
P31: not applicable
Reason: <one sentence>
```

## Terminology

Use these terms precisely:

- Fault: the injected broken condition.
- Error: invalid internal state, bad evidence, malformed artifact, or
  unavailable dependency caused by the fault.
- Failure: externally visible wrong behavior if Upkeeper mishandles the error.
- Containment: behavior that prevents operator damage, stale evidence reuse,
  false success, false fallback, ambiguous diagnostics, or unsafe mutation.

## Required Fault Model

Every valid P31 scenario must declare each field below. If a field is not
applicable, say why; do not omit it.

```text
P31 Fault Scenario:
Component:
Function protected:
Assumption challenged:
Injected fault:
Fault trigger:
Expected internal error state:
Expected externally visible behavior:
Containment behavior:
Operator diagnostic:
Cleanup expectation:
Recovery expectation:
Oracle classes:
Control run:
Injection run:
Recovery run:
Scenario registry action:
```

## Required Phases

- Control run: prove the harness or fixture passes without the injected fault
  when practical. If a control run is impossible or irrelevant, state why.
- Injection run: inject the fault and assert explicit oracles. A scenario with
  no oracle is invalid.
- Recovery run: when runtime state, cache state, lock state, local ledger state,
  backup state, transcript state, or other persisted state is touched, prove the
  next invocation is not poisoned by the injected fault.

## Oracle Classes

Use one or more explicit oracle classes. At least one must be present before a
scenario is valid.

- Exit oracle: expected exit code or marker state.
- Reason oracle: expected machine-readable reason, status, or classification.
- Log oracle: expected log key/value record or absence of an unsafe log record.
- Terminal oracle: expected operator-facing message or absence of confusing
  terminal output.
- Artifact oracle: expected file, permission, content class, hash, redaction, or
  absence of a stale artifact.
- Mutation oracle: expected tracked-source, runtime-state, or local-state
  mutation boundary.
- Cleanup oracle: expected temporary-file, lock, backup, or process cleanup.
- Recovery oracle: expected next-run behavior after the injected state exists.
- Non-oracle declaration: intentionally unasserted behavior with a reason. This
  never satisfies the minimum oracle requirement by itself.

## Injector Catalog

Prefer deterministic local injectors from the Scenario registry docs:

- Temp implementation tree.
- Temp client repo.
- Fake `codex` in temp `PATH`.
- Fake `CODEX_HOME`.
- Fake runtime dirs.
- Directory-where-file-expected.
- Empty file.
- Malformed file.
- Invalid env/config.
- Crafted final message.
- Crafted transcript.
- Git temp repo.
- Shell function override inside helper-level sourced tests.

If a proposed injector is not in that catalog, either add it to the registry
docs with a flakiness analysis or mark the P31 idea as not ready.

## Flakiness Bans And Restrictions

P31 must not rely on uncontrolled sleep races, real network, real Codex, real
quota exhaustion, real user `CODEX_HOME`, real disk-full behavior, real `/proc`
PID reuse assumptions, real `screen` sessions in quick mode, unbounded random
mutation, or mutation testing against tracked source. `chmod` unreadable checks
cannot be the only proof when validation may run as root.

## Scenario Registry Rule

Every accepted scenario must leave one of these registry actions:

- Added scenario: the scenario is implemented in a focused local test, stress
  corpus case, or validator fixture.
- Proposed scenario: the scenario is documented as a follow-up with exact owner,
  target file, oracle classes, and expected evidence.
- Rejected scenario: the scenario is intentionally not pursued, with a concrete
  reason such as nondeterminism, backend cost, unsafe source mutation, or lack
  of an oracle.

Unregistered fault ideas are not P31 output. They are notes.

The tracked scenario registry is `docs/fault-injection-scenarios.md`. Use its
stable `FI-###` ids when adding, proposing, rejecting, or retiring scenarios.

## Output Contract

When P31 applies, include this block in the review summary:

```text
P31 Fault-Injection Review:
Scenario:
Fault:
Error:
Failure prevented:
Containment:
Oracles:
Control evidence:
Injection evidence:
Recovery evidence:
Registry action:
```

If the scenario cannot be implemented safely in the current patch, do not fake
coverage. Record the proposed scenario and the missing oracle or recovery proof.
