# Upkeeper Stress Corpus Contract

Upkeeper should grow a local stress corpus that exercises wrapper behavior
against representative repository shapes without spending Codex quota by
default.

The corpus exists to find central Upkeeper defects before they appear in real
client repositories. It is not a replacement for testing client projects on
their own branches.

## Goals

- Verify central wrapper behavior across many realistic repo layouts.
- Keep selection, prompt packaging, terminal output, transcript filtering,
  review-summary parsing, dirty-worktree handling, and symlinked invocation under
  repeatable local tests.
- Add language and toolchain samples cheaply, with model-backed Codex runs kept
  behind explicit opt-in commands.
- Preserve evidence from every failed corpus job in a small, predictable runtime
  directory.

## Default Corpus Shape

Sample repositories should be generated under ignored runtime state, for
example:

```text
runtime/stress-corpus/
  bash-tool/
  python-package/
  node-typescript/
  go-cli/
  rust-cli/
  ruby-script/
  php-cli/
  java-gradle/
  dotnet-tool/
  cpp-cmake/
  data-config/
  docs-only/
```

Each sample should be tiny. The point is wrapper coverage, not complete language
fixtures.

## Minimum Sample Coverage

The first useful suite should include:

- Bash scripts with shell syntax checks, argument validation, and heredocs.
- Python modules with JSON/config parsing, malformed-input fixtures, and pytest
  when available.
- Node or TypeScript packages with package scripts, generated output ignored,
  and one intentionally stale doc.
- Go and Rust CLIs with fast unit tests and simple data-contract failures.
- Ruby, PHP, Java/Kotlin, .NET, and C/C++ samples when local toolchains are
  available, otherwise marked skipped with clear dependency evidence.
- YAML, JSON, TOML, SQL, Dockerfile, Makefile, and CI workflow samples that
  exercise non-code selection and data/config boundaries.
- Docs-only repos that confirm Upkeeper does not invent source files just to
  make a cycle look productive.

## Required Wrapper Scenarios

Every corpus run should cover these central behaviors:

- Central symlink install: sample repo invokes a local `./Upkeeper.sh` symlink
  that resolves modules and prompts from the central checkout.
- Dry-run startup: `UPKEEPER_DRY_RUN=1 ./Upkeeper.sh` succeeds without backend
  Codex work.
- Selection: the oldest eligible non-test script/tool file is selected, while
  `.git/`, ignored paths, runtime evidence, generated outputs, and tests are not
  selected by accident.
- Dirty worktree handling: already-dirty files are treated as baseline state,
  not silently reverted.
- Terminal modes: `basic`, `quiet`, `silent`, `verbose`, `debug1`, and `full`
  obey their contracts.
- Transcript filtering: prompt echoes, source views, diffs, and uninteresting
  search failures do not become runtime ERROR evidence.
- Finale parsing: parsed final responses surface outcome, selected file,
  findings, changes, and verification in both logs and terminal summaries.
- Failure classification: empty transcripts, malformed analyzer JSON, missing
  modules, missing prompt files, active locks, quota guardrails, and local
  dependency gaps produce distinct exit reasons.

## Execution Modes

Corpus tooling should have at least two modes:

- `--local`: build samples and run dry-run, parser, terminal, and fake-Codex
  checks only. This must be the default and must not spend Codex quota.
- `--backend`: opt into real Codex cycles against selected samples. This mode
  must require an explicit flag and should log model, reasoning effort, quota
  snapshot identity, transcript path, selected sample, and selected file.

Future large suites may add sharding, but the first contract should stay boring:
generate samples, run local checks, print a concise summary, and leave evidence
under `runtime/`.

## Acceptance Criteria

A stress-corpus implementation is ready to trust when:

- It is invoked by a tracked tool, for example `tools/stress_upkeeper_corpus.sh`.
- `tools/validate_upkeeper.sh --quick` does not require real backend work.
- Corpus local mode can run repeatedly without tracked file churn.
- Missing optional language toolchains are reported as skips, not failures.
- At least one sample proves symlinked client invocation against the central
  module tree.
- At least one sample proves malformed data/config input produces a focused
  diagnostic instead of being treated as absence.
- Terminal-mode assertions cover `basic`, `quiet`, and `silent`.
- The README and operator guide point to this contract.
