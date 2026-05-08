# Upkeeper Stress Corpus Contract

Upkeeper has a local stress corpus harness that exercises wrapper behavior
against representative repository shapes without spending Codex quota.

The corpus exists to find central Upkeeper defects before they appear in real
client repositories. It is not a replacement for testing client projects on
their own branches.

## Command

Run the no-quota local harness from the central checkout:

```sh
tools/stress_upkeeper_corpus.sh --local
```

`--local` is the default mode. It builds temporary sample repositories, invokes
their local `./Upkeeper.sh` symlinks with `UPKEEPER_DRY_RUN=1`, runs parser and
fixture checks that do not require a backend model, and prints a concise
summary. The command removes its temp directory after a clean run. If a check
fails, it keeps the temp directory and prints the evidence path. Use `--keep` to
preserve a successful corpus for inspection.

`tools/validate_upkeeper.sh --full` runs this local harness after the normal
central dry-run and fake-Codex checks. `--quick` does not run the corpus.

Backend stress runs are intentionally not implemented in this harness yet.
`tools/stress_upkeeper_corpus.sh --backend` fails closed instead of launching
real Codex work.

## Goals

- Verify central wrapper behavior across realistic repo layouts.
- Keep selection, prompt packaging, terminal output, transcript filtering,
  review-summary parsing, dirty-worktree handling, and symlinked invocation under
  repeatable local tests.
- Add language and toolchain samples cheaply, with model-backed Codex runs kept
  behind explicit opt-in commands.
- Preserve evidence from failed corpus jobs in the printed temp directory.

## Current Local Shape

The current harness generates this temp layout:

```text
samples/
  bash-tool/
  python-package/
  node-typescript/
  docs-only/
  generated-heavy/
  symlinked-client/
  dirty-worktree/
  historical-log/
  active-lock/
  terminal-modes/
evidence/
codex-home/
```

Each sample is tiny. The point is wrapper coverage, not complete language
fixtures.

## Current Coverage

The tracked harness currently covers:

- Bash script selection with tests and generated output present but excluded.
- Python parser selection plus a malformed JSON fixture that must produce a
  focused diagnostic.
- Node/TypeScript package shape selection without requiring Node to be
  installed.
- Docs-only repos that must report no eligible automatic script/tool target.
- Generated-heavy repos that keep ignored generated, dist, and runtime paths out
  of selection.
- Symlinked client invocation through local `./Upkeeper.sh`, proving modules and
  prompts resolve from the central checkout while the target repo remains local.
- Dirty worktree selection metadata, proving dirty content is baseline state.
- Historical log anomaly handling that gates normal rotation to the repo-local
  Upkeeper symlink.
- Active-lock failure classification without backend work.
- Terminal mode assertions for `basic`, `quiet`, and `silent`.
- Review-summary parsing from a final-message fixture.
- Transcript filtering that keeps prompt/search noise out of runtime evidence
  while surfacing a real test failure and status marker.

## Future Coverage

The local suite should continue growing toward:

- Go and Rust CLIs with fast unit tests and simple data-contract failures.
- Ruby, PHP, Java/Kotlin, .NET, and C/C++ samples when local toolchains are
  available, otherwise marked skipped with clear dependency evidence.
- YAML, JSON, TOML, SQL, Dockerfile, Makefile, and CI workflow samples that
  exercise non-code selection and data/config boundaries.
- Additional failure classification fixtures for empty transcripts, malformed
  analyzer JSON, missing modules, missing prompt files, quota guardrails, and
  local dependency gaps when those checks are not already covered by
  `tools/validate_upkeeper.sh --full`.
- Terminal-mode assertions for `verbose`, `debug1`, and `full` where the expected
  output can stay stable and readable.

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
- Terminal modes: `basic`, `quiet`, and `silent` obey their local contracts.
- Transcript filtering: prompt echoes, source views, diffs, and uninteresting
  search failures do not become runtime ERROR evidence.
- Finale parsing: parsed final responses surface outcome and selected file from
  a local fixture.
- Failure classification: active locks produce a distinct exit reason in corpus
  local mode; other failure classes remain covered by full validation until the
  corpus adds matching local samples.

## Execution Modes

Corpus tooling has one implemented mode and one reserved mode:

- `--local`: build samples and run dry-run, parser, terminal, and parser/filter
  checks only. This is the default and must not spend Codex quota.
- `--backend`: reserved for future real Codex cycles against selected samples.
  It must require an explicit flag, log model, reasoning effort, quota snapshot
  identity, transcript path, selected sample, and selected file, and stay outside
  default validation.

Future large suites may add sharding, but the default contract should stay
boring: generate samples, run local checks, print a concise summary, and leave
evidence only when requested or when a check fails.

## Acceptance Criteria

A stress-corpus implementation is ready to trust when:

- It is invoked by tracked `tools/stress_upkeeper_corpus.sh`.
- `tools/validate_upkeeper.sh --quick` does not require real backend work.
- `tools/validate_upkeeper.sh --full` runs the local corpus without backend
  quota.
- Corpus local mode can run repeatedly without tracked file churn.
- Missing optional language toolchains are reported as skips, not failures.
- At least one sample proves symlinked client invocation against the central
  module tree.
- At least one sample proves malformed data/config input produces a focused
  diagnostic instead of being treated as absence.
- Terminal-mode assertions cover `basic`, `quiet`, and `silent`.
- The README and operator guide point to this command and contract.
